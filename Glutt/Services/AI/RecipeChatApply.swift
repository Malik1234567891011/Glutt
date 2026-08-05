import Foundation
import SwiftData

/// What happens when the cook taps Apply on a proposal.
///
/// Lives outside the view because the branch it picks is the part with
/// consequences: one path round-trips ingredients through text, the other keeps
/// them intact, and picking wrong quietly loses quantities and units. A view
/// closure is not testable in this project; this is.
enum RecipeChatApply {

    enum Outcome {
        case created(Recipe)
        /// The pantry moved on between the offer and the tap, so there is
        /// nothing left to swap. Nothing was written.
        case pantryPlanWentStale

        var recipe: Recipe? {
            if case .created(let recipe) = self { return recipe }
            return nil
        }
    }

    /// Mints the version and stamps the message as spent. The message is only
    /// stamped on success, so a stale plan leaves the card offering again.
    static func run(
        _ proposal: RecipeChatProposal,
        on message: RecipeChatMessage?,
        recipe: Recipe,
        servings: Int,
        pantry: [PantryItem],
        prefs: UserPrefs,
        context: ModelContext
    ) -> Outcome {
        let created: Recipe
        if proposal.isPantryPlan {
            // Re-planned rather than replayed: the pantry may have changed since
            // the offer, and `RecipeOptimizer.apply` preserves quantities, units,
            // notes, and optional flags that a text round trip would flatten.
            let plan = RecipeOptimizer.plan(
                for: recipe,
                pantry: pantry,
                rules: prefs.dietaryRules,
                allergies: prefs.allergies
            )
            guard plan.isWorthIt else { return .pantryPlanWentStale }
            created = RecipeOptimizer.apply(plan, to: recipe, context: context)
        } else {
            created = RecipeAdjuster.apply(
                proposal.adjustment(defaultServings: servings),
                versionLabel: proposal.versionLabel,
                to: recipe,
                context: context
            )
        }
        message?.appliedLabel = created.versionLabel ?? proposal.versionLabel
        return .created(created)
    }

    /// Shown in the thread when the plan went stale under the cook's feet.
    static let staleMessage = "Your pantry changed since I suggested that, and there's nothing left to swap."
}
