import XCTest
import SwiftData
@testable import Glutt

/// Advancing a judgement step without looking at it.
///
/// Chef was told to look before agreeing and stopped doing it: "the water is at
/// a rolling boil" came back as `mark_step_done` with no frame requested and
/// nothing said about what she saw. A cook wearing streaming glasses cannot tell
/// that apart from an assistant that never looks, so the rule stopped being a
/// prompt and became a tool refusal.
@MainActor
final class PollyToolRegistryLookTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self, PantryItem.self,
                         UserPrefs.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    override func tearDownWithError() throws { container = nil }

    private func makeRegistry(seesContinuously: Bool) -> PollyToolRegistry {
        let context = container.mainContext
        let recipe = Recipe(title: "Gnocchi", sourcePlatform: .manual)
        context.insert(recipe)
        let prefs = UserPrefs()
        context.insert(prefs)
        let plan = CookPlan(
            title: "Gnocchi",
            servings: 4,
            steps: [
                CookPlan.PlanStep(
                    id: "s1", index: 0, title: "Water on",
                    instruction: "Salt it well and put it on high.", kind: .active,
                    visualCheck: "Big bubbles breaking across the whole surface.",
                    recovery: "Give it another minute."),
                CookPlan.PlanStep(
                    id: "s2", index: 1, title: "Serve",
                    instruction: "Into bowls.", kind: .active),
            ])
        let registry = PollyToolRegistry(
            plan: plan, recipe: recipe, pantry: [], prefs: prefs,
            timers: TimerManager(), context: context)
        registry.seesContinuously = seesContinuously
        return registry
    }

    /// The refusal itself, and the fact that it says what to do about it.
    func testAJudgementStepWillNotCloseUnseen() async {
        let registry = makeRegistry(seesContinuously: true)

        let refused = await registry.handle(name: "mark_step_done", argumentsJSON: "{}")

        XCTAssertTrue(refused.contains("look_first"), refused)
        XCTAssertTrue(refused.contains("request_camera_frame"),
                      "the refusal has to name the way out of itself")
        XCTAssertTrue(refused.contains("Big bubbles"), "and hand her the step's own cue")
        XCTAssertEqual(registry.state.stepIndex, 0, "and it must not have advanced")
    }

    /// It refuses once. A cook who says "it's fine, move on" gets to move on,
    /// they just get one honest look asked for first.
    func testItRefusesOnlyOnceSoNobodyIsStranded() async {
        let registry = makeRegistry(seesContinuously: true)

        _ = await registry.handle(name: "mark_step_done", argumentsJSON: "{}")
        _ = await registry.handle(name: "mark_step_done", argumentsJSON: "{}")

        XCTAssertEqual(registry.state.stepIndex, 1, "the second attempt goes through")
    }

    /// Having actually looked is what clears it, not having been refused.
    func testLookingClearsIt() async {
        let registry = makeRegistry(seesContinuously: true)
        registry.onRequestFrame = { _ in PollyFrameOutcome(captured: true, source: "meta_glasses") }

        _ = await registry.handle(name: "request_camera_frame", argumentsJSON: "{}")
        let done = await registry.handle(name: "mark_step_done", argumentsJSON: "{}")

        XCTAssertFalse(done.contains("look_first"), done)
        XCTAssertEqual(registry.state.stepIndex, 1)
    }

    /// Without glasses a look costs the cook a tap and a hand, so demanding one
    /// before every step would be the phone wording all over again.
    func testNoGlassesMeansNoDemand() async {
        let registry = makeRegistry(seesContinuously: false)

        let done = await registry.handle(name: "mark_step_done", argumentsJSON: "{}")

        XCTAssertFalse(done.contains("look_first"), done)
        XCTAssertEqual(registry.state.stepIndex, 1)
    }
}
