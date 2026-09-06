import XCTest
import SwiftData
@testable import Glutt

/// The timer contract, from both ends.
///
/// One end is `offerableTimerSeconds`: the single answer to "should this step
/// hand the cook a countdown", asked by the cooking screen and by appliance
/// occupancy. The other is the compiler, which now hands the model the timing
/// the recipe already carried instead of making it re-derive one from prose.
///
/// The bug worth keeping fixed: "sear four minutes per side" is active work,
/// arrives with a timer, and used to offer none, because the screen required
/// `kind == .passive` before it would show one.
@MainActor
final class CookPlanTimerTests: XCTestCase {

    // MARK: - Fixtures

    private func step(
        kind: CookPlan.StepKind,
        estimatedSeconds: Int? = nil,
        timerSeconds: Int? = nil
    ) -> CookPlan.PlanStep {
        CookPlan.PlanStep(
            id: "s1", index: 0, title: "Sear the chicken",
            instruction: "Sear the chicken thighs 4 minutes per side until golden.",
            kind: kind,
            estimatedSeconds: estimatedSeconds,
            timerSeconds: timerSeconds)
    }

    // MARK: - A. An authored timer is a timer, whatever the kind

    /// The regression this whole change exists for.
    func testAnActiveStepWithAnAuthoredTimerOffersIt() {
        let sear = step(kind: .active, estimatedSeconds: 480, timerSeconds: 240)
        XCTAssertEqual(sear.offerableTimerSeconds, 240,
                       "active work with an explicit timer is exactly the work a cook wants a countdown for")
    }

    func testACheckpointWithAnAuthoredTimerOffersIt() {
        let rest = step(kind: .checkpoint, timerSeconds: 120)
        XCTAssertEqual(rest.offerableTimerSeconds, 120)
    }

    /// `timerSeconds` wins over the hands-on estimate rather than being averaged
    /// with it or losing to it.
    func testTheAuthoredTimerWinsOverTheHandsOnEstimate() {
        let sear = step(kind: .passive, estimatedSeconds: 900, timerSeconds: 240)
        XCTAssertEqual(sear.offerableTimerSeconds, 240)
    }

    // MARK: - B. Zero and negative are not timers

    func testAZeroTimerIsNotATimer() {
        let bad = step(kind: .active, timerSeconds: 0)
        XCTAssertNil(bad.offerableTimerSeconds,
                     "a zero second countdown is a button that does nothing")
    }

    func testANegativeTimerIsNotATimer() {
        let bad = step(kind: .active, timerSeconds: -30)
        XCTAssertNil(bad.offerableTimerSeconds)
    }

    /// A junk timer must not shadow a genuine unattended wait sitting next to it.
    func testAZeroTimerOnAPassiveStepFallsBackToTheWait() {
        let simmer = step(kind: .passive, estimatedSeconds: 600, timerSeconds: 0)
        XCTAssertEqual(simmer.offerableTimerSeconds, 600)
    }

    func testAZeroEstimateOnAPassiveStepIsNotATimer() {
        let simmer = step(kind: .passive, estimatedSeconds: 0)
        XCTAssertNil(simmer.offerableTimerSeconds)
    }

    // MARK: - E. Nothing is invented

    /// The rule that stops every step growing a countdown: elsewhere
    /// `estimatedSeconds` is hands-on time, and counting down a cook's own
    /// working speed is noise.
    func testAnActiveStepWithOnlyHandsOnTimeOffersNoTimer() {
        let chop = step(kind: .active, estimatedSeconds: 300)
        XCTAssertNil(chop.offerableTimerSeconds,
                     "hands-on time is not an unattended wait")
    }

    func testACheckpointWithOnlyHandsOnTimeOffersNoTimer() {
        let taste = step(kind: .checkpoint, estimatedSeconds: 60)
        XCTAssertNil(taste.offerableTimerSeconds)
    }

    func testAPassiveStepWithOnlyAnEstimateOffersTheWait() {
        let prove = step(kind: .passive, estimatedSeconds: 3600)
        XCTAssertEqual(prove.offerableTimerSeconds, 3600,
                       "an unattended wait is the original reason timers exist")
    }

    func testAStepWithNoTimingAtAllOffersNothing() {
        XCTAssertNil(step(kind: .active).offerableTimerSeconds)
        XCTAssertNil(step(kind: .passive).offerableTimerSeconds)
        XCTAssertNil(step(kind: .checkpoint).offerableTimerSeconds)
    }
}

/// The compiler half: the authored duration reaches the model, carries the
/// recipe's own number, and never reaches the cook as text.
@MainActor
final class CookPlanAuthoredTimingPromptTests: XCTestCase {

    private var container: ModelContainer!
    private var tempDir: URL!
    private var originalCacheDirectory: URL!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("polly-timing-\(UUID().uuidString)", isDirectory: true)
        originalCacheDirectory = CookPlanCompiler.cacheDirectory
        CookPlanCompiler.cacheDirectory = tempDir
    }

    override func tearDownWithError() throws {
        CookPlanCompiler.cacheDirectory = originalCacheDirectory
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        container = nil
    }

    /// A dish nothing bundles, so `compile` actually reaches the model.
    private func makeRecipe(steps: [(String, Int?)]) -> Recipe {
        let recipe = Recipe(title: "Pan Seared Thighs", servings: 2, prepMinutes: 5, cookMinutes: 20)
        recipe.ingredients = [RecipeIngredient(name: "chicken thighs", quantity: 4, sortIndex: 0)]
        recipe.steps = steps.enumerated().map { offset, pair in
            RecipeStep(index: offset, text: pair.0, durationSeconds: pair.1)
        }
        container.mainContext.insert(recipe)
        return recipe
    }

    private func fixturePlan() throws -> CookPlan {
        let json = """
        {"title": "Pan Seared Thighs", "servings": 2,
         "mise": [{"name": "chicken thighs", "prep": "patted dry"}],
         "equipment": ["skillet"],
         "steps": [{"id": "s1", "index": 0, "title": "Sear",
                    "instruction": "Sear the thighs 4 minutes per side.", "kind": "active",
                    "estimatedSeconds": 480, "timerSeconds": 480, "dependsOn": [],
                    "ingredientNames": ["chicken thighs"]}]}
        """
        return try JSONDecoder().decode(CookPlan.self, from: Data(json.utf8))
    }

    /// Captures the user prompt `compile` sends, or skips when this environment
    /// has no proxy key and `compile` short-circuits to the offline fallback.
    private func capturedPrompt(for recipe: Recipe) async throws -> String {
        var captured: String?
        let plan = try fixturePlan()
        _ = await CookPlanCompiler.compile(recipe: recipe, scale: 1.0) { _, user in
            captured = user
            return plan
        }
        try XCTSkipIf(captured == nil, "LLM not configured in this environment; compile never called the model")
        return try XCTUnwrap(captured)
    }

    // MARK: - C and D. The marker carries the recipe's own number

    func testAuthoredTimingReachesTheModelWithTheRecipesOwnNumber() async throws {
        let recipe = makeRecipe(steps: [("Sear the thighs 4 minutes per side.", 480)])
        let prompt = try await capturedPrompt(for: recipe)

        XCTAssertTrue(prompt.contains("[authored timing: 480s]"),
                      "the recipe already knew the number; the model should not have to re-derive it")
    }

    /// The structured timing travels *alongside* the prose, not instead of it:
    /// the model still needs the sentence it is rewriting.
    func testTheAuthoredTimingIsAddedToTheStepTextRatherThanReplacingIt() async throws {
        let recipe = makeRecipe(steps: [("Sear the thighs 4 minutes per side.", 480)])
        let prompt = try await capturedPrompt(for: recipe)

        XCTAssertTrue(prompt.contains("Sear the thighs 4 minutes per side. [authored timing: 480s]"),
                      "prose and structured timing must both reach the model, in that order")
    }

    func testEachStepCarriesItsOwnNumber() async throws {
        let recipe = makeRecipe(steps: [
            ("Sear the thighs 4 minutes per side.", 480),
            ("Rest them for ten minutes.", 600),
        ])
        let prompt = try await capturedPrompt(for: recipe)

        XCTAssertTrue(prompt.contains("[authored timing: 480s]"))
        XCTAssertTrue(prompt.contains("[authored timing: 600s]"))
    }

    // MARK: - E. No authored timing, no marker

    func testAStepWithoutAuthoredTimingGetsNoMarker() async throws {
        let recipe = makeRecipe(steps: [("Season the thighs all over.", nil)])
        let prompt = try await capturedPrompt(for: recipe)

        XCTAssertFalse(prompt.contains("authored timing"),
                       "nothing to hand over means nothing is added")
        XCTAssertTrue(prompt.contains("Season the thighs all over."))
    }

    func testAZeroAuthoredDurationGetsNoMarker() async throws {
        let recipe = makeRecipe(steps: [("Season the thighs all over.", 0)])
        let prompt = try await capturedPrompt(for: recipe)

        XCTAssertFalse(prompt.contains("authored timing"),
                       "a zero duration is not a timing worth sending")
    }

    // MARK: - D. The marker is prompt input only

    /// The leak that would matter: the marker is built into a prompt string, so
    /// the recipe the cook owns must come back untouched.
    func testCompilingNeverWritesTheMarkerIntoTheRecipe() async throws {
        let recipe = makeRecipe(steps: [("Sear the thighs 4 minutes per side.", 480)])
        let before = recipe.sortedSteps.map(\.text)

        _ = try await capturedPrompt(for: recipe)

        let after = recipe.sortedSteps.map(\.text)
        XCTAssertEqual(before, after, "compiling must not rewrite the cook's own recipe text")
        for text in after {
            XCTAssertFalse(text.contains("authored timing"))
        }
    }

    /// The offline fallback renders `RecipeStep.text` straight onto the cooking
    /// screen, so it is the surface a leaked marker would show up on first.
    func testTheOfflineFallbackShowsNoMarker() throws {
        let recipe = makeRecipe(steps: [("Sear the thighs 4 minutes per side.", 480)])
        let fallback = CookPlan.linear(from: recipe, scale: 1.0)

        for step in fallback.steps {
            XCTAssertFalse(step.instruction.contains("authored timing"), "instruction leaked the marker")
            XCTAssertFalse(step.title.contains("authored timing"), "title leaked the marker")
            for line in step.glanceLines {
                XCTAssertFalse(line.contains("authored timing"), "glance line leaked the marker")
            }
        }
    }

    /// And the authored duration still survives into the fallback as a real
    /// timer, which is the whole point of the recipe having carried it.
    func testTheOfflineFallbackStillOffersTheAuthoredTimer() throws {
        let recipe = makeRecipe(steps: [("Sear the thighs 4 minutes per side.", 480)])
        let fallback = CookPlan.linear(from: recipe, scale: 1.0)
        let sear = try XCTUnwrap(fallback.steps.first { $0.instruction.contains("Sear the thighs") })

        XCTAssertEqual(sear.offerableTimerSeconds, 480)
    }
}
