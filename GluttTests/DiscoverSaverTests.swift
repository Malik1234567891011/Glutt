import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class DiscoverSaverTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    func testSaveCreatesYouTubeRecipeFromDraft() async throws {
        let context = container.mainContext
        let video = DiscoverVideo(videoId: "abc123", title: "Crispy Tofu",
                                  creator: "Wok Wed", thumbnailURL: nil, durationSeconds: nil)

        var draft = ImportedRecipeDraft()
        draft.title = "Crispy Tofu"
        draft.platform = .youtube
        draft.sourceURL = video.watchURL.absoluteString
        draft.ingredientLines = ["200 g firm tofu"]
        draft.stepTexts = ["Press the tofu", "Fry until golden"]

        let recipe = try await DiscoverSaver.save(video: video, importDraft: { _ in draft }, into: context)

        XCTAssertEqual(recipe.sourcePlatform, .youtube)
        XCTAssertEqual(recipe.sourceURL, "https://www.youtube.com/watch?v=abc123")
        let all = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(all.count, 1)
    }

    func testSaveDedupsBySourceURLWithoutImporting() async throws {
        let context = container.mainContext
        let video = DiscoverVideo(videoId: "abc123", title: "Crispy Tofu",
                                  creator: nil, thumbnailURL: nil, durationSeconds: nil)
        let preexisting = Recipe(title: "Already here",
                                 sourceURL: video.watchURL.absoluteString,
                                 sourcePlatform: .youtube)
        context.insert(preexisting)
        try context.save()

        var importCalled = false
        let recipe = try await DiscoverSaver.save(
            video: video,
            importDraft: { _ in importCalled = true; return ImportedRecipeDraft() },
            into: context
        )

        XCTAssertFalse(importCalled, "should not re-import a video already saved")
        XCTAssertEqual(recipe.persistentModelID, preexisting.persistentModelID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Recipe>()).count, 1)
    }
}
