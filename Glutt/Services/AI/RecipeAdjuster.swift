import Foundation
import SwiftData

/// One-tap recipe adjustment: "make this higher protein / lighter / cheaper /
/// match my food rules". LLM-powered; results save as versions so the
/// original is never touched. Requires AI (hidden in UI when unconfigured).
enum RecipeAdjuster {

    enum Goal: String, CaseIterable, Identifiable {
        case higherProtein
        case lighter
        case cheaper
        case foodRules

        var id: String { rawValue }

        var label: String {
            switch self {
            case .higherProtein: "Higher protein"
            case .lighter: "Lighter"
            case .cheaper: "Cheaper"
            case .foodRules: "Match my food rules"
            }
        }

        var icon: String {
            switch self {
            case .higherProtein: "dumbbell"
            case .lighter: "leaf"
            case .cheaper: "dollarsign.circle"
            case .foodRules: "checkmark.shield"
            }
        }

        var versionLabel: String {
            switch self {
            case .higherProtein: "High-protein version"
            case .lighter: "Lighter version"
            case .cheaper: "Budget version"
            case .foodRules: "My-rules version"
            }
        }

        fileprivate var instruction: String {
            switch self {
            case .higherProtein:
                "Increase protein meaningfully (aim ~40g+ per serving) using the SIMPLEST change that works — usually adding more of the protein the dish already has (e.g. another chicken breast, an extra ½ lb of beef) or one clean high-protein addition (Greek yogurt, eggs, cottage cheese, beans). Prefer a single obvious move over many small swaps. Keep it tasting like the same dish. In 'changes', name the concrete addition plainly (e.g. 'Add 1 more chicken breast')."
            case .lighter:
                "Reduce calories noticeably (lighter cooking methods, less oil/sugar/cream, more vegetables). Keep it satisfying — no sad food."
            case .cheaper:
                "Reduce cost: swap expensive ingredients for affordable ones, prefer pantry staples, keep flavor. Mention rough savings in the changes."
            case .foodRules:
                "Rewrite the recipe so it fully complies with the user's dietary rules and allergies listed below. Substitute, don't just delete — the dish must stay complete."
            }
        }
    }

    /// A concrete adjustment request — either a one-tap preset goal or the
    /// cook's own free-text ask ("use 2.4 lb chicken breast instead of thighs").
    struct Request {
        enum Kind: Equatable {
            case preset(Goal)
            case custom(String)
        }

        let kind: Kind

        static func preset(_ goal: Goal) -> Request { Request(kind: .preset(goal)) }
        static func custom(_ text: String) -> Request { Request(kind: .custom(text)) }

        var instruction: String {
            switch kind {
            case .preset(let goal): goal.instruction
            case .custom(let text): Request.customInstruction(text)
            }
        }

        /// Label used for the saved version.
        var versionLabel: String {
            switch kind {
            case .preset(let goal): goal.versionLabel
            case .custom: "Custom version"
            }
        }

        /// Human phrase for the "Rewriting for …" progress line.
        var displayName: String {
            switch kind {
            case .preset(let goal): goal.label.lowercased()
            case .custom: "your request"
            }
        }

        /// Presets keep servings fixed so the before/after macros stay comparable.
        /// A free-text ask may legitimately change the yield (e.g. "double the chicken").
        var allowsServingsChange: Bool {
            if case .custom = kind { return true }
            return false
        }

        /// Wraps the cook's own words in chef-grade guidance so the model swaps
        /// and scales like a real cook rather than a find-and-replace.
        private static func customInstruction(_ request: String) -> String {
            """
            The cook wants this specific change, in their own words:
            "\(request)"

            Interpret it like an expert chef and apply it faithfully:
            - If they swap an ingredient or change its amount (a different cut or protein,
              "2.4 lb chicken breast instead of the thighs", "half the rice"), make that exact
              change and SCALE the supporting ingredients — marinade, sauce, oil, seasoning,
              liquid — proportionally to the new main-ingredient amount so the ratios stay
              balanced. Never leave a sauce sized for the old quantity.
            - Respect their units and amounts as given; convert sensibly (lb ↔ g, cups ↔ g) and
              keep the converted amount in the ingredient line.
            - Account for the REAL differences between ingredients, not just the name. Example:
              chicken breast is leaner and drier than thigh — it cooks faster, overcooks easily,
              and wants slightly more fat or a shorter, gentler cook; adjust the method, times,
              temperatures, and seasoning to match. Do the equivalent reasoning for any swap.
            - Food safety is non-negotiable: give correct doneness cues/temperatures for the NEW
              ingredient (e.g. chicken to 165°F / 74°C).
            - When an amount or time is your judgement rather than certain, hedge in the change
              note ("about", "roughly") — never present a guess as exact.
            If the request isn't about cooking or is impossible, do the closest sensible thing and
            say what you assumed in the summary.
            """
        }
    }

    struct Adjustment: Decodable {
        /// Ingredient lines as plain text ("2 tbsp olive oil") — parsed on apply.
        let ingredients: [String]
        let steps: [String]
        /// Human-readable change list ("Swapped cream for Greek yogurt (−180 cal)").
        let changes: [String]
        let summary: String?
        /// New yield when the change alters how many it feeds; nil keeps the original.
        let servings: Int?
    }

    static func adjust(
        recipe: Recipe,
        request: Request,
        rules: [DietaryRule],
        allergies: [String],
        client: LLMClient = .live
    ) async throws -> Adjustment {
        let servingsRule = request.allowsServingsChange
            ? "Keep the original \(recipe.servings) servings UNLESS the change clearly alters how many it feeds; if it does, set \"servings\" to the new count."
            : "Keep the SAME number of servings as the original (\(recipe.servings)), so amounts stay comparable, and omit the \"servings\" field."

        let system = """
        You adjust home recipes toward a goal. Return JSON only:
        {"ingredients": ["2 tbsp olive oil", ...], "steps": ["...", ...],
         "changes": ["short explanation of each change", ...], "summary": "one sentence",
         "servings": 4}

        Rules:
        - Keep the dish recognizable; this is an adjustment, not a new recipe.
        - \(servingsRule)
        - ingredients: complete final list, one per line, quantities included.
        - steps: the complete final method, updated where changes matter.
        - changes: 2-6 short bullets a home cook understands.
        - Never include anything that violates the dietary rules or allergies listed.
        """

        var user = "GOAL: \(request.instruction)\n\n"
        if !rules.isEmpty {
            user += "User's dietary rules: \(rules.map(\.label).joined(separator: ", "))\n"
        }
        if !allergies.isEmpty {
            user += "User's allergies (NEVER include): \(allergies.joined(separator: ", "))\n"
        }
        user += "\nRECIPE: \(recipe.title) (serves \(recipe.servings))\n"
        user += "INGREDIENTS:\n"
        for ingredient in recipe.ingredients.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            var line = "- "
            if let quantity = ingredient.quantity { line += "\(quantity.formatted()) " }
            if let unit = ingredient.unit { line += "\(unit) " }
            line += ingredient.name
            user += line + "\n"
        }
        user += "STEPS:\n"
        for step in recipe.sortedSteps {
            user += "\(step.index + 1). \(step.text)\n"
        }

        let adjustment = try await client.chatJSON(
            Adjustment.self,
            system: system,
            user: String(user.prefix(8000)),
            temperature: 0.4
        )
        guard !adjustment.ingredients.isEmpty, !adjustment.steps.isEmpty else {
            throw LLMClient.LLMError.badResponse("Empty adjustment")
        }
        return adjustment
    }

    /// Saves an adjustment as a recipe version. Original untouched.
    @discardableResult
    static func apply(
        _ adjustment: Adjustment,
        versionLabel: String,
        to recipe: Recipe,
        context: ModelContext
    ) -> Recipe {
        let copy = Recipe(
            title: recipe.title,
            summary: adjustment.summary ?? recipe.summary,
            sourceCreator: recipe.sourceCreator,
            sourceURL: recipe.sourceURL,
            sourcePlatform: recipe.sourcePlatform,
            servings: adjustment.servings ?? recipe.servings,
            prepMinutes: recipe.prepMinutes,
            cookMinutes: recipe.cookMinutes,
            difficulty: recipe.difficulty,
            tags: recipe.tags
        )
        copy.imageAssetName = recipe.imageAssetName
        copy.imageData = recipe.imageData
        copy.imageURL = recipe.imageURL

        copy.ingredients = adjustment.ingredients.enumerated().map { index, line in
            let parsed = IngredientLineParser.parse(line)
            return RecipeIngredient(
                name: parsed.name,
                quantity: parsed.quantity,
                unit: parsed.unit,
                sortIndex: index
            )
        }
        copy.steps = adjustment.steps.enumerated().map { index, text in
            RecipeStep(index: index, text: text)
        }
        copy.notes = adjustment.changes.map { "• \($0)" }.joined(separator: "\n")
        copy.parentRecipe = recipe.parentRecipe ?? recipe
        copy.versionLabel = versionLabel
        context.insert(copy)
        return copy
    }
}
