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
