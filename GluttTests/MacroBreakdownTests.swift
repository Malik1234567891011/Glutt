import XCTest
@testable import Glutt

final class MacroBreakdownTests: XCTestCase {
    func testFractionsUseCalorieContribution() {
        // protein 48*4=192, carbs 55*4=220, fat 18*9=162; total 574
        let b = MacroBreakdown(calories: 620, protein: 48, carbs: 55, fat: 18, isEstimated: false)
        XCTAssertTrue(b.hasFullMacros)
        XCTAssertEqual(b.proteinFraction, 192.0 / 574.0, accuracy: 0.0001)
        XCTAssertEqual(b.carbFraction, 220.0 / 574.0, accuracy: 0.0001)
        XCTAssertEqual(b.fatFraction, 162.0 / 574.0, accuracy: 0.0001)
        XCTAssertEqual(b.proteinFraction + b.carbFraction + b.fatFraction, 1.0, accuracy: 0.0001)
    }

    func testNotFullWhenCarbOrFatMissing() {
        let b = MacroBreakdown(calories: 400, protein: 30, carbs: nil, fat: nil, isEstimated: true)
        XCTAssertFalse(b.hasFullMacros)
    }

    func testZeroMacrosDoNotDivideByZero() {
        let b = MacroBreakdown(calories: 0, protein: 0, carbs: 0, fat: 0, isEstimated: true)
        XCTAssertFalse(b.hasFullMacros)
        XCTAssertEqual(b.proteinFraction, 0)
        XCTAssertEqual(b.carbFraction, 0)
        XCTAssertEqual(b.fatFraction, 0)
    }
}
