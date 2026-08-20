import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class CookPlanTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }
    override func tearDownWithError() throws { container = nil; try super.tearDownWithError() }

    // MARK: - Decoding: full compiler contract

    private let fullJSON = """
    {
      "title": "Creamy Lemon Chicken",
      "servings": 4,
      "mise": [
        { "name": "chicken thighs", "prep": "pat dry, season both sides" },
        { "name": "garlic", "prep": "mince" }
      ],
      "equipment": ["large skillet", "tongs"],
      "steps": [
        {
          "id": "s1",
          "index": 0,
          "title": "Sear the chicken",
          "instruction": "Sear the chicken thighs 4 minutes per side until golden.",
          "kind": "active",
          "estimatedSeconds": 480,
          "timerSeconds": 240,
          "dependsOn": [],
          "visualCheck": null,
          "recovery": null,
          "ingredientNames": ["chicken thighs"]
        },
        {
          "id": "s2",
          "index": 1,
          "title": "Check the browning",
          "instruction": "Flip and confirm a deep golden crust before adding the garlic.",
          "kind": "checkpoint",
          "estimatedSeconds": 60,
          "timerSeconds": null,
          "dependsOn": ["s1"],
          "visualCheck": "Crust should be deep golden, not pale or burnt.",
          "recovery": "If pale, sear 2 more minutes; if burnt, lower the heat and scrape the pan.",
          "ingredientNames": ["chicken thighs", "garlic"]
        }
      ],
      "isFallback": false
    }
    """

    func testDecodesFullCompilerContract() throws {
        let plan = try JSONDecoder().decode(CookPlan.self, from: Data(fullJSON.utf8))

        XCTAssertEqual(plan.title, "Creamy Lemon Chicken")
        XCTAssertEqual(plan.servings, 4)
        XCTAssertFalse(plan.isFallback)

        XCTAssertEqual(plan.mise.count, 2)
        XCTAssertEqual(plan.mise[0].name, "chicken thighs")
        XCTAssertEqual(plan.mise[0].prep, "pat dry, season both sides")
        XCTAssertEqual(plan.mise[1].name, "garlic")
        XCTAssertEqual(plan.mise[1].prep, "mince")

        XCTAssertEqual(plan.equipment, ["large skillet", "tongs"])
        XCTAssertEqual(plan.steps.count, 2)

        let s1 = plan.steps[0]
        XCTAssertEqual(s1.id, "s1")
        XCTAssertEqual(s1.index, 0)
        XCTAssertEqual(s1.title, "Sear the chicken")
        XCTAssertEqual(s1.instruction, "Sear the chicken thighs 4 minutes per side until golden.")
        XCTAssertEqual(s1.kind, .active)
        XCTAssertEqual(s1.estimatedSeconds, 480)
        XCTAssertEqual(s1.timerSeconds, 240)
        XCTAssertEqual(s1.dependsOn, [])
        XCTAssertNil(s1.visualCheck)
        XCTAssertNil(s1.recovery)
        XCTAssertEqual(s1.ingredientNames, ["chicken thighs"])

        let s2 = plan.steps[1]
        XCTAssertEqual(s2.id, "s2")
        XCTAssertEqual(s2.index, 1)
        XCTAssertEqual(s2.title, "Check the browning")
        XCTAssertEqual(s2.instruction, "Flip and confirm a deep golden crust before adding the garlic.")
        XCTAssertEqual(s2.kind, .checkpoint)
        XCTAssertEqual(s2.estimatedSeconds, 60)
        XCTAssertNil(s2.timerSeconds)
        XCTAssertEqual(s2.dependsOn, ["s1"])
        XCTAssertEqual(s2.visualCheck, "Crust should be deep golden, not pale or burnt.")
        XCTAssertEqual(s2.recovery, "If pale, sear 2 more minutes; if burnt, lower the heat and scrape the pan.")
        XCTAssertEqual(s2.ingredientNames, ["chicken thighs", "garlic"])
    }

    // MARK: - Decoding: optional tolerance

    func testToleratesMinimalPayloadWithUnknownKind() throws {
        let json = """
        {"title":"x","steps":[{"id":"s1","index":0,"title":"t","instruction":"i","kind":"weird"}]}
        """
        let plan = try JSONDecoder().decode(CookPlan.self, from: Data(json.utf8))

        XCTAssertEqual(plan.title, "x")
        XCTAssertEqual(plan.servings, 0, "missing servings defaults to 0")
        XCTAssertTrue(plan.mise.isEmpty, "missing mise defaults to []")
        XCTAssertTrue(plan.equipment.isEmpty, "missing equipment defaults to []")
        XCTAssertFalse(plan.isFallback, "missing isFallback defaults to false")

        let step = try XCTUnwrap(plan.steps.first)
        XCTAssertEqual(step.id, "s1")
        XCTAssertEqual(step.index, 0)
        XCTAssertEqual(step.title, "t")
        XCTAssertEqual(step.instruction, "i")
        XCTAssertEqual(step.kind, .active, "unknown kind string falls back to .active")
        XCTAssertNil(step.estimatedSeconds)
        XCTAssertNil(step.timerSeconds)
        XCTAssertTrue(step.dependsOn.isEmpty)
        XCTAssertNil(step.visualCheck)
        XCTAssertNil(step.recovery)
        XCTAssertTrue(step.ingredientNames.isEmpty)
    }

    // MARK: - Linear fallback

    func testLinearFallbackFromRecipeSteps() throws {
        let context = container.mainContext
        let recipe = Recipe(title: "Weeknight Ragu", servings: 2)
        recipe.ingredients = [
            RecipeIngredient(name: "ground beef", sortIndex: 0),
            RecipeIngredient(name: "onion", sortIndex: 1),
        ]
        recipe.steps = [
            RecipeStep(index: 0, text: "Brown the ground beef with the onion until no pink remains."),
            RecipeStep(index: 1, text: "Simmer the sauce gently, stirring occasionally.", durationSeconds: 300),
        ]
        context.insert(recipe)
        try context.save()

        let plan = CookPlan.linear(from: recipe, scale: 1.5)

        XCTAssertEqual(plan.title, "Weeknight Ragu")
        XCTAssertEqual(plan.servings, 3, "2 servings x 1.5 scale, rounded")
        XCTAssertTrue(plan.isFallback)
        XCTAssertFalse(plan.mise.isEmpty, "linear synthesizes mise for board work")
        XCTAssertTrue(plan.hasLeadingPrep)
        XCTAssertTrue(plan.equipment.isEmpty)
        // No equipment → Prep only (no Tools step).
        XCTAssertEqual(plan.steps.count, 3, "Prep + 2 cook steps")
        XCTAssertEqual(plan.leadingSetupCount, 1)

        let prep = plan.steps[0]
        XCTAssertEqual(prep.id, CookPlan.prepStepID)
        XCTAssertEqual(prep.index, 0)
        XCTAssertEqual(prep.title, "Prep")
        XCTAssertEqual(prep.kind, .prep)
        XCTAssertTrue(prep.instruction.localizedCaseInsensitiveContains("before any heat"))
        XCTAssertFalse(prep.instruction.localizedCaseInsensitiveContains("measure"),
                       "prep must not ask to pre-measure spices")

        let first = plan.steps[1]
        XCTAssertEqual(first.id, "s1")
        XCTAssertEqual(first.index, 1)
        XCTAssertEqual(first.title, "Brown the ground beef with the…", "first 6 words + ellipsis")
        XCTAssertEqual(first.instruction, "Brown the ground beef with the onion until no pink remains.")
        XCTAssertEqual(first.kind, .active, "no durationSeconds -> active")
        XCTAssertNil(first.estimatedSeconds)
        XCTAssertNil(first.timerSeconds)
        XCTAssertEqual(first.dependsOn, [CookPlan.prepStepID])
        XCTAssertNil(first.visualCheck)
        XCTAssertNil(first.recovery)
        XCTAssertEqual(first.ingredientNames, ["ground beef", "onion"])

        let second = plan.steps[2]
        XCTAssertEqual(second.id, "s2")
        XCTAssertEqual(second.index, 2)
        XCTAssertEqual(second.title, "Simmer the sauce gently, stirring occasionally.", "6 words or fewer -> untruncated")
        XCTAssertEqual(second.kind, .passive, "durationSeconds -> passive")
        XCTAssertEqual(second.estimatedSeconds, 300)
        XCTAssertEqual(second.timerSeconds, 300)
        XCTAssertEqual(second.dependsOn, ["s1"])
        XCTAssertTrue(second.ingredientNames.isEmpty, "step text mentions no ingredient")
    }

    func testEnsuringLeadingPrepSplitsToolsAndPrep() throws {
        let json = """
        {"title":"Pasta","servings":2,
         "mise":[{"name":"onion","prep":"dice"},{"name":"garlic","prep":"mince"},{"name":"cumin","prep":"measure"}],
         "equipment":["skillet"],
         "steps":[{"id":"s1","index":0,"title":"Heat oil","instruction":"Heat oil in a skillet.","kind":"active","dependsOn":[]}]}
        """
        let raw = try JSONDecoder().decode(CookPlan.self, from: Data(json.utf8))
        let plan = raw.ensuringLeadingPrep()

        XCTAssertEqual(plan.leadingSetupCount, 2)
        XCTAssertEqual(plan.steps.count, 3)
        XCTAssertEqual(plan.steps[0].id, CookPlan.toolsStepID)
        XCTAssertEqual(plan.steps[0].title, "Tools")
        XCTAssertEqual(plan.steps[1].id, CookPlan.prepStepID)
        XCTAssertEqual(plan.steps[1].title, "Prep")
        XCTAssertEqual(plan.steps[1].dependsOn, [CookPlan.toolsStepID])
        XCTAssertEqual(plan.mise.map(\.name), ["onion", "garlic"], "cumin measure dropped")
        XCTAssertTrue(plan.steps[1].instruction.localizedCaseInsensitiveContains("dice the onion"))
        XCTAssertFalse(plan.steps[1].instruction.localizedCaseInsensitiveContains("cumin"))
        XCTAssertEqual(plan.steps[2].id, "s1")
        XCTAssertEqual(plan.steps[2].index, 2)
        XCTAssertEqual(plan.steps[2].dependsOn, [CookPlan.prepStepID])
    }

    func testEnsuringLeadingPrepIsIdempotent() throws {
        let json = """
        {"title":"Pasta","servings":2,
         "mise":[{"name":"onion","prep":"dice"}],
         "equipment":["skillet"],
         "steps":[
           {"id":"s1","index":0,"title":"Heat oil","instruction":"Heat oil.","kind":"active","dependsOn":[]}
         ]}
        """
        let once = try JSONDecoder().decode(CookPlan.self, from: Data(json.utf8)).ensuringLeadingPrep()
        let twice = once.ensuringLeadingPrep()
        XCTAssertEqual(once, twice)
    }

    /// Cold technique steps arrive as `kind: prep`. Dropping them (old behavior)
    /// left Crème Brûlée with only heat steps — and no clip targets for scrape /
    /// whisk / strain. They must survive as numbered cook steps.
    func testEnsuringLeadingPrepKeepsColdTechniqueSteps() throws {
        let json = """
        {"title":"Crème Brûlée","servings":6,
         "mise":[{"name":"vanilla bean","prep":"split and scrape"}],
         "equipment":["saucepan","ramekins","torch"],
         "steps":[
           {"id":"step1","index":0,"title":"Prepare vanilla bean","instruction":"Split and scrape the vanilla bean.","kind":"prep","dependsOn":[]},
           {"id":"step2","index":1,"title":"Heat cream with vanilla","instruction":"Simmer the cream with the vanilla.","kind":"active","dependsOn":["step1"]},
           {"id":"step3","index":2,"title":"Whisk yolks","instruction":"Whisk egg yolks with sugar.","kind":"prep","dependsOn":["step2"]},
           {"id":"step4","index":3,"title":"Torch the top","instruction":"Torch the sugar until amber.","kind":"active","dependsOn":["step3"]}
         ]}
        """
        let plan = try JSONDecoder().decode(CookPlan.self, from: Data(json.utf8)).ensuringLeadingPrep()

        XCTAssertEqual(plan.leadingSetupCount, 2, "Tools + Prep only")
        XCTAssertEqual(plan.steps.count, 6, "Tools + Prep + 4 cook steps — none dropped")
        XCTAssertFalse(CookPlan.isSetupStep(plan.steps[2]))
        XCTAssertEqual(plan.steps[2].id, "step1")
        XCTAssertEqual(plan.steps[2].kind, .active, "cold prep promoted so clips/UI treat it as a cook step")
        XCTAssertEqual(plan.steps[3].id, "step2")
        XCTAssertEqual(plan.steps[4].id, "step3")
        XCTAssertEqual(plan.steps[4].kind, .active)
        XCTAssertEqual(plan.steps[5].id, "step4")

        let cookSteps = plan.steps.filter { !CookPlan.isSetupStep($0) }
        XCTAssertEqual(cookSteps.count, 4)
        XCTAssertEqual(cookSteps.map(\.id), ["step1", "step2", "step3", "step4"])
    }

    func testLinearFallbackClampsServingsToAtLeastOne() throws {
        let recipe = Recipe(title: "Tiny Batch", servings: 1)
        container.mainContext.insert(recipe)
        let plan = CookPlan.linear(from: recipe, scale: 0.25)
        XCTAssertEqual(plan.servings, 1, "max(1, rounded scaled servings)")
        XCTAssertTrue(plan.steps.isEmpty)
        XCTAssertTrue(plan.isFallback)
    }
}

// MARK: - Scheduling

/// The complaint that prompted this: a recipe told the cook to put chicken in
/// the oven for 20 minutes and then, as the next step, potatoes in for 30.
final class CookPlanSchedulingTests: XCTestCase {

    private func step(
        _ id: String,
        _ index: Int,
        _ instruction: String,
        kind: CookPlan.StepKind = .passive,
        timer: Int? = nil,
        dependsOn: [String] = []
    ) -> CookPlan.PlanStep {
        CookPlan.PlanStep(
            id: id, index: index, title: instruction, instruction: instruction,
            kind: kind, estimatedSeconds: timer, timerSeconds: timer, dependsOn: dependsOn)
    }

    private func plan(_ steps: [CookPlan.PlanStep]) -> CookPlan {
        CookPlan(title: "Test", servings: 2, mise: [], steps: steps)
    }

    func testCatchesTheSlowerDishGoingIntoTheOvenSecond() {
        let subject = plan([
            step("s1", 0, "Put the chicken in the oven", timer: 20 * 60),
            step("s2", 1, "Put the potatoes in the oven", timer: 30 * 60),
        ])
        let issues = subject.schedulingIssues
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.kind, .slowerItemGoesInSecond(.oven))
        XCTAssertEqual(issues.first?.earlierStepID, "s1")
        XCTAssertEqual(issues.first?.laterStepID, "s2")
    }

    func testTheCorrectOrderIsNotFlagged() {
        let subject = plan([
            step("s1", 0, "Put the potatoes in the oven", timer: 30 * 60),
            step("s2", 1, "Add the chicken to the oven", timer: 20 * 60),
        ])
        XCTAssertTrue(subject.schedulingIssues.isEmpty,
                      "longest thing in first is exactly right and must never be flagged")
    }

    /// A stir or a seasoning step routinely sits between the two oven
    /// instructions, so adjacency is not the test.
    func testCatchesItAcrossAnInterveningStep() {
        let subject = plan([
            step("s1", 0, "Roast the chicken", timer: 20 * 60),
            step("s2", 1, "Season the potatoes", kind: .active),
            step("s3", 2, "Roast the potatoes", timer: 30 * 60),
        ])
        XCTAssertEqual(subject.schedulingIssues.first?.kind, .slowerItemGoesInSecond(.oven))
    }

    /// Two different appliances are not competing for anything.
    func testDifferentAppliancesAreNotAConflict() {
        let subject = plan([
            step("s1", 0, "Bake the chicken in the oven", timer: 20 * 60),
            step("s2", 1, "Simmer the sauce in a saucepan", timer: 30 * 60),
        ])
        XCTAssertTrue(subject.schedulingIssues.filter {
            if case .slowerItemGoesInSecond = $0.kind { return true }
            return false
        }.isEmpty)
    }

    func testAirFryerIsNotReadAsAStovetop() {
        XCTAssertEqual(
            CookPlan.appliance(for: step("s1", 0, "Air fryer at 200C")), .airFryer)
        XCTAssertEqual(
            CookPlan.appliance(for: step("s1", 0, "Slow cooker on low")), .slowCooker)
    }

    func testFlagsHandsOnWorkQueuedBehindALongWait() {
        let subject = plan([
            step("s1", 0, "Bake for 40 minutes", timer: 40 * 60),
            step("s2", 1, "Chop the parsley", kind: .active),
        ])
        XCTAssertEqual(subject.schedulingIssues.first?.kind,
                       .handsFreeTimeWasted(seconds: 40 * 60))
    }

    /// Work that genuinely needs the wait to finish cannot move.
    func testWorkThatDependsOnTheWaitIsNotFlagged() {
        let subject = plan([
            step("s1", 0, "Bake for 40 minutes", timer: 40 * 60),
            step("s2", 1, "Slice the rested roast", kind: .active, dependsOn: ["s1"]),
        ])
        XCTAssertTrue(subject.schedulingIssues.isEmpty)
    }

    /// A short wait is not worth sending the cook away for.
    func testAShortWaitIsLeftAlone() {
        let subject = plan([
            step("s1", 0, "Simmer for 3 minutes", timer: 3 * 60),
            step("s2", 1, "Chop the parsley", kind: .active),
        ])
        XCTAssertTrue(subject.schedulingIssues.isEmpty)
    }

    /// Setup rows are not cooking and must never take part.
    func testSetupStepsAreIgnored() {
        let subject = plan([
            CookPlan.PlanStep(id: CookPlan.prepStepID, index: 0, title: "Prep",
                              instruction: "Dice the onion", kind: .prep),
            step("s1", 1, "Bake the chicken", timer: 20 * 60),
        ])
        XCTAssertTrue(subject.schedulingIssues.isEmpty)
    }
}

/// The setup steps are written for Polly to say out loud. Step-by-step cook has
/// nobody to tell.
final class CookModeSilentInstructionTests: XCTestCase {

    func testDropsTheSpokenAside() {
        XCTAssertEqual(
            CookModeView.silentInstruction(
                "Pull out your skillet, whisk. Tell me when they're on the counter."),
            "Pull out your skillet, whisk.")
    }

    func testDropsItFromTheMiddleAndKeepsTheRest() {
        XCTAssertEqual(
            CookModeView.silentInstruction(
                "Before any heat: dice the onion. Tell me when the board is ready. Stage your pan."),
            "Before any heat: dice the onion. Stage your pan.")
    }

    func testLeavesANormalInstructionAlone() {
        let text = "Sear the chicken skin side down for 6 minutes"
        XCTAssertEqual(CookModeView.silentInstruction(text), text)
    }

    /// Never blank the step out.
    func testAnInstructionThatIsOnlyTheAsideSurvives() {
        let text = "Tell me when the board is ready."
        XCTAssertEqual(CookModeView.silentInstruction(text), text)
    }
}

/// "Cut to size the onions" reads like an instruction and contains none.
final class CookPlanVaguePrepTests: XCTestCase {

    func testRecognisesTheVagueOnes() {
        for prep in ["cut to size", "cut", "prepare", "prep", "as needed",
                     "chop as needed", "cut accordingly", ""] {
            XCTAssertTrue(CookPlan.isVaguePrep(prep), "\"\(prep)\" says nothing")
        }
    }

    func testLeavesRealInstructionsAlone() {
        for prep in ["dice", "mince", "cut into florets", "cut into 1-inch cubes",
                     "slice thinly", "pat dry"] {
            XCTAssertFalse(CookPlan.isVaguePrep(prep), "\"\(prep)\" is a real instruction")
        }
    }

    /// The compiler's shrug is replaced by what we know the ingredient wants.
    func testVaguePrepIsReplacedWithTheRealCut() {
        let cleaned = CookPlan.boardWorkOnly([
            CookPlan.MiseItem(name: "onion", prep: "cut to size"),
            CookPlan.MiseItem(name: "broccoli", prep: "cut"),
            CookPlan.MiseItem(name: "garlic", prep: "prepare"),
        ])
        XCTAssertEqual(cleaned.first { $0.name == "onion" }?.prep, "dice")
        XCTAssertEqual(cleaned.first { $0.name == "broccoli" }?.prep, "cut into florets")
        XCTAssertEqual(cleaned.first { $0.name == "garlic" }?.prep, "mince")
    }

    /// When we cannot say what to do either, saying nothing beats saying
    /// "cut to size".
    func testAnUnknownIngredientWithVaguePrepIsDropped() {
        let cleaned = CookPlan.boardWorkOnly([
            CookPlan.MiseItem(name: "gochujang", prep: "cut to size"),
        ])
        XCTAssertTrue(cleaned.isEmpty)
    }

    func testASpecificCutSurvivesUntouched() {
        let cleaned = CookPlan.boardWorkOnly([
            CookPlan.MiseItem(name: "carrot", prep: "cut into 2cm batons"),
        ])
        XCTAssertEqual(cleaned.first?.prep, "cut into 2cm batons")
    }

    /// The rendered Prep line is what the cook actually reads.
    func testThePrepStepNeverReadsCutToSize() {
        let instruction = CookPlan.prepInstruction(
            mise: CookPlan.boardWorkOnly([
                CookPlan.MiseItem(name: "onion", prep: "cut to size"),
                CookPlan.MiseItem(name: "broccoli", prep: "cut to size"),
            ]))
        XCTAssertFalse(instruction.lowercased().contains("cut to size"))
        XCTAssertTrue(instruction.contains("dice the onion"))
        XCTAssertTrue(instruction.contains("cut the broccoli into florets"))
    }

    /// The verb goes first, the ingredient second, the shape last.
    func testPhrasingReadsLikeEnglish() {
        let cases: [(String, String, String)] = [
            ("onion", "dice", "dice the onion"),
            ("broccoli", "cut into florets", "cut the broccoli into florets"),
            ("potato", "cut into 1-inch cubes", "cut the potato into 1-inch cubes"),
            ("mushroom", "slice thinly", "slice the mushroom thinly"),
            ("chicken thighs", "pat dry", "pat the chicken thighs dry"),
        ]
        for (name, prep, expected) in cases {
            XCTAssertEqual(
                CookPlan.phrase(for: CookPlan.MiseItem(name: name, prep: prep)), expected)
        }
    }

    /// Names are title-cased for the list UI and read as typos in a sentence.
    func testTheIngredientIsLowercasedInsideTheSentence() {
        XCTAssertEqual(
            CookPlan.phrase(for: CookPlan.MiseItem(name: "Chicken breast", prep: "dice")),
            "dice the chicken breast")
        XCTAssertEqual(
            CookPlan.phrase(for: CookPlan.MiseItem(name: "Cherry tomatoes", prep: "halve")),
            "halve the cherry tomatoes")
    }

    /// An all-caps name is a deliberate choice, not title case.
    func testAnAllCapsNameIsLeftAlone() {
        XCTAssertEqual(
            CookPlan.phrase(for: CookPlan.MiseItem(name: "BBQ sauce", prep: "")),
            "BBQ sauce")
    }

    /// An unrecognised opening word keeps the old shape rather than being
    /// rearranged into nonsense.
    func testAnUnknownPrepIsNotRearranged() {
        XCTAssertEqual(
            CookPlan.phrase(for: CookPlan.MiseItem(name: "butter", prep: "bring to room temp")),
            "bring to room temp the butter")
    }
}
