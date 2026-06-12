import Foundation

/// "What should I cook?" — combines pantry match, time pressure, mood,
/// use-soon ingredients, ratings, and cook history into a few good options.
/// Pure heuristics, fully offline.
enum MealRecommender {

    enum Mood: String, CaseIterable, Identifiable {
        case any = "Anything"
        case savory = "Savory"
        case sweet = "Sweet"
        case comfort = "Comfort"
        case fresh = "Fresh & light"

        var id: String { rawValue }

        var keywords: Set<String> {
            switch self {
            case .any: []
            case .savory: ["savory", "chicken", "beef", "garlic", "umami", "soy", "cheese", "bacon", "steak", "pork"]
            case .sweet: ["sweet", "dessert", "chocolate", "honey", "sugar", "cake", "cookie", "brownie", "caramel"]
            case .comfort: ["creamy", "cheese", "pasta", "stew", "soup", "butter", "rich", "cozy", "baked"]
            case .fresh: ["salad", "fresh", "light", "lemon", "cucumber", "herb", "grilled", "bowl", "crisp"]
            }
        }
    }

    struct Request {
        var maxMinutes: Int?
        var mood: Mood = .any
        var preferPantry = true
        var recipes: [Recipe]
        var pantry: [PantryItem]
        var leftovers: [Leftover]
        var sessions: [CookSession]
        /// Learned descriptors ("creamy", "spicy") — nudges, never dominates.
        var tasteProfile: [String] = []
        /// Hard filters: never suggest something that breaks a rule or allergy.
        var rules: [DietaryRule] = []
        var allergies: [String] = []
    }

    struct Recommendation: Identifiable {
        let id = UUID()
        let recipe: Recipe
        let badge: String
        let reasons: [String]
        let missingCount: Int
    }

    static func recommend(_ request: Request) -> [Recommendation] {
        let candidates = request.recipes.filter {
            $0.parentRecipe == nil && !$0.steps.isEmpty
                && DietGuard.isSuggestable($0, rules: request.rules, allergies: request.allergies)
        }
        guard !candidates.isEmpty else { return [] }

        let scored = candidates.map { recipe in
            (recipe: recipe, details: score(recipe, request: request))
        }
        .filter { $0.details.score > 0 }
        .sorted { $0.details.score > $1.details.score }

        var picks: [Recommendation] = []
        var used: Set<ObjectIdentifier> = []

        func take(_ entry: (recipe: Recipe, details: ScoreDetails)?, badge: String) {
            guard let entry, !used.contains(ObjectIdentifier(entry.recipe)) else { return }
            used.insert(ObjectIdentifier(entry.recipe))
            picks.append(Recommendation(
                recipe: entry.recipe,
                badge: badge,
                reasons: entry.details.reasons,
                missingCount: entry.details.missingCount
            ))
        }

        // 1. Best overall match.
        take(scored.first, badge: "Best match")

        // 2. Fastest that still fits.
        take(
            scored.filter { !used.contains(ObjectIdentifier($0.recipe)) }
                .min { $0.recipe.totalMinutes < $1.recipe.totalMinutes },
            badge: "Fastest"
        )

        // 3. Uses ingredients that need eating.
        take(
            scored.first { entry in
                !used.contains(ObjectIdentifier(entry.recipe)) && entry.details.usesUseSoon
            },
            badge: "Uses what's expiring"
        )

        // 4. Wildcard: something good the user hasn't cooked recently.
        take(
            scored.dropFirst(2).first { !used.contains(ObjectIdentifier($0.recipe)) },
            badge: "Why not?"
        )

        return picks
    }

    // MARK: - Scoring

    struct ScoreDetails {
        var score: Double = 0
        var reasons: [String] = []
        var missingCount = 0
        var usesUseSoon = false
    }

    static func score(_ recipe: Recipe, request: Request) -> ScoreDetails {
        var details = ScoreDetails()

        // Hard time cutoff: in a rush means in a rush.
        if let limit = request.maxMinutes, recipe.totalMinutes > limit {
            return details
        }
        if let limit = request.maxMinutes {
            details.reasons.append("\(recipe.totalMinutes) min — fits your \(limit)")
            details.score += 0.5
        }

        // Pantry match.
        let match = PantryMatcher.match(recipe: recipe, pantry: request.pantry)
        details.missingCount = match.missing.count
        if match.totalCount > 0 {
            let ratio = Double(match.ownedCount) / Double(match.totalCount)
            details.score += (request.preferPantry ? 3.0 : 1.5) * ratio
            if match.hasEverything {
                details.reasons.append("you have everything")
            } else if ratio >= 0.7 {
                details.reasons.append("missing only \(match.missing.count)")
            }
        }

        // Mood via tags/title/ingredients.
        if request.mood != .any {
            let text = (recipe.title + " " + recipe.tags.joined(separator: " ") + " "
                + recipe.ingredients.map(\.name).joined(separator: " ")).lowercased()
            let hits = request.mood.keywords.filter { text.contains($0) }
            if hits.isEmpty {
                details.score -= 1.5
            } else {
                details.score += Double(min(hits.count, 3))
                details.reasons.append(hits.first.map { "\(request.mood.rawValue.lowercased()): \($0)" } ?? "")
            }
        }

        // Taste profile overlap (gentle nudge).
        if !request.tasteProfile.isEmpty {
            let recipeTags = Set(recipe.tags.map { $0.lowercased() })
            let overlap = request.tasteProfile.filter { recipeTags.contains($0.lowercased()) }
            details.score += 0.3 * Double(min(overlap.count, 3))
        }

        // Ratings and history.
        if let rating = recipe.rating {
            details.score += Double(rating) / 2.5
            if rating >= 4 { details.reasons.append("you rated it \(rating)★") }
        }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        if request.sessions.contains(where: { $0.recipe === recipe && $0.date > weekAgo }) {
            details.score -= 1.5
        }

        // Use-soon ingredients.
        let useSoonNames = request.pantry
            .filter { $0.useSoonDate != nil && $0.roughQuantity != .out }
            .map(\.canonicalName)
        if !useSoonNames.isEmpty {
            let recipeNames = Set(recipe.ingredients.map(\.canonicalName))
            let usedSoon = useSoonNames.filter { soon in
                recipeNames.contains { $0.contains(soon) || soon.contains($0) }
            }
            if let first = usedSoon.first {
                details.usesUseSoon = true
                details.score += 1.0
                details.reasons.append("uses your \(first) before it goes bad")
            }
        }

        details.reasons = Array(details.reasons.filter { !$0.isEmpty }.prefix(3))
        return details
    }
}
