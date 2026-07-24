import AVFAudio
import AudioToolbox
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
            makeTransport: { RealtimeWebRTCTransport() },
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

    /// Wake-word gate. `dormant` = Realtime input muted, waiting for "Polly";
    /// `listening` = un-gated, capturing the cook's question. Polly only hears you
    /// while listening, so background chatter/music never reaches her.
    enum ListeningMode: Equatable { case dormant, listening }
    private(set) var listeningMode: ListeningMode = .dormant
    /// The cook's live on-device transcript, shown large while Listening.
    private(set) var liveTranscript = ""
    /// Master mute (the mic button): silences everything, including the wake word.
    private(set) var isHardMuted = false
    /// Whether on-device wake-word recognition is running this session. When false
    /// (e.g. simulator, Speech denied), the state pill is a tap-to-talk fallback.
    private(set) var wakeWordAvailable = false

    /// PantryMatcher misses, snapshotted during start() — drives the preflight card.
    private(set) var missingIngredients: [String] = []
    /// Set by the `end_session` tool; the session view observes it and calls `end`.
    private(set) var wantsEnd = false
    /// Watch-mode toggle (the eye button). Read once per watch tick.
    var isWatching = false

    let audio: PollyAudioEngine
    let camera: PollyCameraController
    let wakeWord: WakeWordListening
    let timers = TimerManager()
    var registry: PollyToolRegistry?

    /// The follow-up window: after Polly answers (or you say "Polly" then pause),
    /// listening stays open this long for a natural follow-up before re-muting.
    private var dormancyTask: Task<Void, Never>?

    var stepIndex: Int { registry?.state.stepIndex ?? 0 }

    private let recipe: Recipe
    private let scale: Double
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

    private var watchScheduler = WatchModeScheduler(
        isEnabled: false, interval: PollyConfig.watchFrameInterval)
    private var watchFrameCount = 0
    private var lastWatchFrameItemId: String?
    /// v2 allows two silent reconnects (never-silent contract) — v1 allowed one.
    private var reconnectAttempts = 0
    private var didSendWrapUpWarning = false
    private var isEnding = false

    /// The v2 transport, when live (nil under scripted test transports —
    /// governor calls no-op and the WS-shaped flow still works for tests).
    private var webrtc: RealtimeWebRTCTransport? { transport as? RealtimeWebRTCTransport }
    /// Kept for the watchdog/reconnect paths, which fire outside handle().
    private var sessionContext: ModelContext?
    /// Never-silent contract: armed when the cook stops talking; if her audio
    /// hasn't started when it fires, force a spoken repair; two strikes = the
    /// session is broken and the reconnect ladder takes over.
    private var responseWatchdogTask: Task<Void, Never>?
    private var watchdogStrikes = 0
    /// Wake-question rescue: words spoken in the same breath as "Polly" are
    /// lost while the server mic is still closed (device log: the cook
    /// learned to say the wake word LAST). The on-device recognizer already
    /// transcribed the whole sentence — if server VAD hears nothing shortly
    /// after a wake, the transcript is injected as a text turn instead.
    private var speechSinceWake = false
    private var wakeInjectionTask: Task<Void, Never>?

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
        deps: Dependencies = .live,
        audio: PollyAudioEngine? = nil,
        camera: PollyCameraController? = nil,
        wakeWord: WakeWordListening? = nil
    ) {
        self.recipe = recipe
        self.scale = scale
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
        sessionContext = context

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

        // 4. Mic permission FIRST (WebRTC starts capture at connect), then
        //    mint + connect + configure. Only these failures fail the session.
        phase = .connecting
        if requireMic {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                PollyDebugLog.shared.log("session: mic permission DENIED")
                phase = .failed("Polly needs the microphone to cook with you. Enable it in Settings, or cook without Polly.")
                return
            }
        }

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
                ownedTools: ownedTools),
            tools: PollyToolRegistry.toolDefinitions,
            voice: token.voice,
            model: token.model,
            transcribeInput: true,
            audioPinnedAtMint: true)
        liveConfig = config

        let transport = deps.makeTransport()
        self.transport = transport
        // 5. Wake-word feed: the transport's capture tap hears the room even
        //    while dormant (device-proven) — wire it before capture starts.
        if let webrtc = transport as? RealtimeWebRTCTransport {
            let wake = wakeWord
            webrtc.onCaptureBuffer = { buffer in wake.append(buffer) }
        }
        do {
            try await transport.connect(token: token.value, model: token.model)
            try await transport.send(.sessionUpdate(config))
            PollyDebugLog.shared.log("session: WebRTC connected — session.update sent")
        } catch {
            PollyDebugLog.shared.log("session: connect FAILED — \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
            return
        }

        // 6. Camera stays OFF by default — most cooks keep the phone on the
        //    counter and cook by voice. They flip it on with the camera button
        //    only when they want Polly to look (which also requests permission
        //    then, not up front). Voice-only is the normal path.

        phase = .live
        PollyDebugLog.shared.log("session: LIVE")
        consumeEvents(from: transport, context: context)
        startWatchLoop(context: context)

        // Wake-word gate: start dormant (Realtime input muted) and listen on-device
        // for "Polly". Her greeting still plays; the cook says "Polly" (or taps the
        // pill) to un-gate. If on-device recognition is unavailable, the pill is a
        // tap-to-talk fallback and voice waking is simply off.
        wakeWord.onWake = { [weak self] in self?.wakeUp() }
        wakeWord.onPartialTranscript = { [weak self] text in self?.updateLiveTranscript(text) }
        wakeWordAvailable = wakeWord.isAvailable
        if wakeWordAvailable { wakeWord.start() }
        enterDormant()
        PollyDebugLog.shared.log("session: dormant — wake word \(wakeWordAvailable ? "listening" : "unavailable, tap to talk")")

        // Polly speaks first. The governor holds the mic until her greeting
        // finishes playing — the adaptive AEC's convergence window is the one
        // place her own words can bounce back as user speech (device-proven).
        webrtc?.holdMicForGreeting()
        guard phase == .live else { return }   // user bailed during setup
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

        watchTask?.cancel()
        watchTask = nil
        eventTask?.cancel()
        eventTask = nil
        cancelDormancyTimer()
        cancelResponseWatchdog()
        wakeInjectionTask?.cancel()
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

        let log = PollyCookLog(startedAt: startedAt ?? deps.now(), recipe: recipe)
        log.endedAt = deps.now()
        log.summary = extraction?.summary ?? ""
        log.stepsCompleted = registry?.state.completedStepIDs.count ?? 0
        log.stepsTotal = plan?.steps.count ?? 0
        log.substitutions = registry?.state.substitutions ?? []
        log.endedEarly = endedEarly
        context.insert(log)
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

    // MARK: - Wake-word gate

    /// Un-gate: "Polly" was heard (or the pill tapped). Opens the Realtime input,
    /// shows the Listening UI, and arms the follow-up window.
    func wakeUp() {
        guard phase == .live, !isHardMuted else { return }
        // "Polly" spoken over her = interrupt her, even if already listening.
        if isPollySpeaking {
            PollyDebugLog.shared.log("gate: wake during her turn — cancelling her response")
            Task {
                try? await transport?.send(.responseCancel)
                try? await transport?.send(.outputAudioBufferClear)
            }
        }
        guard listeningMode == .dormant else { return }
        listeningMode = .listening
        liveTranscript = ""
        audio.isMuted = false
        webrtc?.setMicMode(.open)
        PollyDebugLog.shared.log("gate: LISTENING (woken)")
        armDormancyTimer()
        armWakeInjection()
    }

    /// If server VAD hasn't heard anything ~1.6s after the wake, the words
    /// were spoken in the same breath as "Polly" and are gone — inject the
    /// on-device transcript as a text turn so the question still lands.
    private func armWakeInjection() {
        speechSinceWake = false
        wakeInjectionTask?.cancel()
        wakeInjectionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            guard let self, !Task.isCancelled else { return }
            guard phase == .live, listeningMode == .listening,
                  !speechSinceWake, !isPollySpeaking else { return }
            let question = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard question.split(separator: " ").count >= 3,
                  !WakeWordMatcher.containsWake(question) || question.split(separator: " ").count >= 4
            else { return }
            PollyDebugLog.shared.log("wake: injecting transcribed question — \"\(question.prefix(60))\"")
            try? await transport?.send(.createUserText(question))
            try? await transport?.send(.responseCreate)
            isThinking = true
        }
    }

    /// Manual wake for the tap-to-talk fallback (tapping the state pill).
    func forceListen() {
        guard !isHardMuted else { return }
        wakeUp()
    }

    /// Re-gate: mute the Realtime input and return to waiting for "Polly".
    func returnToDormant() {
        cancelDormancyTimer()
        wakeInjectionTask?.cancel()
        liveTranscript = ""
        enterDormant()
        // Fresh recognition segment so the next "Polly" wakes her — the running
        // transcript still holds the last one, which would otherwise block it.
        wakeWord.restart()
        PollyDebugLog.shared.log("gate: dormant (window closed)")
    }

    private func enterDormant() {
        listeningMode = .dormant
        if !isHardMuted { audio.isMuted = true }
        webrtc?.setMicMode(isHardMuted ? .hardMuted : .dormant)
    }

    /// The mic button: hard-mute everything, including the wake word. Un-mute
    /// returns to dormant (wake-word armed), not open — you still say "Polly".
    func toggleHardMute() {
        isHardMuted.toggle()
        cancelDormancyTimer()
        listeningMode = .dormant
        liveTranscript = ""
        audio.isMuted = true
        webrtc?.setMicMode(isHardMuted ? .hardMuted : .dormant)
        if isHardMuted {
            wakeWord.stop()
            PollyDebugLog.shared.log("gate: HARD MUTED")
        } else {
            if wakeWordAvailable { wakeWord.start() }
            PollyDebugLog.shared.log("gate: unmuted → dormant")
        }
    }

    private func updateLiveTranscript(_ text: String) {
        guard listeningMode == .listening else { return }
        liveTranscript = WakeWordMatcher.strippedQuestion(text)
    }

    private func armDormancyTimer() {
        cancelDormancyTimer()
        dormancyTask = Task { [weak self] in
            // v2 hybrid window: closes only after this much TRUE silence.
            // Every activity signal (user speech, her audio, a fresh answer)
            // re-arms or cancels it — the v1 3-second window is gone.
            try? await Task.sleep(for: .seconds(PollyConfig.hybridWindowSeconds))
            guard let self, !Task.isCancelled else { return }
            if phase == .live, listeningMode == .listening, !isHardMuted {
                returnToDormant()
            }
        }
    }

    private func cancelDormancyTimer() {
        dormancyTask?.cancel()
        dormancyTask = nil
    }

    /// Injects a typed/tapped question as a user turn and asks Polly to answer —
    /// backs the suggested-question bubbles for cooks who don't know what to ask.
    func ask(_ text: String) async {
        guard phase == .live else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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

        case .responseCreated:
            // A response is generating — server-initiated ones (normal voice
            // turns) never came through the client, so the Thinking pill was
            // invisible exactly when the cook was waiting. Not while she's
            // audibly speaking (queued follow-ups would flicker the pill).
            if !isPollySpeaking { isThinking = true }

        case .unhandled(let type):
            PollyDebugLog.shared.log("event: unhandled '\(type)'")

        case .outputAudioDelta:
            // WS legacy — audio never arrives as JSON over WebRTC (it rides
            // the media track). Kept only so scripted WS tests still drive
            // the speaking flags.
            isPollySpeaking = true
            isThinking = false

        case .outputAudioStarted:
            // Her voice is physically coming out of the speaker (WebRTC-only
            // event). Playback, interruption, and truncation are all handled
            // server-side + by the transport's governor now.
            PollyDebugLog.shared.log("event: assistant audio START")
            isPollySpeaking = true
            isThinking = false
            watchdogStrikes = 0
            cancelResponseWatchdog()
            // Her audio counts as activity — the hybrid window stays open.
            cancelDormancyTimer()
            // The question was consumed — clear it so the Listening UI can't
            // resurface a stale quote after she finishes answering.
            liveTranscript = ""

        case .outputAudioStopped:
            PollyDebugLog.shared.log("event: assistant audio STOP")
            isPollySpeaking = false
            if listeningMode == .listening { armDormancyTimer() }

        case .speechStarted:
            // Barge-in and truncation are server-side over WebRTC (the buffer
            // clears and conversation.item.truncated arrives on its own).
            PollyDebugLog.shared.log("event: SPEECH STARTED (VAD heard the user)")
            isPollySpeaking = false
            isListening = true
            // The server heard real speech — no wake-transcript rescue needed.
            speechSinceWake = true
            wakeInjectionTask?.cancel()
            // The cook is talking — don't let the window time out mid-question.
            cancelDormancyTimer()
            cancelResponseWatchdog()

        case .speechStopped:
            PollyDebugLog.shared.log("event: speech stopped")
            isListening = false
            // Never-silent contract: her audio must start within the watchdog
            // window, or a spoken repair is forced.
            armResponseWatchdog()

        case .inputTranscript(let text):
            PollyDebugLog.shared.log("heard: \"\(text)\"")
            // Transcription lands ~0.5s after speech ends — sometimes after
            // her reply already started streaming. Don't stomp her caption.
            if !isPollySpeaking { captionText = text }
            transcriptLog.append("USER: \(text)")

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
            isPollySpeaking = false
            isThinking = false
            flushPendingAssistantLine()
            // Follow-up window: Polly answered this turn — keep listening a few
            // seconds for a natural follow-up (no "Polly" needed), else re-gate.
            if listeningMode == .listening { armDormancyTimer() }
            // Only execute tool calls from COMPLETED responses — a cancelled
            // response (barge-in) can carry partial calls, and answering them
            // talks over the cook who just interrupted.
            guard status == "completed", !calls.isEmpty, let registry else { break }
            for call in calls {
                let output = await registry.handle(name: call.name, argumentsJSON: call.argumentsJSON)
                try? await transport?.send(.createFunctionOutput(callId: call.callId, output: output))
            }
            // v2: send tool results IMMEDIATELY — the WebRTC output buffer
            // serializes audio server-side, so the follow-up response
            // generates DURING any preamble she's still speaking and plays
            // seamlessly after it. (The v1 wait-until-quiet existed for the
            // client-side player and was pure latency here — device log
            // showed 3-6s tool turns.)
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

    // MARK: - Never-silent contract

    private func armResponseWatchdog() {
        cancelResponseWatchdog()
        responseWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PollyConfig.responseWatchdogSeconds))
            guard let self, !Task.isCancelled else { return }
            await self.responseWatchdogFired()
        }
    }

    private func cancelResponseWatchdog() {
        responseWatchdogTask?.cancel()
        responseWatchdogTask = nil
    }

    /// The cook said something and her audio never started. Strike one is a
    /// forced spoken repair; strike two means the session is broken — hand
    /// off to the reconnect ladder. Silence is never the outcome.
    private func responseWatchdogFired() async {
        guard phase == .live, !isPollySpeaking, !isEnding else { return }
        watchdogStrikes += 1
        PollyDebugLog.shared.log("watchdog: no reply \(Int(PollyConfig.responseWatchdogSeconds))s after user turn (strike \(watchdogStrikes))")
        if watchdogStrikes >= 2, let context = sessionContext {
            await handleTransportError(message: "Polly stopped responding", context: context)
        } else {
            try? await transport?.send(.responseCreateWithInstructions(
                "You did not respond to what the cook just said. In one short sentence, apologize and ask them to say it again."))
            isThinking = true
            armResponseWatchdog()   // the repair itself is watched too
        }
    }

    /// Silent reconnects with transcript replay (never-silent ladder): an
    /// audible chime marks the drop, the new session gets the recent
    /// conversation back, and Polly acknowledges the recovery out loud.
    /// After the attempts run out the session fails visibly and the view
    /// offers "Cook without Polly".
    private func handleTransportError(message: String, context: ModelContext) async {
        guard !isEnding, phase != .ended else { return }
        guard phase == .live, reconnectAttempts < PollyConfig.reconnectAttempts else {
            phase = .failed(message)
            return
        }
        reconnectAttempts += 1
        AudioServicesPlaySystemSound(1057)   // audible: the drop is heard, not guessed
        captionText = "Connection hiccup — getting Polly back…"
        phase = .reconnecting
        do {
            let token = try await deps.mintToken()
            let transport = deps.makeTransport()
            if let webrtc = transport as? RealtimeWebRTCTransport {
                let wake = wakeWord
                webrtc.onCaptureBuffer = { buffer in wake.append(buffer) }
            }
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
            // would delete a nonexistent item and trigger a server error.
            lastWatchFrameItemId = nil
            isThinking = false
            consumeEvents(from: transport, context: context)
            phase = .live
            // Restore the mic state the cook expects, replay recent context,
            // and say so out loud (never-silent: recovery is audible).
            webrtc?.setMicMode(
                isHardMuted ? .hardMuted : (listeningMode == .listening ? .open : .dormant))
            let tail = transcriptLog.suffix(12).joined(separator: "\n")
            if !tail.isEmpty {
                try? await transport.send(.createUserText(
                    "[system note] The connection dropped and recovered. Recent conversation:\n\(tail)\nContinue from where you left off — do not re-greet."))
            }
            try? await transport.send(.responseCreateWithInstructions(
                "In a few words, let the cook know you're back, then continue helping."))
            isThinking = true
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
