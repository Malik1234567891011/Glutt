import UIKit
import XCTest

@testable import Glutt

/// The gate is what stands between a head-mounted camera at 7 frames a second
/// and a model being shown seven smears of the same pan. If it cannot tell a
/// held shot from a moving one, nothing downstream can.
final class VisualFrameGateTests: XCTestCase {

    // MARK: - Fixtures

    /// Fine checkerboard: lots of edges, the shape of a frame held still.
    private func sharpImage(side: CGFloat = 240, square: CGFloat = 8) -> UIImage {
        renderer(side).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor.black.setFill()
            var row = 0
            var y: CGFloat = 0
            while y < side {
                var x: CGFloat = (row % 2 == 0) ? 0 : square
                while x < side {
                    context.fill(CGRect(x: x, y: y, width: square, height: square))
                    x += square * 2
                }
                y += square
                row += 1
            }
        }
    }

    /// A flat field, which is what motion blur converges toward.
    private func flatImage(_ color: UIColor, side: CGFloat = 240) -> UIImage {
        renderer(side).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func renderer(_ side: CGFloat) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
    }

    // MARK: - Measurement

    func testSharpImageScoresFarAboveFlatOne() throws {
        let gate = VisualFrameGate()
        let sharp = try XCTUnwrap(gate.measure(sharpImage()))
        let flat = try XCTUnwrap(gate.measure(flatImage(.gray)))

        XCTAssertGreaterThan(sharp.sharpness, flat.sharpness * 5,
                             "an edge-rich frame must be clearly separable from a featureless one")
        XCTAssertNil(gate.rejection(for: sharp))
        XCTAssertEqual(gate.rejection(for: flat), .blurred,
                       "a frame with no detail at all fails even the absolute floor")
    }

    /// Measured on the wok fixture: 312 frames of real cooking footage span only
    /// 0.019 to 0.037. An absolute quality bar anywhere near "sharp" would have
    /// refused every frame of it, which is exactly what the first version did.
    func testAbsoluteFloorSitsBelowRealCookingFootage() {
        XCTAssertLessThan(VisualFrameGate().minSharpness, 0.019,
                          "the absolute floor must pass a dim kitchen, blur is judged relatively")
    }

    func testExposureExtremesAreRejectedBeforeBlur() throws {
        let gate = VisualFrameGate()
        let dark = try XCTUnwrap(gate.measure(flatImage(.black)))
        let bright = try XCTUnwrap(gate.measure(flatImage(.white)))

        // Both are also featureless, but the cook can act on "it's too dark".
        XCTAssertEqual(gate.rejection(for: dark), .tooDark)
        XCTAssertEqual(gate.rejection(for: bright), .tooBright)
    }

    func testBrightnessTracksTheImage() throws {
        let gate = VisualFrameGate()
        let dark = try XCTUnwrap(gate.measure(flatImage(.black)))
        let mid = try XCTUnwrap(gate.measure(flatImage(.gray)))
        let bright = try XCTUnwrap(gate.measure(flatImage(.white)))

        XCTAssertLessThan(dark.brightness, mid.brightness)
        XCTAssertLessThan(mid.brightness, bright.brightness)
        XCTAssertEqual(bright.brightness, 1, accuracy: 0.02)
    }

    // MARK: - Duplicates

    func testIdenticalFramesAreDuplicatesAndDifferentOnesAreNot() throws {
        let gate = VisualFrameGate()
        let a = try XCTUnwrap(gate.measure(sharpImage()))
        let again = try XCTUnwrap(gate.measure(sharpImage()))
        let other = try XCTUnwrap(gate.measure(sharpImage(square: 30)))

        XCTAssertTrue(gate.isDuplicate(a, again), "the same picture twice must read as the same picture")
        XCTAssertFalse(gate.isDuplicate(a, other))
    }

    func testHammingDistanceCountsChangedBits() {
        XCTAssertEqual(VisualFrameGate.hammingDistance(0b1011, 0b1011), 0)
        XCTAssertEqual(VisualFrameGate.hammingDistance(0b1011, 0b1000), 2)
    }
}

/// Choosing among buffered frames. Newest is the wrong answer for a camera
/// strapped to someone's head, and these lock in that it is not the answer given.
final class VisualFrameBufferTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func frame(id: String, sharpness: Double, secondsAgo: TimeInterval, brightness: Double = 0.5) -> BufferedVisualFrame {
        BufferedVisualFrame(
            id: id,
            image: UIImage(),
            quality: VisualFrameQuality(sharpness: sharpness, brightness: brightness, hash: 0),
            capturedAt: now.addingTimeInterval(-secondsAgo)
        )
    }

    func testEmptyBufferReportsNoFrames() {
        let buffer = VisualFrameBuffer()
        guard case .failure(let reason) = buffer.best(maxAge: 1, now: now, gate: VisualFrameGate()) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(reason, .noFrames)
    }

    func testPicksSharpestRecentFrameNotNewest() {
        var buffer = VisualFrameBuffer()
        buffer.insert(frame(id: "sharp", sharpness: 0.4, secondsAgo: 0.9))
        buffer.insert(frame(id: "smear", sharpness: 0.28, secondsAgo: 0.1))

        guard case .success(let chosen) = buffer.best(maxAge: 1.5, now: now, gate: VisualFrameGate()) else {
            return XCTFail("expected a frame")
        }
        XCTAssertEqual(chosen.id, "sharp", "the newest frame is often mid head-turn")
    }

    func testFramesOlderThanTheWindowAreRefused() {
        var buffer = VisualFrameBuffer()
        buffer.insert(frame(id: "stale", sharpness: 0.9, secondsAgo: 30))

        guard case .failure(let reason) = buffer.best(maxAge: 1.5, now: now, gate: VisualFrameGate()) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(reason, .tooOld, "a thirty-second-old picture would have Polly answering about the past")
    }

    func testAllUnusableReportsTheNewestFramesReason() {
        var buffer = VisualFrameBuffer()
        buffer.insert(frame(id: "blur", sharpness: 0.0001, secondsAgo: 0.8))
        buffer.insert(frame(id: "dark", sharpness: 0.0001, secondsAgo: 0.2, brightness: 0.01))

        guard case .failure(let reason) = buffer.best(maxAge: 1.5, now: now, gate: VisualFrameGate()) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(reason, .tooDark, "report what the cook is doing now, not what they did a second ago")
    }

    /// The blur test that actually matters: not "is this frame sharp" but "is
    /// this frame much worse than this scene manages when held still". A dim
    /// kitchen and a bright counter score nothing alike, so only the ratio
    /// carries meaning.
    func testWindowFarSofterThanTheSceneIsRefusedAsBlur() {
        var buffer = VisualFrameBuffer(capacity: 2, historyCapacity: 32)
        // The scene has recently been this sharp.
        for index in 0..<8 {
            buffer.insert(frame(id: "held\(index)", sharpness: 0.030, secondsAgo: 5))
        }
        // Right now everything is a head-turn smear, well under the 0.6 floor.
        buffer.insert(frame(id: "turn1", sharpness: 0.015, secondsAgo: 0.3))
        buffer.insert(frame(id: "turn2", sharpness: 0.014, secondsAgo: 0.1))

        guard case .failure(let reason) = buffer.best(maxAge: 1.5, now: now, gate: VisualFrameGate()) else {
            return XCTFail("expected the smear to be refused")
        }
        XCTAssertEqual(reason, .blurred)
    }

    func testFrameCloseToTheScenePeakIsAccepted() {
        var buffer = VisualFrameBuffer(capacity: 4, historyCapacity: 32)
        for index in 0..<8 {
            buffer.insert(frame(id: "held\(index)", sharpness: 0.030, secondsAgo: 5))
        }
        // Softer than the scene's best, but not by enough to be motion.
        buffer.insert(frame(id: "now", sharpness: 0.025, secondsAgo: 0.2))

        guard case .success(let chosen) = buffer.best(maxAge: 1.5, now: now, gate: VisualFrameGate()) else {
            return XCTFail("a frame at 83% of the scene peak is usable")
        }
        XCTAssertEqual(chosen.id, "now")
    }

    /// Sharpness history has to outlive the images, or the baseline is just the
    /// window's own maximum and the relative test can never fire.
    func testSharpnessHistoryOutlivesTheImages() {
        var buffer = VisualFrameBuffer(capacity: 2, historyCapacity: 10)
        buffer.insert(frame(id: "peak", sharpness: 0.9, secondsAgo: 3))
        buffer.insert(frame(id: "a", sharpness: 0.1, secondsAgo: 1))
        buffer.insert(frame(id: "b", sharpness: 0.1, secondsAgo: 0))

        XCTAssertEqual(buffer.frames.count, 2, "the peak frame's image is gone")
        XCTAssertEqual(buffer.recentPeakSharpness, 0.9, accuracy: 0.0001, "but its score is remembered")
    }

    func testCapacityDropsTheOldestFrames() {
        var buffer = VisualFrameBuffer(capacity: 3)
        for index in 0..<6 {
            buffer.insert(frame(id: "f\(index)", sharpness: 0.2, secondsAgo: 0))
        }
        XCTAssertEqual(buffer.frames.count, 3)
        XCTAssertEqual(buffer.frames.map(\.id), ["f3", "f4", "f5"])
    }
}
