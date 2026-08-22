import XCTest
@testable import Glutt

/// Both payloads are real captures from the proxy, taken while preparing the
/// gnocchi demo. The refine one is why this file exists.
final class StepClipDecodingTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
            "missing fixture \(name).json")
        return try Data(contentsOf: url)
    }

    /// The bug: `refine` returns a narrower clip than `ground`, and the
    /// synthesized decoder required every field. So refine threw keyNotFound,
    /// the whole `clips()` call threw with it, and every uncached clip fetch in
    /// the app failed after paying for two Gemini calls. Silent apart from one
    /// line in the debug log.
    func testTheRefinePhasePayloadDecodes() throws {
        let response = try JSONDecoder().decode(
            StepClipIndexResponse.self, from: fixture("stepClipsRefine"))
        XCTAssertEqual(response.youtubeVideoID, "3sUJwjvmzk8")
        XCTAssertFalse(response.clips.isEmpty)
    }

    /// The three keys refine omits.
    func testTheOmittedFieldsDegradeRatherThanThrow() throws {
        let response = try JSONDecoder().decode(
            StepClipIndexResponse.self, from: fixture("stepClipsRefine"))
        let clip = try XCTUnwrap(response.clips.first)
        XCTAssertEqual(clip.primaryAction, "")
        XCTAssertEqual(clip.visualCue, "")
        // Backfilled from the response root rather than left empty, because
        // `StepClip.id` and the player both need it.
        XCTAssertEqual(clip.youtubeVideoID, "3sUJwjvmzk8")
        XCTAssertFalse(clip.id.contains("--"), "id must not have an empty video id in it")
    }

    /// The richer phase must keep everything it sends.
    func testTheGroundPhaseKeepsItsExtraFields() throws {
        let response = try JSONDecoder().decode(
            StepClipIndexResponse.self, from: fixture("stepClipsGround"))
        let clip = try XCTUnwrap(response.clips.first)
        XCTAssertFalse(clip.primaryAction.isEmpty)
        XCTAssertFalse(clip.visualCue.isEmpty)
        XCTAssertEqual(clip.youtubeVideoID, "3sUJwjvmzk8")
    }

    /// Timings are what the clip actually is, so they stay required. A payload
    /// missing them is broken and must fail rather than play from zero.
    func testAClipWithNoTimingStillFails() {
        let json = Data("""
        {"youtube_video_id":"abc","clips":[{"step_id":"s1","match_type":"grounded",
          "confidence":1,"watch_label":"x","notice":"y"}]}
        """.utf8)
        let response = try? JSONDecoder().decode(StepClipIndexResponse.self, from: json)
        XCTAssertEqual(response?.clips.count, 0,
                       "a clip with no window is dropped, not defaulted to 0-0")
    }
}
