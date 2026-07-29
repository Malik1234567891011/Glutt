import Foundation

/// Resolved nutrition for a recipe at a chosen serving count — stored macros,
/// ingredient estimate, and caption/summary numbers merged with clear priority.
///
/// Stored / caption / estimate values are always **per serving**. Display totals
/// multiply by the cook's current serving stepper so the numbers match "making N".
struct RecipeNutrition: Equatable {
    /// Totals for `servings` (current display serving count).
    var calories: Int
    var proteinGrams: Int
    var carbGrams: Int?
    var fatGrams: Int?
    var fiberGrams: Int?
    /// Per-serving (one plate), before multiplying by `servings`.
    var perServingCalories: Int
    var perServingProtein: Int
    var perServingFiber: Int?
    var isEstimated: Bool
    var servings: Int

    /// Callouts based on per-serving amounts (so "high fiber" doesn't depend on batch size).
    var highlights: [Highlight] {
        var out: [Highlight] = []
        if let fiber = perServingFiber, fiber >= 8 {
            out.append(.init(label: "\(fiber)g fiber", kind: .fiber))
        }
        return out
    }

    struct Highlight: Equatable, Identifiable {
        enum Kind { case fiber, protein }
        var id: String { "\(kind)-\(label)" }
        let label: String
        let kind: Kind
    }

    /// Merge stored → caption → estimate. Returns nil when nothing usable.
    static func resolve(for recipe: Recipe, servings displayServings: Int) -> RecipeNutrition? {
        let display = max(1, displayServings)

        let captionText = [recipe.summary, recipe.sourceCaption]
            .compactMap { $0 }
            .joined(separator: "\n")
        let fromCaption = MacroCaptionParser.parse(captionText)
        let estimate = NutritionEstimator.estimate(for: recipe)

        let perCal = recipe.calories
            ?? fromCaption.calories
            ?? estimate?.calories
        let perProtein = recipe.proteinGrams
            ?? fromCaption.proteinGrams
            ?? estimate?.proteinGrams
        guard let perCal, let perProtein else { return nil }

        let perCarbs = recipe.carbGrams ?? fromCaption.carbGrams ?? estimate?.carbGrams
        let perFat = recipe.fatGrams ?? fromCaption.fatGrams ?? estimate?.fatGrams
        let perFiber = fromCaption.fiberGrams ?? estimate?.fiberGrams

        let estimatedFlag: Bool = {
            if fromCaption.calories != nil || fromCaption.proteinGrams != nil { return false }
            if recipe.calories != nil || recipe.proteinGrams != nil {
                return recipe.nutritionIsEstimated
            }
            return true
        }()

        func batch(_ per: Int) -> Int { per * display }

        return RecipeNutrition(
            calories: batch(perCal),
            proteinGrams: batch(perProtein),
            carbGrams: perCarbs.map(batch),
            fatGrams: perFat.map(batch),
            fiberGrams: perFiber.map(batch),
            perServingCalories: perCal,
            perServingProtein: perProtein,
            perServingFiber: perFiber,
            isEstimated: estimatedFlag,
            servings: display
        )
    }

    /// Persist missing cal/P/C/F onto the recipe (per serving) so the next open
    /// doesn't re-derive. Fiber stays ephemeral (no model field yet).
    static func backfillIfNeeded(recipe: Recipe) {
        guard recipe.calories == nil || recipe.proteinGrams == nil
                || recipe.carbGrams == nil || recipe.fatGrams == nil else { return }

        let caption = MacroCaptionParser.parse(
            [recipe.summary, recipe.sourceCaption].compactMap { $0 }.joined(separator: "\n")
        )
        let estimate = NutritionEstimator.estimate(for: recipe)

        if recipe.calories == nil {
            recipe.calories = caption.calories ?? estimate?.calories
        }
        if recipe.proteinGrams == nil {
            recipe.proteinGrams = caption.proteinGrams ?? estimate?.proteinGrams
        }
        if recipe.carbGrams == nil {
            recipe.carbGrams = caption.carbGrams ?? estimate?.carbGrams
        }
        if recipe.fatGrams == nil {
            recipe.fatGrams = caption.fatGrams ?? estimate?.fatGrams
        }
        if caption.calories != nil || caption.proteinGrams != nil {
            recipe.nutritionIsEstimated = false
        } else if recipe.calories != nil, estimate != nil {
            recipe.nutritionIsEstimated = true
        }
    }
}
