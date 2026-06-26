import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PlatesSaverTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        RecipeImageBackfill.resetFailedURLsForTesting()
    }
    override func tearDownWithError() throws { container = nil; try super.tearDownWithError() }

    // A valid 1×1 PNG so ImagePrep can re-encode it during eager backfill.
    private let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="

    private func card(id: String = "spoonacular:1", url: String = "https://feast.test/r") -> PlateCard {
        let json = """
        { "id": "\(id)", "title": "Lemon Chicken", "imageURL": "https://img.test/1.jpg",
          "source": "spoonacular", "sourceURL": "\(url)", "creator": "Feast",
          "servings": 4, "cookMinutes": 30, "tags": ["dinner"], "dietFlags": [],
          "macros": { "calories": 620, "protein": 48, "carbs": 55, "fat": 18, "estimated": false },
          "ingredients": [ { "raw": "600 g chicken thighs", "name": "chicken", "quantity": 600, "unit": "g" } ],
          "steps": ["Season", "Sear 4 min"] }
        """
        return try! JSONDecoder().decode(PlateCard.self, from: Data(json.utf8))
    }

    func testSaveBuildsRecipeWithFullMacros() async throws {
        let context = container.mainContext
        let fetch: RecipeImageBackfill.Fetch = { _ in Data(base64Encoded: self.pngBase64)! }
        let recipe = try await PlatesSaver.save(card: card(), into: context, fetch: fetch)

        XCTAssertEqual(recipe.title, "Lemon Chicken")
        XCTAssertEqual(recipe.sourceURL, "https://feast.test/r")
        XCTAssertEqual(recipe.calories, 620)
        XCTAssertEqual(recipe.carbGrams, 55)
        XCTAssertEqual(recipe.fatGrams, 18)
        XCTAssertFalse(recipe.nutritionIsEstimated)
        XCTAssertEqual(recipe.ingredients.count, 1)
        XCTAssertEqual(recipe.steps.count, 2)
        XCTAssertNotNil(recipe.imageData, "eager backfill should cache the hero image")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Recipe>()).count, 1)
    }

    func testSaveDedupsBySourceURL() async throws {
        let context = container.mainContext
        let pre = Recipe(title: "Already", sourceURL: "https://feast.test/r", sourcePlatform: .website)
        context.insert(pre)
        try context.save()

        let recipe = try await PlatesSaver.save(card: card(), into: context, fetch: { _ in Data() })
        XCTAssertEqual(recipe.persistentModelID, pre.persistentModelID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Recipe>()).count, 1)
    }
}
