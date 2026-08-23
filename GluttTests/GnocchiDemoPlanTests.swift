import XCTest
import SwiftData
@testable import Glutt

/// The live-demo dish. These are deliberately specific, because the demo is
/// built on Chef saying particular things at particular moments and a silent
/// regression here would only show up in front of an audience.
@MainActor
final class GnocchiDemoPlanTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws { container = nil }

    private func gnocchiRecipe() -> Recipe {
        let recipe = Recipe(title: "Gnocchi with Brown Butter and Sage", sourcePlatform: .manual)
        container.mainContext.insert(recipe)
        return recipe
    }

    private func plan() throws -> CookPlan {
        try XCTUnwrap(CookPlanCompiler.bundledPlan(for: gnocchiRecipe()),
                      "the bundled plan must be in the app bundle")
    }

    // MARK: The plan ships and is used

    func testTheBundledPlanLoads() throws {
        let plan = try plan()
        XCTAssertEqual(plan.title, "Gnocchi with Brown Butter and Sage")
        XCTAssertEqual(plan.servings, 4)
        XCTAssertFalse(plan.steps.isEmpty)
    }

    /// The whole point: no LLM call, no cache, no network.
    func testCompileUsesTheBundledPlanAndNeverCallsTheModel() async throws {
        let recipe = gnocchiRecipe()
        var calls = 0
        let plan = await CookPlanCompiler.compile(recipe: recipe, scale: 1.0) { _, _ in
            calls += 1
            throw NSError(domain: "should not be called", code: 1)
        }
        XCTAssertEqual(calls, 0, "a bundled plan must not consult the model")
        XCTAssertFalse(plan.isFallback, "and must not be mistaken for the offline fallback")
        XCTAssertEqual(plan.title, "Gnocchi with Brown Butter and Sage")
    }

    // MARK: The cues the demo turns on

    private func step(_ id: String) throws -> CookPlan.PlanStep {
        try XCTUnwrap(plan().steps.first { $0.id == id }, "missing step \(id)")
    }

    /// "Does the chef call us out when the gnocchi is floating?"
    ///
    /// Boiling and lifting out are one step. They were two, and that asked the
    /// cook to watch them float, then stand there waiting to be told to fish
    /// them out of the water they are going gluey in.
    func testFloatingIsTheDonenessCue() throws {
        let boil = try step("s2")
        XCTAssertTrue(boil.instruction.lowercased().contains("float"))
        XCTAssertTrue(boil.instruction.lowercased().contains("slotted spoon"),
                      "floating and lifting out are the same moment")
        XCTAssertTrue(boil.instruction.lowercased().contains("do not wait for me"))
        let look = try XCTUnwrap(boil.visualCheck).lowercased()
        XCTAssertTrue(look.contains("float") || look.contains("bob"))
        XCTAssertTrue(look.contains("gluey"), "and why leaving them matters")
        XCTAssertEqual(boil.kind, .checkpoint, "a judgement, not a timer")
    }

    /// "Does he tell us to test the pan with water first, and what it should
    /// look like at the right temperature?"
    func testTheWaterTestIsItsOwnStepWithAVisualCue() throws {
        let test = try step("s3")
        XCTAssertTrue(test.instruction.lowercased().contains("water"))
        let look = try XCTUnwrap(test.visualCheck).lowercased()
        XCTAssertTrue(look.contains("skitter") || look.contains("bead"),
                      "what the droplet does at the right temperature")
        XCTAssertTrue(look.contains("too hot"), "and what too hot looks like")
        let recovery = try XCTUnwrap(test.recovery).lowercased()
        XCTAssertTrue(recovery.contains("off the heat"))
        XCTAssertEqual(test.kind, .checkpoint)
    }

    /// Browned is the goal and burnt is the failure, roughly fifteen seconds
    /// apart, so both have to be described.
    func testBrownButterDescribesBothTheTargetAndTheFailure() throws {
        let butter = try step("s5")
        let look = try XCTUnwrap(butter.visualCheck).lowercased()
        XCTAssertTrue(look.contains("foam"))
        XCTAssertTrue(look.contains("hazelnut") || look.contains("nutty"))
        let recovery = try XCTUnwrap(butter.recovery).lowercased()
        XCTAssertTrue(recovery.contains("burnt"))
        XCTAssertTrue(recovery.contains("start the butter again"),
                      "burnt butter cannot be rescued and she must say so")
        XCTAssertEqual(butter.kind, .checkpoint)
    }

    func testGarlicCarriesItsOwnWarning() throws {
        let garlic = try step("s7")
        XCTAssertEqual(garlic.timerSeconds, 60)
        XCTAssertTrue(try XCTUnwrap(garlic.recovery).lowercased().contains("bitter"))
    }

    func testLemonGoesInOffTheHeat() throws {
        XCTAssertTrue(try step("s9").instruction.lowercased().contains("off the heat"))
    }

    // MARK: Shape

    /// The water goes on before anything else, because it is the slowest thing
    /// in a fifteen minute recipe.
    func testTheWaterGoesOnFirst() throws {
        let cookSteps = try plan().steps.filter { !CookPlan.isSetupStep($0) }
        XCTAssertEqual(cookSteps.first?.id, "s1")
        XCTAssertTrue(try XCTUnwrap(cookSteps.first).instruction.lowercased().contains("boil"))
    }

    /// Every step that ends on a judgement has to say what the cook is waiting
    /// for, or they have no idea when to ask for the next one.
    func testEveryJudgementStepSaysWhenToMoveOn() throws {
        for id in ["s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8"] {
            let text = try step(id).instruction.lowercased()
            XCTAssertTrue(
                text.contains("tell me") || text.contains("do not wait for me"),
                "step \(id) never tells the cook when to move on")
        }
    }

    /// The pan gets tested twice, and the second one is the one that saves the
    /// butter: the pan you just fried gnocchi in is too hot for it.
    func testThePanIsRetestedBeforeTheButter() throws {
        let butter = try step("s5").instruction.lowercased()
        XCTAssertTrue(butter.contains("down to medium"), "the target heat is restated")
        XCTAssertTrue(butter.contains("test it again"))
        XCTAssertTrue(butter.contains("too hot for butter"), "and why")
    }

    /// The scheduling detector must be happy with a plan we hand-wrote.
    func testThePlanHasNoSchedulingProblems() throws {
        XCTAssertTrue(try plan().schedulingIssues.isEmpty)
    }

    /// Setup rows survive `ensuringLeadingPrep`, and the board work is real.
    func testToolsAndPrepAreBothPresent() throws {
        let prepared = try plan().ensuringLeadingPrep()
        XCTAssertTrue(prepared.hasLeadingPrep)
        XCTAssertEqual(prepared.leadingSetupCount, 2)
        let prep = try XCTUnwrap(prepared.steps.first { $0.id == CookPlan.prepStepID })
        let text = prep.instruction.lowercased()
        XCTAssertTrue(text.contains("garlic"))
        XCTAssertTrue(text.contains("zest"))
        // Sage was silently dropped here once: `isSeasoningOrPourable` reads a
        // bare "sage" as the dried jar, and only "fresh ..." is exempt. Picking
        // twenty leaves is very much board work.
        XCTAssertTrue(text.contains("sage"), "picking the sage must survive boardWorkOnly")
        XCTAssertFalse(text.contains("cut to size"))
    }

    // MARK: The dish itself

    func testTheDishIsBundledAndClipsAreAllowed() throws {
        let chef = try XCTUnwrap(ChefContent.chef(id: "kitchen-sanctuary"))
        let dish = try XCTUnwrap(
            ChefContent.dishes(for: chef).first { $0.title == "Gnocchi with Brown Butter and Sage" })
        XCTAssertEqual(dish.sourceURL, "https://www.youtube.com/watch?v=3sUJwjvmzk8",
                       "the clip pipeline is keyed on this URL")
        XCTAssertEqual(dish.servings, 4)

        let recipe = gnocchiRecipe()
        recipe.tags = ["Signature", "chef:kitchen-sanctuary"]
        XCTAssertTrue(recipe.isCuratedRecipe)
        XCTAssertTrue(MediaClipConfig.clipsAllowed(for: recipe),
                      "clips only run for curated dishes, which is why this ships as chef content")
    }

    /// Nicky's quantities, not ours.
    func testQuantitiesMatchTheSource() throws {
        let chef = try XCTUnwrap(ChefContent.chef(id: "kitchen-sanctuary"))
        let dish = try XCTUnwrap(ChefContent.dishes(for: chef).first)
        func amount(_ name: String) -> (Double?, String?)? {
            dish.ingredients.first { $0.name == name }.map { ($0.quantity, $0.unit) }
        }
        XCTAssertEqual(amount("Fresh gnocchi")?.0, 500)
        XCTAssertEqual(amount("Fresh gnocchi")?.1, "g")
        XCTAssertEqual(amount("Unsalted butter")?.0, 75)
        XCTAssertEqual(amount("Fresh sage leaves")?.0, 20)
        XCTAssertEqual(amount("Garlic")?.0, 2)
    }
}
