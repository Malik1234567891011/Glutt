import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PollyPromptBuilderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([
                Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
                UserPrefs.self, CookSession.self, PollyMemory.self,
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws {
        container = nil
    }

    // MARK: - Fixtures

    /// 3 ingredients: chicken (owned), onion (missing, required), parsley (missing, optional).
    private func makeRecipe() -> Recipe {
        let recipe = Recipe(title: "Harissa Chicken Skillet", servings: 2, prepMinutes: 10, cookMinutes: 25)
        context.insert(recipe)
        recipe.ingredients = [
            RecipeIngredient(name: "chicken thighs", quantity: 500, unit: "g", sortIndex: 0),
            RecipeIngredient(name: "onion", quantity: 1, sortIndex: 1),
            RecipeIngredient(name: "parsley", isOptional: true, sortIndex: 2),
        ]
        recipe.steps = [
            RecipeStep(index: 0, text: "Sear the chicken until deeply browned."),
            RecipeStep(index: 1, text: "Add onion and harissa, simmer 15 minutes.", durationSeconds: 900),
        ]
        return recipe
    }

    private func makePrefs() -> UserPrefs {
        let prefs = UserPrefs.current(in: context)
        prefs.dietaryRules = [.halal]
        prefs.allergies = ["peanut"]
        prefs.dislikedIngredients = ["cilantro"]
        return prefs
    }

    private func makeMatch(for recipe: Recipe) -> PantryMatcher.MatchResult {
        let sorted = recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }
        return PantryMatcher.MatchResult(
            owned: [sorted[0]],
            missing: [sorted[1]],
            missingOptional: [sorted[2]]
        )
    }

    private func makeMemories() -> [PollyMemory] {
        let facts = [
            PollyMemory(kind: .equipment, text: "Owns a cast iron skillet", confidence: 0.9, sourceRecipeTitle: nil),
            PollyMemory(kind: .technique, text: "Chops slowly, pad prep estimates", confidence: 0.7, sourceRecipeTitle: nil),
            PollyMemory(kind: .preference, text: "Likes food spicier than recipes suggest", confidence: 0.8, sourceRecipeTitle: nil),
        ]
        facts.forEach(context.insert)
        return facts
    }

    private func makePastSession(recipe: Recipe) -> CookSession {
        let session = CookSession(date: Date(timeIntervalSince1970: 1_700_000_000), servingsMade: 2, recipe: recipe)
        session.rating = 4
        session.notes = "Came out great, went heavier on harissa"
        context.insert(session)
        return session
    }

    private func instructions(
        recipe: Recipe,
        memories: [PollyMemory] = [],
        pastSessions: [CookSession] = [],
        chef: PollyChefVoice = .default
    ) -> String {
        PollyPromptBuilder.instructions(
            recipe: recipe,
            plan: CookPlan.linear(from: recipe, scale: 1.0),
            pantryMatch: makeMatch(for: recipe),
            prefs: makePrefs(),
            memories: memories,
            pastSessions: pastSessions,
            ownedTools: [],
            chef: chef
        )
    }

    // MARK: - Chef voices

    func testDefaultChefAddsNoOverlay() {
        let recipe = makeRecipe()
        XCTAssertFalse(instructions(recipe: recipe).contains("Your voice this session"),
                       "house Polly must be the prompt exactly as it was")
    }

    func testChefOverlayIsAppendedLastSoItCannotOutrankTheRulesAboveIt() {
        let recipe = makeRecipe()
        let prompt = instructions(recipe: recipe, chef: .gordonRamsay)

        XCTAssertTrue(prompt.contains("Your voice this session: Gordon Ramsay"))
        // Ordering is the safety property, not a style choice. A persona placed
        // above the run policy would let "how to sound" quietly outrank a
        // food-safety or dietary rule; placed last it can only colour them, and
        // it says so itself.
        let overlayStart = try? XCTUnwrap(prompt.range(of: "Your voice this session"))
        let rulesStart = try? XCTUnwrap(prompt.range(of: "Be directional, never chatty"))
        if let overlayStart, let rulesStart {
            XCTAssertTrue(overlayStart.lowerBound > rulesStart.lowerBound,
                          "the chef overlay must come after the run policy")
        }
        // The dish is still the dish.
        XCTAssertTrue(prompt.contains("Harissa Chicken Skillet"))
        XCTAssertTrue(prompt.contains("peanut"), "allergies survive a persona swap")
    }

    func testRamsayOverlayForbidsTheAbusiveTelevisionPersona() {
        let overlay = PollyChefVoice.gordonRamsay.personaOverlay
        XCTAssertTrue(overlay.contains("Never swear"))
        XCTAssertTrue(overlay.contains("never insult the cook"))
        XCTAssertTrue(overlay.lowercased().contains("lamb sauce"),
                      "the catchphrase is named so it can be banned, not used")
        XCTAssertTrue(overlay.contains("Never claim to be the real person"))
    }

    func testEveryChefHasAVoiceAndAStableID() {
        let ids = PollyChefVoice.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ids are persisted, so they must be unique")
        for chef in PollyChefVoice.all {
            XCTAssertFalse(chef.displayName.isEmpty, chef.id)
            XCTAssertFalse(chef.realtimeVoice.isEmpty, chef.id)
            XCTAssertFalse(chef.briefingStyle.isEmpty, chef.id)
        }
        XCTAssertEqual(PollyChefVoice.named("nope").id, PollyChefVoice.default.id,
                       "an unknown id falls back rather than crashing a cook")
    }

    // MARK: - Tests

    func testInstructionsIncludeDishPantryAndHardRules() {
        let recipe = makeRecipe()
        let plan = CookPlan.linear(from: recipe, scale: 1.0)
        let prompt = instructions(recipe: recipe)

        XCTAssertTrue(prompt.contains("Harissa Chicken Skillet"))
        XCTAssertTrue(prompt.contains("\(plan.servings) servings"))
        XCTAssertTrue(prompt.contains("has 1 of 2"), "ownedCount/totalCount from the pantry match")
        XCTAssertTrue(prompt.contains("onion"), "missing required ingredient is listed")
        XCTAssertTrue(prompt.contains("parsley"), "missing optional ingredient is listed")
        XCTAssertTrue(prompt.contains("halal"), "DietaryRule rawValue, not the display label")
        XCTAssertTrue(prompt.contains("peanut"))
        XCTAssertTrue(prompt.contains("cilantro"), "dislikes appear as a soft preference")
    }

    func testInstructionsIncludeMemoriesAndPastSessionHistory() {
        let recipe = makeRecipe()
        let memories = makeMemories()
        let prompt = instructions(recipe: recipe, memories: memories,
                                  pastSessions: [makePastSession(recipe: recipe)])

        for memory in memories {
            XCTAssertTrue(prompt.contains(memory.text), "missing memory: \(memory.text)")
        }
        XCTAssertTrue(prompt.contains("- [equipment] Owns a cast iron skillet"))
        XCTAssertTrue(prompt.contains("4/5"), "past-session rating string")
        XCTAssertTrue(prompt.contains("Came out great, went heavier on harissa"))
        XCTAssertFalse(prompt.contains("First time cooking this together."))
    }

    func testCookPlanJSONRoundTripsBetweenMarkers() throws {
        let recipe = makeRecipe()
        let plan = CookPlan.linear(from: recipe, scale: 1.0)
        let prompt = instructions(recipe: recipe)

        let start = try XCTUnwrap(prompt.range(of: "<cook_plan>"))
        let end = try XCTUnwrap(prompt.range(of: "</cook_plan>"))
        XCTAssertTrue(start.upperBound <= end.lowerBound, "markers appear in order")
        let json = prompt[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = try JSONDecoder().decode(CookPlan.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, plan)
    }

    func testFirstTimeLineWhenNoPastSessions() {
        let prompt = instructions(recipe: makeRecipe(), pastSessions: [])
        XCTAssertTrue(prompt.contains("First time cooking this together."))
    }

    func testMemoryBulletsAreCappedAtConfigLimit() {
        let memories = (0..<20).map { i in
            PollyMemory(kind: .outcome, text: "Durable kitchen fact number \(i)",
                        confidence: 0.5, sourceRecipeTitle: nil)
        }
        memories.forEach(context.insert)
        let prompt = instructions(recipe: makeRecipe(), memories: memories)

        let bullets = prompt.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }
        XCTAssertEqual(bullets.count, PollyConfig.memoryFactLimit)
        XCTAssertTrue(prompt.contains("Durable kitchen fact number 0"))
        XCTAssertFalse(prompt.contains("Durable kitchen fact number \(PollyConfig.memoryFactLimit)"),
                       "facts past the cap must not leak into the prompt")
    }
}
