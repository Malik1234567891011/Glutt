import XCTest
@testable import Glutt

/// Focused coverage for the Task 5 rules (nutFree, keto). The broader
/// DietGuardTests class lives in GluttTests.swift.
final class DietGuardNutFreeKetoTests: XCTestCase {

    // MARK: - Keto

    func testKetoAllowsKetoSubstituteIngredients() {
        for name in ["almond flour", "baking soda", "cauliflower rice"] {
            XCTAssertTrue(
                DietGuard.isAllowed(ingredientName: name, rules: [.keto], allergies: []),
                "\(name) should not be flagged by the keto guard"
            )
        }
    }

    func testKetoBlocksHighCarbIngredients() {
        for name in ["sugar", "pasta"] {
            XCTAssertFalse(
                DietGuard.isAllowed(ingredientName: name, rules: [.keto], allergies: []),
                "\(name) should be flagged by the keto guard"
            )
        }
    }

    // MARK: - Nut-free

    func testNutFreeBlocksPeanuts() {
        XCTAssertFalse(
            DietGuard.isAllowed(ingredientName: "peanuts", rules: [.nutFree], allergies: []),
            "peanuts should be flagged by the nut-free guard"
        )
    }

    func testNutFreeAllowsButternutSquash() {
        XCTAssertTrue(
            DietGuard.isAllowed(ingredientName: "butternut squash", rules: [.nutFree], allergies: []),
            "butternut squash should not be flagged by the nut-free guard"
        )
    }
}
