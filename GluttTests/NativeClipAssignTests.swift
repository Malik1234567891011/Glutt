import XCTest
@testable import Glutt

/// Shared dessert words ("vanilla", "cream", "sugar", "custard") used to make
/// the same pilot clip win for several steps. Assignment must stay 1:1.
final class NativeClipAssignTests: XCTestCase {

    private func clip(
        id: String,
        keywords: [String],
        start: Double,
        end: Double
    ) -> NativeStepClip {
        NativeStepClip(
            segmentID: id,
            startSeconds: start,
            endSeconds: end,
            durationSeconds: end - start,
            watchLabel: id,
            teachingLabel: id,
            notice: "",
            visualCue: "",
            stepKeywords: keywords,
            presentationMode: "blurFill",
            playbackURL: URL(string: "https://example.com/\(id).mp4")!,
            thumbnailURL: nil,
            masterURL: nil,
            usesVirtualRange: false,
            creatorAttribution: "Preppy Kitchen"
        )
    }

    func testAssignClipsNeverReusesASegmentWhenKeywordsOverlap() async {
        let pilot = NativePilotClipsResponse(
            sourceAssetID: "asset",
            status: "ready",
            durationSeconds: 481,
            title: "Crème Brûlée",
            clips: [
                clip(id: "vanilla", keywords: ["vanilla", "bean", "scrape", "split", "seeds"], start: 17, end: 48),
                clip(id: "cream", keywords: ["cream", "simmer", "steep", "infuse", "scald", "vanilla"], start: 49, end: 86),
                clip(id: "yolks", keywords: ["yolk", "sugar", "salt", "whisk", "separate"], start: 95, end: 150),
                clip(id: "strain", keywords: ["strain", "sieve", "custard", "pour", "temper"], start: 161, end: 218),
                clip(id: "bake", keywords: ["ramekin", "bake", "water bath", "oven", "wobble"], start: 228, end: 289),
                clip(id: "torch", keywords: ["torch", "sugar", "caramel", "brulee", "amber"], start: 321, end: 400),
            ],
            expiresIn: 3600
        )
        // Titles/instructions that all mention overlapping dessert vocabulary —
        // the bug assigned "vanilla" or "cream" to three of these.
        let steps: [(id: String, title: String, instruction: String)] = [
            ("s1", "Prepare vanilla bean", "Split the vanilla bean and scrape the seeds for the cream."),
            ("s2", "Heat cream with vanilla", "Simmer the cream with the vanilla until scalded, then steep."),
            ("s3", "Whisk yolks with sugar", "Whisk egg yolks with sugar and salt."),
            ("s4", "Strain the custard", "Strain the warm cream into the yolks, then strain the custard again."),
            ("s5", "Bake in a water bath", "Fill ramekins and bake in a water bath until the centers wobble."),
            ("s6", "Torch the sugar", "Sprinkle sugar and torch until amber caramel — the crème brûlée top."),
        ]

        let map = await NativeClipService.shared.assignClips(to: steps, from: pilot)
        XCTAssertEqual(map.count, 6)
        let ids = steps.compactMap { map[$0.id]?.segmentID }
        XCTAssertEqual(ids.count, 6)
        XCTAssertEqual(Set(ids).count, 6, "each cook step must get a different clip, got \(ids)")
        XCTAssertEqual(map["s1"]?.segmentID, "vanilla")
        XCTAssertEqual(map["s2"]?.segmentID, "cream")
        XCTAssertEqual(map["s6"]?.segmentID, "torch")
    }

    func testAssignClipsFillsGapsWithoutDuplicating() async {
        let pilot = NativePilotClipsResponse(
            sourceAssetID: "asset",
            status: "ready",
            durationSeconds: 100,
            title: "Test",
            clips: [
                clip(id: "a", keywords: ["zzzz"], start: 0, end: 10),
                clip(id: "b", keywords: ["uniquephrase"], start: 10, end: 20),
                clip(id: "c", keywords: ["yyyy"], start: 20, end: 30),
            ],
            expiresIn: nil
        )
        let steps: [(id: String, title: String, instruction: String)] = [
            ("s1", "No match here", "Nothing relevant."),
            ("s2", "Has the phrase", "Do the uniquephrase carefully."),
            ("s3", "Also no match", "Still nothing."),
        ]
        let map = await NativeClipService.shared.assignClips(to: steps, from: pilot)
        XCTAssertEqual(map["s2"]?.segmentID, "b")
        XCTAssertEqual(Set(map.values.map(\.segmentID)).count, 3)
        XCTAssertEqual(map.count, 3)
    }
}
