import AVFAudio
import Foundation
import Observation
import SwiftData

/// One lesson, taught out loud, with Polly watching.
///
/// A sibling of `PollySessionController` rather than a mode of it. That one
/// takes a `Recipe` in its initialiser and builds a plan, a pantry match and a
/// cook log out of it; a knife lesson has none of those and would spend its life
/// being handed a recipe that does not exist. `SkillChatService` made the same
/// call against `RecipeChatService` for the same reason, and this follows it.
///
/// What is shared is everything expensive: the realtime transport, the token
/// mint, the visual source, and the assessor. What is different is the shape of
/// the conversation.
///
/// **Same wake word as a cook.** It was built without one, on the theory that a
/// lesson is a focused activity and being summoned is ceremony. That was wrong
/// in practice for the reason it is right in a recipe: a kitchen is noisy, the
/// cook talks to other people, and an always open mic turns every stray sentence
/// into a turn. It is also simply what this app has taught people to expect, and
/// inventing a second rule for the same gesture is worse than the ceremony.
@MainActor
@Observable
final class SkillCoachSession {

    enum Phase: Equatable {
        case idle
        case connecting
        case live
        case ended
        case failed(String)
    }

    /// Where the lesson is. Explicit rather than a pile of booleans, because the
    /// screen has to draw something different for nearly every one of these and
    /// "holding" versus "analysing" is exactly the distinction the cook is
    /// waiting on.
    enum Stage: Equatable {
        /// Connecting, or she is teaching. Nothing for the cook to do but listen.
        case teaching
        /// The five seconds. `progress` drives the ring.
        case holding(progress: Double)
        /// Frames are in, the assessor is thinking.
        case analysing
        /// She has just said something about what she saw.
        case coaching(outcome: SkillAttemptOutcome)
        /// Watched, correct, done.
        case learned
        /// Something visibly dangerous. Everything else stops.
        case safetyStop(reason: String)
        /// The camera could not deliver, twice. There is a way out on screen.
        case visionUnavailable
    }

    struct Dependencies {
        var mintToken: (_ voice: String?, _ textOnly: Bool) async throws -> PollySessionToken
        var makeTransport: () -> RealtimeTransporting
        var assess: (SkillVisualCheck, [Data]) async throws -> SkillVisualAssessment
        var now: () -> Date

        static let live = Dependencies(
            mintToken: { voice, textOnly in
                try await PollyTokenService.live.mint(voice: voice, textOnly: textOnly)
            },
            makeTransport: { RealtimeWebRTCTransport() },
            assess: { check, frames in
                try await SkillVisualAssessor.assess(check: check, frames: frames)
            },
            now: { .now }
        )
    }

    // MARK: - State the screen reads

    private(set) var phase: Phase = .idle
    private(set) var stage: Stage = .teaching
    /// Polly's latest line, so a cook who missed it can read it.
    private(set) var caption = ""
    /// Attempts this session, newest last. Drives the little history strip.
    private(set) var attempts: [SkillAttempt] = []
    /// True while she is talking, so the screen can show it and the ring can wait.
    private(set) var isSpeaking = false
    /// A turn is in flight: she is deciding, or a look is being assessed.
    private(set) var isThinking = false
    /// The on-device recogniser is up and the wake word will actually work.
    private(set) var wakeWordAvailable = false
    /// The cook said "Chef" and the mic is open to the server.
    private(set) var isAwake = false

    var canCheck: Bool { phase == .live && stage == .teaching }

    /// Whether the microphone is actually open to the server right now.
    ///
    /// Read from the transport rather than tracked here, because the governor
    /// combines several things to decide it and a second copy would drift. The
    /// screen showing "listening" while the server hears silence is the exact
    /// bug this avoids.
    var isListening: Bool {
        guard phase == .live, isAwake, !isSpeaking, !isThinking else { return false }
        if case .holding = stage { return false }
        if case .analysing = stage { return false }
        return true
    }

    // MARK: - Guts

    let skill: Skill
    private let check: SkillVisualCheck
    private let visuals: PollyVisualSourceCoordinator
    private let deps: Dependencies

    private let wakeWord: WakeWordListening
    private var dormancyTask: Task<Void, Never>?
    private var transport: RealtimeTransporting?
    private var eventTask: Task<Void, Never>?
    private var holdTask: Task<Void, Never>?
    private var context: ModelContext?

    /// Consecutive unusable views. Reset by any assessment we could act on.
    /// After `check.maxUnusableViews` the lesson stops asking and offers the
    /// escape, because a third identical request is where a cook decides the
    /// feature is broken.
    private var unusableViews = 0

    /// A response is generating. Asking for a second one while the first is in
    /// flight is rejected by the server and loses the turn.
    private var responseInFlight = false

    /// What the last look concluded, in the words we want said.
    ///
    /// Kept because a bare `response.create` after a tool call she made mid
    /// sentence very often produces nothing: from the model's point of view it
    /// already spoke this turn. The result of actually looking at somebody is
    /// the one thing that must never be silently dropped, so the follow up is
    /// steered with the sentence rather than hoped for.
    private var pendingSay = ""

    init(
        skill: Skill,
        check: SkillVisualCheck,
        visuals: PollyVisualSourceCoordinator,
        wakeWord: WakeWordListening? = nil,
        deps: Dependencies = .live
    ) {
        self.skill = skill
        self.check = check
        self.visuals = visuals
        self.wakeWord = wakeWord ?? WakeWordListener()
        self.deps = deps
    }

    // MARK: - Lifecycle

    func start(context: ModelContext) async {
        guard phase == .idle else { return }
        self.context = context
        phase = .connecting
        // Fresh log per lesson: the copy button is for sending one session to
        // somebody, and a paste that starts three cooks ago is unreadable.
        PollyDebugLog.shared.reset()
        PollyDebugLog.shared.log("skill: starting lesson \(skill.id) — \(skill.title)")

        // Mic first, because WebRTC starts capturing at connect and a denied
        // permission surfaces there as an audio failure with no explanation.
        // The lesson is a conversation; without a microphone there is nothing
        // to fall back to.
        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .failed(
                "Chef needs the microphone to teach you. Turn it on in Settings and come back.")
            PollyDebugLog.shared.log("skill: mic permission DENIED")
            return
        }

        // The glasses are the whole point here, so unlike a cook session this
        // brings them up and says so if they are missing, rather than quietly
        // carrying on without.
        await visuals.startGlassesIfAvailable()

        let token: PollySessionToken
        do {
            token = try await deps.mintToken(PollyConfig.voice, false)
        } catch {
            phase = .failed(error.localizedDescription)
            PollyDebugLog.shared.log("skill: token mint FAILED — \(error.localizedDescription)")
            return
        }

        let transport = deps.makeTransport()
        self.transport = transport
        // The wake listener hears the room through the capture tap, and it has
        // to be attached before connect: WebRTC starts capturing during
        // negotiation, and a tap wired afterwards misses the words spoken while
        // the screen was still saying "getting Chef ready".
        if let webrtc = transport as? RealtimeWebRTCTransport {
            let wake = wakeWord
            webrtc.onCaptureBuffer = { buffer in wake.append(buffer) }
        }
        let config = RealtimeSessionConfig(
            instructions: SkillCoachPrompt.instructions(
                skill: skill,
                check: check,
                seesContinuously: visuals.activeKind == .metaGlasses),
            tools: SkillCoachPrompt.tools,
            voice: token.voice,
            model: token.model,
            transcribeInput: true,
            audioPinnedAtMint: true
        )

        do {
            try await transport.connect(token: token.value, model: token.model)
            (transport as? RealtimeWebRTCTransport)?.applyAudioLabAndReport()
            try await transport.send(.sessionUpdate(config))
        } catch {
            phase = .failed(error.localizedDescription)
            PollyDebugLog.shared.log("skill: connect FAILED — \(error.localizedDescription)")
            return
        }

        phase = .live
        stage = .teaching
        consumeEvents(from: transport)

        // Wake word up before she says anything, so "Chef" lands even during her
        // opening line.
        _ = await wakeWord.requestAuthorization()
        wakeWord.onWake = { [weak self] in
            guard let self else { return }
            // She must not wake herself. The feed is post AEC and her prompt
            // avoids the word, but a wake landing exactly as she says it is the
            // one failure that makes her interrupt her own sentence.
            if self.isSpeaking, WakeWordMatcher.containsWake(self.caption) {
                PollyDebugLog.shared.log("skill: wake ignored, she said it herself")
                return
            }
            self.wakeUp()
        }
        wakeWord.onListeningChange = { [weak self] listening in
            self?.wakeWordAvailable = listening
            PollyDebugLog.shared.log("skill: wake word \(listening ? "listening" : "unavailable")")
        }
        wakeWord.start()
        wakeWordAvailable = wakeWord.isAvailable

        // Dormant until spoken to, exactly like a cook. The mic is held closed
        // through her opening line as well, because the AEC convergence window
        // is where her own voice can come back as the cook's.
        (transport as? RealtimeWebRTCTransport)?.holdMicForGreeting()
        (transport as? RealtimeWebRTCTransport)?.setMicMode(.dormant)

        try? await transport.send(.responseCreateSpeechOnly)
        PollyDebugLog.shared.log(
            "skill: live, dormant, wake word \(wakeWordAvailable ? "ready" : "UNAVAILABLE")")
    }

    /// Turn what the cook just said into a turn she answers.
    private func commitTurn() async {
        guard phase == .live, !responseInFlight else {
            PollyDebugLog.shared.log("skill: turn not committed (response already in flight)")
            return
        }
        responseInFlight = true
        isThinking = true
        try? await transport?.send(.responseCreate)
        PollyDebugLog.shared.log("skill: committed turn → response.create")
    }

    /// "Chef" was heard. Open the mic and start the clock.
    private func wakeUp() {
        guard phase == .live else { return }
        isAwake = true
        (transport as? RealtimeWebRTCTransport)?.forceMicOpenForWake()
        PollyDebugLog.shared.log("skill: AWAKE, mic open")
        armDormancy(after: PollyConfig.initialListenWindowSeconds)
    }

    /// Back to waiting for the word.
    private func goDormant(reason: String) {
        dormancyTask?.cancel()
        dormancyTask = nil
        guard isAwake else { return }
        isAwake = false
        (transport as? RealtimeWebRTCTransport)?.setMicMode(.dormant)
        PollyDebugLog.shared.log("skill: dormant (\(reason))")
    }

    /// Close the mic again if nothing comes of it. Without this a single "Chef"
    /// leaves the mic open for the rest of the lesson, which is the thing the
    /// wake word exists to prevent.
    private func armDormancy(after seconds: TimeInterval) {
        dormancyTask?.cancel()
        dormancyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.goDormant(reason: "nothing said")
        }
    }

    func end() async {
        dormancyTask?.cancel()
        wakeWord.stop()
        holdTask?.cancel()
        toolTask?.cancel()
        eventTask?.cancel()
        // Wait for the check to actually unwind before returning.
        //
        // Cancelling is not stopping: a hold that is mid-flight still falls
        // through to recording an attempt, and if the screen has gone that write
        // lands on a context nobody owns any more. Cheap to wait for, and the
        // alternative is a crash whose stack points at whatever ran next.
        await holdTask?.value
        await toolTask?.value
        holdTask = nil
        toolTask = nil
        await transport?.close()
        transport = nil
        if case .failed = phase {} else { phase = .ended }
        PollyDebugLog.shared.log("skill: lesson ended after \(attempts.count) attempt(s)")
    }

    /// Kept for the retry path and for tests. There is no button any more: the
    /// way a cook asks to be looked at is to ask.
    func checkNow() {
        guard canCheck else { return }
        holdTask?.cancel()
        holdTask = Task { [weak self] in
            _ = await self?.runHoldAndAssess(announce: true)
        }
    }

    // MARK: - Events

    private func consumeEvents(from transport: RealtimeTransporting) {
        eventTask = Task { [weak self] in
            for await event in transport.events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    /// Tool work runs off the event loop.
    ///
    /// `check_the_hold` takes five seconds of holding plus a vision round trip,
    /// and awaiting that inside `for await event in transport.events` stops the
    /// session hearing anything at all for the duration: transcripts, speech
    /// events and her own audio state all queue up behind a hand that is being
    /// photographed. One tool call was freezing the conversation for ten
    /// seconds.
    private var toolTask: Task<Void, Never>?

    private func handle(_ event: RealtimeServerEvent) async {
        switch event {
        case .outputAudioStarted:
            isSpeaking = true
            wakeWord.setSuppressed(true)
            PollyDebugLog.shared.log("skill: she is speaking")
        case .outputAudioStopped:
            isSpeaking = false
            // Back to a state that can be checked again. She has just delivered
            // the result, so the cook is now free to try the fix and ask for
            // another look. Without this the check runs exactly once per lesson,
            // which is the opposite of the loop this whole thing is built on.
            if case .coaching = stage { stage = .teaching }
            wakeWord.setSuppressed(false)
            // She has answered, so the turn is over. Give them a window to come
            // straight back without saying the word again, then close.
            if isAwake { armDormancy(after: PollyConfig.initialListenWindowSeconds) }
            PollyDebugLog.shared.log(
                "skill: she stopped (awake=\(isAwake) stage=\(stage))")
        case .outputTranscriptDelta(_, let delta):
            caption += delta
        case .inputTranscript(_, let text):
            // Logged because "she is not listening to me" is otherwise
            // indistinguishable from "she heard me and chose not to answer",
            // and those need completely different fixes.
            PollyDebugLog.shared.log("skill: heard \"\(text)\"")
            // They said something real, so do not close the mic underneath them
            // while she is still working out the answer.
            if isAwake { armDormancy(after: PollyConfig.maxListeningSeconds) }
            // AND ASK HER TO ANSWER IT.
            //
            // This is what was missing, and it is why she heard two questions in
            // a row and said nothing to either. The audio plane is pinned at
            // mint and does not create a response when the cook stops talking,
            // so the turn only becomes a turn when the client says so. The cook
            // session has always done this from its gate; this one was waiting
            // for a server that was never going to speak first.
            await commitTurn()
        case .responseCreated:
            responseInFlight = true
            caption = ""
        case .responseDone(let status, let calls, _):
            responseInFlight = false
            isThinking = !calls.isEmpty
            // Only act on a completed response. A cancelled one can carry
            // partial calls, and running them talks over whoever interrupted.
            guard status == "completed", !calls.isEmpty else { return }
            toolTask?.cancel()
            toolTask = Task { [weak self] in
                guard let self else { return }
                for call in calls { await self.run(call) }
            }
        case .error(let code, let message):
            PollyDebugLog.shared.log("skill: realtime error \(code ?? "?") — \(message)")
        default:
            break
        }
    }

    private func run(_ call: RealtimeFunctionCall) async {
        switch call.name {
        case "check_the_hold":
            let payload = await runHoldAndAssess(announce: false)
            await reply(to: call, with: payload)
        case "finish_lesson":
            finishLesson()
            await reply(to: call, with: #"{"done":true}"#)
        default:
            await reply(to: call, with: #"{"error":"unknown tool"}"#)
        }
    }

    private func reply(to call: RealtimeFunctionCall, with output: String) async {
        try? await transport?.send(.createFunctionOutput(callId: call.callId, output: output))

        // Steered rather than open ended. She called this tool in the same
        // breath as "hold it there for five seconds", so as far as the model is
        // concerned it has already spoken this turn and a bare response.create
        // frequently returns silence. The cook is standing there holding a
        // knife waiting to be told what happened, so the one thing that cannot
        // be left to chance is that she says it.
        responseInFlight = true
        if pendingSay.isEmpty {
            try? await transport?.send(.responseCreate)
        } else {
            let line = pendingSay
            pendingSay = ""
            try? await transport?.send(.responseCreateWithInstructions(
                "You have just looked at their hand. Tell them what you found now, in your own "
                + "words, leading with this and nothing else: \"\(line)\" "
                + "Keep it to a sentence or two. Do not add a second correction, do not repeat "
                + "the instruction you gave before the hold, and do not thank them for waiting."))
        }
        isThinking = false
    }

    // MARK: - The check

    /// Hold, look, decide, record. The one path both the tool and the button use.
    private func runHoldAndAssess(announce: Bool) async -> String {
        // Let her finish saying "hold that for me" first.
        //
        // The tool call and the sentence that introduces it are the same
        // response, so without this the five seconds start while she is still
        // talking and the cook is being counted down at before they have been
        // told to hold anything.
        if let webrtc = transport as? RealtimeWebRTCTransport {
            await webrtc.waitUntilAssistantQuiet(timeoutSeconds: 6)
        }

        let started = deps.now()
        stage = .holding(progress: 0)
        // Holding still is not silence to be timed out. Keep the turn alive
        // across the hold and the assessment so the answer does not arrive to a
        // closed mic.
        if isAwake { armDormancy(after: check.holdSeconds + PollyConfig.maxListeningSeconds) }

        let capture = await SkillHoldCapture.run(
            check: check,
            visuals: visuals,
            clock: deps.now
        ) { [weak self] progress in
            self?.stage = .holding(progress: progress)
        }

        stage = .analysing

        guard !capture.isEmpty else {
            return handleUnusable(
                reason: capture.rejection ?? .noFrames,
                seconds: capture.duration,
                startedAt: started)
        }

        let assessment: SkillVisualAssessment
        do {
            assessment = try await deps.assess(check, capture.frames)
        } catch {
            PollyDebugLog.shared.log("skill: assessment FAILED — \(error.localizedDescription)")
            return handleUnusable(
                reason: .noFrames, seconds: capture.duration, startedAt: started)
        }

        let outcome = SkillCoachDecision.decide(assessment, check: check)
        let note = SkillCoachDecision.note(for: outcome, assessment: assessment, check: check)
        PollyDebugLog.shared.log(
            "skill: assessed \(assessment.overall.rawValue) conf=\(String(format: "%.2f", assessment.confidence)) -> \(note)")

        record(
            outcome: attemptOutcome(for: outcome),
            note: note,
            mistakeKey: mistakeKey(of: outcome),
            equipment: assessment.equipment.reading,
            confidence: assessment.confidence,
            seconds: capture.duration,
            startedAt: started)

        return payload(for: outcome, assessment: assessment)
    }

    /// A view we could not use. Never recorded as the cook doing badly, and
    /// after the second one the lesson stops asking.
    private func handleUnusable(
        reason: VisualFrameRejection,
        seconds: TimeInterval,
        startedAt: Date
    ) -> String {
        unusableViews += 1
        record(
            outcome: .inconclusive,
            note: "No usable view (\(reason.rawValue)).",
            mistakeKey: nil,
            equipment: nil,
            confidence: 0,
            seconds: seconds,
            startedAt: startedAt)

        if unusableViews >= check.maxUnusableViews {
            stage = .visionUnavailable
            return json([
                "outcome": "vision_unavailable",
                "say": "I am not getting a clear enough view through the glasses to check this "
                    + "properly. Let me tell you exactly what to feel for instead.",
                "then": "Describe what a correct grip should feel like, then offer to try the "
                    + "check again or carry on without it. Do not ask them to reposition again.",
            ])
        }

        stage = .coaching(outcome: .inconclusive)
        return json([
            "outcome": "cannot_see",
            "say": check.retryFraming,
            "then": "Ask them to hold it again, then call check_the_hold. Make it clear this is "
                + "about the view and not about their grip.",
        ])
    }

    /// Everything Polly needs to say the right thing, and nothing she could use
    /// to say the wrong one.
    private func payload(
        for outcome: SkillCoachDecision.Outcome,
        assessment: SkillVisualAssessment
    ) -> String {
        let evidence = assessment.observedEvidence
        switch outcome {
        case .safetyStop(let reason):
            stage = .safetyStop(reason: reason)
            return json([
                "outcome": "safety_stop",
                "say": "Stop there a second and put the knife down on the board.",
                "reason": reason,
                "then": "Say what you saw, in one calm sentence, and how to fix it. Do not carry "
                    + "on with the lesson until they have put it down and fixed it.",
            ], evidence: evidence)

        case .unsupportedEquipment(let reading):
            stage = .coaching(outcome: .wrongEquipment)
            return json([
                "outcome": "unsupported_equipment",
                "say": "That looks like a \(reading). This lesson is for a chef's knife, a "
                    + "santoku or a gyuto, which you hold a bit differently. Grab one of those "
                    + "if you have one.",
                "then": "If they say it is a chef's knife after all, believe them and check "
                    + "again.",
            ], evidence: evidence)

        case .cannotSee(let regions):
            unusableViews += 1
            if unusableViews >= check.maxUnusableViews {
                stage = .visionUnavailable
                return json([
                    "outcome": "vision_unavailable",
                    "say": "I still cannot see it well enough to be useful. Let me describe what "
                        + "it should feel like instead.",
                    "then": "Do not ask them to reposition again.",
                ], evidence: evidence)
            }
            stage = .coaching(outcome: .inconclusive)
            let names = regions.map(\.spokenName).joined(separator: " or ")
            return json([
                "outcome": "cannot_see",
                "say": "I cannot quite see \(names.isEmpty ? "your hand" : names). "
                    + check.retryFraming,
                "then": "Ask them to hold again and call check_the_hold. Be clear this is the "
                    + "view, not their grip.",
            ], evidence: evidence)

        case .correct(let key, let certainty):
            unusableViews = 0
            stage = .coaching(outcome: .corrected)
            guard let mistake = SkillCoachDecision.mistake(for: key, in: check) else {
                return json(["outcome": "cannot_see", "say": check.retryFraming])
            }
            var body: [String: String] = [
                "outcome": "correct",
                "say": mistake.correction,
                "why": mistake.rationale,
                "then": "Ask them to try that and hold it again, then call check_the_hold. "
                    + "One correction only. Do not mention anything else you can see.",
            ]
            if certainty == .tentative {
                body["hedge"] = "You are not certain. Say it as something that looks like it may "
                    + "be happening, and that you will take another look."
            }
            if mistake.isContextual {
                body["nuance"] = "This is not wrong in general, it is wrong for what you are "
                    + "teaching today. Say so if they push back."
            }
            return json(body, evidence: evidence)

        case .passed(let isVariation):
            unusableViews = 0
            stage = .coaching(outcome: .passed)
            var body: [String: String] = [
                "outcome": "passed",
                "say": isVariation
                    ? "That is a little different from the textbook pinch, and you have got good "
                        + "control of the knife, so I am happy with it."
                    : "Yep, that is it.",
                "then": "Name specifically what they got right, using the evidence. Then ask "
                    + "whether it feels comfortable or tense, because you cannot see that. If "
                    + "they say it is fine, say why the grip matters in one line and call "
                    + "finish_lesson.",
            ]
            if isVariation {
                body["nuance"] = "Do not try to move them onto the textbook version. They have "
                    + "control, which is the thing that mattered."
            }
            return json(body, evidence: evidence)
        }
    }

    // MARK: - Recording

    /// Nothing is written after the lesson is over. A cancelled check unwinds
    /// through here, and an attempt recorded against a screen the cook has
    /// already left is at best noise in their history.
    private func record(
        outcome: SkillAttemptOutcome,
        note: String,
        mistakeKey: String?,
        equipment: String?,
        confidence: Double,
        seconds: TimeInterval,
        startedAt: Date
    ) {
        let attempt = SkillAttempt(
            skillID: skill.id,
            checkID: check.id,
            startedAt: startedAt,
            seconds: seconds,
            outcome: outcome,
            note: note,
            mistakeKey: mistakeKey,
            equipmentReading: equipment,
            confidence: confidence)
        guard phase == .live, !Task.isCancelled else { return }
        attempts.append(attempt)
        guard let context else { return }
        let mastered = SkillProgressStore.recordAttempt(attempt, skill: skill, in: context)
        if mastered { stage = .learned }
    }

    private func finishLesson() {
        guard let context else { return }
        SkillProgressStore.markLearned(skill, in: context)
        stage = .learned
    }

    private func attemptOutcome(for outcome: SkillCoachDecision.Outcome) -> SkillAttemptOutcome {
        switch outcome {
        case .safetyStop: .stoppedForSafety
        case .unsupportedEquipment: .wrongEquipment
        case .cannotSee: .inconclusive
        case .correct: .corrected
        case .passed: .passed
        }
    }

    private func mistakeKey(of outcome: SkillCoachDecision.Outcome) -> String? {
        if case .correct(let key, _) = outcome { return key }
        return nil
    }

    private func json(_ body: [String: String], evidence: [String] = []) -> String {
        // Every payload carries the line she owes the cook, so the follow up can
        // be steered with it. Captured here rather than at each call site
        // because a result that silently fails to get said is the worst bug this
        // feature can have, and it should not depend on remembering.
        pendingSay = body["say"] ?? ""
        var object: [String: Any] = body
        if !evidence.isEmpty { object["evidence"] = evidence }
        object["attemptsSoFar"] = attempts.count
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"outcome":"cannot_see"}"#
        }
        return text
    }
}
