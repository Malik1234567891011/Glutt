import XCTest
import SwiftData
@testable import Glutt

/// Clip generation is switched off for user imports in the App Store build.
/// These pin the two halves of that promise: nothing gets enqueued for an
/// import, and the bundled chef dishes — whose clips were generated and reviewed
/// in an earlier release — are untouched.
@MainActor
final class MediaClipGateTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
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

    private func youTubeImport() -> Recipe {
        let recipe = Recipe(title: "Someone's YouTube dinner", sourcePlatform: .youtube)
        recipe.sourceURL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        container.mainContext.insert(recipe)
        return recipe
    }

    // MARK: - Imports

    func testYouTubeImportIsNotEnqueuedWhileGenerationIsOff() throws {
        try XCTSkipIf(
            MediaClipConfig.generatesClipsForImports,
            "Generation is on — this build intends to clip imports")
        XCTAssertFalse(MediaClipEnqueue.shouldEnqueue(youTubeImport()))
    }

    func testAnImportMayNotUseClipsAtAll() throws {
        try XCTSkipIf(MediaClipConfig.generatesClipsForImports)
        XCTAssertFalse(MediaClipConfig.clipsAllowed(for: youTubeImport()))
    }

    /// The status poll is what re-drives a stalled job, so leaving it open would
    /// quietly undo the gate the moment someone opened the recipe.
    func testRefreshStatusLeavesAnImportsClipFieldsAlone() async throws {
        try XCTSkipIf(MediaClipConfig.generatesClipsForImports)
        let recipe = youTubeImport()
        await MediaClipEnqueue.refreshStatus(for: recipe, in: container.mainContext)
        XCTAssertNil(recipe.mediaStatus)
        XCTAssertNil(recipe.mediaJobID)
        XCTAssertNil(recipe.mediaSourceAssetID)
    }

    // MARK: - Bundled chef content

    func testBundledChefDishesKeepTheirClips() throws {
        try XCTSkipIf(MediaClipConfig.generatesClipsForImports)
        ChefContent.install(context: container.mainContext)
        let stored = try container.mainContext.fetch(FetchDescriptor<Recipe>())
        let withVideo = stored.filter { $0.isChefRecipe && $0.sourceURL?.isEmpty == false }
        XCTAssertFalse(withVideo.isEmpty, "Expected at least one chef dish with a technique video")
        for recipe in withVideo {
            XCTAssertTrue(
                MediaClipConfig.clipsAllowed(for: recipe),
                "\(recipe.title) lost its reviewed clips")
        }
    }

    func testRestaurantDishesAreNotClaimedToHaveClips() throws {
        RestaurantContent.install(context: container.mainContext)
        let stored = try container.mainContext.fetch(FetchDescriptor<Recipe>())
        let restaurantDishes = stored.filter(\.isRestaurantRecipe)
        XCTAssertFalse(restaurantDishes.isEmpty)
        for recipe in restaurantDishes {
            XCTAssertFalse(
                MediaClipEnqueue.shouldEnqueue(recipe),
                "\(recipe.title) has no source video and must never enqueue")
        }
    }
}
