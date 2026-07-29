import XCTest
@testable import Glutt

final class CookRecapBuilderTests: XCTestCase {

    func testBuildsSoftScoresAndTimeLabel() {
        let recap = CookRecapBuilder.build(.init(
            dishTitle: "Spicy Vodka Pasta",
            cookName: "Malik",
            durationSeconds: 37 * 60,
            expectedMinutes: 40,
            stepsCompleted: 8,
            stepsTotal: 8,
            endedEarly: false,
            pollySaves: ["Stopped garlic from burning", "Recovered a split sauce"],
            substitutions: [],
            summary: "Sauce almost split when cream went in cold. Recovered off heat. Plate looked glossy.",
            visualSelfScore: 8.4,
            previousBestOverall: 7.2
        ))

        XCTAssertEqual(recap.runTitle, "Malik's Spicy Vodka Pasta Run")
        XCTAssertEqual(recap.timeLabel, "37:00")
        XCTAssertEqual(recap.saves.count, 2)
        XCTAssertEqual(recap.badge, "Beat Your Best")
        XCTAssertNotNil(recap.visualScore)
        XCTAssertNotNil(recap.timingScore)
        XCTAssertNotNil(recap.techniqueScore)
        XCTAssertGreaterThan(recap.overallScore, 7.0)
        XCTAssertTrue(recap.improvement?.isEmpty == false)
        XCTAssertFalse(recap.headline.isEmpty)
    }

    func testCleanRunBadgeWhenNoSaves() {
        let recap = CookRecapBuilder.build(.init(
            dishTitle: "Eggs",
            durationSeconds: 10 * 60,
            expectedMinutes: 10,
            stepsCompleted: 4,
            stepsTotal: 4,
            endedEarly: false,
            pollySaves: [],
            substitutions: [],
            summary: nil
        ))
        XCTAssertEqual(recap.badge, "Clean Run")
        XCTAssertTrue(recap.saves.isEmpty)
    }

    func testSubstitutionsBecomeSaves() {
        let recap = CookRecapBuilder.build(.init(
            dishTitle: "Tacos",
            durationSeconds: 20 * 60,
            expectedMinutes: 25,
            stepsCompleted: 5,
            stepsTotal: 6,
            endedEarly: false,
            pollySaves: [],
            substitutions: ["Substituted thighs for breast in Tacos"],
            summary: nil
        ))
        XCTAssertEqual(recap.saves.count, 1)
        XCTAssertTrue(recap.saves[0].moment.localizedCaseInsensitiveContains("substituted"))
    }

    func testSauceSaverBadge() {
        let recap = CookRecapBuilder.build(.init(
            dishTitle: "Alfredo",
            durationSeconds: 30 * 60,
            expectedMinutes: 30,
            stepsCompleted: 6,
            stepsTotal: 6,
            endedEarly: false,
            pollySaves: ["Saved the sauce from splitting"],
            substitutions: [],
            summary: nil
        ))
        XCTAssertEqual(recap.badge, "Sauce Saver")
    }
}
