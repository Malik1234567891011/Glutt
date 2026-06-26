import XCTest
@testable import Glutt

final class RecipeFactoryMacroTests: XCTestCase {
    func testMakeCarriesFullMacrosAndTrustedFlag() {
        var draft = ImportedRecipeDraft()
        draft.title = "Lemon Chicken Bowl"
        draft.calories = 620
        draft.proteinGrams = 48
        draft.carbGrams = 55
        draft.fatGrams = 18
        draft.nutritionIsEstimated = false

        let recipe = RecipeFactory.make(from: draft)

        XCTAssertEqual(recipe.calories, 620)
        XCTAssertEqual(recipe.proteinGrams, 48)
        XCTAssertEqual(recipe.carbGrams, 55)
        XCTAssertEqual(recipe.fatGrams, 18)
        XCTAssertFalse(recipe.nutritionIsEstimated)
    }

    func testMakeDefaultsToEstimatedWhenDraftSaysSo() {
        var draft = ImportedRecipeDraft()
        draft.title = "Guess Bowl"
        // nutritionIsEstimated defaults to true on the draft
        let recipe = RecipeFactory.make(from: draft)
        XCTAssertTrue(recipe.nutritionIsEstimated)
        XCTAssertNil(recipe.carbGrams)
        XCTAssertNil(recipe.fatGrams)
    }
}
