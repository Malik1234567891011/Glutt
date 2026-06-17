import XCTest
@testable import Glutt

final class RecipeFactoryTests: XCTestCase {

    func testBuildsRecipeWithParsedIngredientsAndStepDurations() {
        var draft = ImportedRecipeDraft()
        draft.title = "  Spicy Peanut Noodles  "
        draft.creator = "@cookfast"
        draft.sourceURL = "https://www.tiktok.com/@cookfast/video/1"
        draft.platform = .tiktok
        draft.servings = 3
        draft.prepMinutes = 5
        draft.cookMinutes = 15
        draft.ingredientLines = ["200 g rice noodles", "", "2 tbsp peanut butter"]
        draft.stepTexts = ["Boil noodles for 8 minutes.", "Toss with sauce."]
        draft.tags = ["quick"]
        draft.calories = 520
        draft.proteinGrams = 18

        let recipe = RecipeFactory.make(from: draft)

        XCTAssertEqual(recipe.title, "Spicy Peanut Noodles")     // trimmed
        XCTAssertEqual(recipe.sourceCreator, "@cookfast")
        XCTAssertEqual(recipe.sourcePlatform, .tiktok)
        XCTAssertEqual(recipe.servings, 3)
        XCTAssertEqual(recipe.calories, 520)
        XCTAssertEqual(recipe.proteinGrams, 18)
        XCTAssertNotNil(recipe.importedAt)

        // Empty ingredient line is dropped; the rest parse into qty/unit/name.
        XCTAssertEqual(recipe.ingredients.count, 2)
        let noodles = recipe.ingredients.first { $0.name == "rice noodles" }
        XCTAssertEqual(noodles?.quantity, 200)
        XCTAssertEqual(noodles?.unit, "g")
        XCTAssertEqual(noodles?.sortIndex, 0)

        // "8 minutes" -> 480 seconds; second step has no duration.
        XCTAssertEqual(recipe.steps.count, 2)
        XCTAssertEqual(recipe.steps[0].durationSeconds, 480)
        XCTAssertNil(recipe.steps[1].durationSeconds)
    }

    func testMissingTitleAndServingsGetSafeDefaults() {
        let recipe = RecipeFactory.make(from: ImportedRecipeDraft())
        XCTAssertEqual(recipe.title, "")
        XCTAssertEqual(recipe.servings, 2)
        XCTAssertTrue(recipe.ingredients.isEmpty)
        XCTAssertTrue(recipe.steps.isEmpty)
    }
}
