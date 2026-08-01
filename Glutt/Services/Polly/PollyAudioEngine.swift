import AVFoundation
import Observation
import os

// MARK: - PCM helpers

/// Pure PCM conversion utilities for the Realtime wire format (16-bit
/// little-endian mono at 24 kHz). No hardware access — fully unit-testable.
enum PCM {
    /// Extracts channel 0 of a float32 or int16 buffer as little-endian
    /// 16-bit mono `Data`. Float samples are clamped to -1...1 first.
    static func pcm16Data(from buffer: AVAudioPCMBuffer) -> Data {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return Data() }
        var samples = [Int16](repeating: 0, count: frames)

        if let floatChannels = buffer.floatChannelData {
            let channel = floatChannels[0]
            let step = buffer.stride
            for frame in 0..<frames {
                let clamped = max(-1, min(1, channel[frame * step]))
                samples[frame] = Int16((clamped * 32_767).rounded()).littleEndian
            }
        } else if let intChannels = buffer.int16ChannelData {
            let channel = intChannels[0]
            let step = buffer.stride
            for frame in 0..<frames {
                samples[frame] = channel[frame * step].littleEndian
            }
        } else {
            return Data()
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Rebuilds an int16 mono buffer from little-endian PCM16 bytes.
    /// `format` must be a 1-channel `.pcmFormatInt16` format.
    static func buffer(fromPCM16 data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard format.commonFormat == .pcmFormatInt16, format.channelCount == 1 else { return nil }
        let frames = data.count / MemoryLayout<Int16>.size
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.int16ChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            for frame in 0..<frames {
                channel[frame] = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: frame * 2, as: Int16.self))
            }
        }
        return buffer
    }

    /// Converts a buffer to another sample rate and/or sample format via
    /// `AVAudioConverter`. Returns nil on any conversion failure.
    static func resample(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        // No priming latency: per-buffer streaming conversion must not eat frames.
        converter.primeMethod = .none

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var fedSource = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if fedSource {
                outStatus.pointee = .endOfStream
                return nil
            }
            fedSource = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, status != .error else { return nil }
        // Trim any padding frames the converter appended beyond the expected output.
        let expectedFrames = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded())
        if output.frameLength > expectedFrames {
            output.frameLength = expectedFrames
        }
        return output
    }
}

// MARK: - Errors

enum PollyAudioError: LocalizedError {
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: "The microphone isn't available right now."
        }
    }
}

// MARK: - Engine

/// Owns the echo-cancelled voice pipeline for a live Polly session: mic
/// capture (emitted as ~100 ms base64 PCM16 24 kHz chunks for the Realtime
/// socket) and assistant audio playback through a player node. Everything
/// hardware-touching is confined to `start()`/`stop()`; failures throw from
/// `start()` and never crash.
@MainActor
@Observable
final class PollyAudioEngine {
    private(set) var isRunning = false
    /// While muted the tap stays installed but chunk emission is gated off, so
    /// nothing reaches the socket. We deliberately do NOT toggle the IO unit's
    /// `isVoiceProcessingInputMuted`: doing so can fire an engine configuration
    /// change that stops the graph (dead mic tap) and the voice-processing mute
    /// can wedge so capture never truly re-enables — the "mute → unmute → Polly
    /// stops listening, silent fail" bug. The render-thread `mutedFlag` gate is
    /// enough to guarantee silence upstream, and it's instantly reversible.
    var isMuted = false {
        didSet {
            let value = isMuted
            mutedFlag.withLock { $0 = value }
            guard !value else { return }
            // Unmuting: clear any stale onset/greeting capture gate that would
            // otherwise keep dropping the cook's audio, and make sure the engine
            // (hence the mic tap) is actually running before we resume.
            captureGateDeadline.withLock { $0 = 0 }
            restartEngineIfNeeded()
        }
    }
    /// True while any assistant audio buffer is scheduled and unplayed.
    private(set) var isPlaying = false
    /// Smoothed mic RMS in 0...1, for the session orb.
    private(set) var inputLevel: Float = 0
    /// Fired on main when the audio session is interrupted (`true` = began)
    /// or when mic permission / capture is lost.
    var onSessionInterrupted: ((Bool) -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private var isPlayerAttached = false
    @ObservationIgnored private var voiceProcessingActive = false
    @ObservationIgnored private var routeObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var configObserver: NSObjectProtocol?
    /// CFAbsoluteTime when mic first cleared the speaking barge-in floor; 0 = none.
    @ObservationIgnored private let sustainedSpeechSince = OSAllocatedUnfairLock(initialState: 0.0)
    @ObservationIgnored private var enqueueCount = 0
    @ObservationIgnored private var outstandingBuffers = 0
    @ObservationIgnored private let mutedFlag = OSAllocatedUnfairLock(initialState: false)
    /// Deadline (CFAbsoluteTime) until which mic chunks are dropped. Armed at
    /// each utterance onset — the AEC-vulnerable window where Polly's own
    /// opening words leak into the mic and trip server VAD (false barge-ins).
    @ObservationIgnored private let captureGateDeadline = OSAllocatedUnfairLock(initialState: 0.0)
    /// Mirrors `isPlaying` for the audio render thread. While true, mic buffers
    /// quieter than `PollyConfig.bargeInRMSFloor` are dropped — residual echo of
    /// Polly's own voice and slight room noise stay below it, so they can't trip
    /// server VAD and cut her off, while a clear close voice clears it and can
    /// still barge in. Between turns (false) the mic is fully open.
    @ObservationIgnored private let speakingFlag = OSAllocatedUnfairLock(initialState: false)
    /// 4 800 bytes = 2 400 Int16 samples = ~100 ms at 24 kHz.
    @ObservationIgnored private let accumulator = PCMChunkAccumulator(chunkByteCount: 4_800)

    /// PCM16 mono 24 kHz — what the Realtime socket speaks in both directions.
    /// Force-unwraps are safe: these initializers only fail for invalid parameters.
    @ObservationIgnored private let wireFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: false
    )!
    /// Float mono 24 kHz — what the player node feeds the main mixer.
    @ObservationIgnored private let playbackFormat = AVAudioFormat(
        standardFormatWithSampleRate: 24_000, channels: 1
    )!

    // MARK: Capture

    /// `onBuffer`, if given, receives every raw mic buffer BEFORE the mute gate —
    /// so an on-device wake-word listener keeps hearing even while the Realtime
    /// input is muted (dormant). It must be cheap and thread-safe (audio thread).
    func start(onChunk: @escaping @Sendable (String) -> Void,
               onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? = nil) throws {
        guard !isRunning else { return }

        // Never touch AVAudioEngine without a granted mic. This is a check,
        // not a prompt (the session view requests permission BEFORE start()).
        // It also keeps CoreAudio entirely out of unit tests: accessing
        // `engine.inputNode` while the host's audio server is unresponsive
        // aborts the process inside AudioToolbox (RPC timeout) — not a
        // catchable Swift error.
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw PollyAudioError.microphoneUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        // Allow Bluetooth HFP so AirPods work for mic + speaker. Prefer the
        // headset when it's on the route; otherwise force the built-in speaker
        // (kitchen counter). See PollyAudioSession.
        try PollyAudioSession.configure(active: true)
        PollyDebugLog.shared.log(
            "audio: session active — sampleRate=\(session.sampleRate) sysVolume=\(session.outputVolume) "
            + "route \(PollyAudioSession.routeSummary())")
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).map(String.init) ?? "?"
            PollyDebugLog.shared.log(
                "audio: ROUTE CHANGE reason=\(reason) \(PollyAudioSession.routeSummary())")
            // AirPods in/out mid-cook: drop/restore speaker override, then
            // re-arm the engine if iOS stopped it on the graph change.
            Task { @MainActor [weak self] in
                PollyAudioSession.applyPreferredOutputPort()
                self?.restartEngineIfNeeded()
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            let typeVal = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = typeVal == AVAudioSession.InterruptionType.began.rawValue
            PollyDebugLog.shared.log("audio: INTERRUPTION began=\(began)")
            Task { @MainActor [weak self] in
                self?.onSessionInterrupted?(began)
            }
        }

        let input = engine.inputNode
        // REAL echo cancellation. The session's .voiceChat mode alone does NOT
        // give a custom AVAudioEngine graph echo cancellation — without this,
        // Polly's own voice re-enters the mic, the server's VAD hears "the
        // user", cancels her mid-sentence, and she answers her own words (the
        // repeat/stack/cut-off loop from live testing). Enabling voice
        // processing on the input node pairs the output node automatically,
        // and brings AGC + noise suppression along — good in a loud kitchen.
        do {
            try input.setVoiceProcessingEnabled(true)
            voiceProcessingActive = true
            PollyDebugLog.shared.log("audio: voice processing ENABLED (AEC on)")
        } catch {
            voiceProcessingActive = false   // degraded: raw IO, no AEC
            PollyDebugLog.shared.log("audio: voice processing FAILED (\(error.localizedDescription)) — no AEC")
        }
        let inputFormat = input.inputFormat(forBus: 0)
        PollyDebugLog.shared.log("audio: inputFormat=\(Int(inputFormat.sampleRate))Hz ch=\(inputFormat.channelCount)")
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw PollyAudioError.microphoneUnavailable
        }

        if !isPlayerAttached {
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
            isPlayerAttached = true
        }

        accumulator.reset()
        let wire = wireFormat
        let muted = mutedFlag
        let gate = captureGateDeadline
        let speaking = speakingFlag
        let sustained = sustainedSpeechSince
        let accumulator = self.accumulator
        let forwardBuffer = onBuffer
        let firstTapLogged = OSAllocatedUnfairLock(initialState: false)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_400, format: inputFormat) { [weak self] buffer, _ in
            // Audio render thread: PCM math + lock-guarded state only.
            let logFirst = firstTapLogged.withLock { seen -> Bool in
                if seen { return false }
                seen = true
                return true
            }
            if logFirst {
                // The delivered format is authoritative — with voice processing
                // it can differ from what inputFormat(forBus:) reported.
                PollyDebugLog.shared.log(
                    "audio: first mic buffer — actual=\(Int(buffer.format.sampleRate))Hz "
                    + "ch=\(buffer.format.channelCount) frames=\(buffer.frameLength)")
            }
            let level = Self.rms(of: buffer)
            Task { @MainActor [weak self] in self?.smoothLevel(level) }
            // Wake-word listener hears the raw mic even while the socket is muted
            // (dormant), so "Hey Chef" can un-gate the Realtime input.
            forwardBuffer?(buffer)
            guard !muted.withLock({ $0 }) else { return }
            // Utterance-onset gate: drop chunks while the echo canceller is
            // still adapting to Polly's voice (see PollyConfig).
            guard gate.withLock({ CFAbsoluteTimeGetCurrent() >= $0 }) else { return }
            // Two-stage barge-in while Polly speaks: stricter RMS floor + must
            // stay above it for bargeInSustainedMs (pan clank / sizzle die out).
            if speaking.withLock({ $0 }) {
                let floor = PollyConfig.bargeInSpeakingRMSFloor > 0
                    ? PollyConfig.bargeInSpeakingRMSFloor
                    : PollyConfig.bargeInRMSFloor
                if level < floor {
                    sustained.withLock { $0 = 0 }
                    return
                }
                let now = CFAbsoluteTimeGetCurrent()
                let since = sustained.withLock { (start: inout CFAbsoluteTime) -> CFAbsoluteTime in
                    if start == 0 {
                        start = now
                        return now
                    }
                    return start
                }
                let needed = Double(PollyConfig.bargeInSustainedMs) / 1_000
                if now - since < needed { return }
            } else {
                sustained.withLock { $0 = 0 }
            }
            guard let converted = PCM.resample(buffer, to: wire) else { return }
            accumulator.append(PCM.pcm16Data(from: converted), emit: onChunk)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            PollyDebugLog.shared.log("audio: engine.start FAILED — \(error.localizedDescription)")
            throw error
        }
        playerNode.volume = 1
        engine.mainMixerNode.outputVolume = 1
        playerNode.play()
        isRunning = true
        PollyDebugLog.shared.log(
            "audio: engine running — output=\(Int(engine.outputNode.outputFormat(forBus: 0).sampleRate))Hz "
            + "mixerVol=\(engine.mainMixerNode.outputVolume) playerVol=\(playerNode.volume)")

        // iOS silently STOPS the engine whenever the audio graph gets
        // reconfigured (voice-processing init, route/category change — the
        // live-call log showed engineRunning=false 0.02s after start). A
        // stopped engine is silent playback AND a dead mic tap, so re-arm it.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                PollyDebugLog.shared.log("audio: CONFIG CHANGE — engineRunning=\(self.engine.isRunning)")
                self.restartEngineIfNeeded()
            }
        }
    }

    /// Re-arms a stopped engine (playback + mic tap) mid-session.
    private func restartEngineIfNeeded() {
        guard isRunning, !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
            playerNode.play()
            PollyDebugLog.shared.log("audio: engine RESTARTED ok")
        } catch {
            PollyDebugLog.shared.log("audio: engine restart FAILED — \(error.localizedDescription)")
        }
    }

    func stop() {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        onSessionInterrupted = nil
        // Everything below only makes sense for an engine that actually started.
        //
        // In the shipped WebRTC path `start()` is never called, yet `stop()` is —
        // from PollySessionController.end(), three lines before transport.close().
        // So this method used to deactivate the shared AVAudioSession out from
        // under a live WebRTC stack, behind libwebrtc's back and with its
        // activationCount left unbalanced. It is reachable mid-cook whenever
        // Polly calls her own end_session tool. Touching inputNode is not free
        // either: it lazily instantiates the node and queries the hardware format
        // against that same live session.
        guard isRunning else {
            PollyDebugLog.shared.log("audio: stop() on an engine that never started — nothing to tear down")
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        if isPlayerAttached { playerNode.stop() }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        accumulator.reset()
        outstandingBuffers = 0
        enqueueCount = 0
        setPlaying(false)
        isRunning = false
        inputLevel = 0
        PollyDebugLog.shared.log("audio: stopped")
    }

    /// Puts the player node into the clean STOPPED state a barge-in leaves it
    /// in, so the FIRST utterance renders exactly like every later one. After
    /// the AEC-triggered engine restart the player reports isPlaying but its
    /// render pipeline hasn't actually re-engaged — the greeting scheduled into
    /// it is silently dropped (caption shows, no sound), while every later turn
    /// works because a barge-in stop()/play() cycle preceded it. enqueue()
    /// re-play()s it fresh when the audio arrives. Only meaningful with an
    /// empty queue (early startup), so it never discards live audio.
    func resetPlaybackForNextUtterance() {
        guard isRunning, isPlayerAttached, outstandingBuffers == 0 else { return }
        playerNode.stop()
        setPlaying(false)
        PollyDebugLog.shared.log("audio: player reset to stopped — fresh render for greeting")
    }

    /// Suspends until scheduled assistant audio has finished playing (or the
    /// timeout elapses). Used so a post-tool follow-up response can't start
    /// speaking while her previous sentence is still draining from the queue.
    func waitUntilQuiet(timeoutSeconds: TimeInterval = 12) async {
        let deadline = CFAbsoluteTimeGetCurrent() + timeoutSeconds
        while outstandingBuffers > 0, CFAbsoluteTimeGetCurrent() < deadline {
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    /// Suppresses mic capture for `seconds` from now (extends, never shortens,
    /// any gate already armed). Used to bridge the session-startup window so
    /// ambient noise / echo can't trip server VAD and truncate Polly's greeting
    /// before it's heard.
    func holdCapture(forSeconds seconds: TimeInterval) {
        let deadline = CFAbsoluteTimeGetCurrent() + seconds
        captureGateDeadline.withLock { $0 = max($0, deadline) }
        PollyDebugLog.shared.log("audio: capture held for \(seconds)s")
    }

    // MARK: Playback

    /// Decodes a base64 PCM16 24 kHz chunk from the socket and queues it.
    func enqueue(base64: String) {
        guard isRunning else {
            PollyDebugLog.shared.log("audio: enqueue DROPPED — engine not running")
            return
        }
        guard let data = Data(base64Encoded: base64),
              let wireBuffer = PCM.buffer(fromPCM16: data, format: wireFormat),
              let playable = PCM.resample(wireBuffer, to: playbackFormat) else {
            PollyDebugLog.shared.log("audio: enqueue DROPPED — decode/convert failed")
            return
        }

        // Self-heal: scheduling into a stopped engine is silent audio loss.
        restartEngineIfNeeded()

        // A new utterance is starting (nothing was queued): arm the onset
        // capture gate so her opening words can't echo back as "user speech".
        // Use max() so this never SHORTENS a longer hold already in place (e.g.
        // the greeting mic-hold armed before her first audio arrived).
        if outstandingBuffers == 0 {
            let deadline = CFAbsoluteTimeGetCurrent() + PollyConfig.onsetCaptureGateSeconds
            captureGateDeadline.withLock { $0 = max($0, deadline) }
            PollyDebugLog.shared.log("audio: onset capture gate armed (\(PollyConfig.onsetCaptureGateSeconds)s)")
        }

        enqueueCount += 1
        if enqueueCount == 1 || enqueueCount % 50 == 0 {
            PollyDebugLog.shared.log(
                "audio: enqueue #\(enqueueCount) frames=\(playable.frameLength) "
                + "playerPlaying=\(playerNode.isPlaying) engineRunning=\(engine.isRunning) queued=\(outstandingBuffers)")
        }
        outstandingBuffers += 1
        setPlaying(true)
        playerNode.scheduleBuffer(playable) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.outstandingBuffers = max(0, self.outstandingBuffers - 1)
                self.setPlaying(self.outstandingBuffers > 0)
            }
        }
        if !playerNode.isPlaying { playerNode.play() }
    }

    /// Stops assistant playback (barge-in) and reports how many milliseconds
    /// have actually rendered, for `conversation.item.truncate`.
    @discardableResult
    func interruptPlayback() -> Int {
        outstandingBuffers = 0
        setPlaying(false)
        guard isPlayerAttached else { return 0 }

        var playedMs = 0
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
           playerTime.sampleRate > 0 {
            playedMs = max(0, Int(Double(playerTime.sampleTime) * 1_000 / playerTime.sampleRate))
        }
        playerNode.stop()
        return playedMs
    }

    /// Non-destructive read of the same player-node timeline `interruptPlayback()`
    /// reports — cumulative ms rendered since the player node started, NOT ms into
    /// the current assistant item (the node never stops between turns). The
    /// controller samples this at the start of each assistant item and subtracts
    /// the baseline so barge-in can send a per-item `audio_end_ms` that
    /// `conversation.item.truncate` accepts. Returns 0 when the timeline is
    /// unavailable. Reads only; does not touch playback state.
    func currentPlayedMs() -> Int {
        guard isPlayerAttached,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else { return 0 }
        return max(0, Int(Double(playerTime.sampleTime) * 1_000 / playerTime.sampleRate))
    }

    /// Keeps the observable `isPlaying` and the render-thread `speakingFlag`
    /// (which gates the barge-in noise floor) in lockstep.
    private func setPlaying(_ value: Bool) {
        isPlaying = value
        speakingFlag.withLock { $0 = value }
    }

    // MARK: Level metering

    private func smoothLevel(_ rawRMS: Float) {
        // Voice RMS rarely exceeds ~0.25; boost before clamping so the orb
        // has range, then smooth so it breathes instead of flickering.
        let boosted = min(1, rawRMS * 4)
        inputLevel = inputLevel * 0.8 + boosted * 0.2
    }

    nonisolated private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0, let channel = buffer.floatChannelData?[0] else { return 0 }
        let step = buffer.stride
        var sum: Float = 0
        for frame in 0..<frames {
            let sample = channel[frame * step]
            sum += sample * sample
        }
        return sqrt(sum / Float(frames))
    }
}

// MARK: - Chunk accumulator

/// Collects converted mic bytes on the audio tap thread and emits fixed-size
/// base64 chunks. Lock-guarded because the tap thread and `reset()` race.
private final class PCMChunkAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let chunkByteCount: Int
    private var pending = Data()

    init(chunkByteCount: Int) {
        self.chunkByteCount = chunkByteCount
    }

    func append(_ data: Data, emit: (String) -> Void) {
        lock.lock()
        pending.append(data)
        var chunks: [Data] = []
        while pending.count >= chunkByteCount {
            chunks.append(Data(pending.prefix(chunkByteCount)))
            pending.removeFirst(chunkByteCount)
        }
        lock.unlock()
        for chunk in chunks {
            emit(chunk.base64EncodedString())
        }
    }

    func reset() {
        lock.lock()
        pending.removeAll()
        lock.unlock()
    }
}
