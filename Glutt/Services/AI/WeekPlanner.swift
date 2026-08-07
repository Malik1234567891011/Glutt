import Foundation

/// Generates a week of dinners as one set, not five separate recipes.
///
/// The whole value is the overlap. Five individually good recipes need forty
/// ingredients and three trips; the same five designed together share a grain,
/// spread their proteins, and come home in one bag. So the prompt does not ask
/// for "five dinner recipes" — it asks for a shared core first and dishes that
/// spend it.
///
/// Follows the `PantryChef.invent` shape: one JSON call, an injectable
/// `LLMClient`, and no persistence. The caller turns `Meal` values into drafts,
/// recipes, and a list.
enum WeekPlanner {

    // MARK: - Inputs

    struct Request: Equatable {
        /// How many dinners to cook. Jen's "20 healthy meals" is five recipes
        /// at four servings, not twenty dishes.
        var mealCount: Int = 5
        var servings: Int = 4
        /// Rough dollar target for the whole shop. Steers the list toward cheap
        /// staples, and is also what `estimateCost` is judged against.
        var budgetTarget: Int?
        /// How many distinct things the cook is willing to put in the trolley.
        ///
        /// The number that decides whether this feels like a quick grab or a
        /// full week's shop, and the cook is the only one who knows which they
        /// wanted. Used to be fixed at "roughly 20 to 28", which is right for
        /// five dinners and far too many for someone who asked for three meals
        /// off ten items.
        var ingredientTarget: Int = 22
        /// Things the cook wants worked into the meals, in their own words.
        ///
        /// Not the same as the pantry. The pantry means "already here, do not
        /// buy it"; this means "buy it and build a dinner around it", which is
        /// what someone means when they say they fancy salmon this week.
        var mustInclude: String = ""
        /// Free text from the setup step ("no pork", "one vegetarian night").
        var notes: String = ""

        init(
            mealCount: Int = 5,
            servings: Int = 4,
            budgetTarget: Int? = nil,
            ingredientTarget: Int = 22,
            mustInclude: String = "",
            notes: String = ""
        ) {
            self.mealCount = mealCount
            self.servings = servings
            self.budgetTarget = budgetTarget
            self.ingredientTarget = ingredientTarget
            self.mustInclude = mustInclude
            self.notes = notes
        }
    }

    /// What the shop is likely to cost, as a range.
    ///
    /// A range and never a single figure, because a single figure reads as a
    /// promise. Grocery prices move by store, city and week, and the model is
    /// working from an ingredient list rather than a till receipt, so the honest
    /// output is a band with the uncertainty stated in the UI next to it.
    struct CostEstimate: Equatable {
        var low: Int
        var high: Int

        /// "$52 to $68"
        var range: String { "$\(low) to $\(high)" }
    }

    // MARK: - Outputs

    /// One dinner. A value type so a plan can be swapped and re-consolidated
    /// without touching SwiftData.
    struct Meal: Equatable, Identifiable {
        var id = UUID()
        var title: String
        var summary: String?
        var servings: Int
        var prepMinutes: Int
        var cookMinutes: Int
        var ingredientLines: [String]
        var stepTexts: [String]
        var tags: [String] = []

        /// Ready for `RecipeFactory.make(from:)`, so a planned meal becomes an
        /// ordinary library recipe by the same path as an import.
        var draft: ImportedRecipeDraft {
            var draft = ImportedRecipeDraft()
            draft.title = title
            draft.summary = summary
            draft.creator = "Glutt"
            draft.platform = .manual
            draft.servings = servings
            draft.prepMinutes = prepMinutes
            draft.cookMinutes = cookMinutes
            draft.ingredientLines = ingredientLines
            draft.stepTexts = stepTexts
            draft.tags = tags
            draft.isAIGenerated = true
            return draft
        }
    }

    struct Plan: Equatable, Identifiable {
        var id = UUID()
        var request: Request
        var meals: [Meal]
        /// The ingredients the set was built to share, as the model named them.
        /// Shown as the reason the list is short, and used to constrain a swap.
        var sharedCore: [String]
        /// Filled in by `estimateCost`, and cleared whenever the meals change so
        /// a stale number can never be shown against a list it does not match.
        var cost: CostEstimate?

        /// Every canonical ingredient any meal calls for. A swap is held to
        /// this pool, which is what keeps the shopping list still.
        var ingredientPool: [String] {
            var seen = Set<String>()
            var pool: [String] = []
            for meal in meals {
                for line in meal.ingredientLines {
                    let name = IngredientLineParser.parse(line).name
                    let canonical = IngredientCanonicalizer.canonicalize(name)
                    guard !canonical.isEmpty, seen.insert(canonical).inserted else { continue }
                    pool.append(name)
                }
            }
            return pool
        }
    }

    enum PlanError: LocalizedError, Equatable {
        case notConfigured
        case failed

        var errorDescription: String? {
            switch self {
            case .notConfigured: "AI isn’t available in this build."
            case .failed: "Couldn’t plan the week just now. Try again in a moment."
            }
        }
    }

    // MARK: - Wire shape

    private struct Response: Decodable {
        struct Dish: Decodable {
            var title: String?
            var summary: String?
            var servings: Int?
            var prepMinutes: Int?
            var cookMinutes: Int?
            var ingredients: [String]?
            var steps: [String]?
            var tags: [String]?
        }

        var sharedCore: [String]?
        var meals: [Dish]?
    }

    // MARK: - Generate

    /// One overlap-constrained pass. Returns `mealCount` dinners built to share
    /// a core, or throws.
    static func generate(
        request: Request,
        pantry: [PantryItem] = [],
        prefs: UserPrefs? = nil,
        client: LLMClient = .live
    ) async throws -> Plan {
        guard client.isConfigured else { throw PlanError.notConfigured }

        let response = try await call(
            system: generateSystem(request),
            user: generateUser(request, pantry: pantry, prefs: prefs),
            temperature: 0.7,
            client: client
        )
        let meals = decodeMeals(response, request: request)
        guard meals.count >= 2 else { throw PlanError.failed }
        return Plan(request: request, meals: meals, sharedCore: cleanCore(response.sharedCore))
    }

    // MARK: - Swap one meal

    /// Regenerates a single slot **inside the ingredient pool the other meals
    /// already established**, so the shopping list barely moves.
    ///
    /// This is the invariant the feature rests on. A swap that reshuffles the
    /// groceries means the cook has to shop again, and then there was no point
    /// planning the week as a set. The pool is a hard constraint in the prompt,
    /// and `MealPlanConsolidator.diff` reports whatever still changed.
    static func swap(
        mealAt index: Int,
        in plan: Plan,
        hint: String = "",
        pantry: [PantryItem] = [],
        prefs: UserPrefs? = nil,
        client: LLMClient = .live
    ) async throws -> Plan {
        guard client.isConfigured else { throw PlanError.notConfigured }
        guard plan.meals.indices.contains(index) else { throw PlanError.failed }

        let keepers = plan.meals.enumerated().filter { $0.offset != index }.map(\.element)
        let pool = Plan(request: plan.request, meals: keepers, sharedCore: plan.sharedCore).ingredientPool

        let system = """
        You are Glutt, planning one week of dinners bought in a single shop. The cook wants to \
        replace ONE dinner. The other dinners are already decided and the groceries are already \
        settled, so your replacement must be cookable from the SAME ingredients.

        Return JSON only:
        {"meals": [{"title": str, "summary": str, "servings": int, "prepMinutes": int,
                    "cookMinutes": int, "ingredients": [str], "steps": [str], "tags": [str]}]}

        Exactly ONE dish in "meals".

        HARD CONSTRAINT — the shopping list must not change:
        - Use ONLY ingredients from the ALLOWED POOL below, plus basic staples \
          (salt, pepper, cooking oil, water, common dried spices) which are never on the list.
        - Do NOT introduce any other ingredient, however small. A single new item means \
          another trip to the shop, which defeats the whole plan.
        - You do not have to use all of them. Pick the ones that make one good dish.
        - Amounts may differ from the other dishes; the items may not.

        Also:
        - Make it CLEARLY different from the dishes being kept: different cooking method, \
          different shape of meal, different flavour direction.
        - Do not repeat the main protein of the dish immediately before or after it in the week.
        - ingredients: "quantity unit ingredient" per line, realistic home amounts for the serving count.
        - steps: clear imperative sentences, one action per step, in order.
        - tags: up to 5 lowercase tags.
        - Honest appetizing name, no hype.
        """

        var user = "SERVINGS PER DISH: \(plan.request.servings)"
        user += "\n\nALLOWED POOL (the only shoppable ingredients you may use):\n"
        user += pool.map { "- \($0)" }.joined(separator: "\n")
        user += "\n\nDISHES BEING KEPT (do not repeat these):\n"
        user += keepers.map { "- \($0.title)" }.joined(separator: "\n")
        user += "\n\nDISH BEING REPLACED (make something clearly different): "
            + plan.meals[index].title
        user += preferenceBlock(pantry: [], prefs: prefs)
        if !hint.trimmingCharacters(in: .whitespaces).isEmpty {
            user += "\nThe cook asked for: \"\(hint.trimmingCharacters(in: .whitespaces))\""
        }
        if !plan.request.notes.trimmingCharacters(in: .whitespaces).isEmpty {
            user += "\nPLAN NOTES (still apply): \(plan.request.notes)"
        }
        user += "\nVariation seed: \(Int.random(in: 1000...9999))."

        let response = try await call(system: system, user: user, temperature: 0.85, client: client)
        guard let replacement = decodeMeals(response, request: plan.request).first else {
            throw PlanError.failed
        }

        var updated = plan
        updated.meals[index] = replacement
        // A swap is held to the existing pool, so the list barely moves and the
        // old figure is probably still about right. "Probably about right" is
        // not good enough to show as a price, so it is dropped and re-estimated.
        updated.cost = nil
        return updated
    }

    // MARK: - Refine the whole plan

    /// Free-text refinement against the whole week ("less chicken", "make one
    /// vegetarian"). Unlike a swap this is allowed to move the list, because
    /// that is what the cook asked for. The shared core is still enforced, and
    /// the current ingredients are offered as a strong preference so the plan
    /// shifts rather than restarts.
    static func refine(
        _ plan: Plan,
        instruction: String,
        pantry: [PantryItem] = [],
        prefs: UserPrefs? = nil,
        client: LLMClient = .live
    ) async throws -> Plan {
        guard client.isConfigured else { throw PlanError.notConfigured }
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlanError.failed }

        var user = generateUser(plan.request, pantry: pantry, prefs: prefs)
        user += "\n\nTHE CURRENT PLAN:\n"
        user += plan.meals.enumerated()
            .map { "\($0.offset + 1). \($0.element.title)" }
            .joined(separator: "\n")
        user += "\n\nCURRENT INGREDIENTS (keep as many as you can, so the shop barely changes):\n"
        user += plan.ingredientPool.map { "- \($0)" }.joined(separator: "\n")
        user += "\n\nTHE COOK ASKED FOR: \"\(trimmed)\""
        user += "\nChange only what that asks for. Keep every dish it does not touch as it is, "
        user += "including its title, and keep the shared core intact."

        let response = try await call(
            system: generateSystem(plan.request),
            user: user,
            temperature: 0.6,
            client: client
        )
        let meals = decodeMeals(response, request: plan.request)
        guard meals.count >= 2 else { throw PlanError.failed }
        var updated = plan
        updated.meals = meals
        updated.sharedCore = cleanCore(response.sharedCore).isEmpty
            ? plan.sharedCore
            : cleanCore(response.sharedCore)
        // A refine is allowed to move the groceries, so the old figure is not
        // just stale, it is wrong.
        updated.cost = nil
        return updated
    }

    // MARK: - What it costs

    /// Price the finished shopping list, as a range.
    ///
    /// A separate pass on purpose. The generating call is busy inventing recipes
    /// and has every incentive to report whatever total it was given as a
    /// budget; this one is shown only the items and asked what they cost, which
    /// is a question it can answer on its own terms and be wrong about
    /// visibly rather than invisibly.
    ///
    /// Never throws. A missing estimate is a fine outcome and the UI simply
    /// shows no figure, whereas a failed estimate must not cost the cook their
    /// meal plan.
    /// `shoppingList` is what the cook will actually put in the trolley, which
    /// is **not** the same as the plan's ingredients: anything the pantry
    /// already covers has been dropped by `MealPlanConsolidator`. Pricing the
    /// full ingredient pool instead was measurably wrong, and wrong in the
    /// direction that matters. A run planning four dinners showed "7 items for
    /// the whole week" beside "roughly $55 to $75", where the figure had quietly
    /// charged for the chicken, rice and eggs already in the kitchen.
    static func estimateCost(
        for plan: Plan,
        shoppingList: [String],
        client: LLMClient = .live
    ) async -> CostEstimate? {
        guard client.isConfigured else { return nil }
        let items = shoppingList.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty else { return nil }

        let system = """
        You estimate what a bag of groceries costs at an ordinary supermarket in the United States, \
        at 2026 prices.

        Return JSON only: {"low": int, "high": int}

        - Whole numbers of dollars for the WHOLE list, not per item.
        - "low" is a discount supermarket and store brands. "high" is a pricier chain and name \
          brands. The gap between them is real: 25 to 40 percent is normal for groceries.
        - Price the quantity a home cook actually buys. A recipe wanting two tablespoons of soy \
          sauce still costs a whole bottle if they have none, but rice, oil and spices are bought \
          once and last months, so charge a fraction of the pack for those.
        - Salt, pepper, water and common dried spices are free; assume they are already owned.
        - Do not pad the estimate to match any number you may have been told before. If the list \
          is cheap, say so.
        """

        var user = "SHOPPING LIST (\(items.count) items, feeding "
        user += "\(plan.request.servings) people across \(plan.meals.count) dinners):\n"
        user += items.map { "- \($0)" }.joined(separator: "\n")

        do {
            let response = try await client.chatJSON(
                CostResponse.self,
                system: system,
                user: user,
                temperature: 0.2,
                feature: "week-plan-cost",
                timeout: 30
            )
            guard let low = response.low, let high = response.high, low > 0, high > 0 else {
                return nil
            }
            // The model occasionally returns them the wrong way round, and a
            // range that reads "$70 to $52" destroys trust in the whole screen.
            return CostEstimate(low: min(low, high), high: max(low, high))
        } catch {
            return nil
        }
    }

    private struct CostResponse: Decodable {
        var low: Int?
        var high: Int?
    }

    // MARK: - Prompt building

    private static func generateSystem(_ request: Request) -> String {
        """
        You are Glutt, planning \(request.mealCount) dinners that one person buys in a SINGLE \
        grocery shop and cooks across a week. Each dish serves \(request.servings) and is cooked \
        once, so the week is \(request.mealCount * request.servings) meals from \
        \(request.mealCount) recipes.

        Return JSON only:
        {"sharedCore": [str],
         "meals": [{"title": str, "summary": str, "servings": int, "prepMinutes": int,
                    "cookMinutes": int, "ingredients": [str], "steps": [str], "tags": [str]}]}

        Exactly \(request.mealCount) dishes in "meals".

        THE POINT IS THE OVERLAP. \(request.mealCount) individually good recipes need forty \
        ingredients and the cook gives up. Design them as one set:
        - Pick the shared core FIRST and list it in "sharedCore": one starch or grain that carries \
          most of the dishes, two or three cheap bulk vegetables, one or two pantry sauces. Then \
          write dishes that spend it.
        - Every non-staple ingredient should earn its place. Prefer an ingredient that appears in \
          two or three dishes over one that appears in a single dish.
        - An ingredient bought in one form gets used in one form. Do not ask for both a whole \
          chicken and chicken thighs, or both fresh and canned tomatoes.

        THE SHOPPING LIST MUST BE AT MOST \(request.ingredientTarget) DISTINCT ITEMS for all \
        \(request.mealCount) dishes together. This is a hard ceiling the cook chose, not a \
        suggestion. Salt, pepper, cooking oil, water and common dried spices do not count toward \
        it. Everything else does, counted once no matter how many dishes use it. If you cannot fit \
        \(request.mealCount) dishes inside it, make the dishes share more, not the list longer.

        MAKE THEM DIFFERENT KINDS OF DINNER. Same ingredients, genuinely different meals. Do not \
        return \(request.mealCount) variations on a theme: a stir fry, tacos, a noodle bowl, a \
        soup, a tray bake and a rice bowl can all come out of the same bag of groceries, and that \
        contrast is the entire point. Vary three things at once:
        - The FORM of the dish. Noodles, tacos or wraps, stir fry, soup or stew, tray bake, \
          rice bowl, pasta, salad with something warm in it.
        - The FLAVOUR direction, so one night does not taste like the last.
        - The COOKING METHOD. One sheet pan, one skillet, one pot.
        Also order them so the same main protein never lands two nights running, and no protein \
        carries more than two of the dishes.

        MONEY. Reach for what is cheap in any supermarket: rice, pasta, potatoes, dried or canned \
        beans and lentils, eggs, chicken thighs, ground turkey, cabbage, carrots, onions, frozen \
        vegetables. Skip anything specialty, out of season, or sold in a tiny jar. Do not write a \
        price or a total into any field you return here; the cost is estimated separately.

        Also:
        - ingredients: "quantity unit ingredient" per line, realistic amounts scaled to \
          \(request.servings) servings.
        - steps: clear imperative sentences, one action per step, in order. Real weeknight cooking.
        - tags: up to 5 lowercase tags.
        - Honest, appetizing dish names, no hype.
        - servings must equal \(request.servings) for every dish.
        """
    }

    private static func generateUser(
        _ request: Request,
        pantry: [PantryItem],
        prefs: UserPrefs?
    ) -> String {
        var user = "DINNERS TO PLAN: \(request.mealCount)"
        user += "\nSERVINGS PER DISH: \(request.servings)"
        user += "\nSHOPPING LIST CEILING: \(request.ingredientTarget) distinct items, all dishes combined."
        if let budget = request.budgetTarget, budget > 0 {
            // Shapes the list. Not echoed back here: the figure the cook sees
            // comes from `estimateCost`, priced against the finished list rather
            // than asserted by the same call that invented the recipes.
            user += "\nBUDGET FOR THE WHOLE SHOP: about $\(budget)."
            user += " Use it to decide how generous the ingredients can be. Do NOT mention it,"
            user += " and do NOT return any price or total anywhere."
        }
        if !request.mustInclude.trimmingCharacters(in: .whitespaces).isEmpty {
            user += "\nMUST INCLUDE (the cook specifically wants these, build dishes around them "
            user += "and put them on the list): "
            user += request.mustInclude.trimmingCharacters(in: .whitespaces)
        }
        user += preferenceBlock(pantry: pantry, prefs: prefs)
        if !request.notes.trimmingCharacters(in: .whitespaces).isEmpty {
            user += "\nTHE COOK ALSO SAID: \"\(request.notes.trimmingCharacters(in: .whitespaces))\""
        }
        user += "\nVariation seed: \(Int.random(in: 1000...9999))."
        return user
    }

    /// Diet, allergies, dislikes, taste, and what is already in the kitchen.
    /// Shared by generate / swap / refine so a swapped dish honours the same
    /// rules the original five did.
    private static func preferenceBlock(pantry: [PantryItem], prefs: UserPrefs?) -> String {
        var block = ""
        if let prefs {
            if !prefs.dietaryRules.isEmpty {
                block += "\nDIETARY RULES (must respect): "
                    + prefs.dietaryRules.map(\.label).joined(separator: ", ")
            }
            if !prefs.allergies.isEmpty {
                block += "\nALLERGIES (never include, in any dish): "
                    + prefs.allergies.joined(separator: ", ")
            }
            if !prefs.dislikedIngredients.isEmpty {
                block += "\nDISLIKES (avoid): " + prefs.dislikedIngredients.joined(separator: ", ")
            }
            if !prefs.tasteProfile.isEmpty {
                block += "\nTASTES THEY LIKE: "
                    + prefs.tasteProfile.prefix(8).joined(separator: ", ")
            }
        }
        let onHand = pantry.filter { $0.roughQuantity != .out }.map(\.name)
        if !onHand.isEmpty {
            block += "\nALREADY IN THE KITCHEN (lean on these, they cost nothing): "
                + onHand.prefix(40).joined(separator: ", ")
        }
        return block
    }

    // MARK: - Decoding

    private static func call(
        system: String,
        user: String,
        temperature: Double,
        client: LLMClient
    ) async throws -> Response {
        do {
            return try await client.chatJSON(
                Response.self,
                system: system,
                user: user,
                temperature: temperature,
                feature: "week-planner",
                // Five recipes in one response is a long generation.
                timeout: 90
            )
        } catch {
            throw PlanError.failed
        }
    }

    private static func decodeMeals(_ response: Response, request: Request) -> [Meal] {
        (response.meals ?? []).compactMap { dish -> Meal? in
            let title = (dish.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ingredients = clean(dish.ingredients)
            let steps = clean(dish.steps)
            guard !title.isEmpty, !ingredients.isEmpty, !steps.isEmpty else { return nil }
            return Meal(
                title: title,
                summary: dish.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                servings: max(1, dish.servings ?? request.servings),
                prepMinutes: max(0, dish.prepMinutes ?? 0),
                cookMinutes: max(0, dish.cookMinutes ?? 0),
                ingredientLines: ingredients,
                stepTexts: steps,
                tags: Array(clean(dish.tags).map { $0.lowercased() }.prefix(5))
            )
        }
    }

    private static func clean(_ lines: [String]?) -> [String] {
        (lines ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func cleanCore(_ core: [String]?) -> [String] {
        Array(clean(core).prefix(8))
    }
}
