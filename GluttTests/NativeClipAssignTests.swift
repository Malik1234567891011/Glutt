import XCTest
@testable import Glutt

/// Clip assignment on the gnocchi demo, which is where this went wrong in a way
/// nobody would have caught by reading the code.
final class NativeClipAssignTests: XCTestCase {

    private func clip(_ id: String, _ keywords: [String]) -> NativeStepClip {
        NativeStepClip(
            segmentID: id, startSeconds: 0, endSeconds: 10, durationSeconds: 10,
            watchLabel: id, teachingLabel: id, notice: "", visualCue: "cue for \(id)",
            stepKeywords: keywords, presentationMode: "blurFill",
            playbackURL: URL(string: "http://localhost/\(id).mp4")!,
            thumbnailURL: nil, masterURL: nil, usesVirtualRange: false,
            creatorAttribution: nil)
    }

    private var pilot: NativePilotClipsResponse {
        response([
            clip("boil", ["float", "floats", "slotted"]),
            clip("garlic", ["garlic", "sliced", "minute"]),
            clip("butter", ["butter", "brown", "nutty"]),
        ])
    }

    private func response(_ clips: [NativeStepClip]) -> NativePilotClipsResponse {
        NativePilotClipsResponse(
            sourceAssetID: "asset", status: "ready", durationSeconds: 236,
            title: "Test", clips: clips, expiresIn: nil)
    }

    /// The bug. "Water on" matches nothing, and used to be handed whichever clip
    /// was next in the list, which was the garlic one. The canvas then played
    /// garlic frying full screen AND printed the garlic cue as the step's
    /// description, so filling a pan with water read as "pale gold at the edges
    /// and must not go brown".
    func testAStepWithNoMatchGetsNoClip() async {
        let map = await NativeClipService.shared.assignClips(
            to: [
                (id: "s1", title: "Water on", instruction: "Fill a large pan with water and salt it well."),
                (id: "s2", title: "Boil the gnocchi", instruction: "They are done when they float, then out with a slotted spoon."),
            ],
            from: pilot)
        XCTAssertNil(map["s1"], "filling a pan with water has nothing to show")
        XCTAssertEqual(map["s2"]?.segmentID, "boil")
    }

    /// "boil" must not match the "oil" keyword. The word-boundary regex is what
    /// stops it, and it is the sort of thing that silently regresses.
    func testBoilDoesNotMatchOil() async {
        let map = await NativeClipService.shared.assignClips(
            to: [(id: "s1", title: "Water on", instruction: "Put it on to boil.")],
            from: response([clip("oil", ["oil", "heat"])]))
        XCTAssertNil(map["s1"], "\"boil\" contains \"oil\" and must not match it")
    }

    /// One segment per step, still.
    func testASegmentIsNeverUsedTwice() async {
        let map = await NativeClipService.shared.assignClips(
            to: [
                (id: "s1", title: "Garlic in", instruction: "Add the sliced garlic."),
                (id: "s2", title: "More garlic", instruction: "Add the sliced garlic again."),
            ],
            from: pilot)
        XCTAssertEqual(map["s1"]?.segmentID, "garlic")
        XCTAssertNil(map["s2"], "the second step cannot reuse the same segment")
    }
}
