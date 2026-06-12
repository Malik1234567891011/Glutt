import Foundation

/// Learns what the user actually likes from their own behavior:
/// ratings, repeats, and what they keep saving. No black box —
/// the result is visible and editable in Settings.
enum TasteProfileBuilder {

    static func descriptors(recipes: [Recipe], sessions: [CookSession], limit: Int = 8) -> [String] {
        var weights: [String: Double] = [:]

        for recipe in recipes where recipe.parentRecipe == nil {
            // Saved at all: mild signal.
            var weight = 0.5
            // Loved it: strong signal.
            if let rating = recipe.rating {
                weight += rating >= 4 ? 2.0 : (rating <= 2 ? -1.0 : 0.5)
            }
            // Cooked repeatedly: strongest signal there is.
            let cookCount = sessions.filter { $0.recipe === recipe }.count
            weight += Double(cookCount)

            for tag in recipe.tags {
                weights[tag.lowercased(), default: 0] += weight
            }
        }

        return weights
            .filter { $0.value > 1.0 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map(\.key)
    }
}
