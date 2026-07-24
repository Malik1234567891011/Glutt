import AVFoundation
import Foundation
import LiveKitWebRTC

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
        set { hook.onBuffer = newValue }
    }

    /// Raw JSON of every server event, before decoding. Spike/debug use.
    var onRawEvent: ((String) -> Void)?

    /// Latest capture-frame RMS from the hook (spike/diagnostics readout).
    var captureRMS: Float { hook.latestRMS }

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
        return "audio: vpAllowed=\(adm.isPlatformVoiceProcessingAllowed ? 1 : 0)"
            + " vpBypassed=\(adm.isVoiceProcessingBypassed ? 1 : 0)"
            + " vpActive=\(state.isVoiceProcessingEnabledActive ? 1 : 0)"
            + " AEC[avail=\(aec.isAvailable ? 1 : 0) req=\(aec.isRequested ? 1 : 0) ACTIVE=\(aec.isActive ? 1 : 0)]"
            + " NS[active=\(state.noiseSuppression.isActive ? 1 : 0)]"
            + " engine=\(adm.isEngineRunning ? "running" : "stopped")"
    }

    /// Fallback when the platform (VPIO) echo canceller won't engage: turn on
    /// libWebRTC's software AEC in mobile mode. Runtime-swappable by design —
    /// the APM's `config` property applies live.
    func enableSoftwareAEC() {
        guard let apm = lock.withLock({ processingModule }) else { return }
        let config = LKRTCAudioProcessingConfig()
        config.isEchoCancellationEnabled = true
        config.isEchoCancellationMobileMode = true
        config.isNoiseSuppressionEnabled = true
        config.isHighpassFilterEnabled = true
        apm.config = config
    }

    private let continuation: AsyncStream<RealtimeServerEvent>.Continuation
    private let hook: PollyCaptureHook
    private let renderMonitor: PollyRenderMonitor
    private let lock = NSLock()

    private var factory: LKRTCPeerConnectionFactory?
    private var processingModule: LKRTCDefaultAudioProcessingModule?
    private var peerConnection: LKRTCPeerConnection?
    private var dataChannel: LKRTCDataChannel?
    private var micTrack: LKRTCAudioTrack?

    private var iceGatheringContinuation: CheckedContinuation<Void, Never>?
    private var channelOpenContinuation: CheckedContinuation<Void, Error>?
    private var isClosing = false

    override init() {
        let (stream, continuation) = AsyncStream.makeStream(of: RealtimeServerEvent.self)
        self.events = stream
        self.continuation = continuation
        let hook = PollyCaptureHook()
        self.hook = hook
        self.renderMonitor = PollyRenderMonitor(hook: hook)
        super.init()
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

    /// Dormant gate. Device-proven finding (2026-07-24): disabling the mic
    /// TRACK kills the whole capture path — including the wake-word feed. So
    /// dormancy is enforced INSIDE the capture hook instead: the track stays
    /// enabled, capture keeps running (AEC stays converged, wake feed stays
    /// hot), and the hook zeroes every frame bound for the server. What
    /// leaves the device while dormant is literal silence.
    func setMicEnabled(_ enabled: Bool) {
        hook.setServerMuted(!enabled)
    }

    func close() async {
        lock.withLock { isClosing = true }
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

    /// Mirrors v1's proven speakerphone config: `.videoChat` (speaker-tuned
    /// AEC) beat `.voiceChat` in the echo war; Bluetooth stays off for
    /// determinism. The same values are pushed into WebRTC's OWN session
    /// configuration — the ADM re-applies that template whenever it starts
    /// the engine, and its stock template would otherwise clobber ours.
    private func configureAudioSession() {
        let webRTCConfig = LKRTCAudioSessionConfiguration.webRTC()
        webRTCConfig.category = AVAudioSession.Category.playAndRecord.rawValue
        webRTCConfig.mode = AVAudioSession.Mode.videoChat.rawValue
        webRTCConfig.categoryOptions = [.defaultToSpeaker]
        LKRTCAudioSessionConfiguration.setWebRTC(webRTCConfig)

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker])
        try? session.overrideOutputAudioPort(.speaker)
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
        continuation.yield(RealtimeServerEvent.decode(buffer.data))
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
            format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRateHz),
                channels: 1,
                interleaved: false
            )
        }
    }

    func audioProcessingProcess(audioBuffer: LKRTCAudioBuffer) {
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
