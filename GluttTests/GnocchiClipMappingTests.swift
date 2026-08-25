import XCTest
@testable import Glutt

/// What the investor actually sees: a clip playing next to an instruction.
///
/// `assignClips` is keyword driven and unique assignment, and this recipe reuses
/// its own nouns constantly (gnocchi is in five steps, butter in three), so the
/// mapping is not obvious by reading either side. This pins it, printed, so a
/// wrong pairing is caught here rather than on stage.
@MainActor
final class GnocchiClipMappingTests: XCTestCase {

    private func plan() throws -> CookPlan {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "CookPlan-gnocchi-brown-butter-sage", withExtension: "json")
            ?? Bundle.main.url(forResource: "CookPlan-gnocchi-brown-butter-sage", withExtension: "json"))
        return try JSONDecoder().decode(CookPlan.self, from: Data(contentsOf: url))
    }

    func testEveryCookStepGetsTheRightClip() async throws {
        let plan = try plan()
        let cookSteps = plan.steps.filter { !CookPlan.isSetupStep($0) }

        // Deliberately a live call against the real pilot, because the thing
        // being checked is what the proxy actually serves, not a fixture of it.
        // Skipped rather than failed without a network, so a plane does not turn
        // the suite red.
        let pilot: NativePilotClipsResponse
        do {
            pilot = try await NativeClipService.shared.clips(forMediaID: "3sUJwjvmzk8", force: true)
        } catch {
            throw XCTSkip("clip pilot unreachable (\(error.localizedDescription))")
        }
        // Exactly what the session does: the bundled plan names its clips, and
        // keyword scoring never gets a vote. It used to, and rewording a step
        // moved the videos.
        let pinned = Dictionary(
            uniqueKeysWithValues: cookSteps.compactMap { step in
                step.clipSegmentID.map { (step.id, $0) }
            })
        XCTAssertEqual(pinned.count, 9, "every cook step but Water on names its clip")
        let map = await NativeClipService.shared.assignClips(
            to: cookSteps.map { (id: $0.id, title: $0.title, instruction: $0.instruction) },
            from: pilot,
            pinned: pinned)

        print("\n=== gnocchi step -> clip ===")
        for step in cookSteps {
            let seg = map[step.id]?.segmentID ?? "(none)"
            print(String(format: "%-26@ -> %@", step.title as NSString, seg as NSString))
        }
        print("===========================\n")

        // The pairs that would read as broken on stage.
        let expected: [String: String] = [
            "s2": "seg-gnocchi-boil",
            "s3": "seg-gnocchi-oil",
            "s4": "seg-gnocchi-fry",
            "s5": "seg-gnocchi-brownbutter",
            "s6": "seg-gnocchi-sage",
            "s7": "seg-gnocchi-garlic",
            "s8": "seg-gnocchi-combine",
            "s9": "seg-gnocchi-lemon",
            "s10": "seg-gnocchi-serve",
        ]
        for (stepID, segment) in expected {
            XCTAssertEqual(map[stepID]?.segmentID, segment,
                           "step \(stepID) is showing the wrong clip")
        }
        // Water on has no honest clip in this video and must stay empty rather
        // than borrowing one, which is how it ended up showing garlic.
        XCTAssertNil(map["s1"], "Water on must not borrow another step's clip")

        let segments = map.values.map(\.segmentID)
        XCTAssertEqual(Set(segments).count, segments.count, "a segment is used twice")
    }
}
