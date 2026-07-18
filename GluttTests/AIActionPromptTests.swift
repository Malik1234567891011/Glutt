import XCTest
import SwiftData
@testable import Glutt

/// The transport seam's payoff: each AI action's prompt-building runs under
/// test, with `FakeLLMTransport` capturing the request and returning a canned
/// reply. Asserts the domain facts that must reach the model, and that gated
/// actions short-circuit before the network when the client is unconfigured.
@MainActor
final class AIActionPromptTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func makeRecipe(title: String = "Chicken Alfredo") -> Recipe {
        let recipe = Recipe(title: title, servings: 4, prepMinutes: 10, cookMinutes: 20)
        recipe.ingredients = [
            RecipeIngredient(name: "chicken breast", quantity: 2, sortIndex: 0),
            RecipeIngredient(name: "heavy cream", quantity: 200, unit: "ml", sortIndex: 1),
        ]
        recipe.steps = [
            RecipeStep(index: 0, text: "Sear the chicken."),
            RecipeStep(index: 1, text: "Add the cream."),
        ]
        container.mainContext.insert(recipe)
        return recipe
    }

    // MARK: - RecipeAdjuster

    func testAdjustPutsAllergiesAndRecipeInPrompt() async throws {
        let fake = FakeLLMTransport(replyJSON:
            #"{"ingredients":["x"],"steps":["y"],"changes":["c"],"summary":"s","servings":4}"#)
        let out = try await RecipeAdjuster.adjust(
            recipe: makeRecipe(), request: .preset(.higherProtein),
            rules: [], allergies: ["peanuts"], client: fake.client()
        )
        XCTAssertEqual(out.ingredients, ["x"])
        XCTAssertTrue(fake.jsonMode)
        XCTAssertTrue(fake.user.contains("peanuts"))
        XCTAssertTrue(fake.user.contains("chicken breast"))
        XCTAssertTrue(fake.system.contains("Return JSON"))
    }

    // MARK: - PantryScan (vision)

    func testScanAttachesImageAndAsksToReadLabels() async throws {
        let fake = FakeLLMTransport(replyJSON:
            #"{"items":[{"name":"eggs","quantity":"full","category":"dairy"}]}"#)
        let items = try await PantryScan.scan(
            imageData: Data([0x01, 0x02, 0x03]), existingPantry: [], client: fake.client()
        )
        XCTAssertEqual(items.first?.name, "eggs")
        XCTAssertTrue(fake.hasImage)
        XCTAssertTrue(fake.system.contains("Read any visible text"))
    }

    // MARK: - MealPhotoEstimator (vision)

    func testEstimateAttachesImage() async throws {
        let fake = FakeLLMTransport(replyJSON:
            #"{"title":"Burrito bowl","calories":700,"proteinGrams":40}"#)
        let est = try await MealPhotoEstimator.estimate(imageData: Data([0x09]), client: fake.client())
        XCTAssertEqual(est.title, "Burrito bowl")
        XCTAssertTrue(fake.hasImage)
    }

    // MARK: - PantryChef (gated)

    func testInventBuildsPromptFromOnHandIngredients() async {
        let pantry = [PantryItem(name: "eggs"), PantryItem(name: "rice")]
        let fake = FakeLLMTransport(replyJSON:
            #"{"title":"Egg Fried Rice","summary":"s","servings":2,"prepMinutes":5,"cookMinutes":10,"ingredients":["2 eggs","1 cup rice"],"steps":["Fry it."],"tags":["quick"]}"#)
        let draft = await PantryChef.invent(pantry: pantry, prefs: UserPrefs(), client: fake.client())
        XCTAssertEqual(draft?.title, "Egg Fried Rice")
        XCTAssertTrue(fake.user.contains("eggs"))
        XCTAssertTrue(fake.system.contains("Invent ONE original"))
    }

    func testInventShortCircuitsWhenUnconfigured() async {
        let pantry = [PantryItem(name: "eggs"), PantryItem(name: "rice")]
        let fake = FakeLLMTransport()
        let draft = await PantryChef.invent(pantry: pantry, prefs: UserPrefs(),
                                            client: fake.client(baseURL: ""))
        XCTAssertNil(draft)
        XCTAssertEqual(fake.callCount, 0)
    }

    // MARK: - AskGlutt (gated)

    func testRankSearchPutsQueryAndRecipesInPrompt() async {
        let results = [RecipeSearchEngine.SearchResult(
            recipe: makeRecipe(title: "Lemon Salmon"), score: 1, reasons: ["lemon"])]
        let fake = FakeLLMTransport(replyJSON: #"{"headline":"Found it","picks":[]}"#)
        let outcome = await AskGlutt.rankSearch(
            query: "creamy salmon", results: results, pantry: [], client: fake.client())
        XCTAssertTrue(outcome.usedAI)
        XCTAssertTrue(fake.user.contains("creamy salmon"))
        XCTAssertTrue(fake.user.contains("Lemon Salmon"))
        XCTAssertTrue(fake.system.contains("saved recipes"))
    }

    func testRankSearchShortCircuitsWhenUnconfigured() async {
        let results = [RecipeSearchEngine.SearchResult(
            recipe: makeRecipe(), score: 1, reasons: [])]
        let fake = FakeLLMTransport()
        let outcome = await AskGlutt.rankSearch(
            query: "x", results: results, pantry: [], client: fake.client(baseURL: ""))
        XCTAssertFalse(outcome.usedAI)
        XCTAssertEqual(fake.callCount, 0)
    }

    // MARK: - DraftCleanup ×3

    func testCleanUpBuildsPromptFromCaption() async {
        var draft = ImportedRecipeDraft()
        draft.title = "Garlic Pasta"
        draft.caption = "the creamiest garlic pasta with parmesan and black pepper, so good"
        let fake = FakeLLMTransport(replyJSON:
            #"{"title":"Garlic Pasta","ingredients":["200g pasta","3 cloves garlic"],"steps":["Boil pasta.","Make sauce."]}"#)
        let out = await DraftCleanup.cleanUp(draft, client: fake.client())
        XCTAssertEqual(out.ingredientLines.first, "200g pasta")
        XCTAssertTrue(fake.user.contains("garlic pasta"))
        XCTAssertTrue(fake.system.contains("clean up recipes"))
    }

    func testInferStepsBuildsPromptFromIngredients() async {
        var draft = ImportedRecipeDraft()
        draft.title = "Omelette"
        draft.ingredientLines = ["3 eggs", "butter", "salt"]
        let fake = FakeLLMTransport(replyJSON: #"{"steps":["Beat the eggs.","Cook in butter."]}"#)
        let out = await DraftCleanup.inferSteps(draft, client: fake.client())
        XCTAssertEqual(out.stepTexts.count, 2)
        XCTAssertTrue(out.stepsAreAISuggested)
        XCTAssertTrue(fake.user.contains("3 eggs"))
        XCTAssertTrue(fake.system.contains("cooking method steps"))
    }

    func testReconstructBuildsPromptFromDishName() async {
        var draft = ImportedRecipeDraft()
        draft.title = "Pad Thai"
        let fake = FakeLLMTransport(replyJSON:
            #"{"title":"Pad Thai","ingredients":["rice noodles","peanuts"],"steps":["Soak noodles.","Stir fry."]}"#)
        let out = await DraftCleanup.reconstruct(draft, client: fake.client())
        XCTAssertFalse(out.ingredientLines.isEmpty)
        XCTAssertTrue(fake.user.contains("Pad Thai"))
        XCTAssertTrue(fake.system.contains("STANDARD HOME version"))
    }
}
