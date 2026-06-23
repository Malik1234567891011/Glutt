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

    struct Adjustment: Decodable {
        /// Ingredient lines as plain text ("2 tbsp olive oil") — parsed on apply.
        let ingredients: [String]
        let steps: [String]
        /// Human-readable change list ("Swapped cream for Greek yogurt (−180 cal)").
        let changes: [String]
        let summary: String?
    }

    static func adjust(
        recipe: Recipe,
        goal: Goal,
        rules: [DietaryRule],
        allergies: [String]
    ) async throws -> Adjustment {
        let system = """
        You adjust home recipes toward a goal. Return JSON only:
        {"ingredients": ["2 tbsp olive oil", ...], "steps": ["...", ...],
         "changes": ["short explanation of each change", ...], "summary": "one sentence"}

        Rules:
        - Keep the dish recognizable; this is an adjustment, not a new recipe.
        - Keep the SAME number of servings as the original, so amounts stay comparable.
        - ingredients: complete final list, one per line, quantities included.
        - steps: the complete final method, updated where changes matter.
        - changes: 2-6 short bullets a home cook understands.
        - Never include anything that violates the dietary rules or allergies listed.
        """

        var user = "GOAL: \(goal.instruction)\n\n"
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

        let adjustment = try await LLMClient.chatJSON(
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
        goal: Goal,
        to recipe: Recipe,
        context: ModelContext
    ) -> Recipe {
        let copy = Recipe(
            title: recipe.title,
            summary: adjustment.summary ?? recipe.summary,
            sourceCreator: recipe.sourceCreator,
            sourceURL: recipe.sourceURL,
            sourcePlatform: recipe.sourcePlatform,
            servings: recipe.servings,
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
        copy.versionLabel = goal.versionLabel
        context.insert(copy)
        return copy
    }
}
