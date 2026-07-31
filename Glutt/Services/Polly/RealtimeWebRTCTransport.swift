import AVFoundation
import Foundation
import LiveKitWebRTC
import os

/// What the session wants from the mic. The transport's governor combines
/// this with live playback state (half-duplex + voice-reopen + greeting
/// hold) to decide the actual track state.
enum PollyMicMode: Equatable {
    /// Conversation window open — Polly hears the cook (subject to the
    /// half-duplex gate while she's speaking).
    case open
    /// Asleep, waiting for "Polly" — the server hears nothing; the wake feed
    /// (capture tap) keeps hearing the room.
    case dormant
    /// The mic button — nothing reaches the server, wake word is off too
    /// (the controller stops the listener; the tap's frames go nowhere).
    case hardMuted
}

/// Polly v2 transport: OpenAI Realtime GA over first-party WebRTC.
///
/// Why WebRTC (see docs/plan-polly-v2-voice.md, docs/webrtc-transport-vetting-2026-07-23.md):
/// libWebRTC owns mic capture, playback, AEC, and jitter — replacing the
/// AVAudioEngine graph and its echo-war band-aids. Audio never crosses this
/// seam as PCM events; only JSON protocol events do, over the "oai-events"
/// data channel, so the existing `RealtimeEvent` codec is unchanged.
///
/// Wake-word feed: a second mic tap CANNOT coexist with WebRTC's
/// voice-processing capture (VPIO exclusivity — vetting doc §"coexistence").
/// Instead `PollyCaptureHook` is injected as the audio-processing module's
/// capture-post delegate; it keeps receiving real mic frames even while the
/// track is disabled (dormant), which is what lets "say Polly" work mid-call.
final class RealtimeWebRTCTransport: NSObject, RealtimeTransporting, @unchecked Sendable {
    nonisolated let events: AsyncStream<RealtimeServerEvent>

    /// Capture-side mic frames (post-processing, pre-encoder), delivered on a
    /// WebRTC audio thread. Set before `connect`. Fires regardless of
    /// `setMicEnabled` — that gate is downstream of this hook.
    var onCaptureBuffer: ((AVAudioPCMBuffer) -> Void)? {
        get { hook.onBuffer }
        set {
            hook.onBuffer = newValue
            trackRenderer.onBuffer = newValue
            engineTap.onBuffer = newValue
        }
    }

    /// Raw JSON of every server event, before decoding. Spike/debug use.
    var onRawEvent: ((String) -> Void)?

    /// One-time X-ray of the ADM's input graph (spike/debug).
    var onGraphInfo: ((String) -> Void)? {
        get { engineTap.onGraphInfo }
        set { engineTap.onGraphInfo = newValue }
    }

    /// Fired when Polly's audio physically starts/stops playing (from the
    /// WebRTC-only output_audio_buffer events). Called on a transport thread —
    /// consumers hop to the main actor themselves.
    var onAssistantAudioChange: ((Bool) -> Void)?
    /// Fired when the voice-reopen gate detected a real voice during her turn
    /// and reopened the mic for barge-in. Transport thread.
    var onBargeInReopen: (() -> Void)?
    /// True when the audio session was taken by a call/alarm/Siri, false when it
    /// came back. Main queue.
    var onAudioInterrupted: ((Bool) -> Void)?

    /// Latest mic-observation RMS, from whichever feed is actually alive
    /// (capture hook, local-track renderer, or the engine tap).
    var captureRMS: Float {
        max(hook.latestRMS, trackRenderer.latestRMS, engineTap.latestRMS)
    }

    /// Is Apple's platform echo canceller actually running right now?
    var isPlatformAECActive: Bool {
        lock.withLock {
            factory?.audioDeviceModule.platformAudioProcessingState.echoCancellation.isActive ?? false
        }
    }

    /// One-line snapshot of the audio stack's health for the spike log.
    func audioDiagnostics() -> String {
        guard let adm = lock.withLock({ factory?.audioDeviceModule }) else { return "audio: no ADM" }
        let state = adm.platformAudioProcessingState
        let aec = state.echoCancellation
        let hookStats = hook.stats
        return "audio: vpAllowed=\(adm.isPlatformVoiceProcessingAllowed ? 1 : 0)"
            + " vpBypassed=\(adm.isVoiceProcessingBypassed ? 1 : 0)"
            + " vpActive=\(state.isVoiceProcessingEnabledActive ? 1 : 0)"
            + " AEC[avail=\(aec.isAvailable ? 1 : 0) req=\(aec.isRequested ? 1 : 0) ACTIVE=\(aec.isActive ? 1 : 0)]"
            + " NS[active=\(state.noiseSuppression.isActive ? 1 : 0)]"
            + " engine=\(adm.isEngineRunning ? "running" : "stopped")"
            + " hook[frames=\(hookStats.frames)]"
            + " tapA[f=\(engineTap.statsA.frames) rms=\(String(format: "%.3f", engineTap.statsA.rms)) pk=\(String(format: "%.3f", engineTap.statsA.peak))]"
            + " tapB[f=\(engineTap.statsB.frames) rms=\(String(format: "%.3f", engineTap.statsB.rms)) pk=\(String(format: "%.3f", engineTap.statsB.peak))]"
    }

    /// Turn libWebRTC's software echo canceller on or off. Runtime-swappable by
    /// design — the APM's `config` property applies live, which is what makes an
    /// in-session A/B possible at all.
    ///
    /// `mobileMode` selects AECM, webrtc's legacy mobile canceller, rather than
    /// AEC3. It defaults to false: AEC3 is the modern one, and the log line that
    /// used to call the old setting "software AEC3 (mobile)" was simply wrong
    /// about which canceller it had enabled.
    func setSoftwareAEC(_ enabled: Bool, mobileMode: Bool = false) {
        guard let apm = lock.withLock({ processingModule }) else { return }
        let config = LKRTCAudioProcessingConfig()
        config.isEchoCancellationEnabled = enabled
        config.isEchoCancellationMobileMode = mobileMode
        config.isNoiseSuppressionEnabled = true
        config.isHighpassFilterEnabled = true
        apm.config = config
        PollyDebugLog.shared.log(
            "audio: software AEC \(enabled ? (mobileMode ? "ON (AECM)" : "ON (AEC3)") : "OFF")")
    }

    /// Tell the governor she is speaking when the audio is NOT coming from the
    /// model.
    ///
    /// With a cloned voice the session is minted text-only, so no
    /// `output_audio_buffer.started/stopped` events ever arrive and
    /// `noteAssistantAudio` never fires. Without this the half-duplex gate would
    /// believe she was silent for the entire cook and leave the mic wide open
    /// while she talked, feeding her own voice straight back to the server.
    func setAssistantSpeaking(_ speaking: Bool) {
        noteAssistantAudio(playing: speaking)
    }

    /// Re-apply the lab toggles mid-session. Shipping them in the overflow menu
    /// is only useful if flipping one takes effect without a rebuild, which
    /// means the transport has to be told.
    func refreshAudioLab() {
        setSoftwareAEC(PollyAudioLab.stackedAEC)
        lock.withLock { resolveTrackLocked() }
        PollyDebugLog.shared.log(PollyAudioLab.summary)
    }

    /// Apply the audio-lab experiments and then report what the hardware
    /// actually did. Called from the production connect path, which is the whole
    /// point: every AEC control in this file used to be reachable only from a
    /// launch-argument-gated debug screen, so a shipping cook could neither turn
    /// echo cancellation on nor discover that it was off.
    func applyAudioLabAndReport() {
        setSoftwareAEC(PollyAudioLab.stackedAEC)
        PollyDebugLog.shared.log(PollyAudioLab.summary)
        // The ADM reports requested-vs-active only once input is configured, so
        // reading it immediately after connect returns a meaningless NO.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self else { return }
            PollyDebugLog.shared.log(self.audioDiagnostics())
            if !self.isPlatformAECActive {
                PollyDebugLog.shared.log(
                    "audio: WARNING platform AEC (VPIO) is NOT active — software AEC is all that stands between her voice and the mic")
            }
        }
    }

    private let continuation: AsyncStream<RealtimeServerEvent>.Continuation
    private let hook: PollyCaptureHook
    private let renderMonitor: PollyRenderMonitor
    private let trackRenderer = PollyLocalTrackRenderer()
    private let engineTap = PollyEngineTapObserver()
    private let lock = NSLock()

    private var factory: LKRTCPeerConnectionFactory?
    private var processingModule: LKRTCDefaultAudioProcessingModule?
    private var peerConnection: LKRTCPeerConnection?
    private var dataChannel: LKRTCDataChannel?
    private var micTrack: LKRTCAudioTrack?

    private var iceGatheringContinuation: CheckedContinuation<Void, Never>?
    private var channelOpenContinuation: CheckedContinuation<Void, Error>?
    private var isClosing = false

    // Audio governor state (lock-guarded). Device-proven rules, 2026-07-24:
    // half-duplex (track closed for her whole utterance — echo phantoms are
    // physically impossible), voice-reopen (real voice reopens for barge-in),
    // greeting hold (mic closed until her first utterance finishes playing so
    // the adaptive AEC converges), dormancy (wake-word sleep).
    private var micMode: PollyMicMode = .dormant
    private var assistantSpeaking = false
    private var greetingHold = false
    private var voiceReopened = false
    private var meterTask: Task<Void, Never>?
    private var greetingFailsafeTask: Task<Void, Never>?
    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    /// How many transports exist right now. A healthy cook is 1; a reconnect
    /// briefly touches 2 and must settle back to 1. Anything that stays above 1
    /// means a leaked stack — a second audio device module and a second claim on
    /// the microphone, which is inaudible in code review and unmistakable in a
    /// kitchen. Logged on every init and deinit so the debug dump proves it.
    private static let liveCount = OSAllocatedUnfairLock(initialState: 0)

    override init() {
        let (stream, continuation) = AsyncStream.makeStream(of: RealtimeServerEvent.self)
        self.events = stream
        self.continuation = continuation
        let hook = PollyCaptureHook()
        self.hook = hook
        self.renderMonitor = PollyRenderMonitor(hook: hook)
        super.init()
        let n = Self.liveCount.withLock { $0 += 1; return $0 }
        PollyDebugLog.shared.log("transport: init (live=\(n))")
    }

    deinit {
        let n = Self.liveCount.withLock { $0 -= 1; return $0 }
        PollyDebugLog.shared.log("transport: deinit (live=\(n))")
    }

    // MARK: - RealtimeTransporting

    func connect(token: String, model: String) async throws {
        configureAudioSession()

        // Render-side monitor gives the anti-echo gates a sample-accurate
        // "her audio is physically playing" signal — event-driven gating left
        // a 200-500ms unprotected crack at each utterance onset (device log:
        // phantom speech_started 0.5s into her turn).
        let apm = LKRTCDefaultAudioProcessingModule(
            config: nil,
            capturePostProcessingDelegate: hook,
            renderPreProcessingDelegate: renderMonitor
        )
        // .audioEngine is LiveKit's AVAudioEngine-based ADM — the one their SDK
        // ships on and the one proven with capture hooks + muted-speech
        // detection. bypassVoiceProcessing=false keeps VPIO AEC (the point).
        let factory = LKRTCPeerConnectionFactory(
            audioDeviceModuleType: .audioEngine,
            bypassVoiceProcessing: false,
            encoderFactory: LKRTCDefaultVideoEncoderFactory(),
            decoderFactory: LKRTCDefaultVideoDecoderFactory(),
            audioProcessingModule: apm
        )

        // Apple's voice-processing unit is the echo canceller. Nothing here is
        // assumed: the spike reads platformAudioProcessingState back after
        // connect and falls back to software AEC if the platform unit refuses.
        let adm = factory.audioDeviceModule
        adm.setPlatformVoiceProcessingAllowed(true)
        adm.isVoiceProcessingBypassed = false
        // AGC stays OFF: between user turns the "input" is silence + residual
        // echo, and auto-gain pumping that residue up is a classic way to
        // resurrect echo the AEC already attenuated.
        adm.isVoiceProcessingAGCEnabled = false
        // Wake-feed path #3 (paths #1 capture-post APM and #2 track renderer
        // were device-proven dead — init=0/frames=0): observe the ADM's OWN
        // AVAudioEngine and tap its mic node. Same engine, no VPIO conflict.
        // Recording stays prepared so dormancy can't idle capture out.
        adm.observer = engineTap
        adm.setRecordingAlwaysPreparedMode(true)
        // THE fix for the zero-data tap (3:25am X-ray): default mute mode
        // silences at the voice-processing unit — UPSTREAM of the input node
        // we tap, so track-disable zeroed our wake feed too. .inputMixer
        // moves the mute point downstream of the tap: server still goes deaf
        // when the track is off, but the tap keeps hearing the room.
        adm.setMuteMode(.inputMixer)

        let config = LKRTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw RealtimeTransportError.notConnected
        }

        // Mic track first, so the offer contains the audio m-line.
        let source = factory.audioSource(with: constraints)
        let mic = factory.audioTrack(with: source, trackId: "polly-mic")
        pc.add(mic, streamIds: ["polly"])
        // Parallel wake-feed candidate: a renderer on the local track (the
        // capture-post hook was device-proven dead — never called by this
        // ADM). Key open question the spike answers: does this keep seeing
        // audio while the track is disabled (dormant)?
        mic.add(trackRenderer)

        // Protocol events ride this channel, both directions.
        let dcConfig = LKRTCDataChannelConfiguration()
        let dc = pc.dataChannel(forLabel: "oai-events", configuration: dcConfig)
        dc?.delegate = self

        lock.withLock {
            self.factory = factory
            self.processingModule = apm
            self.peerConnection = pc
            self.micTrack = mic
            self.dataChannel = dc
        }

        // Offer → wait for ICE gathering (OpenAI's answer is non-trickle; the
        // POSTed SDP must carry our candidates) → calls endpoint → answer.
        let offer = try await createOffer(pc, constraints: constraints)
        try await setLocalDescription(pc, offer)
        await waitForICEGathering(timeoutSeconds: 5)

        guard let localSDP = pc.localDescription?.sdp else {
            throw RealtimeTransportError.badURL
        }
        let answerSDP = try await postOffer(sdp: localSDP, token: token, model: model)
        try await setRemoteDescription(pc, LKRTCSessionDescription(type: .answer, sdp: answerSDP))

        // Connected means "events can flow": the data channel is open.
        try await waitForDataChannelOpen(timeoutSeconds: 10)
        startReopenMeter()
    }

    func send(_ event: RealtimeClientEvent) async throws {
        let data = try event.encoded()
        try sendData(data)
    }

    /// Spike/debug escape hatch: send a hand-built JSON event without going
    /// through `RealtimeClientEvent`. Not part of `RealtimeTransporting`.
    func sendRaw(_ json: String) throws {
        try sendData(Data(json.utf8))
    }

    // MARK: - Audio governor

    /// The session's intent; the governor combines it with playback state.
    func setMicMode(_ mode: PollyMicMode) {
        lock.withLock {
            micMode = mode
            if mode != .open { voiceReopened = false }
            resolveTrackLocked()
        }
        PollyDebugLog.shared.log("governor: micMode=\(mode)")
    }

    /// Mic stays closed until the greeting finishes playing (first
    /// output_audio_buffer.stopped) — the adaptive AEC's convergence window
    /// is the one place her own words can bounce back as user speech.
    /// A 6s failsafe prevents a lost event from leaving the mic dead.
    func holdMicForGreeting() {
        lock.withLock {
            greetingHold = true
            resolveTrackLocked()
        }
        PollyDebugLog.shared.log("governor: greeting hold ON")
        greetingFailsafeTask?.cancel()
        greetingFailsafeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.releaseGreetingHold(reason: "failsafe")
        }
    }

    /// Blocks until Polly's current audio finishes draining (or timeout) —
    /// keeps post-tool follow-ups from stacking onto a still-playing reply.
    func waitUntilAssistantQuiet(timeoutSeconds: Double) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !lock.withLock({ assistantSpeaking }) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Legacy spike API: true = open, false = dormant.
    func setMicEnabled(_ enabled: Bool) {
        setMicMode(enabled ? .open : .dormant)
    }

    private func releaseGreetingHold(reason: String) {
        let released = lock.withLock { () -> Bool in
            guard greetingHold else { return false }
            greetingHold = false
            resolveTrackLocked()
            return true
        }
        if released {
            greetingFailsafeTask?.cancel()
            greetingFailsafeTask = nil
            PollyDebugLog.shared.log("governor: greeting hold released (\(reason))")
        }
    }

    /// Wake word / pill: open the Realtime mic immediately even if the
    /// greeting is still playing or half-duplex has the track gated.
    /// Without this, UI shows Listening while the server hears silence —
    /// the classic "have to say Polly twice" bug.
    func forceMicOpenForWake() {
        releaseGreetingHold(reason: "wake")
        lock.withLock {
            micMode = .open
            voiceReopened = true
            resolveTrackLocked()
        }
        PollyDebugLog.shared.log("governor: force open for wake")
    }

    /// True when wake flipped UI to Listening but the track is still closed.
    var isMicServerGated: Bool {
        lock.withLock {
            !(micMode == .open && !greetingHold && (!assistantSpeaking || voiceReopened))
        }
    }

    /// The one place track state is computed. Caller must hold `lock`.
    private func resolveTrackLocked() {
        // Half-duplex: the mic track is closed for Polly's entire utterance, so
        // echo phantoms are physically impossible — but so is simply talking over
        // her. Getting back in means clearing an RMS gate, which is why
        // interrupting her takes a raised voice. Full duplex hands that job to
        // the echo canceller instead, which is only a good trade if the canceller
        // is actually running. Hence the toggle, and hence logging AEC state.
        let duplexAllows = PollyAudioLab.fullDuplex || !assistantSpeaking || voiceReopened
        let enabled = micMode == .open && !greetingHold && duplexAllows
        micTrack?.isEnabled = enabled
        hook.setServerMuted(!enabled)
    }

    /// Assistant playback state, driven from the data channel's
    /// output_audio_buffer events (parsed before decode so the governor works
    /// with any consumer, including tests that never read raw events).
    private func noteAssistantAudio(playing: Bool) {
        lock.withLock {
            assistantSpeaking = playing
            if playing { voiceReopened = false }
            resolveTrackLocked()
        }
        if !playing { releaseGreetingHold(reason: "greeting finished") }
        onAssistantAudioChange?(playing)
    }

    /// 50ms voice-reopen meter: while she talks and the track is gated, a
    /// real sustained voice reopens the mic (instant when loud, 2-in-600ms
    /// when normal). Consecutive-tick rules fail on syllable gaps.
    private func startReopenMeter() {
        meterTask?.cancel()
        meterTask = Task.detached(priority: .userInitiated) { [weak self] in
            var window: [Date] = []
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                let rms = self.captureRMS
                let fired: Bool = self.lock.withLock {
                    guard self.assistantSpeaking, self.micMode == .open,
                          !self.voiceReopened, !self.greetingHold else {
                        window.removeAll()
                        return false
                    }
                    let now = Date()
                    if rms > PollyConfig.bargeReopenSoftRMS { window.append(now) }
                    window.removeAll { now.timeIntervalSince($0) > 0.6 }
                    if rms > PollyConfig.bargeReopenLoudRMS || window.count >= 2 {
                        self.voiceReopened = true
                        self.resolveTrackLocked()
                        window.removeAll()
                        return true
                    }
                    return false
                }
                if fired {
                    PollyDebugLog.shared.log(String(format: "governor: voice during her turn (rms %.3f) — mic reopened", rms))
                    self.onBargeInReopen?()
                }
            }
        }
    }

    func close() async {
        lock.withLock { isClosing = true }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        meterTask?.cancel()
        meterTask = nil
        greetingFailsafeTask?.cancel()
        greetingFailsafeTask = nil
        iceGatheringContinuation?.resume()
        iceGatheringContinuation = nil
        channelOpenContinuation?.resume(throwing: CancellationError())
        channelOpenContinuation = nil
        dataChannel?.close()
        peerConnection?.close()
        lock.withLock {
            dataChannel = nil
            peerConnection = nil
            micTrack = nil
            factory = nil
            processingModule = nil
            assistantSpeaking = false
            greetingHold = false
            voiceReopened = false
        }
        continuation.finish()
    }

    // MARK: - Internals

    private func sendData(_ data: Data) throws {
        guard let dc = lock.withLock({ dataChannel }), dc.readyState == .open else {
            throw RealtimeTransportError.notConnected
        }
        dc.sendData(LKRTCDataBuffer(data: data, isBinary: false))
    }

    /// A phone call, alarm, Siri or another app took the session, then gave it
    /// back. On `.began` the input is dead whatever we do; on `.ended` with
    /// `shouldResume` the session has to be reactivated explicitly, because
    /// nothing does it for us and libwebrtc's audio unit will not restart on its
    /// own. Without this the cook went silent and never came back.
    private func handleInterruption(type: AVAudioSession.InterruptionType, userInfo: [AnyHashable: Any]?) {
        switch type {
        case .began:
            PollyDebugLog.shared.log("audio: INTERRUPTED (call, alarm, Siri or another app took the session)")
            onAudioInterrupted?(true)
        case .ended:
            let options = (userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            let shouldResume = options.contains(.shouldResume)
            PollyDebugLog.shared.log("audio: interruption ended shouldResume=\(shouldResume ? 1 : 0)")
            if shouldResume {
                do {
                    try PollyAudioSession.configure(active: true)
                    PollyDebugLog.shared.log("audio: session resumed \(PollyAudioSession.routeSummary())")
                } catch {
                    PollyDebugLog.shared.log("audio: session RESUME FAILED — \(error.localizedDescription)")
                }
            }
            onAudioInterrupted?(false)
        @unknown default:
            break
        }
    }

    /// Shared with the WebSocket engine path: `.videoChat` (speaker-tuned AEC),
    /// Bluetooth HFP allowed for AirPods, speaker override only when no headset.
    private func configureAudioSession() {
        let webRTCConfig = LKRTCAudioSessionConfiguration.webRTC()
        webRTCConfig.category = AVAudioSession.Category.playAndRecord.rawValue
        webRTCConfig.mode = AVAudioSession.Mode.videoChat.rawValue
        webRTCConfig.categoryOptions = PollyAudioSession.categoryOptions
        LKRTCAudioSessionConfiguration.setWebRTC(webRTCConfig)

        // What we are taking the session OVER from. The briefing runs immediately
        // before this with .playback/.spokenAudio, and a hot category swap on a
        // still-active session is a plausible reason the voice-processing unit
        // comes up unhappy. If this line ever reads Playback, the handover did
        // not happen.
        let incoming = AVAudioSession.sharedInstance()
        PollyDebugLog.shared.log(
            "audio: taking session from category=\(incoming.category.rawValue) mode=\(incoming.mode.rawValue)")

        do {
            try PollyAudioSession.configure(active: true)
            PollyDebugLog.shared.log("audio: WebRTC session \(PollyAudioSession.routeSummary())")
        } catch {
            PollyDebugLog.shared.log("audio: WebRTC session configure FAILED — \(error.localizedDescription)")
        }

        // A phone call, an alarm, Siri, or any other app taking the session used
        // to be entirely unhandled: nothing observed interruptions on the shipping
        // path, and DormantReason.audioInterrupted was a declared enum case that
        // nothing ever emitted. The cook simply went quiet and stayed quiet.
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                self?.handleInterruption(type: type, userInfo: note.userInfo)
            }
        }

        if routeObserver == nil {
            routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
            ) { note in
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                    .map(String.init) ?? "?"
                PollyDebugLog.shared.log(
                    "audio: ROUTE CHANGE reason=\(reason) \(PollyAudioSession.routeSummary())")
                // AirPods in/out: clear or restore speaker override so HFP can win.
                PollyAudioSession.applyPreferredOutputPort()
            }
        }
    }

    private func createOffer(
        _ pc: LKRTCPeerConnection, constraints: LKRTCMediaConstraints
    ) async throws -> LKRTCSessionDescription {
        try await withCheckedThrowingContinuation { cont in
            pc.offer(for: constraints) { sdp, error in
                if let sdp { cont.resume(returning: sdp) } else {
                    cont.resume(throwing: error ?? RealtimeTransportError.notConnected)
                }
            }
        }
    }

    private func setLocalDescription(
        _ pc: LKRTCPeerConnection, _ sdp: LKRTCSessionDescription
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(sdp) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    private func setRemoteDescription(
        _ pc: LKRTCPeerConnection, _ sdp: LKRTCSessionDescription
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(sdp) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    /// Resolves when ICE gathering completes (delegate) or the timeout passes —
    /// whichever first. The timeout path still POSTs whatever candidates exist.
    private func waitForICEGathering(timeoutSeconds: Double) async {
        if peerConnection?.iceGatheringState == .complete { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.withLock { iceGatheringContinuation = cont }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                guard let self else { return }
                let pending = self.lock.withLock { () -> CheckedContinuation<Void, Never>? in
                    let c = self.iceGatheringContinuation
                    self.iceGatheringContinuation = nil
                    return c
                }
                pending?.resume()
            }
        }
    }

    private func waitForDataChannelOpen(timeoutSeconds: Double) async throws {
        if lock.withLock({ dataChannel?.readyState }) == .open { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.withLock { channelOpenContinuation = cont }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                guard let self else { return }
                let pending = self.lock.withLock { () -> CheckedContinuation<Void, Error>? in
                    let c = self.channelOpenContinuation
                    self.channelOpenContinuation = nil
                    return c
                }
                pending?.resume(throwing: RealtimeTransportError.notConnected)
            }
        }
    }

    /// `POST /v1/realtime/calls?model=…` — offer SDP in, answer SDP out.
    /// 201 Created per the GA docs; 200 tolerated.
    private func postOffer(sdp: String, token: String, model: String) async throws -> String {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "api.openai.com"
        comps.path = "/v1/realtime/calls"
        comps.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let url = comps.url else { throw RealtimeTransportError.badURL }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(sdp.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...201).contains(http.statusCode),
              let answer = String(data: data, encoding: .utf8), !answer.isEmpty else {
            throw RealtimeTransportError.notConnected
        }
        return answer
    }
}

// MARK: - LKRTCDataChannelDelegate

extension RealtimeWebRTCTransport: LKRTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: LKRTCDataChannel) {
        switch dataChannel.readyState {
        case .open:
            let pending = lock.withLock { () -> CheckedContinuation<Void, Error>? in
                let c = channelOpenContinuation
                channelOpenContinuation = nil
                return c
            }
            pending?.resume()
        case .closed:
            let closing = lock.withLock { isClosing }
            if !closing {
                continuation.yield(.error(code: "transport", message: "Data channel closed"))
                continuation.finish()
            }
        default:
            break
        }
    }

    func dataChannel(_ dataChannel: LKRTCDataChannel, didReceiveMessageWith buffer: LKRTCDataBuffer) {
        if let onRawEvent, let text = String(data: buffer.data, encoding: .utf8) {
            onRawEvent(text)
        }
        let event = RealtimeServerEvent.decode(buffer.data)
        switch event {
        case .outputAudioStarted: noteAssistantAudio(playing: true)
        case .outputAudioStopped: noteAssistantAudio(playing: false)
        default: break
        }
        continuation.yield(event)
    }
}

// MARK: - LKRTCPeerConnectionDelegate

extension RealtimeWebRTCTransport: LKRTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {
        guard newState == .complete else { return }
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let c = iceGatheringContinuation
            iceGatheringContinuation = nil
            return c
        }
        pending?.resume()
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {
        if newState == .failed {
            let closing = lock.withLock { isClosing }
            if !closing {
                continuation.yield(.error(code: "transport", message: "ICE connection failed"))
                continuation.finish()
            }
        }
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {
        // OpenAI may open the events channel from its side; adopt it either way.
        dataChannel.delegate = self
        lock.withLock { self.dataChannel = dataChannel }
    }
}

// MARK: - Capture hook (wake-word feed)

/// Receives 10 ms capture frames from inside the WebRTC audio-processing
/// chain (post-AEC/NS, pre-encoder) — the only reliable way to observe the mic
/// during a call on iOS (no second tap; VPIO exclusivity). Converts channel 0
/// to a mono Float32 `AVAudioPCMBuffer` for SFSpeech/SpeechAnalyzer, tracks a
/// running RMS so UI/diagnostics can prove frames stay live while dormant.
final class PollyCaptureHook: NSObject, LKRTCAudioCustomProcessingDelegate, @unchecked Sendable {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// Rolling RMS of the most recent frame. Atomic-ish via lock; read by UI.
    var latestRMS: Float { lock.withLock { _latestRMS } }

    private let lock = NSLock()
    private var _latestRMS: Float = 0
    private var format: AVAudioFormat?
    private var serverMuted = false
    private var lastRenderActiveAt: Date = .distantPast
    private var onsetGateDeadline: Date?
    private var initCount = 0
    private var processCount = 0

    /// Liveness forensics: if `frames` stays 0 while a conversation works,
    /// this ADM never routes capture through the injected APM's custom
    /// processing — the wake feed must come from elsewhere.
    var stats: (inits: Int, frames: Int) {
        lock.withLock { (initCount, processCount) }
    }

    /// Dormant/greeting gate: zero everything bound for the server while the
    /// wake feed keeps the raw frames. Replaces track disabling, which was
    /// device-proven to kill capture (and the wake feed) entirely.
    func setServerMuted(_ muted: Bool) {
        lock.withLock { serverMuted = muted }
    }

    /// Fed by `PollyRenderMonitor` from the render (playback) side of the
    /// processing chain — sample-accurate truth about whether Polly's voice
    /// is physically coming out of the speaker. Arms v1's two proven gates:
    /// - onset gate: server hears silence for the first beat of each
    ///   utterance while the adaptive AEC re-converges on her voice.
    /// - RMS floor (applied in capture): while she's audibly speaking,
    ///   capture quieter than a close human voice is zeroed. A deliberate
    ///   barge-in sails over the floor.
    func noteRenderActive() {
        let now = Date()
        lock.withLock {
            if now.timeIntervalSince(lastRenderActiveAt) > 0.5 {
                onsetGateDeadline = now.addingTimeInterval(PollyConfig.onsetCaptureGateSeconds)
            }
            lastRenderActiveAt = now
        }
    }

    func audioProcessingInitialize(sampleRate sampleRateHz: Int, channels: Int) {
        lock.withLock {
            initCount += 1
            format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRateHz),
                channels: 1,
                interleaved: false
            )
        }
    }

    func audioProcessingProcess(audioBuffer: LKRTCAudioBuffer) {
        lock.withLock { processCount += 1 }
        let frames = audioBuffer.frames
        guard frames > 0, audioBuffer.channels > 0 else { return }
        let source = audioBuffer.rawBuffer(forChannel: 0)

        var sum: Float = 0
        for i in 0..<frames { sum += source[i] * source[i] }
        let rms = (sum / Float(frames)).squareRoot()
        lock.withLock { _latestRMS = rms }

        // Wake-word feed gets the RAW frames, before any server-side gating —
        // "Polly" must be hearable even while she's talking or gated.
        if let onBuffer, let format = lock.withLock({ format }),
           let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) {
            pcm.frameLength = AVAudioFrameCount(frames)
            if let dest = pcm.floatChannelData?[0] {
                dest.update(from: source, count: frames)
            }
            onBuffer(pcm)
        }

        // Server-bound gates: dormant mute, onset gate, RMS floor while her
        // voice is audibly playing (render seen within the last 350ms).
        let now = Date()
        let (muted, gateOnset, playing) = lock.withLock {
            (serverMuted,
             onsetGateDeadline.map { now < $0 } ?? false,
             now.timeIntervalSince(lastRenderActiveAt) < 0.35)
        }
        if muted || gateOnset || (playing && rms < PollyConfig.bargeInRMSFloor) {
            for channel in 0..<audioBuffer.channels {
                audioBuffer.rawBuffer(forChannel: channel).update(repeating: 0, count: frames)
            }
        }
    }

    func audioProcessingRelease() {
        lock.withLock {
            format = nil
            _latestRMS = 0
            serverMuted = false
            lastRenderActiveAt = .distantPast
            onsetGateDeadline = nil
        }
    }
}

/// Render-side (playback) observer: tells the capture hook, sample-accurately,
/// when Polly's voice is actually being played — no event-loop lag. Observe
/// only; frames pass through untouched.
final class PollyRenderMonitor: NSObject, LKRTCAudioCustomProcessingDelegate, @unchecked Sendable {
    private unowned let hook: PollyCaptureHook

    init(hook: PollyCaptureHook) {
        self.hook = hook
        super.init()
    }

    func audioProcessingInitialize(sampleRate sampleRateHz: Int, channels: Int) {}

    func audioProcessingProcess(audioBuffer: LKRTCAudioBuffer) {
        let frames = audioBuffer.frames
        guard frames > 0, audioBuffer.channels > 0 else { return }
        let source = audioBuffer.rawBuffer(forChannel: 0)
        var sum: Float = 0
        for i in 0..<frames { sum += source[i] * source[i] }
        if (sum / Float(frames)).squareRoot() > 0.0005 {
            hook.noteRenderActive()
        }
    }

    func audioProcessingRelease() {}
}

/// Wake-feed path #3: observes the ADM's own AVAudioEngine via the module's
/// delegate seam and taps the mic-side node inside it. One engine — no VPIO
/// exclusivity conflict — and the tap sits upstream of WebRTC's track gating,
/// so it should keep hearing the room while the track is disabled (dormant).
///
/// 3:18am forensics round: frames flow but carry ZEROS on `source ??
/// inputNode` — the node renders on schedule without the mic signal. This
/// version X-rays the graph (`onGraphInfo`) and runs TWO probes — A on the
/// source/input node, B on the context's input mixer — to find which node
/// actually carries audio.
final class PollyEngineTapObserver: NSObject, LKRTCAudioDeviceModuleDelegate, @unchecked Sendable {
    struct ProbeStats {
        var frames = 0
        var rms: Float = 0
        var peak: Float = 0
    }

    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// One-time description of the ADM's input graph, for the spike log.
    var onGraphInfo: ((String) -> Void)?

    var statsA: ProbeStats { lock.withLock { probeA } }
    var statsB: ProbeStats { lock.withLock { probeB } }
    var latestRMS: Float { lock.withLock { max(probeA.rms, probeB.rms) } }
    var frames: Int { lock.withLock { probeA.frames } }

    private let lock = NSLock()
    private var probeA = ProbeStats()
    private var probeB = ProbeStats()
    private weak var nodeA: AVAudioNode?
    private weak var nodeB: AVAudioNode?

    // MARK: LKRTCAudioDeviceModuleDelegate

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule,
        didReceiveSpeechActivityEvent speechActivityEvent: LKRTCSpeechActivityEvent
    ) {}

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule, didCreateEngine engine: AVAudioEngine
    ) -> Int { 0 }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule, willEnableEngine engine: AVAudioEngine,
        isPlayoutEnabled: Bool, isRecordingEnabled: Bool
    ) -> Int { 0 }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule, willStartEngine engine: AVAudioEngine,
        isPlayoutEnabled: Bool, isRecordingEnabled: Bool
    ) -> Int { 0 }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule, didStopEngine engine: AVAudioEngine,
        isPlayoutEnabled: Bool, isRecordingEnabled: Bool
    ) -> Int {
        removeTap()
        return 0
    }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule, didDisableEngine engine: AVAudioEngine,
        isPlayoutEnabled: Bool, isRecordingEnabled: Bool
    ) -> Int {
        removeTap()
        return 0
    }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule, willReleaseEngine engine: AVAudioEngine
    ) -> Int {
        removeTap()
        return 0
    }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule, engine: AVAudioEngine,
        configureInputFromSource source: AVAudioNode?, toDestination destination: AVAudioNode,
        format: AVAudioFormat, context: [AnyHashable: Any]
    ) -> Int {
        let mixer = context.values.compactMap { $0 as? AVAudioMixerNode }.first

        let sourceDesc = source.map { String(describing: type(of: $0)) } ?? "nil"
        let keys = context.keys.map { String(describing: $0) }.joined(separator: ",")
        onGraphInfo?(
            "🧭 input graph: src=\(sourceDesc) dst=\(String(describing: type(of: destination)))"
            + " fmt=\(Int(format.sampleRate))Hz/\(format.channelCount)ch/"
            + (format.commonFormat == .pcmFormatInt16 ? "i16" : format.commonFormat == .pcmFormatFloat32 ? "f32" : "other")
            + " ctx=[\(keys)] mixer=\(mixer != nil ? "yes" : "no")"
        )

        // Probe A: the node the ADM hands us (previous rounds: frames flowed
        // but all-zero). Probe B: the input mixer from the context, if any.
        installProbe(on: source ?? engine.inputNode, format: format, index: 0, forward: true)
        if let mixer, mixer !== (source ?? engine.inputNode) {
            installProbe(on: mixer, format: nil, index: 1, forward: false)
        }
        return 0
    }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule, engine: AVAudioEngine,
        configureOutputFromSource source: AVAudioNode, toDestination destination: AVAudioNode?,
        format: AVAudioFormat, context: [AnyHashable: Any]
    ) -> Int { 0 }

    func audioDeviceModuleDidUpdateDevices(_ audioDeviceModule: LKRTCAudioDeviceModule) {}

    // MARK: Probes

    private func installProbe(on node: AVAudioNode, format: AVAudioFormat?, index: Int, forward: Bool) {
        (index == 0 ? nodeA : nodeB)?.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            var peak: Float = 0
            if let floats = buffer.floatChannelData?[0] {
                for i in 0..<n {
                    let v = floats[i]
                    sum += v * v
                    peak = max(peak, abs(v))
                }
            } else if let ints = buffer.int16ChannelData?[0] {
                for i in 0..<n {
                    let v = Float(ints[i]) / Float(Int16.max)
                    sum += v * v
                    peak = max(peak, abs(v))
                }
            }
            let rms = (sum / Float(n)).squareRoot()
            self.lock.withLock {
                if index == 0 {
                    self.probeA.frames += 1
                    self.probeA.rms = rms
                    self.probeA.peak = max(self.probeA.peak, peak)
                } else {
                    self.probeB.frames += 1
                    self.probeB.rms = rms
                    self.probeB.peak = max(self.probeB.peak, peak)
                }
            }
            if forward { self.onBuffer?(buffer) }
        }
        if index == 0 { nodeA = node } else { nodeB = node }
    }

    private func removeTap() {
        nodeA?.removeTap(onBus: 0)
        nodeB?.removeTap(onBus: 0)
        nodeA = nil
        nodeB = nil
    }
}

/// Fallback mic observer: attached to the local audio track via addRenderer.
/// Observe-only (cannot mute), delivers AVAudioPCMBuffer directly. Candidate
/// wake-word feed if it stays live while the track is disabled.
final class PollyLocalTrackRenderer: NSObject, LKRTCAudioRenderer, @unchecked Sendable {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    var latestRMS: Float { lock.withLock { _latestRMS } }
    var frames: Int { lock.withLock { frameCount } }

    private let lock = NSLock()
    private var _latestRMS: Float = 0
    private var frameCount = 0

    func render(pcmBuffer: AVAudioPCMBuffer) {
        let n = Int(pcmBuffer.frameLength)
        guard n > 0 else { return }

        var rms: Float = 0
        if let floats = pcmBuffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<n { sum += floats[i] * floats[i] }
            rms = (sum / Float(n)).squareRoot()
        } else if let ints = pcmBuffer.int16ChannelData?[0] {
            var sum: Float = 0
            for i in 0..<n {
                let v = Float(ints[i]) / Float(Int16.max)
                sum += v * v
            }
            rms = (sum / Float(n)).squareRoot()
        }
        lock.withLock {
            _latestRMS = rms
            frameCount += 1
        }
        onBuffer?(pcmBuffer)
    }
}
