import Foundation

/// Free-text asking: "fuck I'm in a rush, what can I cook in 30 mins" →
/// real options from the user's own library. One LLM round trip when
/// configured; search-engine + heuristics fallback when not.
enum AskGlutt {

    struct Answer {
        var recommendations: [MealRecommender.Recommendation]
        /// One conversational line from the model ("Rough day? Here's the fastest comfort food you own.")
        var headline: String?
        var usedAI: Bool
    }

    // MARK: - Entry point

    static func ask(
        query: String,
        recipes: [Recipe],
        pantry: [PantryItem],
        leftovers: [Leftover],
        sessions: [CookSession],
        prefs: UserPrefs
    ) async -> Answer {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Answer(recommendations: [], headline: nil, usedAI: false)
        }

        // Pre-rank with the same heuristics either way: the model only ever
        // chooses among recipes that are real, allowed, and scored.
        let candidates = candidateList(
            query: trimmed,
            recipes: recipes,
            pantry: pantry,
            leftovers: leftovers,
            sessions: sessions,
            prefs: prefs
        )
        guard !candidates.isEmpty else {
            return Answer(recommendations: [], headline: nil, usedAI: false)
        }

        if LLMClient.isConfigured {
            if let answer = await askLLM(query: trimmed, candidates: candidates, pantry: pantry) {
                return answer
            }
        }

        // Offline / failure fallback: top candidates as-is.
        return Answer(
            recommendations: Array(candidates.prefix(4)).map(\.recommendation),
            headline: nil,
            usedAI: false
        )
    }

    // MARK: - Candidate building (heuristics, offline)

    struct Candidate {
        let recipe: Recipe
        let missingCount: Int
        let searchReasons: [String]
        let score: Double

        var recommendation: MealRecommender.Recommendation {
            MealRecommender.Recommendation(
                recipe: recipe,
                badge: missingCount == 0 ? "Ready now" : "Good match",
                reasons: searchReasons,
                missingCount: missingCount
            )
        }
    }

    private static func candidateList(
        query: String,
        recipes: [Recipe],
        pantry: [PantryItem],
        leftovers: [Leftover],
        sessions: [CookSession],
        prefs: UserPrefs
    ) -> [Candidate] {
        let usable = recipes.filter {
            $0.parentRecipe == nil && !$0.steps.isEmpty
                && DietGuard.isSuggestable($0, rules: prefs.dietaryRules, allergies: prefs.allergies)
        }
        guard !usable.isEmpty else { return [] }

        // Blend semantic search hits with general recommendability.
        let searchHits = RecipeSearchEngine.search(query: query, recipes: usable, sessions: sessions)
        let searchScore = Dictionary(
            searchHits.map { (ObjectIdentifier($0.recipe), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return usable
            .map { recipe in
                let match = PantryMatcher.match(recipe: recipe, pantry: pantry)
                let hit = searchScore[ObjectIdentifier(recipe)]
                let base = MealRecommender.score(
                    recipe,
                    request: MealRecommender.Request(
                        recipes: usable, pantry: pantry, leftovers: leftovers, sessions: sessions
                    )
                ).score
                return Candidate(
                    recipe: recipe,
                    missingCount: match.missing.count,
                    searchReasons: hit?.reasons ?? [],
                    score: base + (hit?.score ?? 0) * 2.0
                )
            }
            .sorted { $0.score > $1.score }
            .prefix(12)
            .map { $0 }
    }

    // MARK: - LLM ranking

    private struct LLMAnswer: Decodable {
        struct Pick: Decodable {
            let index: Int
            let reason: String
            let badge: String?
        }
        let headline: String?
        let picks: [Pick]
    }

    private static func askLLM(
        query: String,
        candidates: [Candidate],
        pantry: [PantryItem]
    ) async -> Answer? {
        let system = """
        You are Glutt, a no-nonsense kitchen sidekick. The user asks what to cook;
        you choose from THEIR OWN saved recipes listed below. Never invent recipes.

        Return JSON: {"headline": str, "picks": [{"index": int, "reason": str, "badge": str}]}
        - picks: 2-4 recipes, best first, index refers to the numbered list.
        - reason: one short, specific, casual sentence tied to their request ("25 min and you already have everything").
        - badge: 1-3 words ("Fastest", "Comfort pick", "Uses your salmon").
        - headline: one friendly line answering their vibe. Match their energy, keep it clean-ish.
        - Respect explicit constraints (time, cravings, ingredients) strictly.
        """

        let list = candidates.enumerated().map { index, candidate in
            let recipe = candidate.recipe
            var line = "\(index). \(recipe.title) — \(recipe.totalMinutes) min"
            if !recipe.tags.isEmpty { line += ", tags: \(recipe.tags.joined(separator: "/"))" }
            line += candidate.missingCount == 0
                ? ", has all ingredients"
                : ", missing \(candidate.missingCount) ingredients"
            if let rating = recipe.rating { line += ", user rated \(rating)/5" }
            return line
        }
        .joined(separator: "\n")

        let useSoon = pantry.filter { $0.useSoonDate != nil && $0.roughQuantity != .out }.map(\.name)
        var user = "User asks: \"\(query)\"\n\nTheir recipes:\n\(list)"
        if !useSoon.isEmpty {
            user += "\n\nIngredients that need using soon: \(useSoon.joined(separator: ", "))"
        }

        do {
            let answer = try await LLMClient.chatJSON(
                LLMAnswer.self,
                system: system,
                user: user,
                temperature: 0.5,
                timeout: 20
            )
            let recommendations = answer.picks.compactMap { pick -> MealRecommender.Recommendation? in
                guard candidates.indices.contains(pick.index) else { return nil }
                let candidate = candidates[pick.index]
                return MealRecommender.Recommendation(
                    recipe: candidate.recipe,
                    badge: pick.badge ?? "Pick",
                    reasons: [pick.reason],
                    missingCount: candidate.missingCount
                )
            }
            guard !recommendations.isEmpty else { return nil }
            return Answer(recommendations: recommendations, headline: answer.headline, usedAI: true)
        } catch {
            return nil
        }
    }
}
