import AppKit
import Foundation
import Vision

// Ground truth, read off each picture by eye. `nil` means no knife is visible
// in that frame at all, which happens and must not count as a miss.
struct Labelled {
    let folder: String
    let original: Int
    /// Normalised x of the hand holding the knife, Vision's coordinates.
    let knifeHandX: CGFloat?
}

let labels: [Labelled] = [
    // The failures. Knife hand small, at the frame edge, landmarks half hidden
    // by the knife it is holding.
    Labelled(folder: "20260830-200723", original: 1, knifeHandX: 0.90),
    Labelled(folder: "20260830-200723", original: 3, knifeHandX: 0.90),
    Labelled(folder: "20260830-182732", original: 1, knifeHandX: 0.78),
    // Knife hand central, empty hand off to one side. These x values are the
    // centre of the HAND box, not of the blade, which is what the first draft
    // of these labels got wrong and the harness caught.
    Labelled(folder: "20260830-182820", original: 1, knifeHandX: 0.55),
    Labelled(folder: "20260830-192656", original: 1, knifeHandX: 0.50),
    Labelled(folder: "20260830-192714", original: 1, knifeHandX: 0.68),
    Labelled(folder: "20260830-192717", original: 1, knifeHandX: 0.68),
]

let runs = Int(CommandLine.arguments.dropFirst().first ?? "100") ?? 100
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("skill-looks")

guard FileManager.default.fileExists(atPath: root.path) else {
    print("no skill-looks/ here. Run ./scripts/pull-skill-looks.sh first.")
    exit(2)
}

func frame(_ label: Labelled) -> CGImage? {
    guard let folder = (try? FileManager.default
        .contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
        .first(where: { $0.lastPathComponent.hasPrefix(label.folder) }) else { return nil }
    let file = folder.appendingPathComponent("original-\(label.original).jpg")
    guard let image = NSImage(contentsOf: file) else { return nil }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

var hits = 0, total = 0
var perFrame: [String: Int] = [:]

for run in 0..<runs {
    for label in labels {
        guard let wanted = label.knifeHandX, let image = frame(label) else { continue }
        total += 1
        let found = HandBoxes.detect(in: image)
        let key = "\(label.folder.dropFirst(9))/\(label.original)"
        if found.contains(where: { abs($0.box.midX - wanted) < 0.18 }) {
            hits += 1
            perFrame[key, default: 0] += 1
        } else if run == 0 {
            let seen = found.map { String(format: "%.2f", $0.box.midX) }.joined(separator: ", ")
            print("  MISS \(key): wanted a hand near \(String(format: "%.2f", wanted)), got [\(seen)]")
        }
    }
}

print("")
print("knife hand present in the crops we send:")
for key in perFrame.keys.sorted() {
    print("  \(key)  \(perFrame[key]!)/\(runs)")
}
print("")
print("\(hits)/\(total) across \(runs) runs")
exit(hits == total ? 0 : 1)
