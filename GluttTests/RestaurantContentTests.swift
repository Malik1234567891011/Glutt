import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class RestaurantContentTests: XCTestCase {

    private var container: ModelContainer!
    private let versionKey = "glutt.restaurantContent.contentVersion"

    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: versionKey)
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
        UserDefaults.standard.removeObject(forKey: versionKey)
    }

    private func recipes() throws -> [Recipe] {
        try container.mainContext.fetch(FetchDescriptor<Recipe>())
    }

    func testCotoaShipsItsFiveSignaturePlates() {
        XCTAssertEqual(RestaurantContent.restaurants.count, 1)
        let cotoa = try! XCTUnwrap(RestaurantContent.restaurant(id: "cotoa"))
        XCTAssertEqual(RestaurantContent.dishes(for: cotoa).count, 5)
    }

    func testEveryDishHasIngredientsStepsAndArt() {
        for restaurant in RestaurantContent.restaurants {
            for dish in RestaurantContent.dishes(for: restaurant) {
                XCTAssertFalse(dish.ingredients.isEmpty, "\(dish.title) has no ingredients")
                XCTAssertFalse(dish.steps.isEmpty, "\(dish.title) has no steps")
                XCTAssertFalse(dish.imageAsset.isEmpty, "\(dish.title) has no image")
            }
        }
    }

    func testInstallSeedsEveryDishTaggedToItsRestaurant() throws {
        RestaurantContent.install(context: container.mainContext)
        let stored = try recipes()
        let expected = RestaurantContent.restaurants
            .reduce(0) { $0 + RestaurantContent.dishes(for: $1).count }
        XCTAssertEqual(stored.count, expected)

        let mahi = stored.first { $0.title == "Mahi Mahi Manicero" }
        XCTAssertEqual(mahi?.restaurantSlug, "cotoa")
        XCTAssertEqual(mahi?.restaurant?.name, "Cotoa")
        XCTAssertEqual(mahi?.sourceCreator, "Cotoa")
        XCTAssertEqual(mahi?.isRestaurantRecipe, true)
        XCTAssertEqual(mahi?.isCuratedRecipe, true)
        XCTAssertFalse(mahi?.ingredients.isEmpty ?? true)
        XCTAssertFalse(mahi?.steps.isEmpty ?? true)
    }

    func testInstallIsIdempotent() throws {
        RestaurantContent.install(context: container.mainContext)
        let first = try recipes().count
        RestaurantContent.install(context: container.mainContext)
        XCTAssertEqual(try recipes().count, first, "Second install should not duplicate dishes")
    }

    func testInstallLeavesAUserRecipeOfTheSameNameAlone() throws {
        let mine = Recipe(title: "El Pincho")
        mine.summary = "My own version"
        container.mainContext.insert(mine)
        RestaurantContent.install(context: container.mainContext)

        XCTAssertEqual(mine.summary, "My own version")
        XCTAssertFalse(mine.isRestaurantRecipe)
        XCTAssertFalse(mine.isCuratedRecipe)
        XCTAssertEqual(try recipes().filter { $0.title == "El Pincho" }.count, 2)
    }

    func testRankedPairsDishesWithStoredRecipesInPackOrder() throws {
        RestaurantContent.install(context: container.mainContext)
        let cotoa = try XCTUnwrap(RestaurantContent.restaurant(id: "cotoa"))
        let ranked = RestaurantContent.ranked(for: cotoa, in: try recipes())

        XCTAssertEqual(ranked.count, 5)
        XCTAssertEqual(ranked.map(\.rank), [1, 2, 3, 4, 5])
        XCTAssertEqual(ranked.first?.dish.title, "Mahi Mahi Manicero")
        XCTAssertEqual(ranked.map(\.dish.title), ranked.map(\.recipe.title))
    }

    /// Chef and restaurant tags share a namespace shape, so a mix-up would show
    /// restaurant plates on a chef's page.
    func testChefAndRestaurantTagsDoNotCrossOver() throws {
        RestaurantContent.install(context: container.mainContext)
        ChefContent.install(context: container.mainContext)
        for recipe in try recipes() {
            XCTAssertFalse(
                recipe.isChefRecipe && recipe.isRestaurantRecipe,
                "\(recipe.title) is tagged as both")
        }
    }
}
