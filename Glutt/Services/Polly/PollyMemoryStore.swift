import Foundation
import SwiftData

/// Write/read chokepoint over `PollyMemory`. All writes go through `upsert`,
/// which reinforces an existing near-duplicate fact (same kind, fuzzy text
/// match) instead of inserting a new row — memories get stronger, not noisier.
/// Callers own saving the context.
enum PollyMemoryStore {
    /// Two texts describe "the same fact" when the Jaccard index of their
    /// lowercased word sets is at least this.
    private static let duplicateThreshold = 0.6

    @discardableResult
    static func upsert(
        kind: MemoryKind,
        text: String,
        confidence: Double,
        sourceRecipeTitle: String?,
        in context: ModelContext
    ) -> PollyMemory {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<PollyMemory>(
            predicate: #Predicate { $0.kindRaw == raw },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let sameKind = (try? context.fetch(descriptor)) ?? []
        let newWords = words(in: text)

        if let existing = sameKind.first(where: { jaccard(words(in: $0.text), newWords) >= duplicateThreshold }) {
            existing.timesReinforced += 1
            existing.confidence = max(existing.confidence, confidence)
            existing.updatedAt = .now
            if text.count > existing.text.count {
                existing.text = text
            }
            if existing.sourceRecipeTitle == nil {
                existing.sourceRecipeTitle = sourceRecipeTitle
            }
            return existing
        }

        let memory = PollyMemory(kind: kind, text: text, confidence: confidence, sourceRecipeTitle: sourceRecipeTitle)
        context.insert(memory)
        return memory
    }

    /// Strongest facts first: most-reinforced, then most recently updated.
    static func topFacts(limit: Int, in context: ModelContext) -> [PollyMemory] {
        var descriptor = FetchDescriptor<PollyMemory>(sortBy: [
            SortDescriptor(\.timesReinforced, order: .reverse),
            SortDescriptor(\.updatedAt, order: .reverse),
        ])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Fuzzy match

    /// Lowercased alphanumeric word set: "My stove runs HOT!" ->
    /// {"my", "stove", "runs", "hot"}.
    private static func words(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b)
        guard !union.isEmpty else { return 1 } // two empty texts are the same fact
        return Double(a.intersection(b).count) / Double(union.count)
    }
}
