import Foundation

/// Estimates recipe nutrition from ingredients using a built-in table of
/// common foods. Honest about uncertainty: every estimate carries a
/// confidence based on how many ingredients were actually recognized.
/// No fake precision — values round to friendly numbers.
///
/// It works the way a person would: look up each ingredient's per-100g values,
/// scale by the amount, add them up, divide by servings. Matching is
/// word-aware so "peanut butter" isn't scored as peas and "butternut squash"
/// isn't scored as nuts.
enum NutritionEstimator {

    struct Entry {
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double

        init(calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double = 0) {
            self.calories = calories
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
            self.fiber = fiber
        }
    }

    struct Estimate {
        /// Per serving.
        var calories: Int
        var proteinGrams: Int
        var carbGrams: Int
        var fatGrams: Int
        var fiberGrams: Int
        /// 0...1 — fraction of ingredients we could identify.
        var confidence: Double
        var matchedCount: Int
        var totalCount: Int

        var caloriesRange: ClosedRange<Int> {
            let spread = max(30, Int(Double(calories) * (1.1 - confidence) * 0.6))
            return (calories - spread)...(calories + spread)
        }
    }

    /// Per-100g values (calories, protein, carbs, fat — grams) for common
    /// ingredients. Keyed by canonical-name fragments; FIRST match wins, so
    /// list more specific multi-word keys before their generic fallbacks.
    /// Multi-word keys match as substrings; single-word keys match whole words
    /// only (so "nut" won't hit "butternut"/"coconut", "pea" won't hit "peanut").
    private static let per100g: [(key: String, value: Entry)] = [
        // Poultry / meat / fish
        ("chicken breast", Entry(calories: 165, protein: 31, carbs: 0, fat: 3.6)),
        ("chicken thigh", Entry(calories: 209, protein: 26, carbs: 0, fat: 11)),
        ("chicken", Entry(calories: 190, protein: 27, carbs: 0, fat: 8)),
        ("ground turkey", Entry(calories: 170, protein: 27, carbs: 0, fat: 7)),
        ("turkey", Entry(calories: 135, protein: 29, carbs: 0, fat: 1)),
        ("ground beef", Entry(calories: 250, protein: 26, carbs: 0, fat: 15)),
        ("beef", Entry(calories: 250, protein: 26, carbs: 0, fat: 15)),
        ("steak", Entry(calories: 271, protein: 25, carbs: 0, fat: 19)),
        ("salmon", Entry(calories: 208, protein: 20, carbs: 0, fat: 13)),
        ("shrimp", Entry(calories: 99, protein: 24, carbs: 0.2, fat: 0.3)),
        ("tuna", Entry(calories: 132, protein: 28, carbs: 0, fat: 1)),
        ("pork sausage", Entry(calories: 300, protein: 18, carbs: 2, fat: 25)),
        ("sausage", Entry(calories: 300, protein: 18, carbs: 2, fat: 25)),
        ("bacon", Entry(calories: 541, protein: 37, carbs: 1.4, fat: 42)),
        ("ham", Entry(calories: 145, protein: 21, carbs: 1.5, fat: 5)),
        ("pork", Entry(calories: 242, protein: 27, carbs: 0, fat: 14)),
        ("egg", Entry(calories: 155, protein: 13, carbs: 1.1, fat: 11)),
        // Plant proteins / legumes
        ("tofu", Entry(calories: 76, protein: 8, carbs: 1.9, fat: 4.8)),
        ("chickpea", Entry(calories: 164, protein: 9, carbs: 27, fat: 2.6, fiber: 8)),
        ("lentil", Entry(calories: 116, protein: 9, carbs: 20, fat: 0.4, fiber: 8)),
        ("black bean", Entry(calories: 132, protein: 9, carbs: 24, fat: 0.5, fiber: 9)),
        ("bean", Entry(calories: 127, protein: 9, carbs: 23, fat: 0.5, fiber: 7)),
        // Grains / starches
        ("rice", Entry(calories: 130, protein: 2.7, carbs: 28, fat: 0.3, fiber: 0.4)),
        ("pasta", Entry(calories: 158, protein: 6, carbs: 31, fat: 0.9, fiber: 2)),
        ("noodle", Entry(calories: 138, protein: 5, carbs: 25, fat: 2, fiber: 1)),
        ("sweet potato", Entry(calories: 86, protein: 1.6, carbs: 20, fat: 0.1, fiber: 3)),
        ("potato", Entry(calories: 77, protein: 2, carbs: 17, fat: 0.1, fiber: 2)),
        ("bread", Entry(calories: 265, protein: 9, carbs: 49, fat: 3.2, fiber: 3)),
        ("tortilla", Entry(calories: 312, protein: 8, carbs: 50, fat: 8, fiber: 2)),
        ("flour", Entry(calories: 364, protein: 10, carbs: 76, fat: 1, fiber: 3)),
        ("oat", Entry(calories: 389, protein: 17, carbs: 66, fat: 7, fiber: 11)),
        ("quinoa", Entry(calories: 120, protein: 4.4, carbs: 21, fat: 1.9, fiber: 3)),
        // Dairy / fats
        ("butter", Entry(calories: 717, protein: 0.9, carbs: 0.1, fat: 81)),
        ("olive oil", Entry(calories: 884, protein: 0, carbs: 0, fat: 100)),
        ("oil", Entry(calories: 884, protein: 0, carbs: 0, fat: 100)),
        ("heavy cream", Entry(calories: 340, protein: 2.8, carbs: 2.8, fat: 36)),
        ("cream cheese", Entry(calories: 342, protein: 6, carbs: 4, fat: 34)),
        ("sour cream", Entry(calories: 198, protein: 2, carbs: 5, fat: 19)),
        ("cream", Entry(calories: 340, protein: 2.8, carbs: 2.8, fat: 36)),
        ("cheddar", Entry(calories: 403, protein: 25, carbs: 1.3, fat: 33)),
        ("parmesan", Entry(calories: 431, protein: 38, carbs: 4.1, fat: 29)),
        ("mozzarella", Entry(calories: 280, protein: 28, carbs: 3.1, fat: 17)),
        ("feta", Entry(calories: 264, protein: 14, carbs: 4, fat: 21)),
        ("cheese", Entry(calories: 350, protein: 25, carbs: 3, fat: 28)),
        ("greek yogurt", Entry(calories: 59, protein: 10, carbs: 3.6, fat: 0.4)),
        ("yogurt", Entry(calories: 61, protein: 3.5, carbs: 4.7, fat: 3.3)),
        ("milk", Entry(calories: 61, protein: 3.2, carbs: 4.8, fat: 3.3)),
        // Produce
        ("avocado", Entry(calories: 160, protein: 2, carbs: 9, fat: 15, fiber: 7)),
        ("banana", Entry(calories: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 3)),
        ("apple", Entry(calories: 52, protein: 0.3, carbs: 14, fat: 0.2, fiber: 2)),
        ("berry", Entry(calories: 50, protein: 0.7, carbs: 12, fat: 0.3, fiber: 4)),
        ("onion", Entry(calories: 40, protein: 1.1, carbs: 9, fat: 0.1, fiber: 2)),
        ("garlic", Entry(calories: 149, protein: 6.4, carbs: 33, fat: 0.5, fiber: 2)),
        ("tomato", Entry(calories: 18, protein: 0.9, carbs: 3.9, fat: 0.2, fiber: 1)),
        ("spinach", Entry(calories: 23, protein: 2.9, carbs: 3.6, fat: 0.4, fiber: 2)),
        ("broccoli", Entry(calories: 34, protein: 2.8, carbs: 7, fat: 0.4, fiber: 3)),
        ("carrot", Entry(calories: 41, protein: 0.9, carbs: 10, fat: 0.2, fiber: 3)),
        ("pepper", Entry(calories: 31, protein: 1, carbs: 6, fat: 0.3, fiber: 2)),
        ("cucumber", Entry(calories: 15, protein: 0.7, carbs: 3.6, fat: 0.1, fiber: 0.5)),
        ("lettuce", Entry(calories: 15, protein: 1.4, carbs: 2.9, fat: 0.2, fiber: 1)),
        ("cabbage", Entry(calories: 25, protein: 1.3, carbs: 6, fat: 0.1, fiber: 3)),
        ("zucchini", Entry(calories: 17, protein: 1.2, carbs: 3.1, fat: 0.3, fiber: 1)),
        ("mushroom", Entry(calories: 22, protein: 3.1, carbs: 3.3, fat: 0.3, fiber: 1)),
        ("corn", Entry(calories: 86, protein: 3.3, carbs: 19, fat: 1.4, fiber: 2)),
        ("pea", Entry(calories: 81, protein: 5.4, carbs: 14, fat: 0.4, fiber: 5)),
        ("lemon", Entry(calories: 29, protein: 1.1, carbs: 9, fat: 0.3, fiber: 3)),
        ("lime", Entry(calories: 30, protein: 0.7, carbs: 11, fat: 0.2, fiber: 3)),
        // Sweet / pantry
        ("sugar", Entry(calories: 387, protein: 0, carbs: 100, fat: 0)),
        ("honey", Entry(calories: 304, protein: 0.3, carbs: 82, fat: 0)),
        ("maple", Entry(calories: 260, protein: 0, carbs: 67, fat: 0.2)),
        ("chocolate", Entry(calories: 546, protein: 4.9, carbs: 61, fat: 31, fiber: 7)),
        ("cocoa", Entry(calories: 228, protein: 20, carbs: 58, fat: 14, fiber: 33)),
        ("soy sauce", Entry(calories: 53, protein: 8, carbs: 5, fat: 0.6)),
        ("mayo", Entry(calories: 680, protein: 1, carbs: 0.6, fat: 75)),
        ("ketchup", Entry(calories: 112, protein: 1.3, carbs: 26, fat: 0.1)),
        ("coconut milk", Entry(calories: 230, protein: 2.3, carbs: 6, fat: 24, fiber: 2)),
        ("coconut", Entry(calories: 354, protein: 3, carbs: 15, fat: 33, fiber: 9)),
        ("peanut", Entry(calories: 567, protein: 26, carbs: 16, fat: 49, fiber: 9)),
        ("almond", Entry(calories: 579, protein: 21, carbs: 22, fat: 50, fiber: 12)),
        ("walnut", Entry(calories: 654, protein: 15, carbs: 14, fat: 65, fiber: 7)),
        ("nut", Entry(calories: 600, protein: 20, carbs: 20, fat: 55, fiber: 8)),
        ("chia", Entry(calories: 486, protein: 17, carbs: 42, fat: 31, fiber: 34)),
        ("flax", Entry(calories: 534, protein: 18, carbs: 29, fat: 42, fiber: 27)),
        ("salt", Entry(calories: 0, protein: 0, carbs: 0, fat: 0)),
        ("water", Entry(calories: 0, protein: 0, carbs: 0, fat: 0)),
        ("vinegar", Entry(calories: 18, protein: 0, carbs: 0.9, fat: 0)),
        ("broth", Entry(calories: 5, protein: 0.5, carbs: 0.5, fat: 0.2)),
        ("stock", Entry(calories: 5, protein: 0.5, carbs: 0.5, fat: 0.2)),
        ("wine", Entry(calories: 83, protein: 0.1, carbs: 2.6, fat: 0)),
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
        estimate(ingredients: recipe.ingredients, servings: recipe.servings)
    }

    /// Same engine, but over a loose ingredient list — lets us score a proposed
    /// adjustment (the "after") with the exact same numbers as the original.
    static func estimate(ingredients allIngredients: [RecipeIngredient], servings: Int) -> Estimate? {
        let ingredients = allIngredients.filter { !$0.isOptional }
        guard !ingredients.isEmpty, servings > 0 else { return nil }

        var totalCalories = 0.0
        var totalProtein = 0.0
        var totalCarbs = 0.0
        var totalFat = 0.0
        var totalFiber = 0.0
        var matched = 0

        for ingredient in ingredients {
            guard let entry = lookup(ingredient.canonicalName) else { continue }
            let grams = estimatedGrams(for: ingredient)
            totalCalories += entry.calories * grams / 100
            totalProtein += entry.protein * grams / 100
            totalCarbs += entry.carbs * grams / 100
            totalFat += entry.fat * grams / 100
            totalFiber += entry.fiber * grams / 100
            matched += 1
        }

        guard matched > 0 else { return nil }

        let confidence = Double(matched) / Double(ingredients.count)
        let s = Double(servings)

        return Estimate(
            // Round calories to 10s — false precision erodes trust.
            calories: Int((totalCalories / s / 10).rounded() * 10),
            proteinGrams: Int((totalProtein / s).rounded()),
            carbGrams: Int((totalCarbs / s).rounded()),
            fatGrams: Int((totalFat / s).rounded()),
            fiberGrams: Int((totalFiber / s).rounded()),
            confidence: confidence,
            matchedCount: matched,
            totalCount: ingredients.count
        )
    }

    // MARK: - Internals

    static func lookup(_ canonicalName: String) -> Entry? {
        let name = canonicalName.lowercased()
        let words = Set(name.split(whereSeparator: { !$0.isLetter }).map(String.init))
        for entry in per100g {
            if entry.key.contains(" ") {
                if name.contains(entry.key) { return entry.value }
            } else if words.contains(entry.key) {
                return entry.value
            }
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
