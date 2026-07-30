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
        /// Reports finished-session duration for AI cost accounting. Best-effort.
        var reportSessionUsage: (TimeInterval, String?, RealtimeUsage?) async -> Void
        var now: () -> Date

        static let live = Dependencies(
            mintToken: { try await PollyTokenService.live.mint() },
            makeTransport: { RealtimeWebRTCTransport() },
            compilePlan: { await CookPlanCompiler.compile(recipe: $0, scale: $1) },
            extractMemories: { try await PollyMemoryExtractor.extract(transcript: $0, recipeTitle: $1) },
            reportSessionUsage: {
                await PollyTokenService.live.reportSessionEnd(duration: $0, model: $1, usage: $2)
            },
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
    /// True after cook (or Polly via tool) dismisses the missing-ingredients screen.
    private(set) var preflightDismissed = false
    /// Desired mute for the technique clip player (UI + voice tools).
    private(set) var clipMuted = true
    /// True when the clip should be playing (voice/UI). Adaptive canvas observes this.
    private(set) var clipPlaybackDesired = false
    /// Bumps on every play/restart request so the canvas remounts from the start
    /// even when the clip already finished (AVPlayer won't restart without seek).
    private(set) var clipRestartToken = 0
    /// True while WE hold the mic muted because a technique clip is playing with
    /// sound. Deliberately distinct from `isHardMuted`, which is the cook's own
    /// mute and must survive anything a clip does. Readable so a test can prove
    /// the hold is released — the bug it replaces was invisible from outside.
    private(set) var micHeldForClipAudio = false
    private var clipMicFailsafeTask: Task<Void, Never>?
    /// Set by the `end_session` tool; the session view observes it and calls `end`.
    private(set) var wantsEnd = false
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

    /// Auto-indexed YouTube demo clips for the current CookPlan (step id → clip).
    private(set) var stepClipsByID: [String: StepClip] = [:]
    /// Native downloaded clips (preferred over YouTube IFrame when ready).
    private(set) var nativeClipsByStepID: [String: NativeStepClip] = [:]
    /// Polly duplex media mode while a native clip plays.
    private(set) var mediaState: PollyMediaState = .idle
    /// True while Gemini indexing is in flight (first cook of a linked video).
    private(set) var isIndexingStepClips = false
    private var didStartClipIndex = false

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

    func clipForCurrentStep() -> StepClip? {
        guard let plan, plan.steps.indices.contains(stepIndex) else { return nil }
        return stepClipsByID[plan.steps[stepIndex].id]
    }

    func nativeClipForCurrentStep() -> NativeStepClip? {
        guard let plan, plan.steps.indices.contains(stepIndex) else { return nil }
        return nativeClipsByStepID[plan.steps[stepIndex].id]
    }

    func dismissPreflight() {
        guard !preflightDismissed else { return }
        preflightDismissed = true
        PollyDebugLog.shared.log("preflight: dismissed")
    }

    func setClipMuted(_ muted: Bool) {
        clipMuted = muted
        if case .playing(let id, _) = mediaState {
            updateMediaState(.playing(segmentID: id, muted: muted))
        }
    }

    /// Voice/UI: play, pause, mute, unmute the current step's technique clip.
    @discardableResult
    func controlStepVideo(action: String) -> [String: Any] {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let clip = nativeClipForCurrentStep() else {
            return ["ok": false, "reason": "no clip for this step"]
        }
        switch normalized {
        case "play", "show":
            clipPlaybackDesired = true
            clipRestartToken += 1
            updateMediaState(.playing(segmentID: clip.segmentID, muted: clipMuted))
            return clipControlPayload(clip, action: "play")
        case "pause":
            clipPlaybackDesired = false
            updateMediaState(.paused(segmentID: clip.segmentID))
            return clipControlPayload(clip, action: "pause")
        case "mute":
            setClipMuted(true)
            return clipControlPayload(clip, action: "mute")
        case "unmute":
            setClipMuted(false)
            return clipControlPayload(clip, action: "unmute")
        default:
            return ["ok": false, "reason": "unknown action — use play|pause|mute|unmute"]
        }
    }

    /// Called when the cook advances steps — autoplay if this step has a clip.
    func syncClipPlaybackForCurrentStep() {
        if let clip = nativeClipForCurrentStep() {
            clipPlaybackDesired = true
            clipRestartToken += 1
            updateMediaState(.playing(segmentID: clip.segmentID, muted: clipMuted))
            Task { await injectClipAutoplayNotice(clip) }
        } else {
            clipPlaybackDesired = false
            if case .playing = mediaState { updateMediaState(.idle) }
            else if case .paused = mediaState { updateMediaState(.idle) }
            else if case .finished = mediaState { updateMediaState(.idle) }
        }
    }

    /// Silent cue so Polly knows the example is already on / playing — never offers to start it.
    private func injectClipAutoplayNotice(_ clip: NativeStepClip) async {
        guard let transport, phase == .live || phase == .connecting else { return }
        let label = clip.displayLabel
        let cue = clip.visualCue.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = "[ui_event — silent, do not acknowledge] Technique clip \"\(label)\" just AUTOPLAYED full-bleed. Do NOT offer to play or show the video — it is already on screen."
        if !cue.isEmpty {
            text += " Refer to visual_cue if helpful: \(cue)"
        }
        try? await transport.send(.createUserText(text))
    }

    private func clipControlPayload(_ clip: NativeStepClip, action: String) -> [String: Any] {
        [
            "ok": true,
            "action": action,
            "playing": clipPlaybackDesired,
            "muted": clipMuted,
            "teaching_label": clip.displayLabel,
            "visual_cue": clip.visualCue,
            "duration_seconds": Int(clip.durationSeconds),
        ]
    }

    private func nativeClipPayload(_ clip: NativeStepClip, available: Bool = true) -> [String: Any] {
        [
            "available": available,
            "watch_label": clip.watchLabel,
            "teaching_label": clip.displayLabel,
            "visual_cue": clip.visualCue,
            "notice": clip.notice,
            "duration_seconds": Int(clip.durationSeconds),
            "start_seconds": Int(clip.startSeconds),
            "end_seconds": Int(clip.endSeconds),
            "muted_default": clipMuted,
            "prefer_video_technique": true,
            "clip_autoplays": true,
            "do_not_offer_to_play": true,
            "technique_rule": "Describe what the VIDEO shows (visual_cue / teaching_label). Do not invent a different method (e.g. toaster) if the clip shows a pan. Never offer to play the clip — it autoplays when the step opens; only replay if they ask.",
        ]
    }

    func updateMediaState(_ state: PollyMediaState) {
        let previous = mediaState
        mediaState = state
        // Native clip uses AVPlayer (not Realtime). Risk is speaker→mic bleed /
        // wake-word on source audio saying "Polly". Mute default; if cook unmutes
        // original audio, hard-mute the mic path until the clip ends or remutes.
        //
        // Do NOT call publishSessionUI() here. That bumps sessionUIEpoch, which
        // recreates PollyStepGuidePanel (.id(epoch)) while the player is mounting
        // → appear/teardown loop → full simulator freeze.
        switch state {
        case .playing(_, let muted):
            if case .playing(_, let wasMuted) = previous, wasMuted == muted { break }
            clipMuted = muted
            clipPlaybackDesired = true
            if muted {
                releaseMicAfterClip(reason: "clip muted")
            } else if !isHardMuted {
                micHeldForClipAudio = true
                webrtc?.setMicMode(.hardMuted)
                armClipMicFailsafe()
            }
            PollyDebugLog.shared.log("media: playing muted=\(muted)")
        case .finished:
            if previous == state { break }
            clipPlaybackDesired = false
            releaseMicAfterClip(reason: "finished")
            PollyDebugLog.shared.log("media: finished")
        case .paused:
            if previous == state { break }
            clipPlaybackDesired = false
            releaseMicAfterClip(reason: "paused")
            PollyDebugLog.shared.log("media: paused")
        case .idle:
            // Player teardown/remount often reports idle — don't clear a pending play.
            //
            // But DO give the mic back. This used to be an unconditional no-op,
            // and teardown is exactly what emits .idle: advance a step while an
            // unmuted clip is playing and the player is destroyed before it can
            // report .finished, so the mic we hard-muted for its audio was never
            // released. The cook then spent the rest of the session talking to a
            // muted microphone, with the UI still showing her as listening.
            if micHeldForClipAudio {
                releaseMicAfterClip(reason: "player torn down")
            }
        case .preparing:
            break
        }
    }

    /// Give the mic back after a technique clip stops owning the speaker.
    /// Never overrides the cook's own hard mute, which is a different thing
    /// entirely from the hold we take while a clip plays with sound.
    private func releaseMicAfterClip(reason: String) {
        clipMicFailsafeTask?.cancel()
        clipMicFailsafeTask = nil
        let wasHeld = micHeldForClipAudio
        micHeldForClipAudio = false
        guard !isHardMuted else { return }
        webrtc?.setMicMode(listeningMode == .dormant ? .dormant : .open)
        if wasHeld { PollyDebugLog.shared.log("media: mic released after clip (\(reason))") }
    }

    /// Last line of defence for the mic hold. Every path that should hand the mic
    /// back now does, but a player destroyed at the wrong moment can stop
    /// emitting states altogether, and the cost of missing one is that the cook
    /// keeps talking into a dead microphone for the rest of the session. No
    /// technique clip justifies holding it for minutes, so time it out.
    private func armClipMicFailsafe() {
        clipMicFailsafeTask?.cancel()
        clipMicFailsafeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PollyConfig.clipMicHoldMaxSeconds))
            guard let self, !Task.isCancelled, self.micHeldForClipAudio else { return }
            self.releaseMicAfterClip(reason: "failsafe timeout")
        }
    }

    private func injectTechniqueClipContext(_ clipsByStepID: [String: NativeStepClip]) async {
        guard !clipsByStepID.isEmpty, let plan else { return }
        // Clips often finish indexing during connect — wait briefly for transport.
        for _ in 0..<40 {
            if transport != nil, phase == .live || phase == .connecting { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let transport else {
            PollyDebugLog.shared.log("clips: technique context skipped — no transport yet")
            return
        }
        var lines = [
            "[technique_clips — silent context, do not acknowledge out loud]",
            "For these steps, speak ONLY the video method. Ignore any conflicting plan/recipe wording:",
        ]
        for step in plan.steps {
            guard let clip = clipsByStepID[step.id] else { continue }
            let cue = clip.visualCue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cue.isEmpty else { continue }
            lines.append("- \(step.title): \(cue)")
        }
        guard lines.count > 2 else { return }
        lines.append("Clips AUTOPLAY when the cook opens that step — never offer to play them; refer to what's already on screen. Only replay/pause/mute if they ask.")
        try? await transport.send(.createUserText(lines.joined(separator: "\n")))
        PollyDebugLog.shared.log("clips: injected technique context for \(clipsByStepID.count) steps")
    }

    private func startStepClipIndexingIfNeeded(plan: CookPlan) {
        guard !didStartClipIndex else { return }
        guard let sourceURL = recipe.sourceURL,
              YouTubeEmbed.videoId(from: sourceURL) != nil else { return }
        didStartClipIndex = true
        isIndexingStepClips = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isIndexingStepClips = false }

            // Prefer native downloaded clips (media-worker) when available.
            if let youtubeID = YouTubeEmbed.videoId(from: sourceURL),
               NativeClipService.supportsPilot(youtubeID: youtubeID) {
                do {
                    let pilot = try await NativeClipService.shared.pilotClips(youtubeID: youtubeID)
                    var nativeMap: [String: NativeStepClip] = [:]
                    for step in plan.steps where !CookPlan.isSetupStep(step) {
                        if let clip = await NativeClipService.shared.clipMatching(
                            stepTitle: step.title,
                            instruction: step.instruction,
                            in: pilot
                        ) {
                            nativeMap[step.id] = clip
                        }
                    }
                    self.nativeClipsByStepID = nativeMap
                    PollyDebugLog.shared.log("clips: native pilot \(youtubeID) matched \(nativeMap.count) steps")
                    self.publishSessionUI()
                    // If the cook is already on a clip step when matches arrive, start it.
                    if self.nativeClipForCurrentStep() != nil {
                        self.syncClipPlaybackForCurrentStep()
                    }
                    await self.injectTechniqueClipContext(nativeMap)
                    if !nativeMap.isEmpty { return }
                } catch {
                    PollyDebugLog.shared.log(
                        "clips: native pilot unavailable — \(error.localizedDescription); falling back to YouTube index"
                    )
                }
            }

            do {
                let response = try await StepClipService.shared.clips(
                    youtubeURL: sourceURL,
                    recipeTitle: self.recipe.title,
                    steps: plan.steps
                )
                let merged = StepClipFallbacks.merge(
                    indexed: response.clips,
                    steps: plan.steps,
                    youtubeURL: sourceURL
                )
                var map: [String: StepClip] = [:]
                for clip in merged {
                    map[clip.stepID] = clip
                }
                if map.isEmpty {
                    for clip in StepClipFallbacks.clips(for: plan.steps, youtubeURL: sourceURL) {
                        map[clip.stepID] = clip
                    }
                }
                self.stepClipsByID = map
                PollyDebugLog.shared.log(
                    "clips: indexed \(map.count) step clips (cached=\(response.cached ?? false))"
                )
                self.publishSessionUI()
            } catch {
                let fallbacks = StepClipFallbacks.clips(for: plan.steps, youtubeURL: sourceURL)
                var map: [String: StepClip] = [:]
                for clip in fallbacks { map[clip.stepID] = clip }
                self.stepClipsByID = map
                PollyDebugLog.shared.log(
                    "clips: index failed — \(error.localizedDescription); fallback=\(map.count)"
                )
                self.publishSessionUI()
            }
        }
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
    /// Billed tokens accumulated across every response.done this session,
    /// reported to the proxy on teardown for AI cost accounting.
    private var sessionUsage = RealtimeUsage()
    /// Config sent at session start; re-sent verbatim (new token's voice/model)
    /// on the single silent reconnect. Instructions/tools never mutate mid-cook
    /// so the realtime prompt cache stays warm.
    private var liveConfig: RealtimeSessionConfig?

    private var transcriptLog: [String] = []
    private var pendingAssistantItemId: String?
    private var pendingAssistantLine = ""

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
    /// Never-silent, final layer: when the session dies mid-cook and no model
    /// can speak anymore, the on-device system voice says so — dead air is
    /// never the outcome, including airplane mode. (Marin-voiced bundled
    /// lines are the post-soak polish; the guarantee ships now.)
    private let offlineVoice = AVSpeechSynthesizer()
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
        sessionContext = context
        sessionStartedAt = startedAt

        // The PostHog half of `ai_usage.polly_session`. That row says what the
        // minutes cost; this says who spent them and how often, which is the
        // half a cost table cannot answer.
        Analytics.capture(.cookStarted, ["with_polly": true])

        // 1. Execution plan (compiler never fails — it falls back to linear).
        phase = .compiling
        PollyDebugLog.shared.log("session: compiling plan for \"\(recipe.title)\"")
        let plan = await deps.compilePlan(recipe, scale)
        self.plan = plan
        PollyDebugLog.shared.log("session: plan ready — \(plan.steps.count) steps")
        startStepClipIndexingIfNeeded(plan: plan)

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
        registry.onDismissPreflight = { [weak self] in self?.dismissPreflight() }
        registry.onClipInfoForStep = { [weak self] stepID in
            guard let self, let clip = self.nativeClipsByStepID[stepID] else {
                return ["available": false]
            }
            return self.nativeClipPayload(clip)
        }
        registry.onClipPlaybackStatus = { [weak self] in
            guard let self else { return [:] }
            let playing: Bool
            switch self.mediaState {
            case .playing: playing = true
            default: playing = self.clipPlaybackDesired
            }
            return [
                "clipPlaying": playing,
                "clipMuted": self.clipMuted,
                "clipPlaybackDesired": self.clipPlaybackDesired,
            ]
        }
        registry.onShowStepVideo = { [weak self] in
            guard let self, let clip = self.nativeClipForCurrentStep() else {
                return ["available": false, "reason": "no clip for this step"]
            }
            self.clipPlaybackDesired = true
            self.clipRestartToken += 1
            self.updateMediaState(.playing(segmentID: clip.segmentID, muted: self.clipMuted))
            PollyDebugLog.shared.log("media: show_step_video \(clip.displayLabel)")
            return self.nativeClipPayload(clip)
        }
        registry.onControlStepVideo = { [weak self] action in
            guard let self else { return ["ok": false, "reason": "session gone"] }
            PollyDebugLog.shared.log("media: control_step_video \(action)")
            return self.controlStepVideo(action: action)
        }
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
                ownedTools: ownedTools,
                heardBriefing: heardBriefing,
                awaitVerbalGo: awaitVerbalGo),
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
        startSessionClock(context: context)

        // Wake-word gate: normally start dormant (Realtime input muted) and listen
        // on-device for "Polly". Trailer handoff is different — open listening so
        // the cook can say "let's cook" without saying her name first.
        wakeWord.onWake = { [weak self] in
            PollyDebugLog.shared.event(.wakeDetected)
            Analytics.capture(.pollyWakeWord)
            self?.wakeUp()
        }
        wakeWord.onPartialTranscript = { [weak self] text in self?.updateLiveTranscript(text) }
        // Ask unconditionally and let the listener report back when it is really
        // listening. Gating the start on a single read of `isAvailable` was a coin
        // flip: SFSpeechRecognizer reports unavailable for a moment after init, and
        // losing that toss killed the wake word for the whole cook with the UI
        // still promising "Say Polly to talk".
        wakeWord.onListeningChange = { [weak self] listening in
            self?.wakeWordAvailable = listening
        }
        wakeWord.start()
        wakeWordAvailable = wakeWord.isAvailable

        if awaitVerbalGo {
            listeningMode = .listening
            liveTranscript = ""
            audio.isMuted = false
            // v2: the governor owns the mic track — without this the trailer
            // handoff would LOOK open but the server would hear nothing.
            // (The v1 engine-warmup dance died with the engine; WebRTC owns
            // the audio graph and needs no warm-up.)
            webrtc?.setMicMode(.open)
            pollyCaption = "I’m listening — say when you’re ready to cook."
            captionText = pollyCaption
            PollyDebugLog.shared.log("session: listening for verbal go (no opening speech)")
            guard phase == .live else { return }
            // No responseCreate — Polly waits for the cook to speak.
            return
        }

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

        // Grab a plate frame while the camera is still live (Cook Recap).
        if camera.isRunning, let jpeg = await camera.captureFrame() {
            plateJPEG = jpeg
        }

        watchTask?.cancel()
        watchTask = nil
        eventTask?.cancel()
        eventTask = nil
        cancelDormancyTimer()
        cancelResponseWatchdog()
        clipMicFailsafeTask?.cancel()
        clipMicFailsafeTask = nil
        wakeInjectionTask?.cancel()
        wakeWord.stop()
        audio.stop()
        camera.stop()
        timers.cancelAll()
        await transport?.close()
        transport = nil

        // Report the billed span now that the socket is closed, before the
        // memory-extraction network call below — that one can be slow, and a
        // teardown interrupted midway would otherwise lose the usage row.
        if let startedAt {
            let duration = deps.now().timeIntervalSince(startedAt)
            await deps.reportSessionUsage(duration, liveConfig?.model, sessionUsage)
            // Same span the proxy bills, reported to PostHog rounded: a
            // `polly_session_started` with no matching end is a crash, a force
            // quit or a lost network, and the gap between the two counts is
            // worth watching on its own.
            Analytics.capture(.cookFinished, [
                "with_polly": true,
                "duration_s": Int(duration.rounded()),
                "ended_early": endedEarly,
                "steps_done": registry?.state.completedStepIDs.count ?? 0,
                "steps_total": plan?.steps.count ?? 0,
            ])
        }

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

    /// Release every live resource WITHOUT writing a cook log or extracting
    /// memories. This is the "Try again" path after a failed connect.
    ///
    /// `end()` is the wrong tool there twice over: it would record a zero-step
    /// cook in the user's history for a session that never started, and it would
    /// block the retry behind a memory-extraction network call. But the resources
    /// still have to go — before this existed the view simply nil'd its reference
    /// to the controller, which left the WebRTC peer connection, its audio device
    /// module and its claim on the microphone alive while the replacement session
    /// tried to take the mic for itself.
    ///
    /// Deliberately does NOT touch the audio session: the caller is about to start
    /// a new session that reconfigures it, and a deactivate/reactivate cycle in
    /// between is exactly the kind of churn that stops VPIO engaging.
    func abandon() async {
        guard !isEnding, phase != .ended else { return }
        isEnding = true
        watchTask?.cancel()
        watchTask = nil
        eventTask?.cancel()
        eventTask = nil
        cancelDormancyTimer()
        cancelResponseWatchdog()
        clipMicFailsafeTask?.cancel()
        clipMicFailsafeTask = nil
        wakeInjectionTask?.cancel()
        wakeWord.stop()
        camera.stop()
        timers.cancelAll()
        await transport?.close()
        transport = nil
        phase = .ended
        PollyDebugLog.shared.log("session: abandoned (retry) — resources released")
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
        let now = deps.now()
        lastWakeWordAt = now
        lastValidInteractionAt = now
        consecutiveRejects = 0
        awaitingTranscript = false
        listeningMode = .listening
        liveTranscript = ""
        audio.isMuted = false
        webrtc?.setMicMode(.open)
        PollyDebugLog.shared.log("gate: LISTENING (woken)")
        openFollowUpWindow(
            seconds: PollyConfig.initialListenWindowSeconds,
            expectingAnswer: false,
            preferFollowUpUI: false)
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
            webrtc?.setMicMode(.open)
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
        wakeInjectionTask?.cancel()
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
        webrtc?.setMicMode(isHardMuted ? .hardMuted : .dormant)
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
        webrtc?.setMicMode(isHardMuted ? .hardMuted : .dormant)
        if isHardMuted {
            wakeWord.stop()
            PollyDebugLog.shared.event(.sessionClosed, ["reason": DormantReason.hardMute.rawValue])
            PollyDebugLog.shared.log("gate: HARD MUTED")
        } else {
            // Unconditional for the same reason as at session start: a stale
            // `wakeWordAvailable` must never be what stops us re-arming.
            wakeWord.start()
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

    /// After Polly's audible turn ends (or a silent completed turn), refresh the
    /// conversational follow-up window — unless this was the dormant greeting.
    private func reengageAfterAssistantSpeech(expectingAnswer: Bool) {
        guard phase == .live, !isHardMuted else { return }
        let shouldReengage = isEngaged
            || (isHoldingForAssistant && lastUserTurnCommittedAt != nil)
        lastAssistantSpeechEndedAt = deps.now()
        lastValidInteractionAt = deps.now()
        lastAssistantAskedQuestion = expectingAnswer
        isHoldingForAssistant = false
        isThinking = false
        PollyDebugLog.shared.event(.assistantSpeechEnd)
        // Greeting while dormant: remember the question, stay asleep.
        guard shouldReengage || isEngaged else { return }
        if listeningMode == .dormant {
            listeningMode = .followUp
            audio.isMuted = false
            webrtc?.setMicMode(.open)
            PollyDebugLog.shared.log("gate: re-engaged after assistant speech")
        }
        openFollowUpWindow(
            seconds: expectingAnswer
                ? PollyConfig.expectedAnswerWindowSeconds
                : PollyConfig.followUpWindowSeconds,
            expectingAnswer: expectingAnswer)
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
        // WebRTC: barge-in truncation / buffer clear is server-side. Cancel the
        // in-flight response and clear the remote output buffer so her voice stops.
        _ = audio.interruptPlayback()
        try? await transport?.send(.responseCancel)
        try? await transport?.send(.outputAudioBufferClear)
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

        case .responseCreated:
            // A response is generating — server-initiated ones (normal voice
            // turns) never came through the client, so the Thinking pill was
            // invisible exactly when the cook was waiting. Not while she's
            // audibly speaking (queued follow-ups would flicker the pill).
            if !isPollySpeaking { isThinking = true }

        case .unhandled(let type):
            PollyDebugLog.shared.log("event: unhandled '\(type)'")

        case .outputAudioDelta(_, _):
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
            reengageAfterAssistantSpeech(expectingAnswer: lastAssistantAskedQuestion)

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
            // The server heard real speech — no wake-transcript rescue needed.
            speechSinceWake = true
            wakeInjectionTask?.cancel()
            cancelResponseWatchdog()
            if isPollySpeaking {
                bargeInCandidate = true
                PollyDebugLog.shared.event(.bargeInCandidate)
            }


        case .speechStopped:
            PollyDebugLog.shared.log("event: speech stopped — waiting on transcript + gate")
            isListening = false
            awaitingTranscript = true
            noteUserActivity()
            // Never-silent contract: her audio must start within the watchdog
            // window, or a spoken repair is forced.
            armResponseWatchdog()

        case .inputTranscript(let itemId, let text):
            PollyDebugLog.shared.log("heard: \"\(text)\"")
            // Transcription lands ~0.5s after speech ends — sometimes after
            // her reply already started streaming. Don't stomp her caption.
            if !isPollySpeaking { captionText = text }
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

        case .responseDone(let status, let calls, let usage):
            // The server reports exactly what it billed for this response.
            // Accumulating it is what makes Polly's cost measured, not guessed.
            if let usage { sessionUsage += usage }
            PollyDebugLog.shared.log(
                "event: response DONE status=\(status) tools=[\(calls.map(\.name).joined(separator: ","))]"
                + (pendingAssistantLine.isEmpty ? "" : " said=\"\(pendingAssistantLine.prefix(120))\""))
            // Capture before flush — if she already spoke this turn, the
            // post-tool follow-up must not re-open with the same first line.
            let alreadySpoke = !pendingAssistantLine.isEmpty
            let askedQuestion = pendingAssistantLine.contains("?")
                || pendingAssistantLine.lowercased().contains("do you")
            lastAssistantAskedQuestion = askedQuestion
            // Don't clear isPollySpeaking here — on WebRTC, outputAudioStarted /
            // outputAudioStopped own the audible speaking flags.
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
                // v2: send tool results IMMEDIATELY — the WebRTC output buffer
                // serializes audio server-side, so the follow-up response
                // generates DURING any preamble she's still speaking and plays
                // seamlessly after it.
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
                // Follow-up re-arm normally waits for outputAudioStopped. If this
                // turn produced no spoken audio, arm immediately so the hold
                // can't strand the dormancy watcher.
                if !alreadySpoke, !isPollySpeaking {
                    reengageAfterAssistantSpeech(expectingAnswer: askedQuestion)
                }
            }

        case .error(let code, let message):
            PollyDebugLog.shared.log("event: ERROR code=\(code ?? "nil") \(message)")
            // Only the transport's own failure (code "transport", Task 7) means the
            // socket died. Server protocol errors (e.g. deleting an already-gone
            // item) must not kill a live cook — log them and keep going.
            //
            // The `|| phase != .live` clause that used to live here was a live-fire
            // hazard: once a reconnect set phase = .reconnecting, ANY server error
            // routed here, failed handleTransportError's `guard phase == .live`, and
            // spoke the offline failure line. The gate itself generates such errors
            // constantly — it sends conversation.item.delete on every rejected turn,
            // and a delete of an already-gone item comes back as item_not_found. So
            // one rejected turn during a reconnect ended the cook. Phase is not a
            // signal about the socket; only `code` is.
            if code == "transport" {
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
        let wasMidCook = phase == .live || phase == .reconnecting
        guard phase == .live, reconnectAttempts < PollyConfig.reconnectAttempts else {
            phase = .failed(message)
            if wasMidCook { speakOfflineFallback() }
            return
        }
        reconnectAttempts += 1
        AudioServicesPlaySystemSound(1057)   // audible: the drop is heard, not guessed
        captionText = "Connection hiccup. Getting Polly back."
        phase = .reconnecting

        // Tear the dead stack DOWN before building a new one. Skipping this was the
        // single most damaging bug in the voice layer: the old transport was simply
        // overwritten at `self.transport = transport`, so its peer connection, its
        // audio device module, its AVAudioEngine and its VPIO claim on the microphone
        // all stayed alive and fought the new stack for the rest of the cook. Every
        // hiccup added another one. close() is also the only thing that removes the
        // route-change observer and cancels the meter task, both of which were
        // likewise accumulating.
        //
        // Order matters: cancel the event consumer first so we stop reading a stream
        // that is about to finish, then close, and only then mint. Releasing the mic
        // before the new ADM asks for it is the whole point.
        eventTask?.cancel()
        eventTask = nil
        let dyingTransport = transport
        transport = nil
        await dyingTransport?.close()

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
            isThinking = false
            consumeEvents(from: transport, context: context)
            phase = .live
            // Restore the mic state the cook expects, replay recent context,
            // and say so out loud (never-silent: recovery is audible).
            webrtc?.setMicMode(
                isHardMuted ? .hardMuted : (isEngaged ? .open : .dormant))
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
            speakOfflineFallback()
        }
    }

    /// Spoken by the SYSTEM voice — it works with zero network by definition.
    private func speakOfflineFallback() {
        PollyDebugLog.shared.log("offline voice: speaking the failure line")
        let utterance = AVSpeechUtterance(
            string: "I have lost my connection, chef. Your steps stay right here on the screen.")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        offlineVoice.speak(utterance)
    }

    // MARK: - Session clock (cap + wrap-up)

    private func startSessionClock(context: ModelContext) {
        watchTask?.cancel()
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
    }
}
