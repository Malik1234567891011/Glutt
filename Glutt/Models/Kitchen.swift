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

/// A piece of equipment the user owns. A row exists **iff** the tool is owned —
/// checking a preset inserts one, unchecking deletes it. Custom tools are just
/// rows whose name isn't in `KitchenToolCatalog`. Polly reads these mid-cook and
/// recipes flag gear you don't have (see `KitchenToolCatalog`).
@Model
final class KitchenTool {
    var name: String
    /// Lowercased, trimmed — for matching against recipe text and presets.
    var canonicalName: String
    /// Display group: "Appliances", "Cookware", "Tools", or "Custom".
    var category: String
    var addedAt: Date

    init(name: String, category: String = "Custom") {
        self.name = name
        self.canonicalName = name.lowercased().trimmingCharacters(in: .whitespaces)
        self.category = category
        self.addedAt = .now
    }
}

