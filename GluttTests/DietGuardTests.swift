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

    // MARK: - Plant dairy / vegan labels

    func testVeganAllowsPlantDairyAlternatives() {
        for name in [
            "soy milk",
            "oat milk",
            "almond milk",
            "vegan butter",
            "plant-based butter",
            "dairy-free cheese",
            "coconut cream",
            "peanut butter",
            "cocoa butter",
        ] {
            XCTAssertTrue(
                DietGuard.isAllowed(ingredientName: name, rules: [.vegan], allergies: []),
                "\(name) should be allowed for vegan"
            )
            XCTAssertTrue(
                DietGuard.isAllowed(ingredientName: name, rules: [.dairyFree], allergies: []),
                "\(name) should be allowed for dairy-free"
            )
        }
    }

    func testVeganStillBlocksRealDairy() {
        for name in ["butter", "whole milk", "heavy cream", "parmesan"] {
            XCTAssertFalse(
                DietGuard.isAllowed(ingredientName: name, rules: [.vegan], allergies: []),
                "\(name) should still conflict with vegan"
            )
        }
    }

    func testVeganAllowsLabeledPlantMeats() {
        XCTAssertTrue(
            DietGuard.isAllowed(ingredientName: "vegan sausage", rules: [.vegan], allergies: []),
            "vegan sausage should not conflict with vegan"
        )
        XCTAssertTrue(
            DietGuard.isAllowed(ingredientName: "plant-based bacon", rules: [.noPork], allergies: []),
            "plant-based bacon should not conflict with no-pork"
        )
    }

    func testPlantDairyDoesNotBypassNutFreeOrKeto() {
        XCTAssertFalse(
            DietGuard.isAllowed(ingredientName: "almond milk", rules: [.nutFree], allergies: []),
            "almond milk must still fail nut-free"
        )
        XCTAssertFalse(
            DietGuard.isAllowed(ingredientName: "vegan pasta", rules: [.keto], allergies: []),
            "plant label must not clear keto carb hits"
        )
    }

    func testMilkAllergyIgnoresPlantMilksButNotSoyAllergy() {
        XCTAssertTrue(
            DietGuard.isAllowed(ingredientName: "soy milk", rules: [], allergies: ["milk"]),
            "soy milk should not count as a milk allergy hit"
        )
        XCTAssertFalse(
            DietGuard.isAllowed(ingredientName: "soy milk", rules: [], allergies: ["soy"]),
            "soy milk must still fail a soy allergy"
        )
    }
}
