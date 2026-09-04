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
    /// How each part of the grip is doing, filled in as she looks.
    ///
    /// Derived from the assessment rather than announced: a region she could see
    /// on a look that found no fault with it is a part that is right. The model
    /// is asked for nothing extra to make this work.
    private(set) var partStates: [String: SkillPartState] = [:]

    /// The part she is talking about right now, if she has said.
    private(set) var focusedPart: SkillVisibilityRegion?

    /// Whether the demonstration clip is up on the cook's screen.
    ///
    /// Driven by her, through `show_the_video`, and by a button for the times
    /// she mishears. Lives on the session rather than in the view because she is
    /// the one who usually opens it and the view has no idea she was asked.
    private(set) var showingDemonstration = false

    var parts: [SkillCheckPart] { check.parts }

    func state(of part: SkillCheckPart) -> SkillPartState {
        partStates[part.region.rawValue] ?? .unknown
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

    /// How many waiting facts this lesson has spent, so a cook who looks four
    /// times hears four different things rather than the same one four times.
    private var factsUsed = 0

    /// Set the moment a look produces an answer, so the filler knows whether it
    /// is still wanted.
    private var lookAnswered = false

    /// Whether the glasses were up a moment ago, so losing them can be told
    /// apart from never having had them.
    private var hadSight = false

    /// Whether she has said anything since the last tool call, which is how a
    /// dead end is told apart from a tool that behaved.
    private var spokeSinceTool = true
    private var deadEndTask: Task<Void, Never>?

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

    /// When we last said a look out loud without being asked, so a tool call
    /// that arrives late does not make her repeat herself.
    private var deliveredLookAt: Date?

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
            tools: SkillCoachPrompt.tools(for: skill),
            voice: token.voice,
            model: token.model,
            transcribeInput: true,
            audioPinnedAtMint: true
        )

        // Connecting is a network call and network calls fail. A device log has
        // this returning "Chef isn't connected yet" 1.8 seconds in, on the same
        // path that had worked a dozen times, which is what a transient POST
        // failure looks like. One attempt and a dead session is the wrong answer
        // to that, and it is a particularly bad one here because the screen had
        // nothing to say about it.
        var connectError: Error?
        for attempt in 1...3 {
            do {
                try await transport.connect(token: token.value, model: token.model)
                (transport as? RealtimeWebRTCTransport)?.applyAudioLabAndReport()
                try await transport.send(.sessionUpdate(config))
                connectError = nil
                break
            } catch {
                connectError = error
                PollyDebugLog.shared.log(
                    "skill: connect failed on try \(attempt) — \(error.localizedDescription)")
                // Close before trying again, and before giving up.
                //
                // Each `connect` builds a peer connection and claims the audio
                // session on the way to failing, and none of that unwinds by
                // itself. Retrying without this leaks one per attempt and leaves
                // the microphone held, so a single bad minute from the API takes
                // the whole app down with it: the next cook cannot connect
                // either, and force quitting is the only way back.
                await transport.close()
                guard attempt < 3 else { break }
                try? await Task.sleep(for: .seconds(Double(attempt)))
            }
        }
        if let connectError {
            self.transport = nil
            phase = .failed(connectError.localizedDescription)
            PollyDebugLog.shared.log("skill: gave up connecting, audio released")
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
    /// Get the glasses up, and KEEP them up for the rest of the lesson.
    ///
    /// This used to return the moment they connected, and a device log shows
    /// what that cost. The glasses came up at 1.3 seconds, died at 10.0 with
    /// "session error, session ended by device", and nothing noticed: no
    /// reconnect, no word to the cook, and no camera for the remaining seventy
    /// seconds of the lesson. She carried on teaching a grip she could not see,
    /// and the cook carried on holding a knife up to nothing.
    ///
    /// A one shot connect is the wrong shape for hardware on somebody's face
    /// that can be taken off, walk out of range, or drop its session on its own.
    /// This watches for the rest of the lesson.
    private func startGlasses() {
        glassesTask?.cancel()
        glassesTask = Task { [weak self] in
            var attempt = 0
            while true {
                guard let self, !Task.isCancelled, self.phase != .ended else { return }
                guard self.visuals.glassesPossible else { return }

                if self.visuals.activeKind == .metaGlasses {
                    // Up. Watch rather than return.
                    attempt = 0
                    self.hadSight = true
                    try? await Task.sleep(for: .seconds(Self.glassesWatchIntervalSeconds))
                    continue
                }

                attempt += 1
                if attempt == 1, self.hadSight {
                    // Tell her she has gone blind, or she keeps offering to look
                    // at something she can no longer see.
                    self.hadSight = false
                    PollyDebugLog.shared.log("skill: the glasses went, reaching for them again")
                    await self.refreshSightIfNeeded()
                }
                PollyDebugLog.shared.log("skill: reaching for the glasses (try \(attempt))")
                // Before the stream is configured, not after: the resolution is
                // read when the camera opens.
                self.visuals.preferHighestDetail()
                await self.visuals.startGlassesIfAvailable()
                if self.visuals.activeKind == .metaGlasses {
                    PollyDebugLog.shared.log("skill: glasses up on try \(attempt)")
                    self.hadSight = true
                    await self.refreshSightIfNeeded()
                    continue
                }

                // Back off, but never give up entirely: a cook who puts the
                // glasses back on two minutes in should get a lesson that can
                // see, without restarting anything.
                let wait = min(30, Double(attempt) * 4)
                try? await Task.sleep(for: .seconds(wait))
            }
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

        // Saying her name over her stops her, which the cook session has always
        // done and this one never did.
        //
        // The mic was opened and she carried on talking, so a cook who wanted to
        // stop her had to wait out the sentence and say it again. Cancelling the
        // response is only half of it: the audio already sent is sitting in the
        // output buffer and keeps playing after the response is gone, so the
        // buffer is cleared too. Same pair, same order, as `PollySessionController`.
        guard isSpeaking, let transport else { return }
        Task {
            try? await transport.send(.responseCancel)
            try? await transport.send(.outputAudioBufferClear)
            PollyDebugLog.shared.log("skill: cut her off, they said her name over her")
        }
    }

    /// Back to waiting for the word.
    private func goDormant(reason: String) {
        dormancyTask?.cancel()
        dormancyTask = nil
        guard isAwake else { return }

        // Not while the clip is on screen.
        //
        // A device log has the mic closing at 80.46s with the demonstration
        // still playing. A cook watching a clip is exactly the person about to
        // say "can you play that again" or "wait, which finger", and they would
        // have been talking to a closed microphone.
        if showingDemonstration {
            PollyDebugLog.shared.log("skill: staying awake, the clip is still on screen")
            armDormancy(after: PollyConfig.maxListeningSeconds)
            return
        }
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

    /// Start over after a failed connect, without leaving the lesson.
    func retry(context: ModelContext) async {
        guard case .failed = phase else { return }
        await end()
        phase = .idle
        transport = nil
        stage = .teaching
        caption = ""
        await start(context: context)
    }

    func end() async {
        frames.stop()
        earlyLook?.cancel()
        deadEndTask?.cancel()
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
            spokeSinceTool = true
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
        // Cleared no matter which tool ran, and a watchdog armed behind it.
        //
        // `isThinking` was set the moment a tool call arrived and only cleared
        // inside `reply()`. `focus_on` and `show_the_video` never call `reply`,
        // so it stayed true for the rest of the lesson: the screen said
        // "thinking" forever, and `isListening` is gated on `!isThinking`, so
        // the lesson stopped showing itself as listening too. One missing line
        // took out the status display and the listening indicator together.
        defer {
            isThinking = false
            armDeadEndWatchdog(after: call.name)
        }

        switch call.name {
        case "check_the_hold":
            // She may be asking for a look we already gave. That happens when
            // she took longer than the grace period to call the tool: the answer
            // has been said, the cook has already acted on it, and looking again
            // would talk over them with a verdict about a hand that has moved.
            if let delivered = deliveredLookAt,
               deps.now().timeIntervalSince(delivered) < Self.recentlyDeliveredWindow {
                PollyDebugLog.shared.log("skill: that look was already given, not repeating it")
                // Answered without starting a turn, exactly like `focus_on`.
                // She has already said the verdict out loud; a bare
                // response.create here just invents a second sentence about a
                // hand that has moved since.
                try? await transport?.send(.createFunctionOutput(
                    callId: call.callId,
                    output: #"{"outcome":"already_answered","note":"You just told them this. Say nothing further about it."}"#))
                return
            }
            let payload = await runHoldAndAssess(announce: false)
            await reply(to: call, with: payload)
        case "focus_on":
            let raw = Self.stringArgument("part", from: call.argumentsJSON) ?? ""
            focusedPart = check.parts.first { $0.region.rawValue == raw }?.region
            let part = focusedPart
            PollyDebugLog.shared.log("skill: focused on \(part?.rawValue ?? "nothing (\(raw))")")
            try? await transport?.send(.createFunctionOutput(
                callId: call.callId, output: #"{"showing":true}"#))

            // Then CARRY ON TEACHING. This used to create nothing at all.
            //
            // The old reasoning was that she is mid sentence and asking her to
            // speak again would repeat it. That is simply not true: tool calls
            // arrive on `response.done`, so by the time this runs her turn has
            // already finished. A device log shows the whole cost. The cook
            // asked her to explain it, she said "alright, let's walk through it
            // piece by piece", called `focus_on`, and stopped. Fifteen seconds
            // of nothing, then dormant. The screen said "thinking" the entire
            // time.
            await startSpeaking(
                "You just highlighted \(part?.spokenName ?? "that part") on their screen. "
                + "Now teach it. One clear instruction about that part and what it should feel "
                + "like, then stop and let them try it. Do not announce what you are about to "
                + "do, and do not repeat the sentence you just said.")
        case "show_the_video":
            showDemonstration()
            try? await transport?.send(.createFunctionOutput(
                callId: call.callId, output: #"{"showing":true}"#))

            // She TALKS OVER the clip. That is the whole point of playing it.
            //
            // This used to create no response at all, on the reasoning that she
            // was mid sentence saying "here it is". A device log shows what
            // actually happened: the clip went up at 63.0s, she stopped talking
            // at 65.5s, and it played out the remaining fifteen seconds in
            // silence. A cook watching a clip on their own could have found that
            // on the internet.
            await startSpeaking(
                "The demonstration clip is on their screen now and it loops silently. Talk them "
                + "through it while they watch, pointing at what is happening: where the thumb "
                + "sits, what the bottom fingers are doing, what to look at. Keep going for a "
                + "few sentences, the way you would if you were stood beside them pointing at a "
                + "screen. Then ask whether that made sense and whether they want to see it "
                + "again, and tell them what to do when they are ready to try it themselves.")
        case "finish_lesson":
            finishLesson()
            await reply(to: call, with: #"{"done":true}"#)
        default:
            await reply(to: call, with: #"{"error":"unknown tool"}"#)
        }
    }

    func showDemonstration() {
        guard skill.animationAsset != nil, !showingDemonstration else { return }
        showingDemonstration = true
        PollyDebugLog.shared.log("skill: showing the demonstration")
    }

    func hideDemonstration() {
        guard showingDemonstration else { return }
        showingDemonstration = false
        PollyDebugLog.shared.log("skill: demonstration closed")
    }

    /// One string out of a tool call, without decoding a whole struct for it.
    private static func stringArgument(_ key: String, from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object[key] as? String
    }

    private func reply(to call: RealtimeFunctionCall, with output: String) async {
        try? await transport?.send(.createFunctionOutput(callId: call.callId, output: output))

        // Steered rather than open ended. She called this tool in the same
        // breath as "hold it there for five seconds", so as far as the model is
        // concerned it has already spoken this turn and a bare response.create
        // frequently returns silence. The cook is standing there holding a
        // knife waiting to be told what happened, so the one thing that cannot
        // be left to chance is that she says it.
        let line = pendingSay
        pendingSay = ""
        await startSpeaking(line.isEmpty ? nil :
            "You have just looked at their hand. Tell them what you found now, in your own "
            + "words, leading with this and nothing else: \"\(line)\" "
            + "Keep it to a sentence or two. Do not add a second correction, do not repeat "
            + "the instruction you gave before the hold, and do not thank them for waiting.")
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
        // A fresh question is not the old one. Without this, a cook who fixed
        // their grip and asked again inside the window would have the new look
        // suppressed as a duplicate of the answer to the previous one.
        deliveredLookAt = nil
        stage = .analysing
        earlyLookStartedAt = deps.now()
        let ring = frames
        let check = check
        let assess = deps.assess
        earlyLook = Task {
            // Watch them turn it BEFORE reading anything.
            //
            // A look used to fire on the instant the cook stopped speaking, so
            // it read the pose they were in while asking rather than the one
            // they were about to show. The lesson tells them to turn their hand
            // slowly, because the thumb is on one face of the blade and the
            // curled index finger on the other and no single moment shows both,
            // and then it never gave them time to turn it. The bridging line,
            // "right, let me have a look", plays through exactly this window,
            // so the wait costs nothing anybody notices.
            try? await Task.sleep(for: .seconds(Self.turnYourHandSeconds))
            var shots = ring.spread(check.framesPerLook, within: check.lookbackSeconds)
            if shots.isEmpty {
                await ring.fillNow(upTo: check.framesPerLook)
                shots = ring.spread(check.framesPerLook, within: check.lookbackSeconds)
            }
            guard !shots.isEmpty else { throw SkillVisualAssessor.AssessorError.noUsableFrames }
#if DEBUG
            // Marked so a discarded one does not read as a broken check later.
            return try await SkillLookArchive.$origin.withValue(.speculative) {
                try await assess(check, shots)
            }
#else
            return try await assess(check, shots)
#endif
        }
        PollyDebugLog.shared.log("skill: looking already, before she answered")

        // If she never calls the tool, say the answer anyway.
        //
        // This used to throw the look away after twenty seconds, and a device
        // log showed exactly what that costs. The cook asked "does this look
        // good?", the look started on the spot and finished, and she answered
        // by calling `focus_on`, which updates the screen and deliberately does
        // not start a turn. So nothing was ever said. The lesson sat there for
        // twenty seconds, binned a completed assessment, and went dormant with
        // the cook still holding the knife up waiting.
        //
        // A finished answer to a question the cook actually asked is never
        // thrown away now. If she has not claimed it, we say it for her.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.unclaimedLookGrace))
            guard let self, self.earlyLook != nil else { return }
            await self.deliverUnclaimedLook()
        }
    }

    /// How long she gets to ask for the look herself before we deliver it.
    ///
    /// Long enough that the ordinary path, where she calls the tool a second or
    /// two after the cook finishes speaking, always wins. Short enough that a
    /// cook holding a knife up is not left waiting on a turn that is never
    /// coming.
    /// How long the cook gets to turn their hand before anything is read.
    /// How often to check the glasses are still there once they are up.
    static let glassesWatchIntervalSeconds: TimeInterval = 3

    /// How long a tool call gets to be followed by speech before the lesson
    /// assumes it dead ended. Comfortably longer than the gap between a tool
    /// result and her next word, comfortably shorter than a cook giving up.
    static let deadEndGraceSeconds: TimeInterval = 4

    static let turnYourHandSeconds: TimeInterval = 4

    /// How long a look gets to answer on its own before anything fills the gap.
    ///
    /// 3.5 was too eager. The fast path answers in the high single digits, so a
    /// fact started at 3.5 seconds and the verdict arrived on top of it: the
    /// cook got the fact AND the answer, which is exactly the clutter the fact
    /// was meant to prevent.
    ///
    /// 7 sits past where most fast answers land and well short of the twenty to
    /// thirty seconds a rubric request takes. The cost is up to seven seconds of
    /// quiet after they ask, which reads as somebody looking rather than
    /// somebody who has crashed. Going much further would leave a slow look in
    /// silence, which is the problem the facts were written for.
    static let fillerHeadStartSeconds: TimeInterval = 7

    static let unclaimedLookGrace: TimeInterval = 8

    /// How long after saying a look unprompted a tool call counts as asking for
    /// the same one.
    static let recentlyDeliveredWindow: TimeInterval = 15

    /// Say the result of a look nobody asked for out loud.
    ///
    /// Goes through the same steering as a tool reply, because a bare
    /// `response.create` here returns silence often enough to be the bug all
    /// over again.
    private func deliverUnclaimedLook() async {
        guard phase == .live, earlyLook != nil else { return }
        PollyDebugLog.shared.log("skill: she never asked for the look, delivering it anyway")

        _ = await runHoldAndAssess(announce: true)
        guard phase == .live else { return }

        let line = pendingSay
        pendingSay = ""
        guard !line.isEmpty else { return }

        deliveredLookAt = deps.now()
        await startSpeaking(
            "You have just looked at their hand. Tell them what you found now, in your own "
            + "words, leading with this and nothing else: \"\(line)\" "
            + "Keep it to a sentence or two. Do not add a second correction and do not "
            + "thank them for waiting.")
        isThinking = false
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
        // Looking at their hands and showing them a video are mutually
        // exclusive: a cook watching the clip is holding their phone up, so the
        // frames would be of a screen. Closing it here rather than asking them
        // to means she never has to say "put that away first".
        hideDemonstration()

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
        // Only fill the silence if there is going to be one.
        //
        // The single question can now answer in a few seconds, and starting a
        // twenty five second fact in front of a three second answer means
        // cutting her off mid sentence, which is worse than the silence it was
        // meant to cover. So the filler waits to find out whether it is needed.
        lookAnswered = false
        let fillerHeadStart = Self.fillerHeadStartSeconds
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(fillerHeadStart))
            guard let self, !self.lookAnswered, self.phase == .live else { return }
            await self.speakWhileLooking()
        }

        let assessment: SkillVisualAssessment
        do {
            if let running = earlyLook {
                // Claimed BEFORE the await, not after, and that ordering is the
                // whole bug.
                //
                // `await` suspends, so with the clearing underneath it two
                // callers both passed this `if let`, both waited on the same
                // task, and both went on to speak. A device log caught it
                // exactly: the tool called at 23.7s and the eight second grace
                // timer fired at 28.7s still seeing a look nobody had claimed,
                // so the cook heard "let me have a look" twice and then got the
                // same verdict twice, forty six seconds later.
                earlyLook = nil
                earlyLookStartedAt = nil
                assessment = try await running.value
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
        } catch VisualFrameRejection.subjectTooFar {
            // Its own answer, not a generic failure. "I could not see" is wrong
            // here: she CAN see them, they are just across the room from the
            // camera, and the fix is one specific thing they can do.
            earlyLook = nil
            return handleUnusable(
                reason: .subjectTooFar,
                seconds: deps.now().timeIntervalSince(started),
                startedAt: started)
        } catch SkillVisualAssessor.AssessorError.noUsableFrames {
            earlyLook = nil
            return handleUnusable(
                reason: .noFrames,
                seconds: deps.now().timeIntervalSince(started),
                startedAt: started)
        } catch {
            earlyLook = nil
            PollyDebugLog.shared.log("skill: assessment FAILED — \(error.localizedDescription)")
            // A dropped request is not a camera fault, and telling a cook their
            // glasses failed when the network did sends them to fix hardware
            // that is working.
            // Anything that is not the camera is not "I cannot see".
            //
            // A cook watching the live panel fill with frames, being told there
            // is no view, goes and fiddles with their glasses. The camera was
            // never the problem: the request failed, or the model was rejected,
            // or the proxy is not deployed. `noFrames` is reserved for an actual
            // absence of pictures now, which is the only case where asking them
            // to check the camera is honest.
            let cameraReallyFailed = error is SkillVisualAssessor.AssessorError
            return handleUnusable(
                reason: cameraReallyFailed ? .noFrames : .lookRequestFailed,
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

        updateParts(from: assessment, outcome: outcome)

        record(
            outcome: outcome.attemptOutcome,
            note: note,
            mistakeKey: outcome.mistakeKey,
            equipment: assessment.equipment.reading,
            confidence: assessment.confidence,
            seconds: deps.now().timeIntervalSince(started),
            startedAt: started)

        lookAnswered = true
        return payload(for: outcome, assessment: assessment)
    }

    private func speakWhileLooking() async {
        guard phase == .live, !responseInFlight else { return }
        responseInFlight = true

        // Fill the wait with something worth hearing.
        //
        // A look was timed at forty six seconds on a device, and what covered it
        // was "right, let me have a look" followed by nothing. A second filler
        // line would only have made it "still looking", which is worse: it says
        // the app is alive and has nothing to offer. So the wait carries the
        // reason the technique is shaped this way, which is the half of a lesson
        // that otherwise never gets said.
        let instructions: String
        if factsUsed < check.waitingFacts.count {
            let fact = check.waitingFacts[factsUsed]
            factsUsed += 1
            instructions =
                "You are looking at their hand right now and it will take a few seconds. "
                + "Say this, in your own words, keeping every part of the point: \"\(fact)\" "
                + "Do not rush it and do not summarise it down to one line, it is there to "
                + "fill the wait. Do not say anything about what you can see yet, because you "
                + "have not finished looking, and do not ask a question at the end."
            PollyDebugLog.shared.log("skill: filling the wait with fact \(factsUsed)")
        } else {
            instructions =
                "You are looking at their hand right now. Say ONE short line, six words or "
                + "fewer, that you are having a look. Do not ask a question and do not say "
                + "anything about what you can see yet."
            PollyDebugLog.shared.log("skill: bridging line while looking")
        }
        try? await transport?.send(.responseCreateWithInstructions(instructions))
    }

    /// Catch a turn that ended with a tool call and nothing said.
    ///
    /// The guarantee the cook asked for, in the only form that can actually be
    /// guaranteed: not "every tool remembers to speak", which is a promise about
    /// code nobody has written yet, but "if a tool call is followed by silence,
    /// something notices".
    ///
    /// It happened twice from the same cause. `focus_on` deliberately created no
    /// response on the false reasoning that she was mid sentence, when tool
    /// calls in fact arrive after the turn has finished. She said "let's walk
    /// through it piece by piece", highlighted a part, and stopped. Fifteen
    /// seconds of nothing, then dormant, with the screen showing "thinking".
    ///
    /// Only ever fires when NOTHING was said after the tool, so a tool that
    /// speaks properly never triggers it, and a cook being given time to try
    /// something is never nagged.
    private func armDeadEndWatchdog(after tool: String) {
        deadEndTask?.cancel()
        spokeSinceTool = false
        deadEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.deadEndGraceSeconds))
            guard let self, !Task.isCancelled, self.phase == .live else { return }
            guard !self.spokeSinceTool, !self.isSpeaking, !self.responseInFlight else { return }

            PollyDebugLog.shared.log("skill: \(tool) ended the turn in silence, picking it back up")
            await self.startSpeaking(
                "Your last turn ended without you saying anything, which leaves the cook staring "
                + "at a screen waiting. Carry straight on with the lesson from where you were. "
                + "Do not apologise, do not mention this, and do not start again from the "
                + "beginning.")
        }
    }

    /// Start her talking, having made sure she is not already.
    ///
    /// This is why she said the same thing twice. `waitForHerToFinish` spins for
    /// six seconds and then carries on whatever the answer was, so a response
    /// still in flight got a SECOND `response.create` stacked on top of it, both
    /// steered with the same sentence. Two responses, one line, said twice.
    ///
    /// Waiting longer would not fix it: sooner or later the wait times out and
    /// the same thing happens. The stale response has to actually go, and its
    /// audio with it, which is the pair `PollySessionController` has always used
    /// for barge-in.
    private func startSpeaking(_ instructions: String?) async {
        guard phase == .live, let transport else { return }
        await waitForHerToFinish()

        if responseInFlight {
            PollyDebugLog.shared.log("skill: she was still going, cutting the old response")
            try? await transport.send(.responseCancel)
            try? await transport.send(.outputAudioBufferClear)
            responseInFlight = false
        }

        responseInFlight = true
        if let instructions {
            try? await transport.send(.responseCreateWithInstructions(instructions))
        } else {
            try? await transport.send(.responseCreate)
        }
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
        lookAnswered = true
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
        case .confirmWithCook(let confirmed, let question):
            // A question, not a verdict, and deliberately so.
            //
            // The reading behind this caught every hand that really was closed
            // around a blade across the archive, and it also flagged two
            // textbook pinch grips. Asserting on a signal like that either
            // stops people who are doing it right or lets through people who
            // are not, depending on which way you lean it. Asking costs a cook
            // who is correct one word, and it is the only move in this whole
            // loop that consults the one person who can actually see the grip.
            stage = .coaching(outcome: .inconclusive)

            // She asked a question, so she has to be listening for the answer.
            //
            // A device log caught the opposite: the question went out at 46.96s
            // and the mic closed at 47.51s, half a second later, because the
            // dormancy clock had been running since before the look. The cook
            // answered into a dead microphone, had to say "Chef" again, and
            // came back with "why are you asking me that, just take another
            // look and decide yourself". Which is fair.
            if !isAwake { wakeUp() } else { armDormancy(after: PollyConfig.maxListeningSeconds) }

            // Lead with what IS right. A bare "are your fingers on the blade?"
            // reads as an accusation and throws away everything she did see,
            // when in this case the thumb and index were perfect and only the
            // bottom three were out of shot.
            // `spokenName` already carries "your", so this reads as
            // "Your thumb and your index finger are exactly right."
            let named = confirmed.map(\.spokenName).joined(separator: " and ")
            let praise = confirmed.isEmpty
                ? ""
                : "\(named.prefix(1).uppercased())\(named.dropFirst()) "
                    + "\(confirmed.count == 1 ? "is" : "are") exactly right. "
            return json([
                "outcome": "confirm_with_cook",
                "say": "\(praise)I could not see the rest clearly, so tell me: \(question)",
                "then": "Wait for their answer and believe it. If they say the handle, tell them "
                    + "that is the grip and move on. If they say the blade, tell them calmly to "
                    + "put it down and slide their hand back behind the collar onto the handle, "
                    + "then look again. Do not repeat the question, do not lecture, and do not "
                    + "make them ask you to look again.",
            ], evidence: evidence)

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
                // They have finished something. "Yep, that is it" is what you
                // say to a passing glance, not to somebody who has just learned
                // a thing they will use every day for the rest of their life.
                "say": isVariation
                    ? "That is a little different from the textbook pinch, and you have got good "
                        + "control of the knife, so I am happy with it. Nicely done."
                    : "That is it. That is the pinch grip, you have got it.",
                "then": "Congratulate them properly and tell them the skill is done, in one "
                    + "sentence, warmly and without gushing. Name what they got right using the "
                    + "evidence. Then ask whether it feels comfortable or tense, because you "
                    + "cannot see that. If they say it is fine, call finish_lesson.",
            ]
            if isVariation {
                body["nuance"] = "Do not try to move them onto the textbook version. They have "
                    + "control, which is the thing that mattered."
            }
            return json(body, evidence: evidence)
        }
    }

    /// Fill in the grip from what she just saw.
    ///
    /// A part goes green when she has seen it and had nothing to say about it,
    /// and amber when it is the one thing being corrected. A part she could not
    /// see stays blank rather than going green or red, because not seeing
    /// something is not a verdict on it, and a screen that pretends otherwise is
    /// the same lie the spoken side spent this whole build learning not to tell.
    private func updateParts(
        from assessment: SkillVisualAssessment,
        outcome: SkillCoachDecision.Outcome
    ) {
        // Nothing was judged, so nothing changes.
        switch outcome {
        case .cannotSee, .unsupportedEquipment, .safetyStop, .confirmWithCook: return
        case .correct, .passed: break
        }

        let failing: SkillVisibilityRegion? = {
            guard case .correct(let key, _) = outcome else { return nil }
            return SkillCoachDecision.mistake(for: key, in: check)?.requiresVisible.first
        }()

        for part in check.parts {
            if part.region == failing {
                partStates[part.region.rawValue] = .needsFixing
            } else if assessment.visibility[part.region.rawValue]?.isUsable == true {
                partStates[part.region.rawValue] = .good
            }
        }
        let done = check.parts.filter { partStates[$0.region.rawValue] == .good }.count
        PollyDebugLog.shared.log("skill: grip \(done)/\(check.parts.count) parts confirmed")
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
