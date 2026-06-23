import Foundation

/// Estimates how many adult servings a recipe makes by reading the quantities
/// of its main ingredients. Used as a *fallback* only — explicit servings from
/// the source or the AI cleanup always win. Portioning is non-critical and the
/// user can adjust it with a stepper, so a reasoned guess beats a flat "2".
enum ServingEstimator {

    /// Grams of raw protein that feed one adult as the main of a meal.
    private static let gramsProteinPerServing = 200.0
    /// Grams of dry grain/pasta per adult serving (~½–¾ cup dry rice).
    private static let gramsStarchPerServing = 85.0

    private static let proteinWords = [
        "chicken", "beef", "pork", "lamb", "turkey", "salmon", "tuna", "cod",
        "tilapia", "fish", "shrimp", "prawn", "tofu", "tempeh", "steak",
        "mince", "sausage", "bacon", "thigh", "breast", "fillet", "filet",
        "tenderloin", "chuck", "sirloin", "ribeye", "flank", "drumstick", "wing",
    ]
    private static let starchWords = [
        "rice", "pasta", "spaghetti", "penne", "macaroni", "noodle", "couscous",
        "quinoa", "orzo", "gnocchi", "rigatoni", "fusilli", "linguine", "farfalle",
    ]
    /// Names that contain a protein/starch word but aren't a main (condiments,
    /// stocks, seasonings). Counting these would wildly inflate the estimate.
    private static let nonMainWords = [
        "sauce", "stock", "broth", "powder", "seasoning", "bouillon", "paste",
        "oil", "spice", "rub", "marinade", "dressing", "extract", "cube",
    ]

    /// Pieces of a counted protein that make one serving (no weight given).
    private static func piecesPerServing(for name: String) -> Double {
        if name.contains("wing") { return 4 }
        if name.contains("drumstick") || name.contains("thigh") { return 2 }
        return 1   // breast, fillet, steak, chop…
    }

    struct Item { var name: String; var quantity: Double?; var unit: String? }

    static func estimate(fromLines lines: [String]) -> Int? {
        let items = lines.map { line -> Item in
            let parsed = IngredientLineParser.parse(line)
            return Item(name: parsed.name.lowercased(),
                        quantity: parsed.quantity,
                        unit: parsed.unit?.lowercased())
        }
        return estimate(items: items)
    }

    static func estimate(items: [Item]) -> Int? {
        var proteinServings = 0.0
        var starchServings = 0.0
        var eggCount = 0.0
        var sawProtein = false

        for item in items {
            let name = item.name
            if nonMainWords.contains(where: { name.contains($0) }) { continue }

            if name.contains("egg"), !name.contains("eggplant") {
                eggCount += item.quantity ?? 1
                continue
            }

            if proteinWords.contains(where: { name.contains($0) }) {
                sawProtein = true
                if let grams = grams(item.quantity, item.unit) {
                    proteinServings += grams / gramsProteinPerServing
                } else if let count = item.quantity {
                    // A non-weight amount on a protein ("2 fillets", "4 thighs")
                    // is a piece count.
                    proteinServings += count / piecesPerServing(for: name)
                } else {
                    proteinServings += 1   // "chicken breast" with no number ≈ 1
                }
            } else if starchWords.contains(where: { name.contains($0) }) {
                if let grams = grams(item.quantity, item.unit, isGrain: true) {
                    starchServings += grams / gramsStarchPerServing
                }
            }
        }

        // Protein is the strongest portioning signal. Eggs count only when they
        // are the main (no meat/fish present). Starch is the last resort.
        if proteinServings > 0 { return clamp(proteinServings) }
        if sawProtein { return 1 }                       // protein present, no parseable amount
        if eggCount > 0 { return clamp(eggCount / 2) }
        if starchServings > 0 { return clamp(starchServings) }
        return nil
    }

    private static func clamp(_ value: Double) -> Int {
        min(12, max(1, Int(value.rounded())))
    }

    /// Quantity+unit → grams. `isGrain` lets us read "cups" of rice/pasta as a
    /// dry-weight measure rather than refusing it (cups are otherwise ambiguous).
    private static func grams(_ quantity: Double?, _ unit: String?, isGrain: Bool = false) -> Double? {
        guard let quantity, quantity > 0 else { return nil }
        switch unit {
        case "g", "gram", "grams": return quantity
        case "kg": return quantity * 1000
        case "lb", "lbs", "pound", "pounds": return quantity * 453.6
        case "oz", "ounce", "ounces": return quantity * 28.35
        case "cup", "cups": return isGrain ? quantity * 185 : nil
        default: return nil
        }
    }
}
