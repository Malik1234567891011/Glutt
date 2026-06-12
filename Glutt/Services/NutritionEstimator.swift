import Foundation

/// Estimates recipe nutrition from ingredients using a built-in table of
/// common foods. Honest about uncertainty: every estimate carries a
/// confidence based on how many ingredients were actually recognized.
/// No fake precision — values round to friendly numbers.
enum NutritionEstimator {

    struct Estimate {
        /// Per serving.
        var calories: Int
        var proteinGrams: Int
        /// 0...1 — fraction of ingredient mass we could identify.
        var confidence: Double
        var matchedCount: Int
        var totalCount: Int

        var caloriesRange: ClosedRange<Int> {
            let spread = max(30, Int(Double(calories) * (1.1 - confidence) * 0.6))
            return (calories - spread)...(calories + spread)
        }
    }

    /// Per-100g values for common ingredients (calories, protein g).
    /// Keyed by canonical-name fragments; first match wins.
    private static let per100g: [(key: String, calories: Double, protein: Double)] = [
        ("chicken breast", 165, 31), ("chicken thigh", 209, 26), ("chicken", 190, 27),
        ("ground beef", 250, 26), ("beef", 250, 26), ("steak", 271, 25),
        ("salmon", 208, 20), ("shrimp", 99, 24), ("tuna", 132, 28),
        ("pork", 242, 27), ("bacon", 541, 37), ("egg", 155, 13),
        ("tofu", 76, 8), ("chickpea", 164, 9), ("lentil", 116, 9),
        ("black bean", 132, 9), ("bean", 127, 9),
        ("rice", 130, 2.7), ("pasta", 158, 6), ("noodle", 138, 5),
        ("potato", 77, 2), ("bread", 265, 9), ("tortilla", 312, 8),
        ("flour", 364, 10), ("oat", 389, 17), ("quinoa", 120, 4.4),
        ("butter", 717, 0.9), ("olive oil", 884, 0), ("oil", 884, 0),
        ("heavy cream", 340, 2.8), ("cream cheese", 342, 6), ("cream", 340, 2.8),
        ("cheddar", 403, 25), ("parmesan", 431, 38), ("mozzarella", 280, 28), ("feta", 264, 14),
        ("cheese", 350, 25), ("greek yogurt", 59, 10), ("yogurt", 61, 3.5), ("milk", 61, 3.2),
        ("avocado", 160, 2), ("banana", 89, 1.1), ("apple", 52, 0.3), ("berr", 50, 0.7),
        ("onion", 40, 1.1), ("garlic", 149, 6.4), ("tomato", 18, 0.9), ("spinach", 23, 2.9),
        ("broccoli", 34, 2.8), ("carrot", 41, 0.9), ("pepper", 31, 1), ("cucumber", 15, 0.7),
        ("lettuce", 15, 1.4), ("cabbage", 25, 1.3), ("zucchini", 17, 1.2), ("mushroom", 22, 3.1),
        ("corn", 86, 3.3), ("pea", 81, 5.4), ("lemon", 29, 1.1), ("lime", 30, 0.7),
        ("sugar", 387, 0), ("honey", 304, 0.3), ("maple", 260, 0),
        ("chocolate", 546, 4.9), ("cocoa", 228, 20),
        ("soy sauce", 53, 8), ("mayo", 680, 1), ("ketchup", 112, 1.3),
        ("almond", 579, 21), ("peanut", 567, 26), ("walnut", 654, 15), ("nut", 600, 20),
        ("salt", 0, 0), ("water", 0, 0), ("vinegar", 18, 0), ("broth", 5, 0.5), ("stock", 5, 0.5),
        ("wine", 83, 0.1), ("coconut milk", 230, 2.3),
    ]

    /// Typical gram weight when a recipe says "1 onion" with no unit.
    private static let pieceWeights: [(key: String, grams: Double)] = [
        ("egg", 50), ("onion", 150), ("garlic", 5), ("tomato", 120), ("potato", 200),
        ("carrot", 60), ("pepper", 120), ("avocado", 150), ("banana", 120), ("apple", 180),
        ("lemon", 60), ("lime", 45), ("chicken breast", 175), ("chicken thigh", 125),
        ("tortilla", 45), ("bread", 40),
    ]

    /// Unit → grams (approximate, density-agnostic on purpose).
    private static let unitGrams: [String: Double] = [
        "g": 1, "gram": 1, "grams": 1, "kg": 1000,
        "oz": 28, "ounce": 28, "ounces": 28, "lb": 454, "lbs": 454, "pound": 454, "pounds": 454,
        "cup": 200, "cups": 200, "tbsp": 14, "tablespoon": 14, "tablespoons": 14,
        "tsp": 5, "teaspoon": 5, "teaspoons": 5, "ml": 1, "l": 1000, "liter": 1000,
        "clove": 5, "cloves": 5, "can": 400, "stick": 113, "sticks": 113,
        "slice": 30, "slices": 30, "bunch": 100, "handful": 40,
    ]

    static func estimate(for recipe: Recipe) -> Estimate? {
        let ingredients = recipe.ingredients.filter { !$0.isOptional }
        guard !ingredients.isEmpty, recipe.servings > 0 else { return nil }

        var totalCalories = 0.0
        var totalProtein = 0.0
        var matched = 0

        for ingredient in ingredients {
            guard let entry = lookup(ingredient.canonicalName) else { continue }
            let grams = estimatedGrams(for: ingredient)
            totalCalories += entry.calories * grams / 100
            totalProtein += entry.protein * grams / 100
            matched += 1
        }

        guard matched > 0 else { return nil }

        let confidence = Double(matched) / Double(ingredients.count)
        let perServingCalories = totalCalories / Double(recipe.servings)
        let perServingProtein = totalProtein / Double(recipe.servings)

        return Estimate(
            // Round to 10s — false precision erodes trust.
            calories: Int((perServingCalories / 10).rounded() * 10),
            proteinGrams: Int(perServingProtein.rounded()),
            confidence: confidence,
            matchedCount: matched,
            totalCount: ingredients.count
        )
    }

    // MARK: - Internals

    static func lookup(_ canonicalName: String) -> (calories: Double, protein: Double)? {
        for entry in per100g where canonicalName.contains(entry.key) {
            return (entry.calories, entry.protein)
        }
        return nil
    }

    static func estimatedGrams(for ingredient: RecipeIngredient) -> Double {
        let quantity = ingredient.quantity ?? 1

        if let unit = ingredient.unit?.lowercased().trimmingCharacters(in: .whitespaces),
           !unit.isEmpty {
            if let grams = unitGrams[unit] {
                return quantity * grams
            }
        }

        // No unit: "2 onions" — use a typical piece weight.
        for entry in pieceWeights where ingredient.canonicalName.contains(entry.key) {
            return quantity * entry.grams
        }
        // Unknown piece: assume a modest 80g each.
        return quantity * 80
    }
}
