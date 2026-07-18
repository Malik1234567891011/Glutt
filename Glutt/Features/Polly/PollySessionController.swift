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
    /// drives the orb's "thinking" state.
    private(set) var isThinking = false
    /// PantryMatcher misses, snapshotted during start() — drives the preflight card.
    private(set) var missingIngredients: [String] = []
    /// Set by the `end_session` tool; the session view observes it and calls `end`.
    private(set) var wantsEnd = false
    /// Watch-mode toggle (the eye button). Read once per watch tick.
    var isWatching = false

    let audio: PollyAudioEngine
    let camera: PollyCameraController
    let timers = TimerManager()
    var registry: PollyToolRegistry?

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
        deps: Dependencies = .live,
        audio: PollyAudioEngine? = nil,
        camera: PollyCameraController? = nil
    ) {
        self.recipe = recipe
        self.scale = scale
        self.deps = deps
        self.audio = audio ?? PollyAudioEngine()
        self.camera = camera ?? PollyCameraController()
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
                ownedTools: ownedTools),
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

        // 5. Mic. Denied mic in production means no session (spec).
        do {
            try audio.start { [weak transport] chunk in
                Task { try? await transport?.send(.appendAudio(base64: chunk)) }
            }
        } catch {
            PollyDebugLog.shared.log("session: mic start FAILED — \(error.localizedDescription)")
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
        try? await transport.send(.responseCreate)
        isThinking = true
        PollyDebugLog.shared.log("session: greeting requested")
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
                PollyDebugLog.shared.log("event: audio item START \(itemId) (baseline \(itemStartPlayedMs)ms)")
            }
            audio.enqueue(base64: base64)
            // 24 kHz PCM16 mono = 48 bytes per ms; base64 is 4 chars per 3 bytes.
            itemEnqueuedMs += (base64.count * 3) / (4 * 48)
            currentAudioItemId = itemId
            isPollySpeaking = true
            isThinking = false

        case .speechStarted:
            // Barge-in: stop playback and tell the server how much of THIS item
            // was heard so the truncated tail never pollutes the conversation
            // state. interruptPlayback() returns cumulative ms since the player
            // node started (it never stops between turns), so subtract the item's
            // start baseline to get ms into the current item.
            let cumulative = audio.interruptPlayback()
            PollyDebugLog.shared.log("event: SPEECH STARTED (VAD heard the user) — playback interrupted at \(cumulative)ms")
            if let itemId = currentAudioItemId {
                let itemMs = max(0, cumulative - itemStartPlayedMs)
                if itemMs < itemEnqueuedMs {
                    try? await transport?.send(.truncateItem(itemId: itemId, audioEndMs: itemMs))
                    PollyDebugLog.shared.log("sent: truncate \(itemId) @ \(itemMs)ms (of \(itemEnqueuedMs)ms)")
                } else {
                    // The item finished playing before the user spoke — there
                    // is no unheard tail to remove, and the server rejects a
                    // truncate past the item's real length.
                    PollyDebugLog.shared.log("skip truncate — item fully played (\(itemEnqueuedMs)ms, clock said \(itemMs)ms)")
                }
                currentAudioItemId = nil
            }
            isPollySpeaking = false
            isListening = true

        case .speechStopped:
            PollyDebugLog.shared.log("event: speech stopped")
            isListening = false

        case .inputTranscript(let text):
            PollyDebugLog.shared.log("heard: \"\(text)\"")
            captionText = text
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
            isPollySpeaking = false
            isThinking = false
            flushPendingAssistantLine()
            // Only execute tool calls from COMPLETED responses — a cancelled
            // response (barge-in) can carry partial calls, and answering them
            // talks over the cook who just interrupted.
            guard status == "completed", !calls.isEmpty, let registry else { break }
            for call in calls {
                let output = await registry.handle(name: call.name, argumentsJSON: call.argumentsJSON)
                try? await transport?.send(.createFunctionOutput(callId: call.callId, output: output))
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
