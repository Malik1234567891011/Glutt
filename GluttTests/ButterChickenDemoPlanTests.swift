import XCTest
import SwiftData
@testable import Glutt

/// Joshua Weissman's butter chicken, the second dish to ship with a hand
/// written cook plan instead of a compiled one.
///
/// Same reasoning as `GnocchiDemoPlanTests`: the value of a bundled plan is that
/// Chef says a particular thing at a particular moment, and a reworded step is a
/// silent regression that only shows up mid cook. So the moments this dish turns
/// on are pinned here, by the words a cook would actually be listening for.
@MainActor
final class ButterChickenDemoPlanTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws { container = nil }

    private func butterChickenRecipe() -> Recipe {
        let recipe = Recipe(title: "Butter Chicken", sourcePlatform: .manual)
        container.mainContext.insert(recipe)
        return recipe
    }

    private func dish() throws -> ChefContent.Dish {
        let chef = try XCTUnwrap(ChefContent.chef(id: "joshua-weissman"))
        return try XCTUnwrap(
            ChefContent.dishes(for: chef).first { $0.title == "Butter Chicken" })
    }

    private func plan() throws -> CookPlan {
        try XCTUnwrap(CookPlanCompiler.bundledPlan(for: butterChickenRecipe()),
                      "the bundled plan must be in the app bundle")
    }

    /// Exactly what `CookPlanCompiler.compile` does with a bundled plan: no
    /// ingredients passed in, no scale. Anything the Prep step is supposed to
    /// say has to survive this call, not just the one the tests find convenient.
    private func preparedPlan() throws -> CookPlan {
        try plan().ensuringLeadingPrep()
    }

    private func step(_ id: String) throws -> CookPlan.PlanStep {
        try XCTUnwrap(plan().steps.first { $0.id == id }, "missing step \(id)")
    }

    // MARK: The plan ships and is used

    func testTheBundledPlanLoads() throws {
        let plan = try plan()
        XCTAssertEqual(plan.title, "Butter Chicken")
        XCTAssertEqual(plan.servings, 4)
        XCTAssertEqual(plan.steps.filter { !CookPlan.isSetupStep($0) }.count, 11)
    }

    func testCompileUsesTheBundledPlanAndNeverCallsTheModel() async throws {
        let recipe = butterChickenRecipe()
        var calls = 0
        let plan = await CookPlanCompiler.compile(recipe: recipe, scale: 1.0) { _, _ in
            calls += 1
            throw NSError(domain: "should not be called", code: 1)
        }
        XCTAssertEqual(calls, 0, "a bundled plan must not consult the model")
        XCTAssertFalse(plan.isFallback, "and must not be mistaken for the offline fallback")
        XCTAssertEqual(plan.title, "Butter Chicken")
    }

    // MARK: The cues the dish turns on

    /// The marinade is the one step that can be done the night before, so the
    /// step has to offer that rather than hold the cook for thirty minutes.
    func testTheMarinadeOffersTheHeadStart() throws {
        let marinade = try step("s1")
        let text = marinade.instruction.lowercased()
        XCTAssertTrue(text.contains("30 minutes"))
        XCTAssertTrue(text.contains("overnight"))
        XCTAssertTrue(text.contains("straight to the pan"),
                      "someone who marinated last night must be able to skip ahead")
        XCTAssertEqual(marinade.timerSeconds, 1800)
        let look = try XCTUnwrap(marinade.visualCheck).lowercased()
        XCTAssertTrue(look.contains("no bare chicken"), "coated means no bare patches")
    }

    /// The save. Yogurt chicken into a pan that is merely warm steams instead of
    /// searing, and grey chicken never recovers, so the temperature gets its own
    /// checkpoint with a test the cook can actually run.
    func testThePanIsTestedBeforeAnyChickenGoesIn() throws {
        let heat = try step("s3")
        XCTAssertEqual(heat.kind, .checkpoint, "a judgement, not a timer")
        XCTAssertTrue(heat.instruction.lowercased().contains("tilt the pan"),
                      "the cook needs an action, not just an adjective")
        let look = try XCTUnwrap(heat.visualCheck).lowercased()
        XCTAssertTrue(look.contains("ripple"), "what ready oil does")
        XCTAssertTrue(look.contains("sluggish"), "and what it does when it is not ready")
        XCTAssertTrue(look.contains("smoke"), "and when it has gone too far")
        let recovery = try XCTUnwrap(heat.recovery).lowercased()
        XCTAssertTrue(recovery.contains("steams"))
        XCTAssertTrue(recovery.contains("grey"), "the failure has to be named out loud")
    }

    /// Crowding the pan is the single most common way this dish goes wrong, and
    /// the fix has to be given before it happens, not after.
    func testTheSearNamesTheGapAndTheBatches() throws {
        let sear = try step("s4")
        XCTAssertEqual(sear.kind, .checkpoint)
        let text = sear.instruction.lowercased()
        XCTAssertTrue(text.contains("gap around every one"))
        XCTAssertTrue(text.contains("batches"))
        let look = try XCTUnwrap(sear.visualCheck).lowercased()
        XCTAssertTrue(look.contains("still raw"),
                      "coming out raw is correct here and must not read as an error")
        // The visual check is also the brief for a look taken mid step, so it has
        // to describe the pan while it is cooking and not only at the end. The
        // gaps are the thing worth catching, and they are gone by the end state.
        XCTAssertTrue(look.contains("gaps around every piece"),
                      "an unprompted look mid sear had nothing to judge")
        XCTAssertTrue(try XCTUnwrap(sear.recovery).lowercased().contains("crowded"))
    }

    /// The fond is free flavour and invisible unless someone points at it.
    func testTheFondIsNamedAsFlavourRatherThanMess() throws {
        let aromatics = try step("s5")
        let text = aromatics.instruction.lowercased()
        XCTAssertTrue(text.contains("scrape the base"))
        XCTAssertTrue(text.contains("splash of water"), "how to lift what will not come")
        XCTAssertTrue(try XCTUnwrap(aromatics.visualCheck).lowercased().contains("crusted to clean"))
    }

    /// Ground spices burn in about the time it takes to fetch the tomatoes,
    /// which is why the step tells you to fetch them first.
    func testTheSpiceStepWarnsBeforeTheBurnRatherThanAfter() throws {
        let spices = try step("s6")
        XCTAssertEqual(spices.timerSeconds, 60, "one minute is the whole window")
        XCTAssertTrue(spices.instruction.lowercased().contains("open the tomatoes before"),
                      "the escape route has to be in reach before the spices go in")
        let recovery = try XCTUnwrap(spices.recovery).lowercased()
        XCTAssertTrue(recovery.contains("ash") || recovery.contains("bitter"))
        XCTAssertTrue(recovery.contains("tomatoes in immediately"),
                      "and the recovery is an action, not a warning")
    }

    /// "Reduced by 30%" is meaningless in a pan. A spoon track is not.
    func testTheReductionIsDescribedAsSomethingYouCanSee() throws {
        let reduce = try step("s7")
        XCTAssertEqual(reduce.kind, .checkpoint)
        let look = try XCTUnwrap(reduce.visualCheck).lowercased()
        XCTAssertTrue(look.contains("a third"))
        XCTAssertTrue(look.contains("track"), "the spoon test, not a percentage")
    }

    /// Cream boiled hard splits, and this is the only step where that can happen.
    func testTheCreamStepNamesSplittingAsTheFailure() throws {
        let cream = try step("s9")
        XCTAssertEqual(cream.kind, .checkpoint)
        XCTAssertTrue(try XCTUnwrap(cream.visualCheck).lowercased().contains("white streaks"))
        let recovery = try XCTUnwrap(cream.recovery).lowercased()
        XCTAssertTrue(recovery.contains("splits"))
        XCTAssertTrue(recovery.contains("grainy"))
    }

    /// The butter is what the dish is named after, and it only works off the heat.
    func testTheButterGoesInOffTheHeat() throws {
        let butter = try step("s10")
        let text = butter.instruction.lowercased()
        XCTAssertTrue(text.contains("heat off first"))
        XCTAssertTrue(text.contains("without stopping"), "stirring is what emulsifies it")
        XCTAssertTrue(text.contains("taste"), "and the seasoning happens here, not earlier")
        XCTAssertTrue(try XCTUnwrap(butter.visualCheck).lowercased().contains("glossy"))
    }

    // MARK: Shape

    /// Rice takes twenty minutes and the curry takes twenty five, so the rice
    /// goes on before the pan comes up rather than after the sauce is finished.
    func testTheRiceGoesOnBeforeTheSear() throws {
        let cookSteps = try plan().steps.filter { !CookPlan.isSetupStep($0) }
        let riceIndex = try XCTUnwrap(cookSteps.firstIndex { $0.id == "s2" })
        let searIndex = try XCTUnwrap(cookSteps.firstIndex { $0.id == "s4" })
        XCTAssertLessThan(riceIndex, searIndex)
        XCTAssertTrue(try step("s2").instruction.lowercased().contains("looks after itself"),
                      "and the reason it can go on now has to be said")
    }

    /// Every step that ends on a judgement says what the cook is waiting for, in
    /// the instruction itself, not only in the visual check.
    func testEveryJudgementStepSaysWhatToWaitFor() throws {
        let cue = [
            "s1": "coated", "s3": "ripples", "s4": "brown", "s5": "soft",
            "s6": "glossy", "s7": "a third", "s8": "no pink", "s9": "even orange",
            "s10": "glossy",
        ]
        for (id, word) in cue {
            let text = try step(id).instruction.lowercased()
            XCTAssertTrue(
                text.contains(word),
                "step \(id) never says what the cook is waiting for (\(word))")
        }
    }

    /// Teach the wake word twice, then stop. Same rule the gnocchi plan follows:
    /// "Chef" opens the mic and the report is a separate sentence, and repeating
    /// that on all eleven steps is noise.
    func testTheWakeWordIsTaughtOnceAndNotRepeatedEveryStep() throws {
        for id in ["s1", "s2"] {
            let text = try step(id).instruction.lowercased()
            XCTAssertTrue(text.contains("say chef"), "step \(id) should teach the wake word")
            XCTAssertTrue(text.contains("tell me"),
                          "step \(id) must show that Chef opens the mic and the report is separate")
        }
        for id in ["s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11"] {
            let text = try step(id).instruction.lowercased()
            XCTAssertFalse(text.contains("say chef"),
                           "step \(id) repeats the mechanic the cook already learned")
            XCTAssertFalse(text.contains("tell me"),
                           "step \(id) implies the mic is open when it is not")
        }
    }

    func testThePlanHasNoSchedulingProblems() throws {
        XCTAssertTrue(try plan().schedulingIssues.isEmpty)
    }

    // MARK: Setup

    func testTheToolListIsWhatTheCookActuallyNeeds() throws {
        let gear = try plan().equipment.map { $0.lowercased() }
        XCTAssertTrue(gear.contains { $0.contains("deep pan") || $0.contains("braiser") })
        XCTAssertTrue(gear.contains { $0.contains("lid") }, "the chicken finishes covered")
        XCTAssertTrue(gear.contains { $0.contains("saucepan") }, "the rice cooks in its own pan")
        XCTAssertTrue(gear.contains { $0.contains("bowl") }, "the marinade lives in it")
        XCTAssertTrue(gear.contains { $0.contains("tray") },
                      "the seared chicken has to go somewhere that is not the pan")
        XCTAssertTrue(gear.contains { $0.contains("tongs") })
    }

    func testToolsAndPrepAreBothPresent() throws {
        let prepared = try preparedPlan()
        XCTAssertTrue(prepared.hasLeadingPrep)
        XCTAssertEqual(prepared.leadingSetupCount, 2)
        let prep = try XCTUnwrap(prepared.steps.first { $0.id == CookPlan.prepStepID })
        let text = prep.instruction.lowercased()
        XCTAssertTrue(text.contains("chicken thighs"), "all the knife work happens before heat")
        XCTAssertTrue(text.contains("onion"))
        XCTAssertTrue(text.contains("ginger"))
        XCTAssertTrue(text.contains("garlic"))
        XCTAssertTrue(text.contains("cilantro"))
        // Spices and oil are measured at the pan, never staged on the board.
        XCTAssertFalse(text.contains("turmeric"))
        XCTAssertFalse(text.contains("oil"))
    }

    /// The amounts have to survive the exact call the compiler makes, which
    /// passes no ingredient list. That is why they are written into the plan's
    /// own mise rather than left to be filled in from the recipe.
    func testPrepSaysHowMuchOfEachThingWithNoIngredientListToLeanOn() throws {
        let prepared = try preparedPlan()
        let prep = try XCTUnwrap(prepared.steps.first { $0.id == CookPlan.prepStepID })

        XCTAssertTrue(prep.instruction.contains("680 g"), "not just \"the chicken thighs\"")
        XCTAssertTrue(prep.instruction.contains("6 cloves"))
        XCTAssertTrue(prep.instruction.contains("5 cm"), "a knob of ginger is not a measurement")

        let rows = StepActionChecklist.items(for: prep, plan: prepared).map(\.text)
        XCTAssertTrue(rows.contains { $0.contains("680 g") && $0.localizedCaseInsensitiveContains("chicken") },
                      "checklist rows: \(rows)")
        XCTAssertTrue(rows.contains { $0.localizedCaseInsensitiveContains("cilantro") },
                      "checklist rows: \(rows)")
    }

    /// Chef takes looks the cook never asked for, and the step's own visual check
    /// is the entire brief she gets. A check that only describes the finish line
    /// leaves a look taken two minutes in with nothing to say, which is how an
    /// unprompted look turns into narration.
    func testEveryJudgementStepDescribesItselfWhileItIsHappening() throws {
        let inProgress = [
            "s1": "come out white", "s3": "when you tilt", "s4": "the whole time they cook",
            "s5": "goes from", "s6": "they go in as", "s7": "starts loose",
            "s8": "pushed down under", "s9": "in about a minute of stirring",
            "s10": "melts in",
        ]
        for (id, phrase) in inProgress {
            let step = try step(id)
            XCTAssertTrue(ChefGlance.canJudge(step), "step \(id) can never be looked at")
            XCTAssertTrue(
                try XCTUnwrap(step.visualCheck).lowercased().contains(phrase),
                "step \(id) only describes its finish line, so a look mid step sees nothing")
        }
        // And the two that cannot be judged on camera must stay off the clock.
        XCTAssertFalse(ChefGlance.canJudge(try step("s2")), "Rice on has nothing to look at")
        XCTAssertFalse(ChefGlance.canJudge(try step("s11")), "plating is not a judgement")
    }

    // MARK: Clips

    /// Ten of the eleven cook steps name the clip they play. Rice is the one
    /// that does not, because Joshua never cooks rice on camera, and a step with
    /// no clip is correct where borrowing someone else's is not.
    func testEveryCookStepButRicePinsItsOwnClip() throws {
        let cookSteps = try plan().steps.filter { !CookPlan.isSetupStep($0) }
        let pinned = cookSteps.compactMap(\.clipSegmentID)
        XCTAssertEqual(pinned.count, 10)
        XCTAssertEqual(Set(pinned).count, pinned.count, "a segment is pinned twice")
        XCTAssertNil(try step("s2").clipSegmentID,
                     "there is no honest shot of rice going on, so Rice on plays nothing")

        // The ids the media worker fixture actually publishes. A rename on
        // either side has to fail here rather than in front of a cook.
        XCTAssertEqual(pinned, [
            "seg-bc-marinade",
            "seg-bc-oil",
            "seg-bc-sear",
            "seg-bc-aromatics",
            "seg-bc-spices",
            "seg-bc-tomatoes",
            "seg-bc-chicken-back",
            "seg-bc-cream",
            "seg-bc-butter",
            "seg-bc-serve",
        ])
    }

    // MARK: The dish itself

    func testTheDishIsBundledAndClipsAreAllowed() throws {
        let dish = try dish()
        XCTAssertEqual(dish.sourceURL, "https://www.youtube.com/watch?v=hDjK5C2aoSs",
                       "the clip pipeline is keyed on this URL")
        XCTAssertEqual(dish.servings, 4)
        XCTAssertEqual(dish.imageAsset, "chefButterChicken")

        let recipe = butterChickenRecipe()
        recipe.tags = ["Signature", "chef:joshua-weissman"]
        XCTAssertTrue(recipe.isCuratedRecipe)
        XCTAssertTrue(MediaClipConfig.clipsAllowed(for: recipe),
                      "clips only run for curated dishes, which is why this ships as chef content")
    }

    func testItIsJoshuasFirstDish() throws {
        let chef = try XCTUnwrap(ChefContent.chef(id: "joshua-weissman"))
        XCTAssertEqual(ChefContent.dishes(for: chef).first?.title, "Butter Chicken",
                       "the dish with the bundled plan and the clips leads his page")
    }

    /// Joshua's quantities, from joshuaweissman.com, not rounded to ours.
    func testQuantitiesMatchTheSource() throws {
        let dish = try dish()
        func amount(_ name: String) -> (Double?, String?)? {
            dish.ingredients.first { $0.name == name }.map { ($0.quantity, $0.unit) }
        }
        XCTAssertEqual(amount("Chicken thighs")?.0, 680)
        XCTAssertEqual(amount("Full fat yogurt")?.0, 240)
        XCTAssertEqual(amount("Crushed tomatoes")?.0, 397, "a 14 oz tin, not a rounded 400g one")
        XCTAssertEqual(amount("Heavy cream")?.0, 240)
        XCTAssertEqual(amount("Unsalted butter")?.0, 28)
        // Garam masala is the one line that is not a single measurement in the
        // source: a tablespoon in the marinade and another in the curry. The
        // shopping line carries the total, and the steps say where each goes.
        XCTAssertEqual(amount("Garam masala")?.0, 2)
        XCTAssertEqual(amount("Garam masala")?.1, "tbsp")
        XCTAssertEqual(amount("Vegetable oil")?.0, 4, "2 tbsp for the sear and 2 for the onions")
    }

    /// The recipe steps carry the same cues as the plan, so a cook who never
    /// opens Polly still gets them, and so a recompile cannot quietly lose them.
    func testTheRecipeStepsCarryTheCuesToo() throws {
        let steps = try dish().steps.map { $0.text.lowercased() }
        XCTAssertEqual(steps.count, 11)
        XCTAssertTrue(steps.contains { $0.contains("ripple") }, "the pan test")
        XCTAssertTrue(steps.contains { $0.contains("gap around every piece") }, "the sear")
        XCTAssertTrue(steps.contains { $0.contains("bitter") }, "the spices")
        XCTAssertTrue(steps.contains { $0.contains("splits") }, "the cream")
        XCTAssertTrue(steps.contains { $0.contains("glossy") }, "the butter")
    }
}
