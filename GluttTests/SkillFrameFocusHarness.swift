import XCTest
import UIKit
@testable import Glutt

/// Runs the real selector over the archived frames and shows what it picks.
///
/// The whole point: "it cropped the wrong hand" is not arguable from a log
/// line. On one archived frame the cook held a knife in their right hand, an
/// empty fist in their left, and a phone lay flat on the counter between them.
/// The selector cropped the fist, and the model duly reported "a hand holding a
/// phone". Nothing in the pipeline could have caught that.
///
/// Skips where no archive has been pulled.
final class SkillFrameFocusHarness: XCTestCase {

    private func archive() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("skill-looks")
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("no archive on this machine")
        }
        return (try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil))
            .filter(\.hasDirectoryPath)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Every hand the detector finds in every archived original, with the
    /// numbers the ordering is built on.
    func testWhatTheDetectorSeesInEveryFrame() throws {
        print("FRAME                       HAND  CONF-BOX            COVER   CLOSED  TOOL")
        for folder in try archive() {
            let originals = (try? FileManager.default
                .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
                .filter { $0.lastPathComponent.hasPrefix("original-") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
            for file in originals {
                guard let data = try? Data(contentsOf: file) else { continue }
                let found = SkillFrameFocus.candidates(in: data)
                let name = "\(folder.lastPathComponent.dropFirst(9).prefix(6))/\(file.lastPathComponent.dropFirst(9).prefix(1))"
                if found.isEmpty {
                    print(String(format: "%-27@  none", name as NSString))
                    continue
                }
                for (index, hand) in found.enumerated() {
                    print(String(
                        format: "%-27@  %d     x%.2f y%.2f w%.2f h%.2f  %.3f   %.2f    %.2f",
                        name as NSString, index,
                        hand.box.minX, hand.box.minY, hand.box.width, hand.box.height,
                        hand.coverage, hand.closedness, hand.holdsTool))
                }
            }
        }
    }
}
