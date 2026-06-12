import Foundation
import NaturalLanguage

/// Semantic recipe search: find "that creamy lemon chicken thing" without
/// remembering its name. Hybrid ranking — keyword hits + on-device word
/// embeddings (NLEmbedding) — fully offline, no API needed.
enum RecipeSearchEngine {

    struct SearchResult {
        let recipe: Recipe
        let score: Double
        /// Why this matched, shown as chips ("creamy", "lemon", "cooked 3 weeks ago").
        let reasons: [String]
    }

    private static let embedding = NLEmbedding.wordEmbedding(for: .english)

    /// Words that carry no food meaning in a search query.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "that", "this", "with", "and", "or", "in", "of",
        "thing", "dish", "recipe", "meal", "from", "for", "my", "i", "made",
        "make", "want", "some", "something", "like", "kind", "sort",
    ]

    static func search(query: String, recipes: [Recipe], sessions: [CookSession] = []) -> [SearchResult] {
        let queryWords = significantWords(in: query)
        guard !queryWords.isEmpty else { return [] }

        let results = recipes.compactMap { recipe -> SearchResult? in
            let document = documentWords(for: recipe)
            var score = 0.0
            var reasons: [String] = []

            for word in queryWords {
                // Exact keyword hit anywhere in the recipe text: strong signal.
                if document.contains(word) {
                    score += 1.0
                    reasons.append(word)
                    continue
                }
                // Embedding similarity: "tangy" should still find "zesty"/"lemon".
                if let best = bestSimilarity(of: word, in: document), best.similarity > 0.55 {
                    score += best.similarity * 0.8
                    reasons.append("\(word) ≈ \(best.word)")
                }
            }

            // Cook-history recency: "the beef thing from last month".
            if mentionsPast(query), let lastCooked = sessions.filter({ $0.recipe === recipe }).map(\.date).max() {
                let weeks = max(1, Int(-lastCooked.timeIntervalSinceNow / 604_800))
                score += 0.5
                reasons.append(weeks == 1 ? "cooked last week" : "cooked \(weeks) weeks ago")
            }

            guard score > 0.4 else { return nil }
            return SearchResult(recipe: recipe, score: score, reasons: Array(reasons.prefix(3)))
        }

        return results.sorted { $0.score > $1.score }
    }

    // MARK: - Internals

    static func significantWords(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    private static func documentWords(for recipe: Recipe) -> Set<String> {
        var text = recipe.title + " " + recipe.tags.joined(separator: " ")
        text += " " + recipe.ingredients.map(\.name).joined(separator: " ")
        text += " " + recipe.notes
        if let summary = recipe.summary { text += " " + summary }
        return Set(significantWords(in: text))
    }

    private static func bestSimilarity(of word: String, in document: Set<String>) -> (word: String, similarity: Double)? {
        guard let embedding else { return nil }
        var best: (String, Double)?
        for candidate in document {
            // NLEmbedding distance is cosine distance: similarity = 1 - distance.
            let distance = embedding.distance(between: word, and: candidate)
            guard distance > 0 else { continue }
            let similarity = 1 - distance
            if similarity > (best?.1 ?? 0) {
                best = (candidate, similarity)
            }
        }
        return best.map { (word: $0.0, similarity: $0.1) }
    }

    private static func mentionsPast(_ query: String) -> Bool {
        let lowered = query.lowercased()
        return ["last week", "last month", "weeks ago", "a while", "before", "again"]
            .contains { lowered.contains($0) }
    }
}
