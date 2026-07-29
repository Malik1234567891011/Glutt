import Foundation
import Observation
import SwiftData

/// The session brain for one "Cook with Polly" session.
///
/// Orchestrates four isolated units — the realtime transport, the audio
/// engine, the camera controller, and the tool registry — plus plan
/// compilation and durable kitchen memory. All state is main-actor; the
/// session view (Task 15) renders it directly. Dependencies are closures
/// with a `.live` default (Plates pattern) so tests script every seam.
@MainActor
@Observable
final class PollySessionController {
    enum Phase: Equatable {
        case idle, compiling, connecting, live, reconnecting, ended, failed(String)
    }

    struct Dependencies {
        var mintToken: () async throws -> PollySessionToken
        var makeTransport: () -> RealtimeTransporting
        var compilePlan: (Recipe, Double) async -> CookPlan
        var extractMemories: (String, String) async throws -> PollyMemoryExtractor.Extraction
        var now: () -> Date

        static let live = Dependencies(
            mintToken: { try await PollyTokenService.live.mint() },
            makeTransport: { RealtimeWebSocketTransport() },
            compilePlan: { await CookPlanCompiler.compile(recipe: $0, scale: $1) },
            extractMemories: { try await PollyMemoryExtractor.extract(transcript: $0, recipeTitle: $1) },
            now: { .now }
        )
    }

    private(set) var phase: Phase = .idle
    private(set) var plan: CookPlan?
    /// Rolling last utterance line (user transcript or Polly's live caption).
    private(set) var captionText = ""
    /// Polly's latest spoken line (live-updating), shown large on screen so the
    /// cook can glance and confirm they didn't miss anything. Persists until her
    /// next utterance — the user's own speech never overwrites it.
    private(set) var pollyCaption = ""
    private(set) var isPollySpeaking = false
    private(set) var isListening = false
    /// True from any response.create until the first audio delta / response.done —
    /// drives the "thinking" state.
    private(set) var isThinking = false

    /// Wake-word / follow-up gate. Mic is open for `.listening` and `.followUp`.
    enum ListeningMode: Equatable {
        /// Realtime input muted — only on-device wake word runs.
        case dormant
        /// Engaged: capturing a user turn (after wake or mid-exchange).
        case listening
        /// Soft listen after Polly answered — no "Polly" needed until timeout.
        case followUp
    }
    private(set) var listeningMode: ListeningMode = .dormant
    /// Polly asked a question and is waiting for a short answer ("yeah"/"no").
    private(set) var expectsAnswer = false
    /// The cook's live on-device transcript, shown large while Listening.
    private(set) var liveTranscript = ""
    /// Master mute (the mic button): silences everything, including the wake word.
    private(set) var isHardMuted = false
    /// Whether on-device wake-word recognition is running this session. When false
    /// (e.g. simulator, Speech denied), the state pill is a tap-to-talk fallback.
    private(set) var wakeWordAvailable = false
    /// Soft UI flash after an acknowledgment was heard and suppressed.
    private(set) var lastAcknowledgedAt: Date?

    /// PantryMatcher misses, snapshotted during start() — drives the preflight card.
    private(set) var missingIngredients: [String] = []
    /// Set by the `end_session` tool; the session view observes it and calls `end`.
    private(set) var wantsEnd = false
    /// Watch-mode toggle (the eye button). Read once per watch tick.
    var isWatching = false
    /// Session start — used by the Cook Recap for elapsed time.
    private(set) var sessionStartedAt: Date?
    /// Optional plated-dish JPEG captured just before teardown.
    private(set) var plateJPEG: Data?
    /// Last PollyCookLog written in `end` — feeds the Cook Recap sheet.
    private(set) var lastCookLog: PollyCookLog?
    /// Polly Saves snapshotted at end (also on the cook log).
    private(set) var sessionSaves: [String] = []

    let audio: PollyAudioEngine
    let camera: PollyCameraController
    let wakeWord: WakeWordListening
    let timers = TimerManager()
    var registry: PollyToolRegistry?

    /// Activity-based follow-up: deadline moves when the user speaks.
    private var dormancyTask: Task<Void, Never>?
    private var followUpDeadline: Date?
    private var lastAssistantSpeechEndedAt: Date?
    private var lastWakeWordAt: Date?
    private var lastUserSpeechStartedAt: Date?
    private var lastUserTurnCommittedAt: Date?
    private var lastValidInteractionAt: Date?
    /// Polly's last spoken line asked a question (survives dormant gaps).
    private var lastAssistantAskedQuestion = false
    /// True from user-turn commit / tool round-trip until follow-up re-arms —
    /// keeps the dormancy watcher from closing mid-response.
    private var isHoldingForAssistant = false
    /// True between speechStarted and a gate decision while Polly is talking.
    private var bargeInCandidate = false
    /// Speech ended; waiting on ASR before we dare close the follow-up window.
    private var awaitingTranscript = false
    /// Consecutive uncertain/background rejects — close session if too many.
    private var consecutiveRejects = 0
    private var unfinishedHoldTask: Task<Void, Never>?

    var stepIndex: Int { registry?.state.stepIndex ?? 0 }

    /// Mic is open to the Realtime session (not dormant / hard-muted).
    var isEngaged: Bool {
        listeningMode == .listening || listeningMode == .followUp
    }

    /// Checklist boxes checked by the cook (tap) or by Polly (`check_step_actions`).
    /// Mirrored from the registry so SwiftUI Observation refreshes the guide.
    private(set) var checkedActionIDs: Set<String> = []
    /// Bumps when step index / checklist changes so the guide panel re-renders.
    private(set) var sessionUIEpoch: Int = 0

    /// Touch/swipe step navigation — keeps voice tools and UI in sync.
    func goToStep(_ index: Int) {
        registry?.jumpToStep(index)
        publishSessionUI()
    }

    func goToPreviousStep() {
        goToStep(stepIndex - 1)
    }

    func goToNextStep() {
        goToStep(stepIndex + 1)
    }

    func toggleChecklistItem(_ id: String) {
        registry?.toggleActionChecked(id)
        publishSessionUI()
    }

    private func publishSessionUI() {
        checkedActionIDs = registry?.state.checkedActionIDs ?? []
        sessionUIEpoch += 1
    }

    private let recipe: Recipe
    private let scale: Double
    private let heardBriefing: Bool
    private let awaitVerbalGo: Bool
    /// After a trailer handoff, keep the mic open until the cook speaks once
    /// (don't snap back to wake-word dormant on the follow-up timer).
    private var isAwaitingVerbalGo = false
    private let deps: Dependencies

    private var transport: RealtimeTransporting?
    private var eventTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var startedAt: Date?
    /// Config sent at session start; re-sent verbatim (new token's voice/model)
    /// on the single silent reconnect. Instructions/tools never mutate mid-cook
    /// so the realtime prompt cache stays warm.
    private var liveConfig: RealtimeSessionConfig?

    private var transcriptLog: [String] = []
    private var pendingAssistantItemId: String?
    private var pendingAssistantLine = ""
    /// The assistant audio item currently playing — the barge-in truncate target.
    private var currentAudioItemId: String?
    /// Player-node cumulative-ms baseline captured on the first audio delta of the
    /// current assistant item. `interruptPlayback()`/`currentPlayedMs()` count ms
    /// since the player node started (it never stops between turns), so this
    /// baseline is subtracted on barge-in to yield ms INTO the current item — the
    /// value `conversation.item.truncate` accepts. Forwarding the raw cumulative
    /// value would make truncate invalid on every barge-in after the first turn.
    private var itemStartPlayedMs = 0
    /// Total audio enqueued for the current assistant item, in ms. The player
    /// clock keeps ticking through post-item silence, so this is the ceiling
    /// for any truncate — and when the clock says the whole item played,
    /// truncating is wrong (live error: "Audio content of 2750ms is already
    /// shorter than 3910ms").
    private var itemEnqueuedMs = 0

    private var watchScheduler = WatchModeScheduler(
        isEnabled: false, interval: PollyConfig.watchFrameInterval)
    private var watchFrameCount = 0
    private var lastWatchFrameItemId: String?
    private var didAttemptReconnect = false
    private var didSendWrapUpWarning = false
    private var isEnding = false

    // Deviation from the brief's signature (documented in the report): the brief
    // declares `audio: PollyAudioEngine = PollyAudioEngine()` /
    // `camera: PollyCameraController = PollyCameraController()`, but under Swift
    // 5.10 a @MainActor init can't be evaluated in a default-argument position
    // (SE-0411 isolated default values isn't enabled). Defaulting to `nil` and
    // constructing inside this main-actor-isolated init body is the minimal fix;
    // every call site is unchanged — omitting the args yields a fresh engine, and
    // passing a `PollyAudioEngine`/`PollyCameraController` still binds directly.
    init(
        recipe: Recipe,
        scale: Double,
        heardBriefing: Bool = false,
        awaitVerbalGo: Bool = false,
        deps: Dependencies = .live,
        audio: PollyAudioEngine? = nil,
        camera: PollyCameraController? = nil,
        wakeWord: WakeWordListening? = nil
    ) {
        self.recipe = recipe
        self.scale = scale
        self.heardBriefing = heardBriefing
        self.awaitVerbalGo = awaitVerbalGo
        self.isAwaitingVerbalGo = awaitVerbalGo
        self.deps = deps
        self.audio = audio ?? PollyAudioEngine()
        self.camera = camera ?? PollyCameraController()
        self.wakeWord = wakeWord ?? WakeWordListener()
    }

    // MARK: - Lifecycle

    /// Compile -> snapshot -> mint -> connect -> session.update -> greet.
    ///
    /// `requireMic` stays true in production: mic denied means no session
    /// (spec). Tests pass false so the sim test host's missing mic can't fail
    /// the phase. Only mint/transport errors (or a mic failure with
    /// `requireMic`) may set `.failed` — camera problems never do.
    func start(context: ModelContext, requireMic: Bool = true) async {
        guard phase == .idle else { return }
        startedAt = deps.now()
        sessionStartedAt = startedAt

        // 1. Execution plan (compiler never fails — it falls back to linear).
        phase = .compiling
        PollyDebugLog.shared.log("session: compiling plan for \"\(recipe.title)\"")
        let plan = await deps.compilePlan(recipe, scale)
        self.plan = plan
        PollyDebugLog.shared.log("session: plan ready — \(plan.steps.count) steps")

        // 2. Session snapshot: pantry, prefs, memories, past cooks of this recipe.
        let pantry = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        let prefs = UserPrefs.current(in: context)
        let memories = PollyMemoryStore.topFacts(limit: PollyConfig.memoryFactLimit, in: context)
        let pastSessions = recipe.cookSessions(in: context)
        let ownedTools = (try? context.fetch(FetchDescriptor<KitchenTool>())) ?? []
        let pantryMatch = PantryMatcher.match(recipe: recipe, pantry: pantry)
        missingIngredients = pantryMatch.missing.map(\.name)

        // 3. Tool registry; side effects that need the session come back here.
        let registry = PollyToolRegistry(
            plan: plan, recipe: recipe, pantry: pantry, prefs: prefs,
            timers: timers, context: context)
        registry.onRequestFrame = { [weak self] in
            guard let self, let jpeg = await self.camera.captureFrame() else { return false }
            let dataURI = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
            do {
                try await self.transport?.send(.createUserImage(dataURI: dataURI, itemId: nil))
                return true
            } catch {
                return false
            }
        }
        registry.onEndSession = { [weak self] in self?.wantsEnd = true }
        self.registry = registry

        // 4. Mint + connect + configure. Only these failures fail the session.
        phase = .connecting
        let token: PollySessionToken
        do {
            token = try await deps.mintToken()
            PollyDebugLog.shared.log("session: token minted — model=\(token.model) voice=\(token.voice)")
        } catch {
            PollyDebugLog.shared.log("session: token mint FAILED — \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
            return
        }

        let config = RealtimeSessionConfig(
            instructions: PollyPromptBuilder.instructions(
                recipe: recipe, plan: plan, pantryMatch: pantryMatch,
                prefs: prefs, memories: memories, pastSessions: pastSessions,
                ownedTools: ownedTools,
                heardBriefing: heardBriefing,
                awaitVerbalGo: awaitVerbalGo),
            tools: PollyToolRegistry.toolDefinitions,
            voice: token.voice,
            model: token.model,
            transcribeInput: true)
        liveConfig = config

        let transport = deps.makeTransport()
        self.transport = transport
        do {
            try await transport.connect(token: token.value, model: token.model)
            try await transport.send(.sessionUpdate(config))
            PollyDebugLog.shared.log("session: socket connected — session.update sent")
        } catch {
            PollyDebugLog.shared.log("session: connect FAILED — \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
            return
        }

        // 5. Mic. Denied mic in production means no session (spec). The wake-word
        //    listener is fed raw buffers via onBuffer so it hears even while the
        //    Realtime input is muted (dormant).
        let wake = wakeWord
        do {
            try audio.start(onChunk: { [weak transport] chunk in
                Task { try? await transport?.send(.appendAudio(base64: chunk)) }
            }, onBuffer: { [weak wake] buffer in
                wake?.append(buffer)
            })
            audio.onSessionInterrupted = { [weak self] began in
                guard let self, began, self.phase == .live else { return }
                PollyDebugLog.shared.event(.audioInterrupted)
                self.returnToDormant(reason: .audioInterrupted)
            }
        } catch {
            PollyDebugLog.shared.log("session: mic start FAILED — \(error.localizedDescription)")
            PollyDebugLog.shared.event(.micLost, ["why": "start_failed"])
            if requireMic {
                phase = .failed("Polly needs the microphone to cook with you. Enable it in Settings, or cook without Polly.")
                await transport.close()
                return
            }
            captionText = "Microphone unavailable — Polly can't hear you."
        }

        // 6. Camera stays OFF by default — most cooks keep the phone on the
        //    counter and cook by voice. They flip it on with the camera button
        //    only when they want Polly to look (which also requests permission
        //    then, not up front). Voice-only is the normal path.

        phase = .live
        PollyDebugLog.shared.log("session: LIVE")
        consumeEvents(from: transport, context: context)
        startWatchLoop(context: context)

        // Wake-word gate: normally start dormant (Realtime input muted) and listen
        // on-device for "Polly". Trailer handoff is different — open listening so
        // the cook can say "let's cook" without saying her name first.
        wakeWord.onWake = { [weak self] in
            PollyDebugLog.shared.event(.wakeDetected)
            self?.wakeUp()
        }
        wakeWord.onPartialTranscript = { [weak self] text in self?.updateLiveTranscript(text) }
        wakeWordAvailable = wakeWord.isAvailable
        if wakeWordAvailable { wakeWord.start() }

        if awaitVerbalGo {
            listeningMode = .listening
            liveTranscript = ""
            audio.isMuted = false
            pollyCaption = "I’m listening — say when you’re ready to cook."
            captionText = pollyCaption
            PollyDebugLog.shared.log("session: listening for verbal go (no opening speech)")
            // Warm the audio graph so the first reply after they speak isn't dropped.
            if audio.isRunning {
                try? await Task.sleep(for: .seconds(PollyConfig.greetingWarmupSeconds))
                audio.resetPlaybackForNextUtterance()
            }
            guard phase == .live else { return }
            // No responseCreate — Polly waits for the cook to speak.
            return
        }

        enterDormant()
        PollyDebugLog.shared.log("session: dormant — wake word \(wakeWordAvailable ? "listening" : "unavailable, tap to talk")")

        // Polly speaks first — but this is requested LAST, once the event loop
        // is already consuming and (on device) the audio graph has settled.
        // Enabling AEC flips the input node into voice-processing mode, which
        // fires an AVAudioEngineConfigurationChange that briefly STOPS the engine
        // ~20ms after start(). A greeting requested before that settles has its
        // opening audio scheduled into an engine that's about to stop, so the
        // buffers are flushed unheard — her caption shows but there's no sound
        // until the user speaks and a later response plays into the now-settled
        // engine. The short warm-up (only when the mic pipeline is actually up,
        // so tests / mic-denied never block) lets the restart land first.
        if audio.isRunning {
            try? await Task.sleep(for: .seconds(PollyConfig.greetingWarmupSeconds))
            // Reset the player to the clean stopped state a barge-in leaves it
            // in, so the greeting's audio render engages like every later turn
            // (see PollyAudioEngine) — the fix for "caption shows but no audio
            // until I speak," where the post-restart player never re-engaged.
            audio.resetPlaybackForNextUtterance()
            // Hold the mic across the greeting startup: it went live ~1s before
            // her first audio arrives, and that ambient/echo stream can trip
            // server VAD and truncate her opening line at ~0ms (caption shows,
            // no sound). The hold bridges to her first spoken words.
            audio.holdCapture(forSeconds: PollyConfig.greetingMicHoldSeconds)
        }
        guard phase == .live else { return }   // user bailed during warm-up
        // Speech-only: if the opening calls a tool (check_pantry, etc.), the
        // post-tool response.create makes her restart the same first sentence.
        try? await transport.send(.responseCreateSpeechOnly)
        isThinking = true
        PollyDebugLog.shared.log("session: greeting requested (speech-only)")
    }

    /// Idempotent teardown: stop the pipelines, close the socket, extract
    /// memories from the transcript, and write the PollyCookLog.
    func end(context: ModelContext, endedEarly: Bool) async {
        guard !isEnding, phase != .ended, phase != .idle else { return }
        isEnding = true

        // Grab a plate frame while the camera is still live (Cook Recap).
        if camera.isRunning, let jpeg = await camera.captureFrame() {
            plateJPEG = jpeg
        }

        watchTask?.cancel()
        watchTask = nil
        eventTask?.cancel()
        eventTask = nil
        cancelDormancyTimer()
        wakeWord.stop()
        audio.stop()
        camera.stop()
        timers.cancelAll()
        await transport?.close()
        transport = nil

        flushPendingAssistantLine()
        let transcript = transcriptLog.joined(separator: "\n")
        let extraction = try? await deps.extractMemories(transcript, recipe.title)
        if let extraction {
            PollyMemoryExtractor.apply(extraction, recipeTitle: recipe.title, in: context)
        }

        let saves = registry?.state.pollySaves ?? []
        sessionSaves = saves
        sessionStartedAt = startedAt

        let log = PollyCookLog(startedAt: startedAt ?? deps.now(), recipe: recipe)
        log.endedAt = deps.now()
        log.summary = extraction?.summary ?? ""
        log.stepsCompleted = registry?.state.completedStepIDs.count ?? 0
        log.stepsTotal = plan?.steps.count ?? 0
        log.substitutions = registry?.state.substitutions ?? []
        log.endedEarly = endedEarly
        log.pollySaves = saves
        context.insert(log)
        lastCookLog = log
        try? context.save()

        phase = .ended
    }

    // MARK: - User actions

    /// The "Show Polly" shutter: one frame straight into the conversation,
    /// then ask her to react to it.
    func sendShowPolly() async {
        guard phase == .live, let jpeg = await camera.captureFrame() else { return }
        let dataURI = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        try? await transport?.send(.createUserImage(dataURI: dataURI, itemId: nil))
        try? await transport?.send(.responseCreate)
        isThinking = true
    }

    func toggleMute() { audio.isMuted.toggle() }   // haptic lives in the view

    // MARK: - Wake-word / follow-up gate

    enum DormantReason: String {
        case timeout
        case explicitEnd = "explicit_end"
        case rejects
        case audioInterrupted = "audio_interrupted"
        case leftScreen = "left_screen"
        case idleMax = "idle_max"
        case hardMute = "hard_mute"
        case manual
    }

    /// Un-gate: "Polly" was heard (or the pill tapped). Opens the Realtime input,
    /// shows the Listening UI, and arms a longer initial listen window.
    func wakeUp() {
        guard phase == .live, !isHardMuted, listeningMode == .dormant else { return }
        let now = deps.now()
        lastWakeWordAt = now
        lastValidInteractionAt = now
        consecutiveRejects = 0
        awaitingTranscript = false
        listeningMode = .listening
        liveTranscript = ""
        audio.isMuted = false
        PollyDebugLog.shared.log("gate: LISTENING (woken)")
        openFollowUpWindow(
            seconds: PollyConfig.initialListenWindowSeconds,
            expectingAnswer: false,
            preferFollowUpUI: false)
    }

    /// Manual wake / extend for the tap-to-talk fallback (tapping the state pill).
    func forceListen() {
        guard !isHardMuted else { return }
        PollyDebugLog.shared.event(.manualReopen)
        if listeningMode == .dormant {
            wakeUp()
        } else {
            consecutiveRejects = 0
            lastValidInteractionAt = deps.now()
            listeningMode = .listening
            audio.isMuted = false
            openFollowUpWindow(
                seconds: PollyConfig.followUpWindowSeconds,
                expectingAnswer: expectsAnswer,
                preferFollowUpUI: false)
            PollyDebugLog.shared.log("gate: LISTENING (manual extend)")
        }
    }

    /// Re-gate: mute the Realtime input and return to waiting for "Polly".
    func returnToDormant(reason: DormantReason = .manual) {
        unfinishedHoldTask?.cancel()
        unfinishedHoldTask = nil
        cancelDormancyTimer()
        followUpDeadline = nil
        expectsAnswer = false
        bargeInCandidate = false
        awaitingTranscript = false
        isHoldingForAssistant = false
        consecutiveRejects = 0
        liveTranscript = ""
        enterDormant()
        // Fresh recognition segment so the next "Polly" wakes her — the running
        // transcript still holds the last one, which would otherwise block it.
        wakeWord.restart()
        PollyDebugLog.shared.event(.sessionClosed, ["reason": reason.rawValue])
        PollyDebugLog.shared.log("gate: dormant (\(reason.rawValue))")
    }

    /// Cook left the session UI — close the follow-up gate (full `end` is separate).
    func leaveCookScreen() {
        guard phase == .live, isEngaged else { return }
        returnToDormant(reason: .leftScreen)
    }

    private func enterDormant() {
        listeningMode = .dormant
        if !isHardMuted { audio.isMuted = true }
    }

    /// The mic button: hard-mute everything, including the wake word. Un-mute
    /// returns to dormant (wake-word armed), not open — you still say "Polly".
    func toggleHardMute() {
        isHardMuted.toggle()
        unfinishedHoldTask?.cancel()
        unfinishedHoldTask = nil
        cancelDormancyTimer()
        followUpDeadline = nil
        expectsAnswer = false
        awaitingTranscript = false
        listeningMode = .dormant
        liveTranscript = ""
        audio.isMuted = true
        if isHardMuted {
            wakeWord.stop()
            PollyDebugLog.shared.event(.sessionClosed, ["reason": DormantReason.hardMute.rawValue])
            PollyDebugLog.shared.log("gate: HARD MUTED")
        } else {
            if wakeWordAvailable { wakeWord.start() }
            PollyDebugLog.shared.log("gate: unmuted → dormant")
        }
    }

    private func updateLiveTranscript(_ text: String) {
        guard isEngaged else { return }
        liveTranscript = WakeWordMatcher.strippedQuestion(text)
    }

    /// Opens / refreshes the activity-based follow-up deadline.
    private func openFollowUpWindow(
        seconds: TimeInterval,
        expectingAnswer: Bool,
        preferFollowUpUI: Bool = true
    ) {
        if isAwaitingVerbalGo { return }
        expectsAnswer = expectingAnswer
        followUpDeadline = deps.now().addingTimeInterval(seconds)
        if listeningMode == .dormant { return }
        // After Polly answers: soft "still with you" UI. After wake / manual
        // extend / expected-answer: full Listening.
        if preferFollowUpUI && !expectingAnswer {
            listeningMode = .followUp
        } else {
            listeningMode = .listening
        }
        startFollowUpWatcher()
        PollyDebugLog.shared.event(.followUpArmed, [
            "seconds": "\(Int(seconds))",
            "expects": expectingAnswer ? "1" : "0",
        ])
        PollyDebugLog.shared.log(
            "gate: follow-up armed \(Int(seconds))s expectsAnswer=\(expectingAnswer)")
    }

    /// User started speaking — extend (never shrink) the deadline so a long
    /// utterance can't expire mid-sentence, and ASR still has time after.
    private func noteUserActivity() {
        guard isEngaged else { return }
        let seconds = expectsAnswer
            ? PollyConfig.expectedAnswerWindowSeconds
            : PollyConfig.followUpWindowSeconds
        let proposed = deps.now().addingTimeInterval(seconds)
        if let existing = followUpDeadline {
            followUpDeadline = max(existing, proposed)
        } else {
            followUpDeadline = proposed
        }
        if listeningMode == .followUp { listeningMode = .listening }
    }

    private func startFollowUpWatcher() {
        cancelDormancyTimer()
        dormancyTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(PollyConfig.followUpPollIntervalMs))
                guard let self else { return }
                guard phase == .live, isEngaged, !isHardMuted else { return }
                // Don't close while the cook is mid-utterance, waiting on ASR,
                // Polly is busy, or a tool/response round-trip is still in flight.
                if isListening || awaitingTranscript || isPollySpeaking || isThinking
                    || bargeInCandidate || isHoldingForAssistant {
                    continue
                }
                if let last = lastValidInteractionAt,
                   deps.now().timeIntervalSince(last) >= PollyConfig.maxEngagedIdleSeconds {
                    PollyDebugLog.shared.log("gate: idle max → dormant")
                    returnToDormant(reason: .idleMax)
                    return
                }
                guard let deadline = followUpDeadline else { return }
                if deps.now() >= deadline {
                    PollyDebugLog.shared.event(.followUpTimeout)
                    PollyDebugLog.shared.log("gate: follow-up timeout → dormant")
                    returnToDormant(reason: .timeout)
                    return
                }
            }
        }
    }

    private func cancelDormancyTimer() {
        dormancyTask?.cancel()
        dormancyTask = nil
    }

    private func gateContext() -> ConversationalGate.Context {
        let spokeRecently: Bool = {
            guard let ended = lastAssistantSpeechEndedAt else { return false }
            return deps.now().timeIntervalSince(ended) < 12
        }()
        var topic: [String] = []
        var onSetup = false
        if let plan {
            if plan.steps.indices.contains(stepIndex) {
                let step = plan.steps[stepIndex]
                onSetup = CookPlan.isSetupStep(step)
                topic.append(contentsOf: step.title.lowercased().split(separator: " ").map(String.init))
                topic.append(contentsOf: step.ingredientNames.map { $0.lowercased() })
            }
            topic.append(contentsOf: plan.title.lowercased().split(separator: " ").map(String.init))
            topic.append(contentsOf: plan.mise.map { $0.name.lowercased() })
            topic.append(contentsOf: plan.equipment.map { $0.lowercased() })
        }
        return ConversationalGate.Context(
            expectsAnswer: expectsAnswer || (lastAssistantAskedQuestion && spokeRecently),
            pollySpokeRecently: spokeRecently || isPollySpeaking,
            onSetupStep: onSetup,
            topicWords: Array(Set(topic)).filter { $0.count >= 3 }
        )
    }

    private func handleGatedTranscript(itemId: String?, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        awaitingTranscript = false
        guard !trimmed.isEmpty else { return }
        // Late transcript after a race-to-dormant: re-open briefly so we don't
        // drop "tools are on the counter" that arrived a beat late.
        if !isEngaged, phase == .live, !isHardMuted {
            wakeUp()
        }
        guard isEngaged else { return }
        // A newer transcript supersedes any unfinished-hold from the prior fragment.
        unfinishedHoldTask?.cancel()
        unfinishedHoldTask = nil
        PollyDebugLog.shared.event(.followUpSpeech, ["len": "\(trimmed.count)"])

        // Trailer handoff — first words always open a real turn.
        if isAwaitingVerbalGo {
            isAwaitingVerbalGo = false
            PollyDebugLog.shared.log("session: verbal go received — normal gate resumes after this turn")
            await commitUserTurn(wasSpeaking: isPollySpeaking)
            return
        }

        let decision = ConversationalGate.classify(trimmed, context: gateContext())
        PollyDebugLog.shared.log("gate: decision=\(decision.rawValue) text=\"\(trimmed.prefix(80))\"")

        switch decision {
        case .explicitEnd:
            consecutiveRejects = 0
            PollyDebugLog.shared.event(.explicitEnd)
            if isPollySpeaking { await cancelAssistantPlayback() }
            returnToDormant(reason: .explicitEnd)

        case .nameOnly:
            // Saying her name again while already listening — extend, don't punish.
            consecutiveRejects = 0
            noteUserActivity()
            lastValidInteractionAt = deps.now()
            if let itemId { try? await transport?.send(.deleteItem(itemId: itemId)) }
            PollyDebugLog.shared.log("gate: name-only — extend listen, no speak")

        case .acknowledgment:
            consecutiveRejects = 0
            lastAcknowledgedAt = deps.now()
            lastValidInteractionAt = deps.now()
            PollyDebugLog.shared.event(.acknowledgment)
            if let itemId { try? await transport?.send(.deleteItem(itemId: itemId)) }
            // Stay available briefly, then quietly close if nothing else comes.
            openFollowUpWindow(
                seconds: PollyConfig.acknowledgmentGraceSeconds,
                expectingAnswer: false)
            listeningMode = .followUp

        case .background, .selfTalk, .uncertain:
            consecutiveRejects += 1
            if let itemId { try? await transport?.send(.deleteItem(itemId: itemId)) }
            PollyDebugLog.shared.event(.followUpRejected, [
                "reason": decision.rawValue,
                "n": "\(consecutiveRejects)",
            ])
            PollyDebugLog.shared.log("gate: rejected (\(decision.rawValue)) rejects=\(consecutiveRejects)")
            if isPollySpeaking, bargeInCandidate {
                PollyDebugLog.shared.event(.bargeInIgnored, ["reason": decision.rawValue])
            }
            noteUserActivity()
            if consecutiveRejects >= 4 {
                PollyDebugLog.shared.log("gate: too many rejects → dormant")
                returnToDormant(reason: .rejects)
            }

        case .directFollowUp:
            consecutiveRejects = 0
            // Hold briefly on unfinished endings so a continuation can arrive.
            if ConversationalGate.looksUnfinished(trimmed) {
                PollyDebugLog.shared.event(.unfinishedHold)
                unfinishedHoldTask?.cancel()
                unfinishedHoldTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(PollyConfig.unfinishedTurnHoldMs))
                    guard let self, !Task.isCancelled else { return }
                    // Still talking — wait for the next committed transcript.
                    if self.isListening {
                        PollyDebugLog.shared.log("gate: unfinished hold — user still speaking, defer")
                        return
                    }
                    let shouldBarge = self.isPollySpeaking && (
                        self.bargeInCandidate || ConversationalGate.isClearInterruption(trimmed))
                    if shouldBarge {
                        PollyDebugLog.shared.event(.bargeInAccepted)
                    }
                    PollyDebugLog.shared.event(.followUpAccepted, ["reason": "directFollowUp"])
                    await self.commitUserTurn(wasSpeaking: shouldBarge)
                    self.bargeInCandidate = false
                }
                return
            }
            let shouldBarge = isPollySpeaking && (
                bargeInCandidate || ConversationalGate.isClearInterruption(trimmed))
            if shouldBarge {
                PollyDebugLog.shared.event(.bargeInAccepted)
            }
            PollyDebugLog.shared.event(.followUpAccepted, ["reason": decision.rawValue])
            await commitUserTurn(wasSpeaking: shouldBarge)
        }

        bargeInCandidate = false
    }

    private func commitUserTurn(wasSpeaking: Bool) async {
        expectsAnswer = false
        lastAssistantAskedQuestion = false
        noteUserActivity()
        listeningMode = .listening
        let now = deps.now()
        lastValidInteractionAt = now
        lastUserTurnCommittedAt = now
        isHoldingForAssistant = true
        if wasSpeaking {
            await cancelAssistantPlayback()
        }
        try? await transport?.send(.responseCreate)
        isThinking = true
        PollyDebugLog.shared.event(.turnCommitted, ["barge": wasSpeaking ? "1" : "0"])
        PollyDebugLog.shared.log("gate: committed user turn → response.create")
    }

    private func cancelAssistantPlayback() async {
        let cumulative = audio.interruptPlayback()
        if let itemId = currentAudioItemId {
            let itemMs = max(0, cumulative - itemStartPlayedMs)
            if itemMs < itemEnqueuedMs {
                try? await transport?.send(.truncateItem(itemId: itemId, audioEndMs: itemMs))
                PollyDebugLog.shared.log("sent: truncate \(itemId) @ \(itemMs)ms (of \(itemEnqueuedMs)ms)")
            }
            currentAudioItemId = nil
        }
        try? await transport?.send(.responseCancel)
        isPollySpeaking = false
    }

    /// Injects a typed/tapped question as a user turn and asks Polly to answer —
    /// backs the suggested-question bubbles for cooks who don't know what to ask.
    func ask(_ text: String) async {
        guard phase == .live else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if listeningMode == .dormant { wakeUp() }
        consecutiveRejects = 0
        try? await transport?.send(.createUserText(trimmed))
        try? await transport?.send(.responseCreate)
        isThinking = true
    }

    func flipCamera() { camera.flip() }

    // MARK: - Event loop

    private func consumeEvents(from transport: RealtimeTransporting, context: ModelContext) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in transport.events {
                guard let self, !Task.isCancelled else { return }
                await self.handle(event, context: context)
            }
        }
    }

    private func handle(_ event: RealtimeServerEvent, context: ModelContext) async {
        switch event {
        case .sessionCreated, .sessionUpdated:
            PollyDebugLog.shared.log("event: \(event)")

        case .responseCancelled:
            PollyDebugLog.shared.log("event: response.cancelled (server-side barge-in cancel)")

        case .unhandled(let type):
            PollyDebugLog.shared.log("event: unhandled '\(type)'")

        case .outputAudioDelta(let itemId, let base64):
            // First delta of a NEW assistant item: capture the player-node
            // baseline (cumulative ms since the node started) BEFORE enqueueing,
            // so a later barge-in can subtract it and send a per-item
            // audio_end_ms. The node never stops between turns, so the raw
            // cumulative value would make conversation.item.truncate reject the
            // audio_end_ms (it would exceed the item's length) on every barge-in
            // after the first turn.
            if currentAudioItemId != itemId {
                itemStartPlayedMs = audio.currentPlayedMs()
                itemEnqueuedMs = 0
                PollyDebugLog.shared.event(.assistantSpeechStart)
                PollyDebugLog.shared.log("event: audio item START \(itemId) (baseline \(itemStartPlayedMs)ms)")
            }
            audio.enqueue(base64: base64)
            // 24 kHz PCM16 mono = 48 bytes per ms; base64 is 4 chars per 3 bytes.
            itemEnqueuedMs += (base64.count * 3) / (4 * 48)
            currentAudioItemId = itemId
            isPollySpeaking = true
            isThinking = false

        case .speechStarted:
            // Two-stage barge-in: do NOT cancel Polly on raw VAD. Mark a
            // candidate and extend the follow-up window; the conversational
            // gate decides after we have a transcript.
            PollyDebugLog.shared.log(
                "event: SPEECH STARTED (VAD) pollySpeaking=\(isPollySpeaking) — hold barge-in for gate")
            isListening = true
            awaitingTranscript = false
            lastUserSpeechStartedAt = deps.now()
            noteUserActivity()
            if isPollySpeaking {
                bargeInCandidate = true
                PollyDebugLog.shared.event(.bargeInCandidate)
            }

        case .speechStopped:
            PollyDebugLog.shared.log("event: speech stopped — waiting on transcript + gate")
            isListening = false
            awaitingTranscript = true
            noteUserActivity()

        case .inputTranscript(let itemId, let text):
            PollyDebugLog.shared.log("heard: \"\(text)\"")
            captionText = text
            transcriptLog.append("USER: \(text)")
            await handleGatedTranscript(itemId: itemId, text: text)

        case .outputTranscriptDelta(let itemId, let delta):
            if pendingAssistantItemId != itemId {
                flushPendingAssistantLine()
                pendingAssistantItemId = itemId
            }
            pendingAssistantLine += delta
            captionText = pendingAssistantLine
            pollyCaption = pendingAssistantLine

        case .responseDone(let status, let calls):
            PollyDebugLog.shared.log(
                "event: response DONE status=\(status) tools=[\(calls.map(\.name).joined(separator: ","))]"
                + (pendingAssistantLine.isEmpty ? "" : " said=\"\(pendingAssistantLine.prefix(120))\""))
            // Capture before flush — if she already spoke this turn, the
            // post-tool follow-up must not re-open with the same first line.
            let alreadySpoke = !pendingAssistantLine.isEmpty
            let askedQuestion = pendingAssistantLine.contains("?")
                || pendingAssistantLine.lowercased().contains("do you")
            lastAssistantAskedQuestion = askedQuestion
            isPollySpeaking = false
            flushPendingAssistantLine()
            // Hold the follow-up watcher open through tool round-trips — clearing
            // isThinking here used to let the 7s timer fire mid-response (log:
            // dormant at +38s while get_current_step was still running).
            if status == "completed" {
                isHoldingForAssistant = true
                isThinking = true
            } else {
                isThinking = false
                isHoldingForAssistant = false
            }
            // Only execute tool calls from COMPLETED responses — a cancelled
            // response (barge-in) can carry partial calls, and answering them
            // talks over the cook who just interrupted.
            if status == "completed", !calls.isEmpty, let registry {
                for call in calls {
                    let output = await registry.handle(name: call.name, argumentsJSON: call.argumentsJSON)
                    try? await transport?.send(.createFunctionOutput(callId: call.callId, output: output))
                }
                // Push step / checklist changes into Observation so the guide updates live.
                publishSessionUI()
                // Wait until her current audio finishes draining so a follow-up
                // doesn't stack on top of the still-playing opening sentence.
                await audio.waitUntilQuiet(timeoutSeconds: 12)
                if alreadySpoke {
                    try? await transport?.send(.createUserText(
                        "[system note] Tool results are in. You already spoke this turn aloud — "
                        + "do NOT greet again and do NOT repeat any sentence you just said. "
                        + "Only speak if the tools require a short correction; otherwise stay silent and wait for the cook."))
                }
                // ONE response for the whole batch. A response.create per call
                // queues N spoken replies back to back — Polly repeating herself.
                try? await transport?.send(.responseCreate)
                isThinking = true
            } else if status == "completed", calls.isEmpty {
                // Re-open follow-up after her audio drains (clock starts then).
                let expect = askedQuestion
                // Greeting while dormant must NOT auto-open listen. A user turn
                // (or already-open follow-up) should stay / come back open.
                let shouldReengage = isEngaged
                    || (isHoldingForAssistant && lastUserTurnCommittedAt != nil)
                Task { [weak self] in
                    guard let self else { return }
                    await audio.waitUntilQuiet(timeoutSeconds: 12)
                    guard phase == .live, !isHardMuted else { return }
                    lastAssistantSpeechEndedAt = deps.now()
                    lastValidInteractionAt = deps.now()
                    lastAssistantAskedQuestion = expect
                    isHoldingForAssistant = false
                    isThinking = false
                    PollyDebugLog.shared.event(.assistantSpeechEnd)
                    // Greeting while dormant: remember the question, stay asleep.
                    guard shouldReengage || isEngaged else { return }
                    if listeningMode == .dormant {
                        listeningMode = .followUp
                        audio.isMuted = false
                        PollyDebugLog.shared.log("gate: re-engaged after assistant speech")
                    }
                    openFollowUpWindow(
                        seconds: expect
                            ? PollyConfig.expectedAnswerWindowSeconds
                            : PollyConfig.followUpWindowSeconds,
                        expectingAnswer: expect)
                }
            }

        case .error(let code, let message):
            PollyDebugLog.shared.log("event: ERROR code=\(code ?? "nil") \(message)")
            // Only the transport's own failure (code "transport", Task 7) means the
            // socket died. Server protocol errors (e.g. deleting an already-gone
            // item) must not kill a live cook — log them and keep going.
            if code == "transport" || phase != .live {
                await handleTransportError(message: message, context: context)
            } else {
                transcriptLog.append("[error] \(message)")
            }
        }
    }

    private func flushPendingAssistantLine() {
        if !pendingAssistantLine.isEmpty {
            transcriptLog.append("POLLY: \(pendingAssistantLine)")
        }
        pendingAssistantLine = ""
        pendingAssistantItemId = nil
    }

    /// One silent reconnect (spec degradation ladder); anything after that
    /// fails the session and the view offers "Cook without Polly".
    private func handleTransportError(message: String, context: ModelContext) async {
        guard !isEnding, phase != .ended else { return }
        guard phase == .live, !didAttemptReconnect else {
            phase = .failed(message)
            return
        }
        didAttemptReconnect = true
        captionText = "Connection hiccup — getting Polly back…"
        phase = .reconnecting
        do {
            let token = try await deps.mintToken()
            let transport = deps.makeTransport()
            try await transport.connect(token: token.value, model: token.model)
            if var config = liveConfig {
                config.voice = token.voice
                config.model = token.model
                try await transport.send(.sessionUpdate(config))
                liveConfig = config
            }
            self.transport = transport
            // A reconnect opens a NEW realtime conversation: item ids from the
            // old one are gone, so forget them — otherwise the next watch tick
            // would delete a nonexistent item and trigger a server error, and a
            // barge-in would truncate against a stale baseline.
            lastWatchFrameItemId = nil
            currentAudioItemId = nil
            itemStartPlayedMs = 0
            itemEnqueuedMs = 0
            isThinking = false
            consumeEvents(from: transport, context: context)
            phase = .live
        } catch {
            phase = .failed(message)
        }
    }

    // MARK: - Watch mode + session cap

    private func startWatchLoop(context: ModelContext) {
        watchTask?.cancel()
        watchScheduler = WatchModeScheduler(
            isEnabled: isWatching, interval: PollyConfig.watchFrameInterval)
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.tick(context: context)
            }
        }
    }

    /// 1 Hz loop body — internal (not private) so tests drive it with a scripted `now`.
    func tick(context: ModelContext) async {
        guard phase == .live else { return }

        let elapsed = startedAt.map { deps.now().timeIntervalSince($0) } ?? 0

        // Hard stop safely before OpenAI's 60-minute session cap. Honest
        // bookkeeping: ending mid-plan is endedEarly even when the clock ran out.
        if elapsed > Double(PollyConfig.maxSessionMinutes * 60) {
            let finished = (registry?.state.completedStepIDs.count ?? 0) >= (plan?.steps.count ?? .max)
            await end(context: context, endedEarly: !finished)
            return
        }

        // One in-conversation nudge near the cap — the model has no clock and the
        // instructions are static, so the warning must arrive as a message.
        if !didSendWrapUpWarning, elapsed > Double(PollyConfig.wrapUpWarningMinutes * 60) {
            didSendWrapUpWarning = true
            try? await transport?.send(.createUserText(
                "[system note] This cooking session has to end in about five minutes. Start wrapping up naturally, and call end_session when the dish is done."))
            try? await transport?.send(.responseCreate)
            isThinking = true
        }

        watchScheduler.isEnabled = isWatching
        guard camera.isRunning, watchScheduler.shouldSendFrame(now: deps.now()) else { return }
        guard let jpeg = await camera.captureFrame() else { return }

        watchFrameCount += 1
        let itemId = "wf_\(watchFrameCount)"
        let dataURI = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        try? await transport?.send(.createUserImage(dataURI: dataURI, itemId: itemId))
        // Drop the previous watch frame — stale frames only burn tokens.
        if let previous = lastWatchFrameItemId {
            try? await transport?.send(.deleteItem(itemId: previous))
        }
        lastWatchFrameItemId = itemId
    }
}
