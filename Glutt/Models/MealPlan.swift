import Foundation
import SwiftData

/// One week of dinners bought in a single shop: five recipes generated together
/// so they share a core of ingredients, plus the consolidated list that shop
/// produces.
///
/// Deliberately **not** a silo. The meals themselves are ordinary `Recipe` rows
/// grouped in a `RecipeCollection`, so they show up in the Recipes tab and cook
/// with Polly like anything else. What lives here is only what a recipe cannot
/// carry on its own: the constraints the set was generated from, and the merged
/// shopping list with the "used in 3 of your 5 meals" attribution already
/// resolved.
///
/// Local-only, like `CookSession`. `RecipeSyncBody` needs no change: a recipe
/// already syncs its collection names, so a restored library comes back with
/// the five meals still grouped under the week they belong to. The plan record
/// is a receipt of one shop, not a thing worth pushing.
@Model
final class MealPlan {
    /// Stable identity for the generated plan, carried from the in-memory draft
    /// so re-committing an edited plan updates this row instead of adding one.
    var planID: UUID
    /// Display name, also the collection's name ("Week of Aug 6").
    var name: String
    var servingsPerMeal: Int
    var mealCount: Int
    /// Rough dollar target the plan was generated against. Steers the list
    /// toward cheap staples.
    var budgetTarget: Int?
    /// Ceiling the cook set on how many distinct things to buy.
    var ingredientTarget: Int
    /// Estimated cost of the shop, as a low and high bound in whole dollars.
    ///
    /// Shown, unlike the target, but never as a bare figure: the UI always
    /// prints it as a range beside a line saying it is an estimate that moves
    /// with the store and the city. Both nil when the estimate could not be
    /// made, which is a normal outcome and simply hides the row.
    var estimatedCostLow: Int?
    var estimatedCostHigh: Int?
    /// Free text the cook typed at setup ("no pork, one vegetarian night").
    var notes: String
    /// The meals in generated order. The collection is a set, and "meal 3" has
    /// to keep meaning the same dish across a swap.
    var mealTitles: [String]
    var createdAt: Date

    /// The library collection holding this plan's recipes.
    var collection: RecipeCollection?

    @Relationship(deleteRule: .cascade, inverse: \MealPlanLine.plan)
    var lines: [MealPlanLine]

    var sortedLines: [MealPlanLine] {
        lines.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Lines the cook actually has to buy (the pantry already covers the rest).
    var toBuy: [MealPlanLine] {
        sortedLines.filter { !$0.alreadyHave }
    }

    /// "$52 to $68", or nil when no estimate was made.
    var estimatedCostRange: String? {
        guard let low = estimatedCostLow, let high = estimatedCostHigh else { return nil }
        return "$\(low) to $\(high)"
    }

    init(
        planID: UUID = UUID(),
        name: String,
        servingsPerMeal: Int = 4,
        mealCount: Int = 5,
        budgetTarget: Int? = nil,
        ingredientTarget: Int = 22,
        estimatedCostLow: Int? = nil,
        estimatedCostHigh: Int? = nil,
        notes: String = "",
        mealTitles: [String] = [],
        createdAt: Date = .now
    ) {
        self.planID = planID
        self.name = name
        self.servingsPerMeal = servingsPerMeal
        self.mealCount = mealCount
        self.budgetTarget = budgetTarget
        self.ingredientTarget = ingredientTarget
        self.estimatedCostLow = estimatedCostLow
        self.estimatedCostHigh = estimatedCostHigh
        self.notes = notes
        self.mealTitles = mealTitles
        self.createdAt = createdAt
        self.lines = []
    }
}

/// One line of a plan's shopping list, after the five recipes have been merged.
///
/// Carries the recipes that need it, so "rice, used in 3 of your 5 meals" is a
/// read rather than a lookup — and so the same attribution can be handed to
/// `GroceryItem.sourceRecipeTitles` when the plan is committed.
@Model
final class MealPlanLine {
    var name: String
    var canonicalName: String
    var quantity: Double?
    var unit: String?
    var category: GroceryCategory
    var isOptional: Bool
    /// Titles of this plan's meals that call for the line.
    var recipeTitles: [String]
    /// True when the pantry already covers it. Shown as "already in your
    /// kitchen" and kept off the grocery list.
    var alreadyHave: Bool
    var sortIndex: Int

    var plan: MealPlan?

    /// How many of the plan's meals use this. The number behind the shared-item
    /// copy, and what makes the list read as one shop.
    var mealCount: Int { recipeTitles.count }

    init(
        name: String,
        quantity: Double? = nil,
        unit: String? = nil,
        category: GroceryCategory = .other,
        isOptional: Bool = false,
        recipeTitles: [String] = [],
        alreadyHave: Bool = false,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.canonicalName = IngredientCanonicalizer.canonicalize(name)
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.isOptional = isOptional
        self.recipeTitles = recipeTitles
        self.alreadyHave = alreadyHave
        self.sortIndex = sortIndex
    }
}
