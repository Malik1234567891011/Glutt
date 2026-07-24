import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class CookBriefingBuilderTests: XCTestCase {
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


    func testPicksAllStepsWhenFew() {
        let steps = (0..<3).map { i in
            CookPlan.PlanStep(
                id: "s\(i)", index: i, title: "Step \(i)",
                instruction: "Do thing \(i).", kind: .active
            )
        }
        let picked = CookBriefingBuilder.pickSteps(steps)
        XCTAssertEqual(picked.map(\.id), ["s0", "s1", "s2"])
    }

    func testSamplesAcrossLongPlanIncludingEnds() {
        let steps = (0..<10).map { i in
            CookPlan.PlanStep(
                id: "s\(i)", index: i, title: "Step \(i)",
                instruction: "Do thing \(i).", kind: i == 0 ? .prep : .active
            )
        }
        let picked = CookBriefingBuilder.pickSteps(steps)
        XCTAssertEqual(picked.count, CookBriefingBuilder.maxBeats)
        XCTAssertEqual(picked.first?.id, "s0")
        XCTAssertEqual(picked.last?.id, "s9")
    }

    func testBuildProducesIntroBeatsAndOutro() {
        let recipe = Recipe(
            title: "Garlic Pasta",
            summary: "Creamy weeknight pasta",
            sourcePlatform: .tiktok,
            servings: 2,
            prepMinutes: 10,
            cookMinutes: 15
        )
        recipe.ingredients = [
            RecipeIngredient(name: "pasta", quantity: 200, unit: "g", sortIndex: 0),
            RecipeIngredient(name: "garlic", quantity: 4, unit: "cloves", sortIndex: 1),
        ]
        recipe.steps = [
            RecipeStep(index: 0, text: "Boil the pasta."),
            RecipeStep(index: 1, text: "Sauté the garlic in butter."),
            RecipeStep(index: 2, text: "Toss with cream and serve."),
        ]
        let plan = CookPlan.linear(from: recipe, scale: 1)
        let briefing = CookBriefingBuilder.build(recipe: recipe, plan: plan)

        XCTAssertEqual(briefing.dishTitle, "Garlic Pasta")
        XCTAssertFalse(briefing.beats.isEmpty)
        XCTAssertTrue(briefing.introLine.localizedCaseInsensitiveContains("garlic pasta"))
        XCTAssertFalse(briefing.outroLine.isEmpty)
        XCTAssertGreaterThanOrEqual(briefing.spokenChunks.count, briefing.beats.count + 2)
    }

    func testSpokenChunksStayShallow() {
        let steps = (0..<8).map { i in
            CookPlan.PlanStep(
                id: "s\(i)", index: i,
                title: "Phase \(i)",
                instruction: String(repeating: "detail ", count: 20),
                kind: .active
            )
        }
        let plan = CookPlan(
            title: "Big Feast",
            servings: 4,
            mise: [CookPlan.MiseItem(name: "onion", prep: "dice")],
            equipment: ["Skillet", "Pot"],
            steps: steps,
            isFallback: true
        )
        let recipe = Recipe(
            title: "Big Feast",
            sourcePlatform: .website,
            servings: 4,
            prepMinutes: 20,
            cookMinutes: 40
        )
        let briefing = CookBriefingBuilder.build(recipe: recipe, plan: plan)
        XCTAssertLessThanOrEqual(briefing.beats.count, CookBriefingBuilder.maxBeats)
        XCTAssertEqual(briefing.miseLine, "Dice onion")
        XCTAssertEqual(briefing.gearLine, "Skillet · Pot")
        // Whole narration should stay trailer-length, not a full recipe read.
        let wordCount = briefing.spokenChunks
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .count
        XCTAssertLessThan(wordCount, 120, "briefing should stay shallow, got \(wordCount) words")
    }

    func testHeardBriefingShortensPollyOpeningPolicy() {
        let recipe = Recipe(title: "Soup", servings: 2)
        context.insert(recipe)
        recipe.steps = [RecipeStep(index: 0, text: "Simmer.")]
        let match = PantryMatcher.MatchResult(owned: [], missing: [], missingOptional: [])
        let prefs = UserPrefs.current(in: context)
        let base = PollyPromptBuilder.instructions(
            recipe: recipe,
            plan: CookPlan.linear(from: recipe, scale: 1),
            pantryMatch: match,
            prefs: prefs,
            memories: [],
            pastSessions: [],
            ownedTools: [],
            heardBriefing: false
        )
        let briefed = PollyPromptBuilder.instructions(
            recipe: recipe,
            plan: CookPlan.linear(from: recipe, scale: 1),
            pantryMatch: match,
            prefs: prefs,
            memories: [],
            pastSessions: [],
            ownedTools: [],
            heardBriefing: true
        )
        XCTAssertTrue(briefed.contains("cook trailer") || briefed.contains("pre-cook rundown"))
        XCTAssertTrue(briefed.contains("Do NOT re-narrate"))
        XCTAssertFalse(base.contains("Do NOT re-narrate"))
    }

    func testAwaitVerbalGoTellsPollyToWaitSilently() {
        let recipe = Recipe(title: "Soup", servings: 2)
        context.insert(recipe)
        recipe.steps = [RecipeStep(index: 0, text: "Simmer.")]
        let prompt = PollyPromptBuilder.instructions(
            recipe: recipe,
            plan: CookPlan.linear(from: recipe, scale: 1),
            pantryMatch: .init(owned: [], missing: [], missingOptional: []),
            prefs: UserPrefs.current(in: context),
            memories: [],
            pastSessions: [],
            ownedTools: [],
            heardBriefing: true,
            awaitVerbalGo: true
        )
        XCTAssertTrue(prompt.contains("WAIT for the cook") || prompt.contains("Stay SILENT"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("let's cook"))
        XCTAssertFalse(prompt.contains("you speak first (once)"))
    }
}
