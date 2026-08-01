import Foundation

/// Matches recipe ingredients against the user's pantry.
/// This powers "You have 6/9 ingredients" everywhere in the app.
enum PantryMatcher {

    /// Assumed always available — nobody tracks salt in an inventory app.
    static let staples: Set<String> = [
        "salt", "pepper", "black pepper", "salt and pepper", "water", "oil",
    ]

    /// The canonical staples we surface in the kitchen so users can opt out of
    /// any they don't actually keep. Ordered for display; capitalize for labels.
    static let assumedStapleCanonicals: [String] = ["salt", "pepper", "oil", "water"]

    struct MatchResult {
        var owned: [RecipeIngredient] = []
        var missing: [RecipeIngredient] = []
        /// Optional ingredients the user doesn't have (never count against the match).
        var missingOptional: [RecipeIngredient] = []

        var ownedCount: Int { owned.count }
        var totalCount: Int { owned.count + missing.count }
        var hasEverything: Bool { missing.isEmpty }
        /// Fraction of required ingredients the cook already owns (0...1).
        var coverage: Double { totalCount == 0 ? 0 : Double(ownedCount) / Double(totalCount) }
    }

    static func match(recipe: Recipe, pantry: [PantryItem]) -> MatchResult {
        let available = pantry.filter { $0.roughQuantity != .out }
        var result = MatchResult()

        for ingredient in recipe.ingredients.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let canonical = ingredient.canonicalName
            let coveredByAvailable = item(covering: canonical, in: available) != nil
            // A staple counts as owned unless an explicit pantry row says it's out.
            let explicitlyOut = !coveredByAvailable && item(covering: canonical, in: pantry) != nil
            let owned = coveredByAvailable || (staples.contains(canonical) && !explicitlyOut)

            if owned {
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
        return item(covering: canonicalName, in: available) != nil
    }

    /// The pantry item that satisfies an ingredient, if any
    /// (regardless of stock level — callers filter on roughQuantity).
    static func item(covering canonicalName: String, in pantry: [PantryItem]) -> PantryItem? {
        let ingredientWords = canonicalName.split(separator: " ").map(String.init)
        // A blank name has no words, so every subset test below would succeed
        // against it. Nothing can cover it and it can cover nothing.
        guard let ingredientHead = ingredientWords.last else { return nil }
        let ingredientSet = Set(ingredientWords)

        return pantry.first { item in
            if item.canonicalName == canonicalName { return true }
            let pantryWords = item.canonicalName.split(separator: " ").map(String.init)
            guard let pantryHead = pantryWords.last else { return false }
            // Food names put the head noun last, and only a shared head noun means
            // the two names are the same thing narrowed down: pantry "rice" covers
            // "basmati rice" but not "rice vinegar", and "beef" does not cover
            // "beef broth". Without this, one staple satisfies unrelated lines.
            guard pantryHead == ingredientHead else { return false }
            return Set(pantryWords).isSubset(of: ingredientSet)
        }
    }
}
