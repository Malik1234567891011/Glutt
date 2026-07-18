import Foundation

/// Invents a brand-new recipe from what's actually in the user's kitchen —
/// not a match against saved recipes, an original dish built around their
/// on-hand ingredients. Result is returned as a draft so it flows through the
/// normal review → edit → save screen (and is labeled as Glutt-invented).
enum PantryChef {

    private struct Invented: Decodable {
        var title: String?
        var summary: String?
        var servings: Int?
        var prepMinutes: Int?
        var cookMinutes: Int?
        var ingredients: [String]?
        var steps: [String]?
        var tags: [String]?
    }

    /// `nil` when AI is off, there's nothing to cook with, or the call fails.
    /// - Parameters:
    ///   - mealType: bias the dish toward breakfast/lunch/dinner/snack (nil = any).
    ///   - avoidTitles: dishes already shown this session — the model is told to
    ///     make something clearly different, so "Something else" never repeats.
    static func invent(
        pantry: [PantryItem],
        prefs: UserPrefs,
        hint: String? = nil,
        maxMinutes: Int? = nil,
        mealType: MealType? = nil,
        avoidTitles: [String] = [],
        client: LLMClient = .live
    ) async -> ImportedRecipeDraft? {
        guard client.isConfigured else { return nil }

        let onHand = pantry.filter { $0.roughQuantity != .out }
        guard onHand.count >= 2 else { return nil }

        let useSoon = onHand.filter { $0.useSoonDate != nil }.map(\.name)
        let haveList = onHand.map { item -> String in
            var line = item.name
            if item.roughQuantity == .low { line += " (almost out)" }
            return line
        }.joined(separator: ", ")

        let system = """
        You are Glutt, a resourceful home cook. Invent ONE original, realistic recipe built
        around the ingredients the user already has. This is creation, not retrieval.

        Return JSON only:
        {"title": str, "summary": str, "servings": int, "prepMinutes": int, "cookMinutes": int,
         "ingredients": [str], "steps": [str], "tags": [str]}

        Rules:
        - Build the dish primarily from the ON-HAND ingredients. You may assume basic staples
          (salt, pepper, cooking oil, water, common dried spices) without listing them as missing.
        - It's fine to use only SOME of the on-hand items — make something that actually tastes good,
          not a kitchen-sink dish. Prefer using anything marked "needs using soon".
        - Do NOT require a major ingredient the user doesn't have. If you add one small optional
          extra, mark it "(optional)".
        - ingredients: "quantity unit ingredient" per line, realistic home amounts.
        - steps: clear imperative sentences, one action per step, in order.
        - tags: up to 5 lowercase tags.
        - Give it an appetizing but honest name (no hype).
        - servings: estimate the realistic number of adult servings from the amounts you use; don't default to 2.
        """

        var user = "ON-HAND INGREDIENTS: \(haveList)"
        if !useSoon.isEmpty {
            user += "\nNEEDS USING SOON: \(useSoon.joined(separator: ", "))"
        }
        if let mealType {
            user += "\nThis must work as a \(mealType.label.uppercased()) dish."
        }
        if let maxMinutes {
            user += "\nMUST be ready in about \(maxMinutes) minutes or less."
        }
        if !prefs.dietaryRules.isEmpty {
            user += "\nDIETARY RULES (must respect): \(prefs.dietaryRules.map(\.label).joined(separator: ", "))"
        }
        if !prefs.allergies.isEmpty {
            user += "\nALLERGIES (never include): \(prefs.allergies.joined(separator: ", "))"
        }
        if !prefs.dislikedIngredients.isEmpty {
            user += "\nDISLIKES (avoid): \(prefs.dislikedIngredients.joined(separator: ", "))"
        }
        if let hint, !hint.trimmingCharacters(in: .whitespaces).isEmpty {
            user += "\nThe user also said: \"\(hint)\""
        }
        if !avoidTitles.isEmpty {
            user += "\nDo NOT suggest any of these — you already proposed them: "
                + avoidTitles.joined(separator: ", ")
                + ". Make something CLEARLY different: change the cuisine, the cooking method, or the main ingredient."
        }
        // A per-call seed nudges the model off its default answer so repeated
        // taps on "Something else" actually vary, even with the same pantry.
        user += "\nVariation seed: \(Int.random(in: 1000...9999))."

        do {
            let result = try await client.chatJSON(
                Invented.self,
                system: system,
                user: user,
                temperature: avoidTitles.isEmpty ? 0.8 : 0.95,
                timeout: 25
            )
            guard let ingredients = result.ingredients, !ingredients.isEmpty,
                  let steps = result.steps, !steps.isEmpty
            else { return nil }

            var draft = ImportedRecipeDraft()
            draft.title = result.title
            draft.summary = result.summary
            draft.creator = "Glutt"
            draft.platform = .manual
            draft.servings = result.servings
            draft.prepMinutes = result.prepMinutes
            draft.cookMinutes = result.cookMinutes
            draft.ingredientLines = ingredients
            draft.stepTexts = steps
            draft.tags = Array((result.tags ?? []).map { $0.lowercased() }.prefix(6))
            draft.isAIGenerated = true
            return draft
        } catch {
            return nil
        }
    }
}
