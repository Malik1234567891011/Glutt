import XCTest
@testable import Glutt

final class RecipeNutritionTests: XCTestCase {

    func testCaptionParserReadsCommonMacroPhrases() {
        let parsed = MacroCaptionParser.parse(
            "High protein bowl — 520 cal, 42g protein, 55g carbs, 18g fat, 12g fiber"
        )
        XCTAssertEqual(parsed.calories, 520)
        XCTAssertEqual(parsed.proteinGrams, 42)
        XCTAssertEqual(parsed.carbGrams, 55)
        XCTAssertEqual(parsed.fatGrams, 18)
        XCTAssertEqual(parsed.fibreOrFiber, 12)
    }

    func testResolveScalesWithDisplayServings() throws {
        let recipe = Recipe(title: "Test", servings: 2)
        recipe.calories = 400
        recipe.proteinGrams = 30
        recipe.nutritionIsEstimated = false

        let forTwo = try XCTUnwrap(RecipeNutrition.resolve(for: recipe, servings: 2))
        XCTAssertEqual(forTwo.calories, 800)
        XCTAssertEqual(forTwo.proteinGrams, 60)
        XCTAssertEqual(forTwo.perServingCalories, 400)
        XCTAssertEqual(forTwo.servings, 2)

        let forFour = try XCTUnwrap(RecipeNutrition.resolve(for: recipe, servings: 4))
        XCTAssertEqual(forFour.calories, 1600)
        XCTAssertEqual(forFour.proteinGrams, 120)
    }

    func testResolveCarriesEveryMacroPerServingAndAsABatchTotal() throws {
        let recipe = Recipe(title: "Muffins", servings: 12)
        recipe.calories = 210
        recipe.proteinGrams = 4
        recipe.carbGrams = 30
        recipe.fatGrams = 9
        recipe.nutritionIsEstimated = false

        let n = try XCTUnwrap(RecipeNutrition.resolve(for: recipe, servings: 12))
        // One muffin.
        XCTAssertEqual(n.perServingCalories, 210)
        XCTAssertEqual(n.perServingProtein, 4)
        XCTAssertEqual(n.perServingCarbs, 30)
        XCTAssertEqual(n.perServingFat, 9)
        // The whole tray.
        XCTAssertEqual(n.calories, 2520)
        XCTAssertEqual(n.carbGrams, 360)
        XCTAssertEqual(n.fatGrams, 108)
    }

    /// The banner leads with ONE serving. Getting these two units the wrong way
    /// round is the entire bug, so lock the strings.
    @MainActor
    func testBannerLabelLeadsWithOneServingAndNamesTheBatchTotal() throws {
        let recipe = Recipe(title: "Muffins", servings: 12)
        recipe.calories = 210
        recipe.proteinGrams = 4
        recipe.nutritionIsEstimated = false

        let forTwelve = try XCTUnwrap(RecipeNutrition.resolve(for: recipe, servings: 12))
        XCTAssertEqual(RecipeNutritionBanner(nutrition: forTwelve).servingLabel,
                       "per serving · makes 12 servings, 2520 cal")

        // Scaling the stepper has to keep BOTH numbers honest.
        let forSix = try XCTUnwrap(RecipeNutrition.resolve(for: recipe, servings: 6))
        XCTAssertEqual(forSix.perServingCalories, 210, "one muffin is one muffin at any batch size")
        XCTAssertEqual(RecipeNutritionBanner(nutrition: forSix).servingLabel,
                       "per serving · makes 6 servings, 1260 cal")

        let forOne = try XCTUnwrap(RecipeNutrition.resolve(for: recipe, servings: 1))
        XCTAssertEqual(RecipeNutritionBanner(nutrition: forOne).servingLabel,
                       "per serving · makes 1 serving",
                       "no redundant total when the batch IS one serving")

        // UI copy rule: no dashes as punctuation.
        for label in [RecipeNutritionBanner(nutrition: forTwelve).servingLabel,
                      RecipeNutritionBanner(nutrition: forOne).servingLabel] {
            XCTAssertFalse(label.contains("—"), label)
            XCTAssertFalse(label.contains("–"), label)
            XCTAssertFalse(label.contains(" - "), label)
        }
    }

    /// Estimated numbers keep their "~" on both the plate and the batch.
    @MainActor
    func testBannerLabelMarksEstimatedBatchTotal() throws {
        let recipe = Recipe(title: "Stew", servings: 4)
        recipe.calories = 300
        recipe.proteinGrams = 20
        recipe.nutritionIsEstimated = true

        let n = try XCTUnwrap(RecipeNutrition.resolve(for: recipe, servings: 4))
        XCTAssertEqual(RecipeNutritionBanner(nutrition: n).servingLabel,
                       "per serving · makes 4 servings, ~1200 cal")
    }

    func testFiberHighlightWhenNotablePerServing() throws {
        let recipe = Recipe(title: "Oats", servings: 1)
        recipe.calories = 300
        recipe.proteinGrams = 12
        recipe.summary = "300 cal · 12g protein · 14g fiber"

        let n = try XCTUnwrap(RecipeNutrition.resolve(for: recipe, servings: 1))
        XCTAssertEqual(n.perServingFiber, 14)
        XCTAssertTrue(n.highlights.contains { $0.label == "14g fiber" })
    }
}

private extension MacroCaptionParser.Parsed {
    /// Alias so the test reads clearly either spelling.
    var fibreOrFiber: Int? { fiberGrams }
}
