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

    /// The same dish with Nicky's ingredient list on it, which is where the prep
    /// amounts come from.
    private func stockedGnocchiRecipe() throws -> Recipe {
        let recipe = gnocchiRecipe()
        let chef = try XCTUnwrap(ChefContent.chef(id: "kitchen-sanctuary"))
        let dish = try XCTUnwrap(
            ChefContent.dishes(for: chef).first { $0.title == recipe.title })
        recipe.ingredients = dish.ingredients.enumerated().map { index, line in
            RecipeIngredient(name: line.name, quantity: line.quantity, unit: line.unit,
                             sortIndex: index)
        }
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
        XCTAssertTrue(boil.instruction.lowercased().contains("sieve"),
                      "floating and draining are the same moment")
        XCTAssertFalse(boil.instruction.lowercased().contains("slotted"),
                       "they drain in a sieve now, and Malik does not own a slotted spoon")
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

    /// Pre-minced garlic from a tube, not cloves. It is already cut, so it
    /// takes half the time and burns sooner, and it is wet, so it spits going
    /// into hot butter. The clip still shows Nicky's slices, so the step has to
    /// say out loud that we are doing it differently.
    func testGarlicCarriesItsOwnWarning() throws {
        let garlic = try step("s7")
        XCTAssertEqual(garlic.timerSeconds, 30, "minced garlic needs half the time slices do")
        let text = garlic.instruction.lowercased()
        XCTAssertTrue(text.contains("minced garlic"))
        XCTAssertTrue(text.contains("video shows sliced garlic"),
                      "the clip shows slices, so the difference must be named")
        XCTAssertTrue(text.contains("spit"), "wet garlic in hot butter spits")
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
    /// for, or they have no idea when to ask for the next one. This is the
    /// condition itself, not the mechanic for reporting it.
    func testEveryJudgementStepSaysWhatToWaitFor() throws {
        let cue = [
            "s1": "rolling boil", "s2": "float", "s3": "skitter",
            "s4": "golden", "s5": "nutty", "s6": "crackling",
            "s7": "sweet", "s8": "glossy",
        ]
        for (id, word) in cue {
            let text = try step(id).instruction.lowercased()
            XCTAssertTrue(
                text.contains(word),
                "step \(id) never says what the cook is waiting for (\(word))")
        }
    }

    /// Teach the wake word, then stop saying it.
    ///
    /// Every step used to end "Say Chef when it is golden", which read as though
    /// "Chef" were itself the report. It is not: it opens the mic, and the cook
    /// still has to say the thing afterwards. Worse, eight steps of the same
    /// trailing sentence is noise to anyone who has cooked with the app once.
    /// So the opening two steps name both halves and the rest carry the
    /// condition alone.
    func testTheWakeWordIsTaughtOnceAndNotRepeatedEveryStep() throws {
        for id in ["s1", "s2"] {
            let text = try step(id).instruction.lowercased()
            XCTAssertTrue(text.contains("say chef"), "step \(id) should teach the wake word")
            XCTAssertTrue(
                text.contains("tell me"),
                "step \(id) must show that Chef opens the mic and the report is separate")
        }
        for id in ["s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10"] {
            let text = try step(id).instruction.lowercased()
            XCTAssertFalse(
                text.contains("say chef"),
                "step \(id) repeats the mechanic the cook already learned")
            // "tell me" with no "say Chef" beside it is the other failure: it
            // promises an open mic that closed when she stopped talking.
            XCTAssertFalse(
                text.contains("tell me"),
                "step \(id) implies the mic is open when it is not")
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

    /// The bug the test below could not see.
    ///
    /// `CookPlanCompiler.compile` hands a bundled plan to `ensuringLeadingPrep()`
    /// with no ingredient list, so `withAmounts` returns early and every amount
    /// it would have filled in is dropped. The test below passes the ingredients
    /// itself and stayed green while the real Prep step read "pick the fresh sage
    /// leaves" with no number in it. The plan's own mise carries the amounts now,
    /// which is what the `withAmounts` doc comment always intended for a
    /// hand-written plan.
    func testPrepAmountsSurviveTheCallTheCompilerActuallyMakes() throws {
        let prepared = try plan().ensuringLeadingPrep()
        let prep = try XCTUnwrap(prepared.steps.first { $0.id == CookPlan.prepStepID })
        XCTAssertTrue(prep.instruction.contains("20"), "twenty sage leaves, with no help")
        XCTAssertTrue(prep.instruction.contains("1 lemon"))
    }

    /// Everything else in this recipe names an amount, so the two lines that did
    /// not read as though they were the ones you were supposed to know already.
    func testEveryStepThatUsesAnIngredientSaysHowMuch() throws {
        let boil = try step("s2").instruction
        XCTAssertTrue(boil.contains("500g"), "\"drop the gnocchi in\" never said how many")
        XCTAssertTrue(try step("s4").instruction.contains("500g"))
        XCTAssertTrue(try step("s6").instruction.contains("20 sage leaves"))
        XCTAssertTrue(try step("s5").instruction.contains("75g"))
        XCTAssertTrue(try step("s3").instruction.contains("2 tbsp"))
    }

    /// "Pick the fresh sage leaves" and nothing else made the cook stop and ask
    /// how many, which is the one question the recipe already answers. The prep
    /// step and its checklist now carry the amount.
    func testPrepSaysHowMuchOfEachThing() throws {
        let recipe = try stockedGnocchiRecipe()
        let plan = try XCTUnwrap(CookPlanCompiler.bundledPlan(for: recipe))
            .ensuringLeadingPrep(ingredients: recipe.ingredients)
        let prep = try XCTUnwrap(plan.steps.first { $0.id == CookPlan.prepStepID })

        XCTAssertTrue(prep.instruction.contains("20"), "twenty sage leaves, not \"the sage\"")
        XCTAssertFalse(prep.instruction.lowercased().contains("the fresh sage leaves"),
                       "the bare name is what sent them looking")

        // The tappable rows are built from the same phrase and must agree.
        let rows = StepActionChecklist.items(for: prep, plan: plan).map(\.text)
        XCTAssertTrue(rows.contains { $0.contains("20") && $0.localizedCaseInsensitiveContains("sage") },
                      "checklist rows: \(rows)")
    }

    /// A pot boils and a pan fries. They were both "pan" once, which reads as one
    /// tool doing two jobs at two temperatures. The sieve replaced the slotted
    /// spoon outright, and bowl and spatula were being used by the steps without
    /// ever being pulled out.
    func testTheToolListIsWhatTheCookActuallyNeeds() throws {
        let gear = try plan().equipment.map { $0.lowercased() }

        XCTAssertTrue(gear.contains { $0.contains("pot") }, "water boils in a pot")
        XCTAssertTrue(gear.contains { $0.contains("frying pan") }, "and the gnocchi fry in a pan")
        XCTAssertTrue(gear.contains { $0.contains("sieve") })
        XCTAssertTrue(gear.contains { $0.contains("bowl") }, "the gnocchi rest in it twice")
        XCTAssertTrue(gear.contains { $0.contains("spatula") || $0.contains("wooden spoon") })
        XCTAssertFalse(gear.contains { $0.contains("slotted") })
        // Knife and board earn their place on one job only, halving the lemon.
        XCTAssertTrue(gear.contains { $0.contains("knife") })
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
        // Garlic comes pre-minced from a tube, so there is nothing to prep. It
        // used to be sliced here, and leaving it in sent the cook to the board
        // for an ingredient that is ready in the fridge.
        XCTAssertFalse(text.contains("garlic"), "pre-minced garlic needs no board work")
        XCTAssertTrue(text.contains("zest"))
        XCTAssertTrue(text.contains("halve"), "the lemon is halved here, not hunted for at s9")
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
        // Ours, not Nicky's: she slices 2 cloves, we squeeze 2 tsp from a tube.
        XCTAssertEqual(amount("Minced garlic")?.0, 2)
        XCTAssertEqual(amount("Minced garlic")?.1, "tsp")
    }
}
