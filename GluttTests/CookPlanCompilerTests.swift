import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class CookPlanCompilerTests: XCTestCase {

    private var container: ModelContainer!
    private var tempDir: URL!
    private var originalCacheDirectory: URL!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("polly-plan-cache-\(UUID().uuidString)", isDirectory: true)
        originalCacheDirectory = CookPlanCompiler.cacheDirectory
        CookPlanCompiler.cacheDirectory = tempDir
    }

    override func tearDownWithError() throws {
        CookPlanCompiler.cacheDirectory = originalCacheDirectory
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        container = nil
    }

    // MARK: - Fixtures

    private func makeRecipe(
        title: String = "Shakshuka",
        stepTexts: [String] = ["Sauté the onions.", "Add the tomatoes.", "Crack in the eggs and cover."]
    ) -> Recipe {
        let recipe = Recipe(title: title, servings: 2, prepMinutes: 10, cookMinutes: 20)
        recipe.ingredients = [
            RecipeIngredient(name: "eggs", quantity: 4, sortIndex: 0),
            RecipeIngredient(name: "crushed tomatoes", quantity: 400, unit: "g", sortIndex: 1),
            RecipeIngredient(name: "onion", quantity: 1, sortIndex: 2),
        ]
        recipe.steps = stepTexts.enumerated().map { RecipeStep(index: $0.offset, text: $0.element) }
        container.mainContext.insert(recipe)
        return recipe
    }

    /// Built through the decoder (house pattern, like PlateCard tests) because
    /// CookPlan's custom init(from:) suppresses the memberwise initializer.
    private func fixturePlan() throws -> CookPlan {
        let json = """
        {"title": "Shakshuka", "servings": 2,
         "mise": [{"name": "onion", "prep": "diced"}],
         "equipment": ["skillet with lid"],
         "steps": [{"id": "s1", "index": 0, "title": "Sauté onions",
                    "instruction": "Sauté the onions until soft.", "kind": "active",
                    "estimatedSeconds": 300, "dependsOn": [],
                    "visualCheck": "translucent and lightly golden",
                    "ingredientNames": ["onion"]}]}
        """
        return try JSONDecoder().decode(CookPlan.self, from: Data(json.utf8))
    }

    private struct Boom: Error {}

    // MARK: - cacheKey

    func testCacheKeyIsStableForSameContent() {
        let a = makeRecipe()
        let b = makeRecipe()  // separate object, identical content
        XCTAssertEqual(CookPlanCompiler.cacheKey(recipe: a, scale: 1.0),
                       CookPlanCompiler.cacheKey(recipe: a, scale: 1.0))
        XCTAssertEqual(CookPlanCompiler.cacheKey(recipe: a, scale: 1.0),
                       CookPlanCompiler.cacheKey(recipe: b, scale: 1.0),
                       "key must depend on content, not object identity")
    }

    func testCacheKeyChangesWithScale() {
        let recipe = makeRecipe()
        XCTAssertNotEqual(CookPlanCompiler.cacheKey(recipe: recipe, scale: 1.0),
                          CookPlanCompiler.cacheKey(recipe: recipe, scale: 1.5))
    }

    func testCacheKeyChangesWhenStepTextChanges() {
        let recipe = makeRecipe()
        let before = CookPlanCompiler.cacheKey(recipe: recipe, scale: 1.0)
        recipe.sortedSteps[0].text = "Char the onions hard."
        XCTAssertNotEqual(before, CookPlanCompiler.cacheKey(recipe: recipe, scale: 1.0))
    }

    // MARK: - File cache

    func testStoreThenCachedPlanRoundTrips() throws {
        let plan = try fixturePlan()
        CookPlanCompiler.store(plan, forKey: "roundtrip")
        XCTAssertEqual(CookPlanCompiler.cachedPlan(forKey: "roundtrip"), plan)
    }

    func testCachedPlanReturnsNilWhenMissing() {
        XCTAssertNil(CookPlanCompiler.cachedPlan(forKey: "never-stored"))
    }

    // MARK: - compile

    func testCompileUsesLLMThenServesFromCache() async throws {
        let recipe = makeRecipe()
        let fixture = try fixturePlan()

        var llmCalls = 0
        var capturedUser = ""
        let first = await CookPlanCompiler.compile(recipe: recipe, scale: 1.0) { _, user in
            llmCalls += 1
            capturedUser = user
            return fixture
        }
        XCTAssertEqual(llmCalls, 1)
        XCTAssertFalse(first.isFallback)
        XCTAssertEqual(first, fixture)
        XCTAssertTrue(capturedUser.contains("Shakshuka"), "user prompt must carry the recipe")

        // Second compile: the llm throws, so only a cache hit can return this plan.
        let second = await CookPlanCompiler.compile(recipe: recipe, scale: 1.0) { _, _ in
            throw Boom()
        }
        XCTAssertEqual(second, first, "second compile must be served from the file cache")
    }

    func testCompileFallsBackToLinearAndDoesNotCache() async {
        let recipe = makeRecipe()
        let plan = await CookPlanCompiler.compile(recipe: recipe, scale: 1.0) { _, _ in
            throw Boom()
        }
        XCTAssertTrue(plan.isFallback, "a failed compile must degrade to the linear plan")
        let key = CookPlanCompiler.cacheKey(recipe: recipe, scale: 1.0)
        XCTAssertNil(CookPlanCompiler.cachedPlan(forKey: key), "fallback plans must never be cached")
    }
}
