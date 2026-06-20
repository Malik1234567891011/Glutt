import Foundation
import SwiftData

@Model
final class PantryItem {
    var name: String
    var canonicalName: String
    var category: GroceryCategory
    var roughQuantity: RoughQuantity
    var location: StorageLocation
    var useSoonDate: Date?
    /// Optional precise amount the user typed ("1 lb", "2 bell peppers", "24 eggs").
    /// The rough quantity stays the fast default; this is for people who want
    /// exactness. Inline default keeps SwiftData migration lightweight.
    var exactQuantity: String? = nil
    var addedAt: Date
    var updatedAt: Date

    var isUseSoon: Bool {
        guard let useSoonDate else { return false }
        return useSoonDate <= Calendar.current.date(byAdding: .day, value: 3, to: .now)!
    }

    init(
        name: String,
        category: GroceryCategory = .other,
        roughQuantity: RoughQuantity = .full,
        location: StorageLocation = .pantry,
        useSoonDate: Date? = nil,
        exactQuantity: String? = nil
    ) {
        self.name = name
        self.canonicalName = IngredientCanonicalizer.canonicalize(name)
        self.category = category
        self.roughQuantity = roughQuantity
        self.location = location
        self.useSoonDate = useSoonDate
        self.exactQuantity = exactQuantity
        self.addedAt = .now
        self.updatedAt = .now
    }
}

@Model
final class GroceryItem {
    var name: String
    var canonicalName: String
    /// Structured quantity for combining duplicates across recipes.
    var quantity: Double?
    var unit: String?
    /// Free-text quantity for manual entries ("1 tub").
    var quantityText: String?
    var category: GroceryCategory
    var isChecked: Bool
    var isOptional: Bool
    var substitutionHint: String?
    /// Recipes that need this item (stored as IDs to keep deletes simple).
    var sourceRecipeTitles: [String]
    var addedAt: Date

    init(
        name: String,
        quantityText: String? = nil,
        category: GroceryCategory = .other,
        isOptional: Bool = false,
        substitutionHint: String? = nil,
        sourceRecipeTitles: [String] = []
    ) {
        self.name = name
        self.canonicalName = IngredientCanonicalizer.canonicalize(name)
        self.quantityText = quantityText
        self.category = category
        self.isChecked = false
        self.isOptional = isOptional
        self.substitutionHint = substitutionHint
        self.sourceRecipeTitles = sourceRecipeTitles
        self.addedAt = .now
    }
}

@Model
final class Leftover {
    var title: String
    var servingsRemaining: Double
    var cookedAt: Date
    var isFrozen: Bool
    var caloriesPerServing: Int?
    var proteinPerServing: Int?

    var sourceRecipe: Recipe?

    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: cookedAt, to: .now).day ?? 0
    }

    init(
        title: String,
        servingsRemaining: Double,
        cookedAt: Date = .now,
        isFrozen: Bool = false,
        sourceRecipe: Recipe? = nil
    ) {
        self.title = title
        self.servingsRemaining = servingsRemaining
        self.cookedAt = cookedAt
        self.isFrozen = isFrozen
        self.sourceRecipe = sourceRecipe
    }
}
