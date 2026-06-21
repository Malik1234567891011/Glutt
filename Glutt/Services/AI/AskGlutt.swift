import Foundation

/// Recipes-search ranking: take the user's on-device semantic search hits and,
/// when the LLM is configured, reorder + annotate them and write a one-line
/// headline. One round trip; graceful on-device fallback when AI is off.
enum AskGlutt {

    struct RankedResult {
        let recipe: Recipe
        let reasons: [String]
        let badge: String?
    }

    struct RankedSearch {
        var headline: String?
        var results: [RankedResult]
        var usedAI: Bool
    }

    /// One model pick, mapping a position in the candidate list to a reason/badge.
    struct Pick {
        let index: Int
        let reason: String?
        let badge: String?
    }

    // MARK: - Entry point

    /// Rank/annotate the user's on-device search hits with one LLM round trip.
    /// Falls back to the on-device order (no headline) when AI is off or fails.
    /// Never drops a recipe — only reorders and annotates.
    static func rankSearch(
        query: String,
        results: [RecipeSearchEngine.SearchResult],
        pantry: [PantryItem]
    ) async -> RankedSearch {
        let passthrough = results.map {
            RankedResult(recipe: $0.recipe, reasons: $0.reasons, badge: nil)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !results.isEmpty, LLMClient.isConfigured else {
            return RankedSearch(headline: nil, results: passthrough, usedAI: false)
        }
        guard let llm = await requestRanking(query: trimmed, results: results, pantry: pantry) else {
            return RankedSearch(headline: nil, results: passthrough, usedAI: false)
        }
        let picks = llm.picks.map { Pick(index: $0.index, reason: $0.reason, badge: $0.badge) }
        let ranked = reorder(results, picks: picks).map { entry in
            RankedResult(
                recipe: entry.item.recipe,
                reasons: entry.reason.map { [$0] } ?? entry.item.reasons,
                badge: entry.badge
            )
        }
        return RankedSearch(headline: llm.headline, results: ranked, usedAI: true)
    }

    // MARK: - Pure reordering (testable)

    /// Picked items first (in pick order, de-duplicated, bounds-checked), then the
    /// untouched remainder in original order. No network, no SwiftData.
    static func reorder<T>(_ items: [T], picks: [Pick]) -> [(item: T, reason: String?, badge: String?)] {
        var used = Set<Int>()
        var out: [(item: T, reason: String?, badge: String?)] = []
        for pick in picks {
            guard items.indices.contains(pick.index), !used.contains(pick.index) else { continue }
            used.insert(pick.index)
            out.append((items[pick.index], pick.reason, pick.badge))
        }
        for (i, item) in items.enumerated() where !used.contains(i) {
            out.append((item, nil, nil))
        }
        return out
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

    private static func requestRanking(
        query: String,
        results: [RecipeSearchEngine.SearchResult],
        pantry: [PantryItem]
    ) async -> LLMAnswer? {
        let system = """
        You are Glutt, a no-nonsense kitchen sidekick. The user is searching THEIR OWN
        saved recipes (numbered below). Pick the ones that best fit their query —
        never invent recipes, only choose from the list.

        Return JSON: {"headline": str, "picks": [{"index": int, "reason": str, "badge": str}]}
        - picks: 1-4 recipes, best first; index refers to the numbered list. Omit ones that don't fit.
        - reason: one short, specific, casual sentence tied to their request ("creamy and ready in 25 min").
        - badge: 1-3 words ("Closest match", "Fastest", "Uses your salmon").
        - headline: one friendly line summarizing what you found. Keep it clean-ish.
        - Respect explicit constraints (time, cravings, ingredients, meal type, mood) strictly.
        """

        let list = results.enumerated().map { index, result -> String in
            let recipe = result.recipe
            var line = "\(index). \(recipe.title) — \(recipe.totalMinutes) min"
            if !recipe.tags.isEmpty { line += ", tags: \(recipe.tags.joined(separator: "/"))" }
            if let rating = recipe.rating { line += ", rated \(rating)/5" }
            return line
        }.joined(separator: "\n")

        let useSoon = pantry.filter { $0.useSoonDate != nil && $0.roughQuantity != .out }.map(\.name)
        var user = "User searched: \"\(query)\"\n\nTheir recipes:\n\(list)"
        if !useSoon.isEmpty {
            user += "\n\nIngredients that need using soon: \(useSoon.joined(separator: ", "))"
        }

        do {
            return try await LLMClient.chatJSON(
                LLMAnswer.self,
                system: system,
                user: user,
                temperature: 0.4,
                timeout: 20
            )
        } catch {
            return nil
        }
    }
}
