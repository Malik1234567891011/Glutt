import XCTest
import SwiftData
@testable import Glutt

/// The "one shopping list, five dinners" planner: the overlap-constrained
/// generation pass, the consolidation that makes five recipes read as one shop,
/// the swap that must not disturb the list, and the commit into the library.
@MainActor
final class WeekPlanTests: XCTestCase {

    // MARK: - Fixtures

    private func meal(
        _ title: String,
        ingredients: [String],
        servings: Int = 4
    ) -> WeekPlanner.Meal {
        WeekPlanner.Meal(
            title: title,
            summary: nil,
            servings: servings,
            prepMinutes: 10,
            cookMinutes: 20,
            ingredientLines: ingredients,
            stepTexts: ["Cook it.", "Serve it."]
        )
    }

    private var planJSON: String {
        """
        {
          "sharedCore": ["white rice", "chicken thighs", "cabbage"],
          "meals": [
            {"title": "Mushroom Chicken and Rice", "summary": "One pan.", "servings": 4,
             "prepMinutes": 10, "cookMinutes": 30,
             "ingredients": ["2 cups white rice", "1.5 lbs chicken thighs", "8 oz mushrooms", "1 yellow onion"],
             "steps": ["Brown the chicken.", "Add rice and stock.", "Simmer covered."],
             "tags": ["one-pan", "chicken"]},
            {"title": "Cabbage and Chickpea Skillet", "summary": "Cheap and fast.", "servings": 4,
             "prepMinutes": 8, "cookMinutes": 18,
             "ingredients": ["1 head cabbage", "2 cans chickpeas", "1 onion"],
             "steps": ["Shred the cabbage.", "Fry until it catches colour."],
             "tags": ["vegetarian"]},
            {"title": "Turkey Rice Bowls", "summary": "Weeknight bowls.", "servings": 4,
             "prepMinutes": 5, "cookMinutes": 20,
             "ingredients": ["1 cup white rice", "1 lb ground turkey", "2 carrots"],
             "steps": ["Cook the rice.", "Brown the turkey."],
             "tags": ["bowls"]},
            {"title": "Chicken Cabbage Soup", "summary": "A big pot.", "servings": 4,
             "prepMinutes": 10, "cookMinutes": 35,
             "ingredients": ["1 lb chicken thighs", "1/2 head cabbage", "2 carrots"],
             "steps": ["Simmer everything.", "Season at the end."],
             "tags": ["soup"]},
            {"title": "Chickpea Rice Pilaf", "summary": "Pantry dinner.", "servings": 4,
             "prepMinutes": 5, "cookMinutes": 25,
             "ingredients": ["1 cup white rice", "1 can chickpeas", "1 onion"],
             "steps": ["Toast the rice.", "Simmer with stock."],
             "tags": ["pantry"]}
          ]
        }
        """
    }

    // MARK: - Generation

    func testGenerateReturnsTheWholeSetWithItsSharedCore() async throws {
        let fake = FakeLLMTransport(replyJSON: planJSON)
        let plan = try await WeekPlanner.generate(
            request: WeekPlanner.Request(mealCount: 5, servings: 4, budgetTarget: 60),
            client: fake.client()
        )

        XCTAssertEqual(plan.meals.count, 5)
        XCTAssertEqual(plan.meals.first?.title, "Mushroom Chicken and Rice")
        XCTAssertEqual(plan.sharedCore, ["white rice", "chicken thighs", "cabbage"])
        XCTAssertTrue(plan.meals.allSatisfy { $0.servings == 4 })
    }

    func testGeneratePromptForcesOverlapAndBansPrices() async throws {
        let fake = FakeLLMTransport(replyJSON: planJSON)
        _ = try await WeekPlanner.generate(
            request: WeekPlanner.Request(mealCount: 5, servings: 4, budgetTarget: 60),
            client: fake.client()
        )

        // The overlap is the whole feature, so it has to be an instruction and
        // not a hope: shared core first, then dishes that spend it.
        XCTAssertTrue(fake.system.contains("sharedCore"))
        XCTAssertTrue(fake.system.localizedCaseInsensitiveContains("overlap"))
        XCTAssertTrue(fake.system.localizedCaseInsensitiveContains("protein"))
        // The budget steers this call and no figure comes back from it. The
        // number the cook is shown is priced separately by `estimateCost`,
        // against the finished list rather than asserted by the call that had
        // the budget in front of it.
        XCTAssertTrue(fake.user.contains("$60"))
        XCTAssertTrue(fake.system.contains("Do not write a price"))
        XCTAssertTrue(fake.user.contains("do NOT return any price"))
    }

    func testGeneratePromptCapsTheShoppingListAtTheCooksNumber() async throws {
        let fake = FakeLLMTransport(replyJSON: planJSON)
        _ = try await WeekPlanner.generate(
            request: WeekPlanner.Request(mealCount: 4, servings: 4, ingredientTarget: 10),
            client: fake.client()
        )

        // A ceiling, not a target to drift past. Someone who asked for ten items
        // so they could grab them quickly has not agreed to twenty-two.
        XCTAssertTrue(fake.system.contains("AT MOST 10 DISTINCT ITEMS"))
        XCTAssertTrue(fake.user.contains("SHOPPING LIST CEILING: 10"))
        // And the way out is sharing more, not quietly buying more.
        XCTAssertTrue(fake.system.contains("make the dishes share more, not the list longer"))
    }

    func testGeneratePromptAsksForDifferentKindsOfDinner() async throws {
        let fake = FakeLLMTransport(replyJSON: planJSON)
        _ = try await WeekPlanner.generate(
            request: WeekPlanner.Request(mealCount: 4, servings: 4),
            client: fake.client()
        )

        // Varying the pan is not variety. Four nights of the same ingredients
        // have to arrive as visibly different dinners or the plan is a chore.
        XCTAssertTrue(fake.system.localizedCaseInsensitiveContains("different kinds of dinner"))
        XCTAssertTrue(fake.system.localizedCaseInsensitiveContains("noodles"))
        XCTAssertTrue(fake.system.localizedCaseInsensitiveContains("tacos"))
        XCTAssertTrue(fake.system.localizedCaseInsensitiveContains("stir fry"))
        XCTAssertTrue(fake.system.localizedCaseInsensitiveContains("flavour"))
    }

    func testGenerateCarriesTheItemsTheCookAskedToInclude() async throws {
        let fake = FakeLLMTransport(replyJSON: planJSON)
        _ = try await WeekPlanner.generate(
            request: WeekPlanner.Request(mealCount: 4, mustInclude: "salmon, halloumi"),
            client: fake.client()
        )

        XCTAssertTrue(fake.user.contains("MUST INCLUDE"))
        XCTAssertTrue(fake.user.contains("salmon, halloumi"))
        // The opposite of the pantry, which means "already here, do not buy it".
        XCTAssertTrue(fake.user.contains("put them on the list"))
    }

    func testGenerateOmitsTheIncludeBlockWhenTheCookNamedNothing() async throws {
        let fake = FakeLLMTransport(replyJSON: planJSON)
        _ = try await WeekPlanner.generate(
            request: WeekPlanner.Request(mealCount: 4, mustInclude: "   "),
            client: fake.client()
        )

        XCTAssertFalse(fake.user.contains("MUST INCLUDE"))
    }

    func testGeneratePromptCarriesDietAllergiesDislikesAndPantry() async throws {
        let prefs = UserPrefs()
        prefs.dietaryRules = [.noPork]
        prefs.allergies = ["peanuts"]
        prefs.dislikedIngredients = ["olives"]
        let pantry = [PantryItem(name: "white rice"), PantryItem(name: "soy sauce")]

        let fake = FakeLLMTransport(replyJSON: planJSON)
        _ = try await WeekPlanner.generate(
            request: WeekPlanner.Request(),
            pantry: pantry,
            prefs: prefs,
            client: fake.client()
        )

        XCTAssertTrue(fake.user.contains("No pork"))
        XCTAssertTrue(fake.user.contains("peanuts"))
        XCTAssertTrue(fake.user.contains("olives"))
        XCTAssertTrue(fake.user.contains("white rice"))
        XCTAssertTrue(fake.user.contains("soy sauce"))
    }

    func testGenerateFailsWhenTheModelReturnsNothingUsable() async {
        let fake = FakeLLMTransport(replyJSON: #"{"meals": []}"#)
        do {
            _ = try await WeekPlanner.generate(request: .init(), client: fake.client())
            XCTFail("expected a failure")
        } catch let error as WeekPlanner.PlanError {
            XCTAssertEqual(error, .failed)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - Swap

    /// The invariant the whole feature rests on: a swap is offered only the
    /// ingredients the other dinners already established.
    // MARK: - What it costs

    private func pricedPlan() -> WeekPlanner.Plan {
        WeekPlanner.Plan(
            request: WeekPlanner.Request(mealCount: 2, servings: 4, budgetTarget: 60),
            meals: [
                meal("Rice Bowls", ingredients: [
                    "2 cups white rice", "1 lb chicken thighs", "2 carrots",
                ]),
                meal("Cabbage Skillet", ingredients: [
                    "1 head cabbage", "1 onion", "1 can chickpeas",
                ]),
            ],
            sharedCore: ["white rice"]
        )
    }

    /// What the cook actually buys, which is the plan's ingredients minus
    /// whatever the pantry already covers.
    private var shoppingList: [String] {
        ["white rice", "chicken thighs", "cabbage", "onion"]
    }

    func testCostEstimateComesBackAsARange() async {
        let fake = FakeLLMTransport(replyJSON: #"{"low": 48, "high": 63}"#)
        let cost = await WeekPlanner.estimateCost(
            for: pricedPlan(), shoppingList: shoppingList, client: fake.client()
        )

        XCTAssertEqual(cost, WeekPlanner.CostEstimate(low: 48, high: 63))
        XCTAssertEqual(cost?.range, "$48 to $63")
    }

    func testCostEstimateIsPricedAgainstTheListAndNotTheBudget() async {
        let fake = FakeLLMTransport(replyJSON: #"{"low": 48, "high": 63}"#)
        _ = await WeekPlanner.estimateCost(
            for: pricedPlan(), shoppingList: shoppingList, client: fake.client()
        )

        // It sees the groceries.
        XCTAssertTrue(fake.user.contains("white rice"))
        XCTAssertTrue(fake.user.contains("cabbage"))
        // And only the groceries. This plan's meals also call for chickpeas and
        // carrots, which the pantry covers and the cook will not be buying, so
        // charging for them would inflate the figure exactly when the pantry is
        // doing the most good.
        XCTAssertFalse(fake.user.contains("chickpeas"))
        XCTAssertFalse(fake.user.contains("carrots"))
        // It does not see the budget, so it cannot simply agree with it. That
        // is the whole reason this is a second call rather than another field
        // on the generation response.
        XCTAssertFalse(fake.user.contains("60"))
        XCTAssertTrue(fake.system.contains("Do not pad the estimate"))
    }

    func testCostEstimateSurvivesABackwardsRange() async {
        // Seen in practice, and "$70 to $52" on screen would discredit the
        // whole plan, so the bounds are sorted rather than trusted.
        let fake = FakeLLMTransport(replyJSON: #"{"low": 70, "high": 52}"#)
        let cost = await WeekPlanner.estimateCost(
            for: pricedPlan(), shoppingList: shoppingList, client: fake.client()
        )

        XCTAssertEqual(cost, WeekPlanner.CostEstimate(low: 52, high: 70))
    }

    func testCostEstimateGivesUpQuietlyRatherThanFailingThePlan() async {
        let fake = FakeLLMTransport(replyJSON: #"{"low": null, "high": null}"#)
        let cost = await WeekPlanner.estimateCost(
            for: pricedPlan(), shoppingList: shoppingList, client: fake.client()
        )

        // No estimate simply hides the row. The cook came for dinners, and
        // losing them over a price guess would be an absurd trade.
        XCTAssertNil(cost)
    }

    func testSwapDropsAStaleCostSoNoWrongPriceIsEverShown() async throws {
        var plan = pricedPlan()
        plan.cost = WeekPlanner.CostEstimate(low: 48, high: 63)

        let fake = FakeLLMTransport(replyJSON: """
        {"meals": [{"title": "Cabbage Fried Rice", "summary": "Uses the same bag.",
          "servings": 4, "prepMinutes": 5, "cookMinutes": 12,
          "ingredients": ["2 cups white rice", "1 head cabbage"],
          "steps": ["Fry the rice.", "Fold the cabbage through."], "tags": ["quick"]}]}
        """)
        let updated = try await WeekPlanner.swap(mealAt: 1, in: plan, client: fake.client())

        XCTAssertNil(updated.cost)
    }

    func testRefineDropsAStaleCostBecauseItIsAllowedToMoveTheList() async throws {
        var plan = pricedPlan()
        plan.cost = WeekPlanner.CostEstimate(low: 48, high: 63)

        let fake = FakeLLMTransport(replyJSON: planJSON)
        let updated = try await WeekPlanner.refine(
            plan, instruction: "make one vegetarian", client: fake.client()
        )

        XCTAssertNil(updated.cost)
    }

    // MARK: - Swap

    func testSwapConstrainsTheModelToTheRemainingIngredientPool() async throws {
        let plan = WeekPlanner.Plan(
            request: .init(mealCount: 3, servings: 4),
            meals: [
                meal("Rice and Beans", ingredients: ["2 cups white rice", "2 cans black beans"]),
                meal("Mushroom Risotto", ingredients: ["1 cup white rice", "8 oz mushrooms"]),
                meal("Cabbage Slaw Bowls", ingredients: ["1 head cabbage", "2 carrots"]),
            ],
            sharedCore: ["white rice"]
        )

        let fake = FakeLLMTransport(replyJSON: """
        {"meals": [{"title": "Rice and Mushroom Skillet", "servings": 4, "prepMinutes": 5,
                    "cookMinutes": 20, "ingredients": ["1 cup white rice", "8 oz mushrooms"],
                    "steps": ["Fry the mushrooms.", "Fold in the rice."]}]}
        """)

        let updated = try await WeekPlanner.swap(mealAt: 2, in: plan, client: fake.client())

        XCTAssertEqual(updated.meals.count, 3)
        XCTAssertEqual(updated.meals[2].title, "Rice and Mushroom Skillet")
        XCTAssertEqual(updated.meals[0].title, "Rice and Beans")

        // The pool is what the kept dinners use, and nothing else. Cabbage and
        // carrots belonged only to the dish being replaced, so offering them
        // would let the model keep an item on the list for no reason.
        XCTAssertTrue(fake.user.contains("ALLOWED POOL"))
        XCTAssertTrue(fake.user.contains("white rice"))
        XCTAssertTrue(fake.user.contains("mushrooms"))
        XCTAssertFalse(fake.user.contains("- cabbage"))
        XCTAssertFalse(fake.user.contains("- carrots"))
        XCTAssertTrue(fake.system.contains("HARD CONSTRAINT"))
        XCTAssertTrue(fake.system.localizedCaseInsensitiveContains("must not change"))
    }

    func testRefineCarriesTheInstructionAndTheCurrentPlan() async throws {
        let plan = WeekPlanner.Plan(
            request: .init(mealCount: 5, servings: 4),
            meals: [
                meal("Chicken and Rice", ingredients: ["2 cups white rice", "1 lb chicken thighs"]),
                meal("Chicken Soup", ingredients: ["1 lb chicken thighs", "2 carrots"]),
            ],
            sharedCore: ["white rice"]
        )
        let fake = FakeLLMTransport(replyJSON: planJSON)

        let updated = try await WeekPlanner.refine(
            plan, instruction: "less chicken", client: fake.client()
        )

        XCTAssertEqual(updated.meals.count, 5)
        XCTAssertTrue(fake.user.contains("less chicken"))
        XCTAssertTrue(fake.user.contains("Chicken and Rice"))
        XCTAssertTrue(fake.user.contains("CURRENT INGREDIENTS"))
    }

    // MARK: - Consolidation

    func testConsolidateMergesNamingVariantsIntoOneLine() {
        let lines = MealPlanConsolidator.consolidate(meals: [
            meal("Skillet", ingredients: ["1 yellow onion", "2 cups white rice"]),
            meal("Soup", ingredients: ["2 onions", "1 cup white rice"]),
        ])

        let onion = lines.first { $0.canonicalName == "onion" }
        XCTAssertNotNil(onion)
        XCTAssertEqual(lines.filter { $0.canonicalName == "onion" }.count, 1)
        // Unitless counts combine, and the shorter spelling wins on the list.
        XCTAssertEqual(onion?.quantity, 3)
        XCTAssertEqual(onion?.name, "onions")
    }

    func testConsolidateKeepsSeasoningInTheRecipeAndOffTheShoppingList() {
        let lines = MealPlanConsolidator.consolidate(meals: [
            meal("Stir Fry", ingredients: [
                "2 carrots", "Salt and pepper to taste", "1 tsp cumin",
            ]),
            meal("Curry", ingredients: ["1 onion", "salt", "black pepper", "water"]),
        ])

        let names = lines.map { $0.name.lowercased() }
        // Nobody adds "salt and pepper to taste" to a trolley, and on a list
        // capped at ten items it would be displacing a real ingredient. The
        // compound phrasing is what needs catching: bare salt and pepper already
        // canonicalize onto the assumed-staples path and sit dimmed under
        // "already in your kitchen".
        XCTAssertFalse(names.contains { $0.contains("to taste") })
        XCTAssertTrue(lines.first { $0.name.lowercased() == "salt" }?.alreadyHave ?? false)
        // Cumin is a real purchase and is not guessed away.
        XCTAssertTrue(names.contains("cumin"))
        XCTAssertTrue(names.contains("carrots"))
        XCTAssertTrue(names.contains("onion"))
    }

    func testConsolidateSumsQuantitiesOnlyWhenUnitsAgree() {
        let agreeing = MealPlanConsolidator.consolidate(meals: [
            meal("A", ingredients: ["2 cups white rice"]),
            meal("B", ingredients: ["1 cup white rice"]),
        ])
        XCTAssertEqual(agreeing.first { $0.canonicalName == "white rice" }?.quantity, 3)
        XCTAssertEqual(agreeing.first { $0.canonicalName == "white rice" }?.unit, "cups")

        // "2 cups" plus "1 lb" is not a number we can show honestly.
        let clashing = MealPlanConsolidator.consolidate(meals: [
            meal("A", ingredients: ["2 cups white rice"]),
            meal("B", ingredients: ["1 lb white rice"]),
        ])
        XCTAssertNil(clashing.first { $0.canonicalName == "white rice" }?.quantity)
    }

    func testConsolidateRecordsWhichMealsNeedEachLine() {
        let lines = MealPlanConsolidator.consolidate(meals: [
            meal("Chicken and Rice", ingredients: ["2 cups white rice", "1 lb chicken thighs"]),
            meal("Rice Bowls", ingredients: ["1 cup white rice", "1 lb ground turkey"]),
            meal("Rice Soup", ingredients: ["1 cup white rice", "2 carrots"]),
        ])

        let rice = lines.first { $0.canonicalName == "white rice" }
        XCTAssertEqual(rice?.mealCount, 3)
        XCTAssertEqual(rice?.sharedLabel, "Used in 3 meals")
        XCTAssertEqual(
            rice?.recipeTitles, ["Chicken and Rice", "Rice Bowls", "Rice Soup"]
        )
        // A line only one dinner wants says nothing about sharing.
        XCTAssertNil(lines.first { $0.canonicalName == "carrot" }?.sharedLabel)
    }

    func testConsolidateCountsARepeatedLineOncePerMeal() {
        let lines = MealPlanConsolidator.consolidate(meals: [
            meal("Skillet", ingredients: ["1 onion", "1 onion, sliced"]),
        ])
        XCTAssertEqual(lines.first { $0.canonicalName == "onion" }?.mealCount, 1)
    }

    func testConsolidateMarksWhatThePantryAlreadyCovers() {
        let pantry = [PantryItem(name: "white rice")]
        let lines = MealPlanConsolidator.consolidate(
            meals: [meal("A", ingredients: ["2 cups white rice", "1 lb chicken thighs", "salt"])],
            pantry: pantry
        )

        XCTAssertEqual(lines.first { $0.canonicalName == "white rice" }?.alreadyHave, true)
        XCTAssertEqual(lines.first { $0.canonicalName == "chicken thigh" }?.alreadyHave, false)
        // Nobody shops for salt.
        XCTAssertEqual(lines.first { $0.canonicalName == "salt" }?.alreadyHave, true)
    }

    func testConsolidateSortsSharedItemsFirstInsideAnAisle() {
        let lines = MealPlanConsolidator.consolidate(meals: [
            meal("A", ingredients: ["1 cup white rice", "1 can chickpeas"]),
            meal("B", ingredients: ["1 cup white rice"]),
            meal("C", ingredients: ["1 cup white rice"]),
        ])
        let pantryAisle = lines.filter { $0.category == .pantry }
        XCTAssertEqual(pantryAisle.first?.canonicalName, "white rice")
    }

    // MARK: - Diff

    func testSwapInsideThePoolLeavesTheShoppingListAlone() {
        let before = MealPlanConsolidator.consolidate(meals: [
            meal("Rice and Beans", ingredients: ["2 cups white rice", "2 cans black beans"]),
            meal("Mushroom Risotto", ingredients: ["1 cup white rice", "8 oz mushrooms"]),
        ])
        let after = MealPlanConsolidator.consolidate(meals: [
            meal("Rice and Beans", ingredients: ["2 cups white rice", "2 cans black beans"]),
            // Swapped, but built from what the other dinner already needs.
            meal("Bean and Mushroom Skillet", ingredients: ["1 can black beans", "8 oz mushrooms"]),
        ])

        let change = MealPlanConsolidator.diff(before: before, after: after)
        XCTAssertTrue(change.isEmpty)
        XCTAssertNil(change.summary)
    }

    func testDiffNamesWhatEnteredAndLeftTheList() {
        let before = MealPlanConsolidator.consolidate(meals: [
            meal("A", ingredients: ["1 cup white rice", "2 carrots"]),
        ])
        let after = MealPlanConsolidator.consolidate(meals: [
            meal("A", ingredients: ["1 cup white rice", "1 head cabbage"]),
        ])

        let change = MealPlanConsolidator.diff(before: before, after: after)
        XCTAssertEqual(change.added, ["cabbage"])
        XCTAssertEqual(change.removed, ["carrots"])
        XCTAssertTrue(change.summary?.contains("cabbage") == true)
    }

    func testDiffIgnoresLinesThePantryAlreadyCovers() {
        let pantry = [PantryItem(name: "carrot")]
        let before = MealPlanConsolidator.consolidate(
            meals: [meal("A", ingredients: ["1 cup white rice", "2 carrots"])], pantry: pantry
        )
        let after = MealPlanConsolidator.consolidate(
            meals: [meal("A", ingredients: ["1 cup white rice"])], pantry: pantry
        )
        XCTAssertTrue(MealPlanConsolidator.diff(before: before, after: after).isEmpty)
    }

    // MARK: - Commit

    /// Held for the length of the test. A `ModelContainer` that goes out of
    /// scope takes its `mainContext` down with it, and the next fetch traps.
    private var container: ModelContainer!

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
            MealPlan.self, MealPlanLine.self, GroceryItem.self, PantryItem.self,
        ])
        container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return container.mainContext
    }

    private var samplePlan: WeekPlanner.Plan {
        WeekPlanner.Plan(
            request: .init(mealCount: 3, servings: 4, budgetTarget: 60),
            meals: [
                meal("Chicken and Rice", ingredients: ["2 cups white rice", "1 lb chicken thighs"]),
                meal("Rice Bowls", ingredients: ["1 cup white rice", "1 lb ground turkey"]),
                meal("Cabbage Slaw", ingredients: ["1 head cabbage", "2 carrots"]),
            ],
            sharedCore: ["white rice"]
        )
    }

    func testCommitSavesOrdinaryRecipesGroupedInACollection() throws {
        let context = try makeContext()
        let plan = samplePlan
        let lines = MealPlanConsolidator.consolidate(meals: plan.meals)

        let record = MealPlanCommitter.commit(plan, lines: lines, name: "Week of Aug 6", in: context)

        XCTAssertEqual(record.name, "Week of Aug 6")
        XCTAssertEqual(record.mealTitles.count, 3)
        XCTAssertEqual(record.collection?.recipes.count, 3)

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.count, 3)
        // Ordinary recipes: real ingredients and steps, cookable like any other.
        let chicken = recipes.first { $0.title == "Chicken and Rice" }
        XCTAssertEqual(chicken?.ingredients.count, 2)
        XCTAssertEqual(chicken?.steps.count, 2)
        XCTAssertEqual(chicken?.servings, 4)
    }

    func testCommitPushesTheListIntoGroceriesWithItsSourceMeals() throws {
        let context = try makeContext()
        let plan = samplePlan
        let lines = MealPlanConsolidator.consolidate(meals: plan.meals)

        MealPlanCommitter.commit(plan, lines: lines, name: "Week of Aug 6", in: context)

        let groceries = try context.fetch(FetchDescriptor<GroceryItem>())
        let rice = groceries.first { $0.canonicalName == "white rice" }
        XCTAssertNotNil(rice)
        // The existing Groceries screen reads this to say which meals need it.
        XCTAssertEqual(rice?.sourceRecipeTitles, ["Chicken and Rice", "Rice Bowls"])
        XCTAssertEqual(rice?.quantity, 3)
    }

    func testCommitLeavesPantryCoveredLinesOffTheGroceryList() throws {
        let context = try makeContext()
        let pantry = PantryItem(name: "white rice")
        context.insert(pantry)
        let plan = samplePlan
        let lines = MealPlanConsolidator.consolidate(meals: plan.meals, pantry: [pantry])

        MealPlanCommitter.commit(plan, lines: lines, name: "Week of Aug 6", in: context)

        let groceries = try context.fetch(FetchDescriptor<GroceryItem>())
        XCTAssertNil(groceries.first { $0.canonicalName == "white rice" })
        XCTAssertNotNil(groceries.first { $0.canonicalName == "chicken thigh" })
    }

    func testRecommittingAfterASwapUpdatesInsteadOfDuplicating() throws {
        let context = try makeContext()
        var plan = samplePlan
        MealPlanCommitter.commit(
            plan,
            lines: MealPlanConsolidator.consolidate(meals: plan.meals),
            name: "Week of Aug 6",
            in: context
        )

        // Swap the third dinner for one built from what the others already need.
        plan.meals[2] = meal("Turkey Rice Skillet", ingredients: ["1 cup white rice", "1 lb ground turkey"])
        MealPlanCommitter.commit(
            plan,
            lines: MealPlanConsolidator.consolidate(meals: plan.meals),
            name: "Week of Aug 6",
            in: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<MealPlan>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RecipeCollection>()).count, 1)

        try context.save()
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.count, 3)
        XCTAssertNil(recipes.first { $0.title == "Cabbage Slaw" })
        XCTAssertNotNil(recipes.first { $0.title == "Turkey Rice Skillet" })

        let groceries = try context.fetch(FetchDescriptor<GroceryItem>())
        // The dropped dinner's exclusive items leave, the shared ones stay once.
        XCTAssertEqual(groceries.filter { $0.canonicalName == "white rice" }.count, 1)
        XCTAssertNil(groceries.first { $0.canonicalName == "cabbage" })
    }

    func testCommitKeepsARecipeTheCookFavorited() throws {
        let context = try makeContext()
        var plan = samplePlan
        let record = MealPlanCommitter.commit(
            plan,
            lines: MealPlanConsolidator.consolidate(meals: plan.meals),
            name: "Week of Aug 6",
            in: context
        )
        let keeper = record.collection?.recipes.first { $0.title == "Cabbage Slaw" }
        keeper?.isFavorite = true

        plan.meals[2] = meal("Turkey Rice Skillet", ingredients: ["1 cup white rice", "1 lb ground turkey"])
        MealPlanCommitter.commit(
            plan,
            lines: MealPlanConsolidator.consolidate(meals: plan.meals),
            name: "Week of Aug 6",
            in: context
        )

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertNotNil(recipes.first { $0.title == "Cabbage Slaw" })
        XCTAssertEqual(record.collection?.recipes.count, 3)
    }

    func testCommitLeavesTheCooksOwnGroceryItemsAlone() throws {
        let context = try makeContext()
        let manual = GroceryItem(name: "dish soap")
        context.insert(manual)
        let plan = samplePlan

        MealPlanCommitter.commit(
            plan,
            lines: MealPlanConsolidator.consolidate(meals: plan.meals),
            name: "Week of Aug 6",
            in: context
        )
        MealPlanCommitter.commit(
            plan,
            lines: MealPlanConsolidator.consolidate(meals: plan.meals),
            name: "Week of Aug 6",
            in: context
        )

        let groceries = try context.fetch(FetchDescriptor<GroceryItem>())
        XCTAssertNotNil(groceries.first { $0.canonicalName == "dish soap" })
    }
}
