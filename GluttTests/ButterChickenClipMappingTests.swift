import XCTest
@testable import Glutt

/// The pairing a cook actually sees: an instruction with the right video beside
/// it. `ButterChickenDemoPlanTests` pins what the plan *asks* for; this checks
/// that what the server serves can answer, and that `assignClips` hands each
/// step the segment it named.
@MainActor
final class ButterChickenClipMappingTests: XCTestCase {

    private func plan() throws -> CookPlan {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "CookPlan-butter-chicken", withExtension: "json")
            ?? Bundle.main.url(forResource: "CookPlan-butter-chicken", withExtension: "json"))
        return try JSONDecoder().decode(CookPlan.self, from: Data(contentsOf: url))
    }

    func testEveryCookStepGetsTheRightClip() async throws {
        let plan = try plan()
        let cookSteps = plan.steps.filter { !CookPlan.isSetupStep($0) }

        // Deliberately a live call against the real pilot, because the thing
        // being checked is what the proxy actually serves, not a fixture of it.
        // Skipped rather than failed without a network, so a plane does not turn
        // the suite red. It also skips until the pilot has been synced to
        // Supabase, which is the state a fresh clone is in.
        let pilot: NativePilotClipsResponse
        do {
            pilot = try await NativeClipService.shared.clips(forMediaID: "hDjK5C2aoSs", force: true)
        } catch {
            throw XCTSkip("clip pilot unreachable (\(error.localizedDescription))")
        }
        try XCTSkipIf(pilot.clips.isEmpty, "butter chicken pilot not published yet")

        let pinned = Dictionary(
            uniqueKeysWithValues: cookSteps.compactMap { step in
                step.clipSegmentID.map { (step.id, $0) }
            })
        XCTAssertEqual(pinned.count, 10, "every cook step but Rice on names its clip")
        let map = await NativeClipService.shared.assignClips(
            to: cookSteps.map { (id: $0.id, title: $0.title, instruction: $0.instruction) },
            from: pilot,
            pinned: pinned)

        print("\n=== butter chicken step -> clip ===")
        for step in cookSteps {
            let seg = map[step.id]?.segmentID ?? "(none)"
            print(String(format: "%-34@ -> %@", step.title as NSString, seg as NSString))
        }
        print("==================================\n")

        let expected: [String: String] = [
            "s1": "seg-bc-marinade",
            "s3": "seg-bc-oil",
            "s4": "seg-bc-sear",
            "s5": "seg-bc-aromatics",
            "s6": "seg-bc-spices",
            "s7": "seg-bc-tomatoes",
            "s8": "seg-bc-chicken-back",
            "s9": "seg-bc-cream",
            "s10": "seg-bc-butter",
            "s11": "seg-bc-serve",
        ]
        for (stepID, segment) in expected {
            XCTAssertEqual(map[stepID]?.segmentID, segment,
                           "step \(stepID) is showing the wrong clip")
        }
        // Rice has no honest clip in this video and must stay empty rather than
        // borrowing one, which is how the gnocchi plan once put garlic on "Water on".
        XCTAssertNil(map["s2"], "Rice on must not borrow another step's clip")

        let segments = map.values.map(\.segmentID)
        XCTAssertEqual(Set(segments).count, segments.count, "a segment is used twice")
    }
}
