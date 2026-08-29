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
        /// She is looking. There is no hold to sit through: the frames already
        /// exist, so this covers the vision call and nothing else.
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
    /// Which written step she is teaching, zero based.
    ///
    /// Reported by her rather than inferred, because inferring it from what she
    /// says is guesswork and a screen showing the wrong instruction to somebody
    /// holding a knife is worse than a screen showing none.
    private(set) var stepIndex = 0

    /// The steps as written on the lesson screen, so both surfaces say the same
    /// words.
    var steps: [String] { skill.lesson?.steps ?? [] }
    var currentStep: String? {
        steps.indices.contains(stepIndex) ? steps[stepIndex] : steps.first
    }

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
    /// A look is in progress, so nothing else gets to close the mic.
    private var isMidCheck: Bool {
        if case .analysing = stage { return true }
        return false
    }

    var isListening: Bool {
        guard phase == .live, isAwake, !isSpeaking, !isThinking else { return false }
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
    /// Keeps trying to bring the glasses up for as long as the lesson lasts.
    private var glassesTask: Task<Void, Never>?
    /// The last few seconds of what they were looking at, kept warm.
    private let frames: SkillFrameRing
    /// A look started the moment they asked, before she had answered.
    private var earlyLook: Task<SkillVisualAssessment, Error>?
    private var earlyLookStartedAt: Date?
    /// The live session config, so the prompt can be re-sent when what she can
    /// see changes.
    private var liveConfig: RealtimeSessionConfig?
    /// What the prompt currently claims about her eyesight.
    private var promptAssumesSight = false
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

    /// The cook spoke while she was mid answer. Held rather than dropped: they
    /// said a whole sentence and got silence for it, which is the behaviour this
    /// whole lesson keeps being accused of.
    private var deferredTurn = false

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
        self.frames = SkillFrameRing(visuals: visuals, clock: deps.now)
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

        // Keep trying, in the background.
        //
        // `startGlassesIfAvailable` gives the toolkit four seconds to enumerate a
        // device and then gives up for good. Sometimes that is plenty and the
        // camera is streaming in under a second; sometimes the selector has not
        // observed the glasses yet and it times out, and a device log has both
        // happening on the same pair of glasses minutes apart. Awaiting one
        // attempt at session start meant losing that coin flip disabled the
        // entire feature for the whole lesson, on hardware that was sitting
        // there connected: the audio route in the same log was already the
        // glasses. So it retries, and the lesson does not wait for it.
        startGlasses()

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

        liveConfig = config
        promptAssumesSight = visuals.activeKind == .metaGlasses
        phase = .live
        stage = .teaching
        frames.start()
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

    /// Bring the glasses up, and keep trying.
    ///
    /// The gaps get longer rather than hammering: a cook who has not put them on
    /// yet will put them on in the next minute, and a cook who has none is
    /// costing us nothing but a few log lines.
    private func startGlasses() {
        glassesTask?.cancel()
        glassesTask = Task { [weak self] in
            let waits: [TimeInterval] = [0, 4, 8, 15, 25]
            for (attempt, wait) in waits.enumerated() {
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard let self, !Task.isCancelled, self.phase != .ended else { return }
                if self.visuals.activeKind == .metaGlasses { return }
                guard self.visuals.glassesPossible else { return }
                PollyDebugLog.shared.log("skill: reaching for the glasses (try \(attempt + 1))")
                await self.visuals.startGlassesIfAvailable()
                if self.visuals.activeKind == .metaGlasses {
                    PollyDebugLog.shared.log("skill: glasses up on try \(attempt + 1)")
                    await self.refreshSightIfNeeded()
                    return
                }
            }
            PollyDebugLog.shared.log("skill: gave up on the glasses")
        }
    }

    /// Re-send the prompt when what she can see stops matching what she was told.
    ///
    /// Glasses that arrive thirty seconds in are the normal case, not the edge
    /// one, and without this she spends the rest of the lesson insisting she
    /// cannot see through a camera that is streaming.
    private func refreshSightIfNeeded() async {
        let seesNow = visuals.activeKind == .metaGlasses
        guard seesNow != promptAssumesSight, var config = liveConfig else { return }
        config.instructions = SkillCoachPrompt.instructions(
            skill: skill, check: check, seesContinuously: seesNow)
        liveConfig = config
        promptAssumesSight = seesNow
        try? await transport?.send(.sessionUpdate(config))
        PollyDebugLog.shared.log(
            "skill: sight rules updated — \(seesNow ? "she can see now" : "no camera")")
    }

    /// Turn what the cook just said into a turn she answers.
    private func commitTurn() async {
        guard phase == .live else { return }
        guard !responseInFlight else {
            deferredTurn = true
            PollyDebugLog.shared.log("skill: turn deferred (response in flight)")
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
        frames.stop()
        earlyLook?.cancel()
        glassesTask?.cancel()
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
            //
            // Except mid check. Her "hold that for me" ends while the five
            // seconds and the assessment are still running, and re-arming the
            // short window there closed the mic underneath a cook who was doing
            // exactly what they were told: the log has `dormant (nothing said)`
            // landing in the middle of a look. The hold owns the clock until it
            // is finished.
            if isAwake, !isMidCheck {
                armDormancy(after: PollyConfig.initialListenWindowSeconds)
            }
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
            // Start looking now, not when she gets round to it.
            //
            // She takes a second or two to decide to call the tool and another
            // second or two to say "let me have a look", and every bit of that is
            // the cook holding a knife up at nothing. Reading the request
            // ourselves means the eyes and the mouth start at the same moment.
            if SkillLookRequest.isAskingToBeSeen(text) { beginEarlyLook() }

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
            // Answer whatever they said while she was talking.
            if deferredTurn, calls.isEmpty {
                deferredTurn = false
                await commitTurn()
            }
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
        case "teaching_step":
            let asked = (Self.argument("number", from: call.argumentsJSON) ?? 1) - 1
            stepIndex = min(max(asked, 0), max(steps.count - 1, 0))
            PollyDebugLog.shared.log("skill: now teaching step \(stepIndex + 1) of \(steps.count)")
            // No response.create: this is a screen update, not a turn. Asking her
            // to speak again here would make her repeat the step she is already
            // in the middle of saying.
            try? await transport?.send(.createFunctionOutput(
                callId: call.callId, output: #"{"showing":true}"#))
        case "finish_lesson":
            finishLesson()
            await reply(to: call, with: #"{"done":true}"#)
        default:
            await reply(to: call, with: #"{"error":"unknown tool"}"#)
        }
    }

    /// One integer out of a tool call, without decoding a whole struct for it.
    private static func argument(_ key: String, from json: String) -> Int? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let number = object[key] as? NSNumber { return number.intValue }
        if let text = object[key] as? String { return Int(text) }
        return nil
    }

    private func reply(to call: RealtimeFunctionCall, with output: String) async {
        try? await transport?.send(.createFunctionOutput(callId: call.callId, output: output))
        await waitForHerToFinish()

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

    /// Look now, from frames we already have.
    ///
    /// No countdown and no hold. See `SkillFrameRing`: the camera has been
    /// streaming since the lesson opened, so a look is a read from memory. The
    /// only thing worth waiting for is the vision call, and even that has
    /// usually been running since the cook finished their sentence.
    private func beginEarlyLook() {
        guard phase == .live, earlyLook == nil, visuals.activeKind != nil else { return }
        stage = .analysing
        earlyLookStartedAt = deps.now()
        let ring = frames
        let check = check
        let assess = deps.assess
        earlyLook = Task {
            var shots = ring.spread(check.framesPerLook, within: check.lookbackSeconds)
            if shots.isEmpty {
                await ring.fillNow(upTo: check.framesPerLook)
                shots = ring.spread(check.framesPerLook, within: check.lookbackSeconds)
            }
            guard !shots.isEmpty else { throw SkillVisualAssessor.AssessorError.noUsableFrames }
            return try await assess(check, shots)
        }
        PollyDebugLog.shared.log("skill: looking already, before she answered")

        // If she never actually calls the tool, do not leave the screen looking
        // like it is mid check forever.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, self.earlyLook != nil else { return }
            self.discardEarlyLook(reason: "nobody used it")
        }
    }

    private func discardEarlyLook(reason: String) {
        guard earlyLook != nil else { return }
        earlyLook?.cancel()
        earlyLook = nil
        earlyLookStartedAt = nil
        if case .analysing = stage { stage = .teaching }
        PollyDebugLog.shared.log("skill: early look discarded (\(reason))")
    }

    /// Look, decide, record. The one path the tool and the retry both use.
    private func runHoldAndAssess(announce: Bool) async -> String {
        // Last chance to get the camera up before we photograph nothing.
        //
        // A cook who asks to be looked at has almost certainly just put the
        // glasses on, which is exactly the moment the earlier attempts would
        // have failed and this one will not.
        if visuals.activeKind == nil, visuals.glassesPossible {
            PollyDebugLog.shared.log("skill: no camera at check time, trying the glasses again")
            await visuals.startGlassesIfAvailable()
            await refreshSightIfNeeded()
        }

        let started = earlyLookStartedAt ?? deps.now()
        stage = .analysing
        // Do not let the mic close underneath a look that is still running.
        if isAwake { armDormancy(after: PollyConfig.maxListeningSeconds) }

        // Say something while it runs. Usually this is the only thing the cook
        // waits for, because the looking started when they asked.
        await speakWhileLooking()

        let assessment: SkillVisualAssessment
        do {
            if let running = earlyLook {
                // Already started when they asked. This is the ordinary path.
                assessment = try await running.value
                earlyLook = nil
                earlyLookStartedAt = nil
                PollyDebugLog.shared.log(
                    "skill: used the early look (\(String(format: "%.1f", deps.now().timeIntervalSince(started)))s old)")
            } else {
                var shots = frames.spread(check.framesPerLook, within: check.lookbackSeconds)
                if shots.isEmpty {
                    await frames.fillNow(upTo: check.framesPerLook)
                    shots = frames.spread(check.framesPerLook, within: check.lookbackSeconds)
                }
                guard !shots.isEmpty else {
                    return handleUnusable(
                        reason: .noFrames,
                        seconds: deps.now().timeIntervalSince(started),
                        startedAt: started)
                }
                assessment = try await deps.assess(check, shots)
            }
        } catch is CancellationError {
            return handleUnusable(
                reason: .noFrames, seconds: 0, startedAt: started)
        } catch SkillVisualAssessor.AssessorError.noUsableFrames {
            earlyLook = nil
            return handleUnusable(
                reason: .noFrames,
                seconds: deps.now().timeIntervalSince(started),
                startedAt: started)
        } catch {
            earlyLook = nil
            PollyDebugLog.shared.log("skill: assessment FAILED — \(error.localizedDescription)")
            return handleUnusable(
                reason: .noFrames,
                seconds: deps.now().timeIntervalSince(started),
                startedAt: started)
        }

        let outcome = SkillCoachDecision.decide(assessment, check: check)
        let note = SkillCoachDecision.note(for: outcome, assessment: assessment, check: check)

        // The whole reading, not just the verdict.
        //
        // When she says she cannot see something, the only way to tell a genuine
        // occlusion from a model being timid is to know what it reported for
        // every region and what it claimed to have observed. Without this the
        // log says "cannotAssess" and there is nothing to argue with.
        let seen = check.reportedVisibility
            .map { "\($0.rawValue)=\(assessment.visibility[$0.rawValue]?.rawValue ?? "-")" }
            .joined(separator: " ")
        PollyDebugLog.shared.log(
            "skill: assessed \(assessment.overall.rawValue) "
                + "conf=\(String(format: "%.2f", assessment.confidence)) -> \(note)")
        PollyDebugLog.shared.log("skill: visibility \(seen)")
        PollyDebugLog.shared.log(
            "skill: knife \"\(assessment.equipment.reading)\" "
                + "supported=\(assessment.equipment.supported) "
                + "conf=\(String(format: "%.2f", assessment.equipment.confidence))")
        for line in assessment.observedEvidence {
            PollyDebugLog.shared.log("skill: saw \(line)")
        }

        record(
            outcome: attemptOutcome(for: outcome),
            note: note,
            mistakeKey: mistakeKey(of: outcome),
            equipment: assessment.equipment.reading,
            confidence: assessment.confidence,
            seconds: deps.now().timeIntervalSince(started),
            startedAt: started)

        return payload(for: outcome, assessment: assessment)
    }

    private func speakWhileLooking() async {
        guard phase == .live, !responseInFlight else { return }
        responseInFlight = true
        try? await transport?.send(.responseCreateWithInstructions(
            "You are looking at their hand right now. Say ONE short line, six words or fewer, "
            + "that you are having a look. Something like \"right, let me have a look\" or "
            + "\"okay, looking now\". Do not ask a question and do not say anything about what "
            + "you can see yet, because you have not finished looking."))
        PollyDebugLog.shared.log("skill: bridging line while looking")
    }

    /// Do not talk over the bridging line with the verdict.
    private func waitForHerToFinish() async {
        if let webrtc = transport as? RealtimeWebRTCTransport {
            await webrtc.waitUntilAssistantQuiet(timeoutSeconds: 6)
        }
        var spins = 0
        while responseInFlight, spins < 60 {
            try? await Task.sleep(for: .milliseconds(100))
            spins += 1
        }
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
        // No frames at all is a different problem from a bad angle, and saying
        // "I cannot see your thumb" here would be inventing a reason.
        let reasonLine: String
        switch reason {
        case _ where visuals.activeKind == nil:
            // Not a bad angle and not a dark kitchen: there is no camera at all.
            // Saying anything about their grip here would be pure invention.
            reasonLine = visuals.glassesPossible
                ? "I have not got a camera yet. Your glasses are connected for audio but the "
                    + "camera has not come up, so give them a moment or take them off and put "
                    + "them back on."
                : "I cannot see anything at all, there are no glasses connected."
        case .warmingUp:
            reasonLine = "The camera on your glasses is still waking up, give it a second."
        case .tooDark:
            reasonLine = "It is too dark for me to make anything out."
        case .tooBright:
            reasonLine = "It is washed out, there is too much light coming in."
        case .blurred, .tooOld:
            reasonLine = "That came through too blurred to read."
        default:
            reasonLine = "I am not getting a picture from your glasses at the moment."
        }
        return json([
            "outcome": "cannot_see",
            "say": "\(reasonLine) \(check.retryFraming)",
            "then": "Say that, then call check_the_hold again. Be clear this is the camera and "
                + "not their grip.",
        ])
    }

    /// "I can see X, but not Y. Do Z."
    ///
    /// Built rather than authored because it depends on what actually happened.
    /// A cook standing there looking straight at their own hand and being told
    /// only "I cannot see it" has nothing to act on and no reason to believe the
    /// camera is working at all. Saying what came through first is also the
    /// honest order: it is the evidence, and the missing part is the conclusion.
    private func partialViewLine(
        missing: [SkillVisibilityRegion],
        assessment: SkillVisualAssessment
    ) -> String {
        let sawRegions = check.reportedVisibility.filter {
            assessment.visibility[$0.rawValue]?.isUsable == true
        }
        let seenPhrase = sawRegions.isEmpty
            ? "I have got a picture but I cannot make your hand out in it"
            : "I can see \(list(sawRegions.map(\.spokenName)))"

        guard let firstMissing = missing.first else {
            return "\(seenPhrase). \(check.retryFraming)"
        }
        let missingPhrase = "not \(list(missing.map(\.spokenName)))"
        return "\(seenPhrase), \(missingPhrase). "
            + "\(firstMissing.howToBringIntoView.prefix(1).uppercased())"
            + "\(firstMissing.howToBringIntoView.dropFirst())."
    }

    /// "a, b and c", so she does not read out a comma separated list.
    private func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " and " + last
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
                    "say": "\(partialViewLine(missing: regions, assessment: assessment)) "
                        + "I am not getting there though, so let me tell you what it should feel "
                        + "like instead and you can check it yourself.",
                    "then": "Describe what a correct grip feels like under the fingers. Do not "
                        + "ask them to reposition again, they have tried twice.",
                ], evidence: evidence)
            }
            stage = .coaching(outcome: .inconclusive)
            return json([
                "outcome": "cannot_see",
                "say": partialViewLine(missing: regions, assessment: assessment),
                "then": "Say that line, then call check_the_hold again once they have moved. "
                    + "Lead with what you CAN see so they know you are looking and know what to "
                    + "change. Never just say you cannot see and stop.",
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
