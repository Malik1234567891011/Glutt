import Foundation

/// Matches recipe ingredients against the user's pantry.
/// This powers "You have 6/9 ingredients" everywhere in the app.
enum PantryMatcher {

    /// Assumed always available — nobody tracks salt in an inventory app.
    static let staples: Set<String> = [
        "salt", "pepper", "black pepper", "salt and pepper", "water", "oil",
    ]

    struct MatchResult {
        var owned: [RecipeIngredient] = []
        var missing: [RecipeIngredient] = []
        /// Optional ingredients the user doesn't have (never count against the match).
        var missingOptional: [RecipeIngredient] = []

        var ownedCount: Int { owned.count }
        var totalCount: Int { owned.count + missing.count }
        var hasEverything: Bool { missing.isEmpty }
    }

    static func match(recipe: Recipe, pantry: [PantryItem]) -> MatchResult {
        let available = pantry.filter { $0.roughQuantity != .out }
        var result = MatchResult()

        for ingredient in recipe.ingredients.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            if owns(ingredientNamed: ingredient.canonicalName, available: available) {
                result.owned.append(ingredient)
            } else if ingredient.isOptional {
                result.missingOptional.append(ingredient)
            } else {
                result.missing.append(ingredient)
            }
        }
        return result
    }

    static func owns(ingredientNamed canonicalName: String, available: [PantryItem]) -> Bool {
        if staples.contains(canonicalName) { return true }

        let ingredientWords = Set(canonicalName.split(separator: " ").map(String.init))
        return available.contains { item in
            if item.canonicalName == canonicalName { return true }
            // Subset match: pantry "rice" covers "basmati rice";
            // pantry "chicken thigh" covers "chicken thigh fillets".
            let pantryWords = Set(item.canonicalName.split(separator: " ").map(String.init))
            return pantryWords.isSubset(of: ingredientWords)
        }
    }
}
