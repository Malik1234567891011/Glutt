import XCTest
import UIKit
@testable import Glutt

/// Does the cropper actually send the hand that is holding the knife?
///
/// This is the question a whole session of "she said I was holding the handle"
/// turned out to be. The cropper was choosing an empty fist over the knife hand
/// and the reader was correctly reporting no knife in it.
///
/// **Must be run on a device.** `VNDetectHumanHandPoseRequest` returns nothing
/// at all in the iOS Simulator, so a green run there proves nothing and this
/// skips rather than lying:
///
///     xcodebuild test -scheme Glutt \
///       -destination 'platform=iOS,id=<udid>' \
///       -only-testing:GluttTests/SkillKnifeSelectionTests
///
/// The frames come from `./scripts/pull-skill-looks.sh`, and the labels below
/// were read off the pictures by eye, one at a time.
final class SkillKnifeSelectionTests: XCTestCase {

    /// Where the knife is in a frame, as a fraction across the picture. Labelled
    /// by looking at each one: `nil` means no knife is visible in that frame at
    /// all, which is a real case and must not be counted as a miss.
    private struct Labelled {
        let folder: String
        let original: Int
        /// Normalised x of the knife hand, Vision's coordinates.
        let knifeHandX: CGFloat?
    }

    private let labels: [Labelled] = [
        // The two that were failing. Knife hand small, at the right edge, its
        // landmarks half hidden by the knife itself.
        Labelled(folder: "20260830-200723", original: 1, knifeHandX: 0.90),
        Labelled(folder: "20260830-200723", original: 3, knifeHandX: 0.90),
        Labelled(folder: "20260830-182732", original: 1, knifeHandX: 0.78),
        // Knife hand central, empty hand off to one side. These two x values are
    // the centre of the HAND box, not of the blade, which is what the first
    // draft of these labels got wrong and the harness caught.
        Labelled(folder: "20260830-182820", original: 1, knifeHandX: 0.55),
        Labelled(folder: "20260830-192656", original: 1, knifeHandX: 0.50),
        Labelled(folder: "20260830-192714", original: 1, knifeHandX: 0.68),
        Labelled(folder: "20260830-192717", original: 1, knifeHandX: 0.68),
    ]

    private func frame(_ label: Labelled) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("skill-looks")
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("no archive pulled on this machine")
        }
        let folder = try XCTUnwrap(
            (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
                .first { $0.lastPathComponent.hasPrefix(label.folder) })
        return try Data(contentsOf: folder
            .appendingPathComponent("original-\(label.original).jpg"))
    }

    /// The knife hand must be among the crops we send. Not necessarily first:
    /// which one holds the tool is the reader's question, and it can only answer
    /// it about pictures it was given.
    func testTheKnifeHandIsAlwaysSent() throws {
        var missed: [String] = []
        for label in labels {
            let data = try frame(label)
            let found = SkillFrameFocus.candidates(in: data)
            guard let wanted = label.knifeHandX else { continue }
            if found.isEmpty {
                throw XCTSkip("Vision found no hands at all, which means this is not a device")
            }
            let hit = found.contains { abs($0.box.midX - wanted) < 0.18 }
            if !hit {
                let seen = found.map { String(format: "%.2f", $0.box.midX) }.joined(separator: ", ")
                missed.append("\(label.folder)/\(label.original): wanted a hand near "
                    + "\(String(format: "%.2f", wanted)), got [\(seen)]")
            }
        }
        XCTAssertTrue(missed.isEmpty, "the knife hand was not sent:\n" + missed.joined(separator: "\n"))
    }

    /// Deterministic, so running it repeatedly proves repeatability rather than
    /// luck. The cook asked for a hundred out of a hundred, and a hundred runs
    /// of a pure function is what that means here.
    func testItPicksTheSameHandsEveryTimeAcrossAHundredRuns() throws {
        let label = labels[0]
        let data = try frame(label)
        let first = SkillFrameFocus.candidates(in: data)
        if first.isEmpty { throw XCTSkip("not a device") }

        for run in 1..<100 {
            let again = SkillFrameFocus.candidates(in: data)
            XCTAssertEqual(again.count, first.count, "run \(run) found a different number of hands")
            for (a, b) in zip(first, again) {
                XCTAssertEqual(a.box.midX, b.box.midX, accuracy: 0.001, "run \(run) moved a hand")
            }
        }
    }
}
