import SwiftData
import UIKit
import XCTest
@testable import Glutt

@MainActor
final class RecipeImageBackfillTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Recipe.self, configurations: config)
        context = container.mainContext
        RecipeImageBackfill.resetFailedURLsForTesting()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        RecipeImageBackfill.resetFailedURLsForTesting()
        try await super.tearDown()
    }

    // Build a recipe via the same path imports use.
    private func makeRecipe(imageURL: String? = nil, imageData: Data? = nil) -> Recipe {
        var draft = ImportedRecipeDraft()
        draft.title = "Test Dish"
        draft.ingredientLines = ["1 cup flour"]
        draft.stepTexts = ["Mix."]
        draft.imageURL = imageURL
        draft.imageData = imageData
        let recipe = RecipeFactory.make(from: draft)
        context.insert(recipe)
        return recipe
    }

    // A large JPEG so we can prove downscaling happened.
    private func bigJPEG(width: CGFloat = 2000, height: CGFloat = 1500) -> Data {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 1.0)!
    }

    // MARK: - needsCaching

    func testNeedsCachingTrueForUrlOnlyRecipe() {
        let recipe = makeRecipe(imageURL: "https://example.com/a.jpg")
        XCTAssertTrue(RecipeImageBackfill.needsCaching(recipe))
    }

    func testNeedsCachingFalseWhenDataPresent() {
        let recipe = makeRecipe(imageURL: "https://example.com/a.jpg", imageData: Data([0x1, 0x2]))
        XCTAssertFalse(RecipeImageBackfill.needsCaching(recipe))
    }

    func testNeedsCachingFalseWhenNoURL() {
        let recipe = makeRecipe(imageURL: nil)
        XCTAssertFalse(RecipeImageBackfill.needsCaching(recipe))
    }

    func testNeedsCachingFalseWhenURLBlank() {
        let recipe = makeRecipe(imageURL: "   ")
        XCTAssertFalse(RecipeImageBackfill.needsCaching(recipe))
    }

    // MARK: - downloadAndPrepare

    func testDownloadAndPrepareReturnsDownscaledBytes() async throws {
        let big = bigJPEG()
        let out = await RecipeImageBackfill.downloadAndPrepare(
            from: "https://example.com/a.jpg",
            fetch: { _ in big }
        )
        let data = try XCTUnwrap(out)
        let image = UIImage(data: data)
        XCTAssertNotNil(image)
        let longest = max(image!.size.width, image!.size.height)
        XCTAssertLessThanOrEqual(longest, 1280, "ImagePrep should cap the longest side at 1280")
        XCTAssertLessThan(data.count, big.count, "Prepared bytes should be smaller than the 2000px original")
    }

    func testDownloadAndPrepareReturnsNilOnFetchFailure() async {
        struct Boom: Error {}
        let out = await RecipeImageBackfill.downloadAndPrepare(
            from: "https://example.com/a.jpg",
            fetch: { _ in throw Boom() }
        )
        XCTAssertNil(out)
    }

    func testDownloadAndPrepareReturnsNilForBadURL() async {
        let out = await RecipeImageBackfill.downloadAndPrepare(from: "", fetch: { _ in Data() })
        XCTAssertNil(out)
    }

    // MARK: - ensure

    func testEnsureStoresBytesForUrlOnlyRecipe() async {
        let recipe = makeRecipe(imageURL: "https://example.com/a.jpg")
        let big = bigJPEG()
        await RecipeImageBackfill.ensure(for: recipe, in: context, fetch: { _ in big })
        XCTAssertNotNil(recipe.imageData)
        XCTAssertNotNil(recipe.imageData.flatMap { UIImage(data: $0) })
    }

    func testEnsureNoOpWhenAlreadyHasData() async {
        let recipe = makeRecipe(imageURL: "https://example.com/a.jpg", imageData: Data([0x9]))
        var fetchCalls = 0
        await RecipeImageBackfill.ensure(for: recipe, in: context, fetch: { _ in
            fetchCalls += 1
            return Data()
        })
        XCTAssertEqual(fetchCalls, 0, "Should not download when bytes already exist")
        XCTAssertEqual(recipe.imageData, Data([0x9]))
    }

    func testEnsureMarksFailedURLAndSkipsSecondAttempt() async {
        struct Boom: Error {}
        let recipe = makeRecipe(imageURL: "https://example.com/dead.jpg")
        var fetchCalls = 0
        let fetch: RecipeImageBackfill.Fetch = { _ in fetchCalls += 1; throw Boom() }
        await RecipeImageBackfill.ensure(for: recipe, in: context, fetch: fetch)
        await RecipeImageBackfill.ensure(for: recipe, in: context, fetch: fetch)
        XCTAssertEqual(fetchCalls, 1, "A URL that failed this session must not be retried")
        XCTAssertNil(recipe.imageData)
    }

    // MARK: - sweep

    func testSweepOnlyCachesUrlOnlyRecipes() async {
        let urlOnly = makeRecipe(imageURL: "https://example.com/a.jpg")
        let hasData = makeRecipe(imageURL: "https://example.com/b.jpg", imageData: Data([0x7]))
        let noURL = makeRecipe(imageURL: nil)
        let big = bigJPEG()
        await RecipeImageBackfill.sweep(in: context, fetch: { _ in big })
        XCTAssertNotNil(urlOnly.imageData)
        XCTAssertEqual(hasData.imageData, Data([0x7]))   // untouched
        XCTAssertNil(noURL.imageData)
    }

    func testSweepRespectsPerSweepLimit() async {
        // Insert more URL-only recipes than the per-sweep ceiling.
        var recipes: [Recipe] = []
        for i in 0..<(RecipeImageBackfill.perSweepLimit + 5) {
            recipes.append(makeRecipe(imageURL: "https://example.com/\(i).jpg"))
        }
        let big = bigJPEG()
        await RecipeImageBackfill.sweep(in: context, fetch: { _ in big })
        let cachedCount = recipes.filter { $0.imageData != nil }.count
        XCTAssertEqual(cachedCount, RecipeImageBackfill.perSweepLimit,
                       "One sweep should cache at most perSweepLimit recipes")
    }

    func testNeedsCachingFalseWhenBundledAssetPresent() {
        let recipe = makeRecipe(imageURL: "https://example.com/a.jpg")
        recipe.imageAssetName = "some_bundled_asset"
        XCTAssertFalse(RecipeImageBackfill.needsCaching(recipe))
    }
}
