import Foundation
import SwiftData

/// Auto-categorizes grocery items so the list mirrors store aisles.
enum GroceryCategorizer {

    private static let keywords: [(GroceryCategory, [String])] = [
        (.produce, [
            "lemon", "lime", "onion", "garlic", "tomato", "cucumber", "spinach", "lettuce",
            "romaine", "potato", "carrot", "broccoli", "parsley", "basil", "dill", "coriander",
            "cilantro", "chive", "berry", "berries", "banana", "apple", "avocado", "pepper",
            "scallion", "green onion", "pomegranate", "mushroom", "zucchini", "celery", "ginger",
        ]),
        (.meat, [
            "chicken", "beef", "steak", "lamb", "turkey", "salmon", "fish", "shrimp",
            "sirloin", "flank", "kofta", "mince", "ground", "sausage", "bacon",
        ]),
        (.dairy, [
            "milk", "yogurt", "cream", "cheese", "butter", "egg", "mozzarella",
            "parmesan", "cheddar", "feta", "ghee",
        ]),
        (.frozen, ["frozen", "ice cream"]),
        (.spices, [
            "salt", "paprika", "cumin", "spice", "seasoning", "saffron", "cinnamon",
            "oregano", "chili flake", "turmeric", "curry powder", "black pepper",
        ]),
        (.pantry, [
            "rice", "pasta", "flour", "sugar", "honey", "oil", "vinegar", "soy sauce",
            "canned", "bean", "chickpea", "broth", "stock", "gnocchi", "tortilla",
            "flatbread", "bread", "granola", "sauce", "pesto", "sriracha", "bbq",
            "bouillon", "oats", "noodle",
        ]),
    ]

    static func categorize(_ name: String) -> GroceryCategory {
        let canonical = IngredientCanonicalizer.canonicalize(name)
        for (category, words) in keywords where words.contains(where: { canonical.contains($0) }) {
            return category
        }
        return .other
    }
}

/// Builds and merges the grocery list from recipes, respecting the pantry.
enum GroceryListBuilder {

    /// Non-optional recipe ingredients the user doesn't have.
    static func missingIngredients(for recipe: Recipe, pantry: [PantryItem]) -> [RecipeIngredient] {
        PantryMatcher.match(recipe: recipe, pantry: pantry).missing
    }

    /// Adds ingredients to the grocery list, combining duplicates
    /// ("2 onions" + "1 onion" = "3 onions" when units agree).
    static func add(
        ingredients: [RecipeIngredient],
        from recipe: Recipe?,
        existing: [GroceryItem],
        context: ModelContext
    ) {
        for ingredient in ingredients {
            let canonical = ingredient.canonicalName

            if let match = existing.first(where: { $0.canonicalName == canonical && !$0.isChecked }) {
                // Combine quantities when the units agree (or both are unitless counts).
                if let addQty = ingredient.quantity, let haveQty = match.quantity,
                   normalizedUnit(match.unit) == normalizedUnit(ingredient.unit) {
                    match.quantity = haveQty + addQty
                }
                if let title = recipe?.title, !match.sourceRecipeTitles.contains(title) {
                    match.sourceRecipeTitles.append(title)
                }
                continue
            }

            let item = GroceryItem(
                name: ingredient.name,
                category: GroceryCategorizer.categorize(ingredient.name),
                isOptional: ingredient.isOptional,
                substitutionHint: SubstitutionService.substitutions(for: ingredient.name).first?.name,
                sourceRecipeTitles: recipe.map { [$0.title] } ?? []
            )
            item.quantity = ingredient.quantity
            item.unit = ingredient.unit
            context.insert(item)
        }
    }

    private static func normalizedUnit(_ unit: String?) -> String {
        guard let unit = unit?.lowercased(), !unit.isEmpty else { return "" }
        // "cup" == "cups", "lb" == "lbs" for combining purposes.
        return unit.hasSuffix("s") ? String(unit.dropLast()) : unit
    }
}

extension GroceryItem {
    /// Display string preferring structured quantity, falling back to free text.
    var displayQuantity: String? {
        if let quantity {
            return UnitConverter.format(quantity: quantity, unit: unit)
        }
        return quantityText
    }
}
