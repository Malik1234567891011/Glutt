import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class ChefContentTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: "glutt.chefContent.contentVersion")
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
        UserDefaults.standard.removeObject(forKey: "glutt.chefContent.contentVersion")
    }

    func testEveryChefHasFiveDishes() {
        XCTAssertEqual(ChefContent.chefs.count, 3)
        for chef in ChefContent.chefs {
            let count = ChefContent.dishes(for: chef).count
            if chef.id == "gordon-ramsay" {
                XCTAssertEqual(count, 6, "Gordon should ship six (Wellington + Eggs Benedict pilots)")
            } else {
                XCTAssertEqual(count, 5, "\(chef.name) should ship five")
            }
        }
    }

    func testInstallSeedsEveryDishTaggedToItsChef() throws {
        let context = container.mainContext
        ChefContent.install(context: context)

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.count, 16)

        let wellington = recipes.first { $0.title == "Beef Wellington" }
        XCTAssertEqual(wellington?.chefSlug, "gordon-ramsay")
        XCTAssertEqual(wellington?.sourceCreator, "Gordon Ramsay")
        XCTAssertEqual(wellington?.isChefRecipe, true)
        XCTAssertEqual(wellington?.sourceURL, "https://www.youtube.com/watch?v=Cyskqnp1j64")
        XCTAssertFalse(wellington?.ingredients.isEmpty ?? true)
        XCTAssertFalse(wellington?.steps.isEmpty ?? true)
        // The discriminator must never be the tag the feed card shows.
        XCTAssertEqual(wellington?.tags.first, "Signature")

        let eggs = recipes.first { $0.title == "Eggs Benedict" }
        XCTAssertEqual(eggs?.chefSlug, "gordon-ramsay")
        XCTAssertEqual(eggs?.sourceURL, "https://www.youtube.com/watch?v=gBJjRYk0yC0")
    }

    func testInstallIsIdempotent() throws {
        let context = container.mainContext
        ChefContent.install(context: context)
        ChefContent.install(context: context)

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.count, 16)
    }

    func testRankedReturnsTheFiveInPackOrder() throws {
        let context = container.mainContext
        ChefContent.install(context: context)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())

        let gordon = try XCTUnwrap(ChefContent.chef(id: "gordon-ramsay"))
        let ranked = ChefContent.ranked(for: gordon, in: recipes)
        XCTAssertEqual(ranked.map(\.rank), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(ranked.first?.recipe.title, "Beef Wellington")
        XCTAssertEqual(ranked[1].recipe.title, "Eggs Benedict")
        XCTAssertEqual(ranked.map(\.recipe.chefSlug), Array(repeating: "gordon-ramsay", count: 6))
    }

    func testUserRecipesHaveNoChefSlug() {
        let mine = Recipe(title: "Beef Wellington", tags: ["Beef"])
        XCTAssertNil(mine.chefSlug)
        XCTAssertFalse(mine.isChefRecipe)
    }

    func testLongRecipesReadInHours() throws {
        let context = container.mainContext
        ChefContent.install(context: context)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())

        let wellington = try XCTUnwrap(recipes.first { $0.title == "Beef Wellington" })
        XCTAssertEqual(wellington.timeLabel, "2 hr 30")
    }
}
