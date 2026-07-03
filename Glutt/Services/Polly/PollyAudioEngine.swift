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
    /// While muted the tap stays installed; chunk emission is gated off.
    var isMuted = false {
        didSet {
            let value = isMuted
            mutedFlag.withLock { $0 = value }
        }
    }
    /// True while any assistant audio buffer is scheduled and unplayed.
    private(set) var isPlaying = false
    /// Smoothed mic RMS in 0...1, for the session orb.
    private(set) var inputLevel: Float = 0

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private var isPlayerAttached = false
    @ObservationIgnored private var outstandingBuffers = 0
    @ObservationIgnored private let mutedFlag = OSAllocatedUnfairLock(initialState: false)
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

    func start(onChunk: @escaping @Sendable (String) -> Void) throws {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
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
        let accumulator = self.accumulator
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_400, format: inputFormat) { [weak self] buffer, _ in
            // Audio render thread: PCM math + lock-guarded state only.
            let level = Self.rms(of: buffer)
            Task { @MainActor [weak self] in self?.smoothLevel(level) }
            guard !muted.withLock({ $0 }) else { return }
            guard let converted = PCM.resample(buffer, to: wire) else { return }
            accumulator.append(PCM.pcm16Data(from: converted), emit: onChunk)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        playerNode.play()
        isRunning = true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if isPlayerAttached { playerNode.stop() }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        accumulator.reset()
        outstandingBuffers = 0
        isPlaying = false
        isRunning = false
        inputLevel = 0
    }

    // MARK: Playback

    /// Decodes a base64 PCM16 24 kHz chunk from the socket and queues it.
    func enqueue(base64: String) {
        guard isRunning,
              let data = Data(base64Encoded: base64),
              let wireBuffer = PCM.buffer(fromPCM16: data, format: wireFormat),
              let playable = PCM.resample(wireBuffer, to: playbackFormat) else { return }

        outstandingBuffers += 1
        isPlaying = true
        playerNode.scheduleBuffer(playable) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.outstandingBuffers = max(0, self.outstandingBuffers - 1)
                self.isPlaying = self.outstandingBuffers > 0
            }
        }
        if !playerNode.isPlaying { playerNode.play() }
    }

    /// Stops assistant playback (barge-in) and reports how many milliseconds
    /// have actually rendered, for `conversation.item.truncate`.
    @discardableResult
    func interruptPlayback() -> Int {
        outstandingBuffers = 0
        isPlaying = false
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
