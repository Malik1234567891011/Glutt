import AVFoundation
import XCTest
@testable import Glutt

final class PCMTests: XCTestCase {

    // MARK: - Helpers

    private func floatFormat(sampleRate: Double) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    private func int16Format(sampleRate: Double) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    /// Mono float32 sine wave at 440 Hz, amplitude 0.5.
    private func sineBuffer(format: AVAudioFormat, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frames) {
            channel[frame] = 0.5 * sin(2 * .pi * 440 * Float(frame) / Float(format.sampleRate))
        }
        return buffer
    }

    /// Reads little-endian Int16 samples back out of wire-format data.
    private func int16Samples(from data: Data) -> [Int16] {
        data.withUnsafeBytes { raw in
            (0..<(data.count / 2)).map { i in
                Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
            }
        }
    }

    // MARK: - Tests

    func testFloatSineRoundTripsThroughPCM16WithinOne() throws {
        let format = floatFormat(sampleRate: 24_000)
        let source = sineBuffer(format: format, frames: 2_400)

        let data = PCM.pcm16Data(from: source)
        XCTAssertEqual(data.count, 4_800, "2400 frames x 2 bytes per sample")

        let decoded = try XCTUnwrap(PCM.buffer(fromPCM16: data, format: int16Format(sampleRate: 24_000)))
        XCTAssertEqual(decoded.frameLength, 2_400)

        let decodedSamples = try XCTUnwrap(decoded.int16ChannelData?[0])
        let floats = source.floatChannelData![0]
        var maxDelta = 0
        for frame in 0..<2_400 {
            let expected = Int((floats[frame] * 32_767).rounded())
            maxDelta = max(maxDelta, abs(Int(decodedSamples[frame]) - expected))
        }
        XCTAssertLessThanOrEqual(maxDelta, 1)
    }

    func testPCM16DataClampsOutOfRangeFloats() throws {
        let format = floatFormat(sampleRate: 24_000)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        channel[0] = 2.5
        channel[1] = -3.0
        channel[2] = 1.0
        channel[3] = -1.0

        let samples = int16Samples(from: PCM.pcm16Data(from: buffer))
        XCTAssertEqual(samples, [32_767, -32_767, 32_767, -32_767])
    }

    func testResample48kTo24kHalvesFrameCount() throws {
        let source = sineBuffer(format: floatFormat(sampleRate: 48_000), frames: 4_800)
        let resampled = try XCTUnwrap(PCM.resample(source, to: int16Format(sampleRate: 24_000)))

        XCTAssertEqual(resampled.format.sampleRate, 24_000)
        XCTAssertEqual(resampled.format.commonFormat, .pcmFormatInt16)
        XCTAssertEqual(Int(resampled.frameLength), 2_400, accuracy: 2)
    }

    func testPCM16DataPassesThroughInt16BufferUnchanged() throws {
        let format = int16Format(sampleRate: 24_000)
        let values: [Int16] = [0, 1, -1, 12_345, -12_345, .max, .min]
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count)))
        buffer.frameLength = AVAudioFrameCount(values.count)
        let channel = try XCTUnwrap(buffer.int16ChannelData?[0])
        for (frame, value) in values.enumerated() { channel[frame] = value }

        XCTAssertEqual(int16Samples(from: PCM.pcm16Data(from: buffer)), values)
    }
}
