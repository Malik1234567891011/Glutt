import Foundation
import SwiftData

/// "Optimize for what I have": adapts a recipe to the user's actual pantry
/// with explained substitutions. Heuristic table first; an LLM (if configured)
/// can refine the explanations later. The original recipe is never touched —
/// the result saves as a version.
enum RecipeOptimizer {

    struct Swap: Identifiable {
        let id = UUID()
        let original: RecipeIngredient
        let substituteName: String
        let reason: String
    }

    struct Plan {
        var swaps: [Swap] = []
        /// Missing with no pantry-available substitute.
        var unresolved: [RecipeIngredient] = []
        /// Essential ingredients we refuse to swap (taste would change too much).
        var essentialWarnings: [RecipeIngredient] = []

        var isWorthIt: Bool { !swaps.isEmpty }
    }

    static func plan(for recipe: Recipe, pantry: [PantryItem]) -> Plan {
        var plan = Plan()
        let match = PantryMatcher.match(recipe: recipe, pantry: pantry)

        for ingredient in match.missing {
            let canonical = ingredient.canonicalName

            if SubstitutionService.isEssential(canonical) {
                plan.essentialWarnings.append(ingredient)
                continue
            }

            let available = SubstitutionService.availableSubstitutions(for: canonical, pantry: pantry)
            if let best = available.first {
                plan.swaps.append(Swap(
                    original: ingredient,
                    substituteName: best.name,
                    reason: best.explanation
                ))
            } else {
                plan.unresolved.append(ingredient)
            }
        }
        return plan
    }

    /// Applies a plan as a new recipe version ("Pantry version"). Original untouched.
    @discardableResult
    static func apply(_ plan: Plan, to recipe: Recipe, context: ModelContext) -> Recipe {
        let copy = Recipe(
            title: recipe.title,
            summary: recipe.summary,
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

        copy.ingredients = recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }.map { ingredient in
            if let swap = plan.swaps.first(where: { $0.original === ingredient }) {
                return RecipeIngredient(
                    name: swap.substituteName,
                    quantity: ingredient.quantity,
                    unit: ingredient.unit,
                    note: "swapped in for \(ingredient.name)",
                    isOptional: ingredient.isOptional,
                    role: ingredient.role,
                    sortIndex: ingredient.sortIndex
                )
            }
            return RecipeIngredient(
                name: ingredient.name,
                quantity: ingredient.quantity,
                unit: ingredient.unit,
                note: ingredient.note,
                isOptional: ingredient.isOptional,
                role: ingredient.role,
                sortIndex: ingredient.sortIndex
            )
        }
        copy.steps = recipe.sortedSteps.map {
            RecipeStep(index: $0.index, text: $0.text, durationSeconds: $0.durationSeconds)
        }
        copy.parentRecipe = recipe.parentRecipe ?? recipe
        copy.versionLabel = "Pantry version"
        context.insert(copy)
        return copy
    }
}
