import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PollyToolRegistryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var recipe: Recipe!
    private var prefs: UserPrefs!
    private var pantry: [PantryItem]!
    private var plan: CookPlan!
    private var timers: TimerManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
            PantryItem.self, UserPrefs.self, PollyMemory.self, PollyCookLog.self,
        ])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)

        recipe = Recipe(title: "Lemon Garlic Chicken", servings: 2)
        recipe.calories = 520
        recipe.proteinGrams = 42
        context.insert(recipe)
        recipe.ingredients = [
            RecipeIngredient(name: "chicken breast", sortIndex: 0),
            RecipeIngredient(name: "butter", sortIndex: 1),
            RecipeIngredient(name: "heavy cream", sortIndex: 2),
            RecipeIngredient(name: "parsley", isOptional: true, sortIndex: 3),
        ]

        // Owns 2 of the 3 required ingredients (heavy cream missing), plus the
        // stock needed for the substitution assertions.
        pantry = [
            PantryItem(name: "chicken breast"),
            PantryItem(name: "butter"),
            PantryItem(name: "olive oil"),
            PantryItem(name: "sour cream"),
            PantryItem(name: "greek yogurt"),
        ]
        pantry.forEach { context.insert($0) }

        prefs = UserPrefs.current(in: context)
        prefs.dietaryRules = [.halal]
        prefs.allergies = ["yogurt"]

        plan = CookPlan(
            title: "Lemon Garlic Chicken",
            servings: 2,
            steps: [
                CookPlan.PlanStep(
                    id: "s1", index: 0, title: "Sear the chicken",
                    instruction: "Sear the chicken breast in butter, 4 minutes per side.",
                    kind: .active, ingredientNames: ["chicken breast", "butter"]
                ),
                CookPlan.PlanStep(
                    id: "s2", index: 1, title: "Simmer the sauce",
                    instruction: "Pour in the cream and simmer gently for 5 minutes.",
                    kind: .passive, timerSeconds: 300, dependsOn: ["s1"],
                    ingredientNames: ["heavy cream"]
                ),
                CookPlan.PlanStep(
                    id: "s3", index: 2, title: "Rest and serve",
                    instruction: "Rest for a few minutes, garnish, and serve.",
                    kind: .checkpoint, dependsOn: ["s2"],
                    visualCheck: "Sauce should coat the back of a spoon.",
                    ingredientNames: ["parsley"]
                ),
            ]
        )
        timers = TimerManager()
    }

    override func tearDownWithError() throws {
        timers.cancelAll()
        timers = nil
        plan = nil
        pantry = nil
        prefs = nil
        recipe = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeRegistry() -> PollyToolRegistry {
        PollyToolRegistry(plan: plan, recipe: recipe, pantry: pantry, prefs: prefs,
                          timers: timers, context: context)
    }

    /// Parses a handler result back into a dictionary so assertions never
    /// depend on JSON key order.
    private func result(of json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try XCTUnwrap(object as? [String: Any], "handler must return a JSON object")
    }

    // MARK: - (g) Tool definitions

    func testToolDefinitionsMatchLockedNames() {
        let names = PollyToolRegistry.toolDefinitions.map(\.name)
        XCTAssertEqual(names, [
            "get_current_step", "mark_step_done", "check_step_actions", "go_to_step",
            "start_timer", "check_timers", "cancel_timer", "check_pantry",
            "find_substitutes", "get_nutrition", "adjust_servings", "remember_fact",
            "record_polly_save", "request_camera_frame", "end_session", "wait_for_user",
            "show_step_video", "control_step_video", "dismiss_preflight",
        ])
        XCTAssertEqual(PollyToolRegistry.toolDefinitions.count, 19)

        for definition in PollyToolRegistry.toolDefinitions {
            XCTAssertFalse(definition.description.isEmpty, definition.name)
            guard case .object(let schema) = definition.parameters else {
                XCTFail("\(definition.name) parameters must be an object schema")
                continue
            }
            XCTAssertEqual(schema["type"], .string("object"), definition.name)
        }
    }

    // MARK: - (a) Step navigation

    func testStepNavigationFlow() async throws {
        let registry = makeRegistry()
        XCTAssertEqual(registry.state.stepIndex, 0)
        XCTAssertEqual(registry.state.servings, 2)
        XCTAssertTrue(registry.state.substitutions.isEmpty)

        let first = try result(of: await registry.handle(name: "get_current_step", argumentsJSON: "{}"))
        XCTAssertEqual(first["index"] as? Int, 0)
        XCTAssertEqual(first["total"] as? Int, 3)
        XCTAssertEqual(first["title"] as? String, "Sear the chicken")
        XCTAssertEqual(first["kind"] as? String, "active")
        XCTAssertEqual(first["ingredients"] as? [String], ["chicken breast", "butter"])
        XCTAssertNil(first["timerSeconds"], "step 1 has no timer, so the key is omitted")
        XCTAssertNil(first["visualCheck"])

        let second = try result(of: await registry.handle(name: "mark_step_done", argumentsJSON: "{}"))
        XCTAssertEqual(second["index"] as? Int, 1)
        XCTAssertEqual(second["kind"] as? String, "passive")
        XCTAssertEqual(second["timerSeconds"] as? Int, 300)
        XCTAssertTrue(registry.state.completedStepIDs.contains("s1"))
        XCTAssertEqual(registry.state.stepIndex, 1)

        let clampedHigh = try result(of: await registry.handle(name: "go_to_step", argumentsJSON: #"{"index": 99}"#))
        XCTAssertEqual(clampedHigh["index"] as? Int, 2, "out-of-range index clamps to the last step")
        XCTAssertEqual(clampedHigh["visualCheck"] as? String, "Sauce should coat the back of a spoon.")

        let clampedLow = try result(of: await registry.handle(name: "go_to_step", argumentsJSON: #"{"index": -5}"#))
        XCTAssertEqual(clampedLow["index"] as? Int, 0, "negative index clamps to the first step")

        _ = await registry.handle(name: "go_to_step", argumentsJSON: #"{"index": 2}"#)
        let done = try result(of: await registry.handle(name: "mark_step_done", argumentsJSON: "{}"))
        XCTAssertEqual(done["done"] as? Bool, true)
        XCTAssertTrue(registry.state.completedStepIDs.contains("s3"))
        XCTAssertEqual(registry.state.stepIndex, 2, "index stays clamped at the last step")

        let doneAgain = try result(of: await registry.handle(name: "mark_step_done", argumentsJSON: "{}"))
        XCTAssertEqual(doneAgain["done"] as? Bool, true, "marking done at the end is idempotent")
    }

    func testCheckStepActionsMatchesCookSpeech() async throws {
        let registry = makeRegistry()
        let current = try result(of: await registry.handle(name: "get_current_step", argumentsJSON: "{}"))
        let actions = try XCTUnwrap(current["actions"] as? [[String: Any]])
        XCTAssertFalse(actions.isEmpty, "get_current_step must expose on-screen checklist actions")

        let updated = try result(of: await registry.handle(
            name: "check_step_actions",
            argumentsJSON: #"{"matches":["chicken","butter"]}"#))
        let ids = try XCTUnwrap(updated["updated"] as? [String])
        XCTAssertFalse(ids.isEmpty)
        XCTAssertEqual(updated["checked"] as? Bool, true)
        for id in ids {
            XCTAssertTrue(registry.state.checkedActionIDs.contains(id))
        }

        // Exact id path + uncheck
        let firstID = try XCTUnwrap(actions.first?["id"] as? String)
        _ = await registry.handle(
            name: "check_step_actions",
            argumentsJSON: "{\"item_ids\":[\"\(firstID)\"],\"checked\":false}")
        XCTAssertFalse(registry.state.checkedActionIDs.contains(firstID))

        let byID = try result(of: await registry.handle(
            name: "check_step_actions",
            argumentsJSON: "{\"item_ids\":[\"\(firstID)\"]}"))
        XCTAssertEqual(byID["updated"] as? [String], [firstID])
        XCTAssertTrue(registry.state.checkedActionIDs.contains(firstID))
    }

    // MARK: - (b) Timers

    func testTimerStartCheckCancel() async throws {
        let registry = makeRegistry()

        let started = try result(of: await registry.handle(
            name: "start_timer", argumentsJSON: #"{"label": "Simmer sauce", "seconds": 300}"#))
        XCTAssertEqual(started["started"] as? Bool, true)
        XCTAssertEqual(started["label"] as? String, "Simmer sauce")
        XCTAssertEqual(started["seconds"] as? Int, 300)
        XCTAssertEqual(timers.timers.count, 1)

        let checked = try result(of: await registry.handle(name: "check_timers", argumentsJSON: "{}"))
        let running = try XCTUnwrap(checked["timers"] as? [[String: Any]])
        XCTAssertEqual(running.count, 1)
        XCTAssertEqual(running[0]["label"] as? String, "Simmer sauce")
        let remaining = try XCTUnwrap(running[0]["remainingSeconds"] as? Int)
        XCTAssertTrue((295...300).contains(remaining), "just-started 300s timer, got \(remaining)")

        let cancelled = try result(of: await registry.handle(
            name: "cancel_timer", argumentsJSON: #"{"label": "simmer SAUCE"}"#))
        XCTAssertEqual(cancelled["cancelled"] as? Bool, true, "label match is case-insensitive")
        XCTAssertEqual(cancelled["label"] as? String, "Simmer sauce")
        XCTAssertTrue(timers.timers.isEmpty)

        let missing = try result(of: await registry.handle(
            name: "cancel_timer", argumentsJSON: #"{"label": "Simmer sauce"}"#))
        XCTAssertEqual(missing["error"] as? String, "no such timer")
    }

    // MARK: - (c) Pantry

    func testCheckPantryCountsAndMissingNames() async throws {
        let registry = makeRegistry()
        let payload = try result(of: await registry.handle(name: "check_pantry", argumentsJSON: "{}"))
        XCTAssertEqual(payload["ownedCount"] as? Int, 2)
        XCTAssertEqual(payload["totalCount"] as? Int, 3, "optional ingredients never count toward the total")
        XCTAssertEqual(payload["missing"] as? [String], ["heavy cream"])
        XCTAssertEqual(payload["missingOptional"] as? [String], ["parsley"])
    }

    // MARK: - (d) Substitutes

    func testFindSubstitutesRespectsPantryAndDietGuard() async throws {
        let registry = makeRegistry()

        let butter = try result(of: await registry.handle(
            name: "find_substitutes", argumentsJSON: #"{"ingredient": "butter"}"#))
        let butterSubs = try XCTUnwrap(butter["substitutes"] as? [[String: Any]])
        XCTAssertEqual(butterSubs.compactMap { $0["name"] as? String }, ["olive oil"])
        XCTAssertEqual(butter["isEssential"] as? Bool, false)
        for sub in butterSubs {
            let name = try XCTUnwrap(sub["name"] as? String)
            XCTAssertTrue(DietGuard.isAllowed(ingredientName: name, rules: [.halal], allergies: ["yogurt"]),
                          "every returned substitute must pass DietGuard")
            XCTAssertFalse((sub["explanation"] as? String ?? "").isEmpty)
        }

        // "Greek yogurt + butter" trips the yogurt allergy; only sour cream survives.
        let cream = try result(of: await registry.handle(
            name: "find_substitutes", argumentsJSON: #"{"ingredient": "heavy cream"}"#))
        let creamSubs = try XCTUnwrap(cream["substitutes"] as? [[String: Any]])
        XCTAssertEqual(creamSubs.compactMap { $0["name"] as? String }, ["sour cream"])

        let chicken = try result(of: await registry.handle(
            name: "find_substitutes", argumentsJSON: #"{"ingredient": "chicken"}"#))
        XCTAssertEqual(chicken["isEssential"] as? Bool, true)
        XCTAssertEqual((chicken["substitutes"] as? [[String: Any]])?.count, 0)

        XCTAssertTrue(registry.state.substitutions.isEmpty,
                      "find_substitutes must never record a substitution by itself")
    }

    // MARK: - (e) Memory

    func testRememberFactWritesMemoryAndRecordsSubstitutions() async throws {
        let registry = makeRegistry()

        let remembered = try result(of: await registry.handle(
            name: "remember_fact",
            argumentsJSON: #"{"kind": "equipment", "text": "Owns a cast iron skillet", "confidence": 0.9}"#))
        XCTAssertEqual(remembered["remembered"] as? Bool, true)

        var memories = try context.fetch(FetchDescriptor<PollyMemory>())
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].kind, .equipment)
        XCTAssertEqual(memories[0].confidence, 0.9)
        XCTAssertEqual(memories[0].sourceRecipeTitle, "Lemon Garlic Chicken")
        XCTAssertTrue(registry.state.substitutions.isEmpty, "a plain fact is not a substitution")

        _ = await registry.handle(
            name: "remember_fact",
            argumentsJSON: #"{"kind": "outcome", "text": "Substituted olive oil for butter in Lemon Garlic Chicken"}"#)
        XCTAssertEqual(registry.state.substitutions,
                       ["Substituted olive oil for butter in Lemon Garlic Chicken"],
                       "text starting with 'Substituted' lands in state.substitutions")
        XCTAssertEqual(registry.state.pollySaves.count, 1, "substitutions also count as a Polly Save")

        let save = try result(of: await registry.handle(
            name: "record_polly_save",
            argumentsJSON: #"{"moment": "Stopped garlic from burning"}"#))
        XCTAssertEqual(save["saved"] as? Bool, true)
        XCTAssertEqual(save["count"] as? Int, 2)
        XCTAssertEqual(registry.state.pollySaves.last, "Stopped garlic from burning")

        // Unknown kind degrades to .outcome; missing confidence defaults to 0.7.
        _ = await registry.handle(
            name: "remember_fact",
            argumentsJSON: #"{"kind": "horoscope", "text": "Prefers crispy edges"}"#)
        memories = try context.fetch(FetchDescriptor<PollyMemory>())
        XCTAssertEqual(memories.count, 3)
        let fallback = try XCTUnwrap(memories.first { $0.text == "Prefers crispy edges" })
        XCTAssertEqual(fallback.kind, .outcome)
        XCTAssertEqual(fallback.confidence, 0.7)
    }

    // MARK: - (f) Error paths

    func testUnknownToolAndBadArguments() async throws {
        let registry = makeRegistry()

        let unknown = try result(of: await registry.handle(name: "fly_to_the_moon", argumentsJSON: "{}"))
        XCTAssertEqual(unknown["error"] as? String, "unknown tool")

        let badJSON = try result(of: await registry.handle(name: "go_to_step", argumentsJSON: "step two please"))
        XCTAssertEqual(badJSON["error"] as? String, "bad arguments")

        let missingField = try result(of: await registry.handle(name: "go_to_step", argumentsJSON: "{}"))
        XCTAssertEqual(missingField["error"] as? String, "bad arguments")

        let wrongTypes = try result(of: await registry.handle(
            name: "start_timer", argumentsJSON: #"{"label": 7, "seconds": "soon"}"#))
        XCTAssertEqual(wrongTypes["error"] as? String, "bad arguments")

        let noText = try result(of: await registry.handle(
            name: "remember_fact", argumentsJSON: #"{"kind": "equipment"}"#))
        XCTAssertEqual(noText["error"] as? String, "bad arguments")

        let emptyArgs = try result(of: await registry.handle(name: "get_current_step", argumentsJSON: ""))
        XCTAssertEqual(emptyArgs["index"] as? Int, 0, "empty arguments string is treated as {}")
    }

    // MARK: - Nutrition

    func testGetNutritionPrefersRecipeMacrosThenEstimatorThenUnavailable() async throws {
        // Stored macros win.
        let direct = try result(of: await makeRegistry().handle(name: "get_nutrition", argumentsJSON: "{}"))
        XCTAssertEqual(direct["available"] as? Bool, true)
        XCTAssertEqual(direct["calories"] as? Int, 520)
        XCTAssertEqual(direct["protein"] as? Int, 42)

        // No stored macros -> NutritionEstimator over the ingredients.
        recipe.calories = nil
        recipe.proteinGrams = nil
        let estimated = try result(of: await makeRegistry().handle(name: "get_nutrition", argumentsJSON: "{}"))
        XCTAssertEqual(estimated["available"] as? Bool, true)
        let calories = try XCTUnwrap(estimated["calories"] as? Int)
        XCTAssertGreaterThan(calories, 0)
        let confidence = try XCTUnwrap(estimated["confidence"] as? Double)
        XCTAssertTrue((0...1).contains(confidence))

        // No macros and no recognizable ingredients -> honest unavailable.
        let bare = Recipe(title: "Mystery Dish")
        context.insert(bare)
        let bareRegistry = PollyToolRegistry(
            plan: CookPlan(title: "Mystery Dish", servings: 2),
            recipe: bare, pantry: [], prefs: prefs, timers: timers, context: context
        )
        let unavailable = try result(of: await bareRegistry.handle(name: "get_nutrition", argumentsJSON: "{}"))
        XCTAssertEqual(unavailable["available"] as? Bool, false)
    }

    // MARK: - Servings

    func testAdjustServingsUpdatesStateAndReturnsScale() async throws {
        let registry = makeRegistry()
        let payload = try result(of: await registry.handle(
            name: "adjust_servings", argumentsJSON: #"{"servings": 4}"#))
        XCTAssertEqual(payload["servings"] as? Int, 4)
        let scale = try XCTUnwrap(payload["scaleFromOriginal"] as? Double)
        XCTAssertEqual(scale, 2.0, accuracy: 0.0001, "recipe is written for 2 servings")
        XCTAssertEqual(registry.state.servings, 4)

        let bad = try result(of: await registry.handle(
            name: "adjust_servings", argumentsJSON: #"{"servings": 0}"#))
        XCTAssertEqual(bad["error"] as? String, "bad arguments")
        XCTAssertEqual(registry.state.servings, 4, "rejected call must not touch state")
    }

    // MARK: - Camera + end hooks

    func testRequestCameraFrameAndEndSessionHooks() async throws {
        let registry = makeRegistry()

        let noCamera = try result(of: await registry.handle(name: "request_camera_frame", argumentsJSON: "{}"))
        XCTAssertEqual(noCamera["captured"] as? Bool, false)
        XCTAssertEqual(noCamera["reason"] as? String, "camera unavailable")

        registry.onRequestFrame = { true }
        let captured = try result(of: await registry.handle(name: "request_camera_frame", argumentsJSON: "{}"))
        XCTAssertEqual(captured["captured"] as? Bool, true)

        registry.onRequestFrame = { false }
        let failed = try result(of: await registry.handle(name: "request_camera_frame", argumentsJSON: "{}"))
        XCTAssertEqual(failed["captured"] as? Bool, false)
        XCTAssertEqual(failed["reason"] as? String,
                       "camera is off or no frame yet — ask the cook to tap the camera button to show you")

        var ended = false
        registry.onEndSession = { ended = true }
        let ending = try result(of: await registry.handle(name: "end_session", argumentsJSON: "{}"))
        XCTAssertEqual(ending["ending"] as? Bool, true)
        XCTAssertTrue(ended)
    }
}
