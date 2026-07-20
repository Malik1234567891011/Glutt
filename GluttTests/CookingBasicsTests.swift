import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class CookingBasicsTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: "glutt.cookingBasics.contentVersion")
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeStep.self,
            RecipeCollection.self, PantryItem.self, GroceryItem.self,
            KitchenTool.self, CookSession.self, UserPrefs.self,
            PollyMemory.self, PollyCookLog.self,
        ])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "glutt.cookingBasics.contentVersion")
    }

    func testInstallSeedsFriedEggLesson() throws {
        let context = container.mainContext
        CookingBasics.install(context: context)

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let lesson = recipes.first { $0.title.contains("Fry an Egg") }
        XCTAssertNotNil(lesson)
        XCTAssertTrue(lesson!.isCookingBasic)
        XCTAssertEqual(lesson!.sourceCreator, "Glutt Basics")
        XCTAssertGreaterThanOrEqual(lesson!.steps.count, 6)
        let joined = lesson!.steps.map(\.text).joined(separator: " ")
        XCTAssertTrue(joined.localizedCaseInsensitiveContains("opaque"))
        XCTAssertTrue(joined.localizedCaseInsensitiveContains("lid"))
        XCTAssertTrue(joined.localizedCaseInsensitiveContains("foam")
                      || joined.localizedCaseInsensitiveContains("bubble"))
        XCTAssertTrue(joined.localizedCaseInsensitiveContains("coats")
                      || joined.localizedCaseInsensitiveContains("coat"))
    }

    func testInstallIsIdempotent() throws {
        let context = container.mainContext
        CookingBasics.install(context: context)
        CookingBasics.install(context: context)

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let fried = recipes.filter { $0.title.contains("Fry an Egg") }
        XCTAssertEqual(fried.count, 1)
    }
}
