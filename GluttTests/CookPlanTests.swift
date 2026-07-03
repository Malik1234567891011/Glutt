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
        XCTAssertTrue(plan.mise.isEmpty)
        XCTAssertTrue(plan.equipment.isEmpty)
        XCTAssertEqual(plan.steps.count, 2)

        let first = plan.steps[0]
        XCTAssertEqual(first.id, "s1")
        XCTAssertEqual(first.index, 0)
        XCTAssertEqual(first.title, "Brown the ground beef with the…", "first 6 words + ellipsis")
        XCTAssertEqual(first.instruction, "Brown the ground beef with the onion until no pink remains.")
        XCTAssertEqual(first.kind, .active, "no durationSeconds -> active")
        XCTAssertNil(first.estimatedSeconds)
        XCTAssertNil(first.timerSeconds)
        XCTAssertEqual(first.dependsOn, [])
        XCTAssertNil(first.visualCheck)
        XCTAssertNil(first.recovery)
        XCTAssertEqual(first.ingredientNames, ["ground beef", "onion"])

        let second = plan.steps[1]
        XCTAssertEqual(second.id, "s2")
        XCTAssertEqual(second.index, 1)
        XCTAssertEqual(second.title, "Simmer the sauce gently, stirring occasionally.", "6 words or fewer -> untruncated")
        XCTAssertEqual(second.kind, .passive, "durationSeconds -> passive")
        XCTAssertEqual(second.estimatedSeconds, 300)
        XCTAssertEqual(second.timerSeconds, 300)
        XCTAssertEqual(second.dependsOn, ["s1"])
        XCTAssertTrue(second.ingredientNames.isEmpty, "step text mentions no ingredient")
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
