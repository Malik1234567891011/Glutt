import XCTest
import UIKit
@testable import Glutt

/// A probe, not a test of behaviour: measures the archived crops with the same
/// gate the pipeline uses, so a threshold can be picked from real frames rather
/// than invented. Skips when the archive is not on this machine.
final class SkillCropQualityProbe: XCTestCase {

    func testMeasureTheArchive() throws {
        // Derived from this file rather than hardcoded, so it works in any
        // clone and simply skips where nobody has pulled an archive.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GluttTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("skill-looks")
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("no archive on this machine")
        }
        let gate = VisualFrameGate()
        let folders = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter(\.hasDirectoryPath)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        print("LOOK             FILE                  SHARP   BRIGHT   SIZE")
        for folder in folders.suffix(6) {
            let files = (try? FileManager.default
                .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "jpg" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
            for file in files {
                guard let data = try? Data(contentsOf: file),
                      let image = UIImage(data: data),
                      let q = gate.measure(image) else { continue }
                let name = folder.lastPathComponent.prefix(15)
                let short = file.lastPathComponent
                    .replacingOccurrences(of: "-knife.grip.pinch", with: "")
                print(String(format: "%@  %-22@  %.4f  %.4f   %dx%d",
                             String(name), short as NSString,
                             q.sharpness, q.brightness,
                             Int(image.size.width), Int(image.size.height)))
            }
        }
    }
}
