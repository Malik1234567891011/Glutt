import Foundation
import SwiftData

/// Post-cook memory: one `chatJSON` pass over the session transcript pulls
/// out durable kitchen facts (stove runs hot, owns cast iron, chops slowly)
/// plus a short summary for the cook log. `apply` lands the facts in
/// `PollyMemory` through the store's dedup/reinforce upsert — the LLM
/// proposes, the store disposes.
enum PollyMemoryExtractor {

    struct Fact: Decodable, Equatable {
        let kind: String
        let text: String
        let confidence: Double
    }

    struct Extraction: Decodable, Equatable {
        let facts: [Fact]
        let summary: String
    }

    typealias LLM = (_ system: String, _ user: String) async throws -> Extraction

    /// One-shot extraction over the full session transcript.
    /// `llm` is injectable for tests; the default routes through the proxy.
    static func extract(
        transcript: String,
        recipeTitle: String,
        llm: LLM = { system, user in
            try await LLMClient.chatJSON(Extraction.self, system: system, user: user, temperature: 0.2, timeout: 30)
        }
    ) async throws -> Extraction {
        guard LLMClient.isConfigured else { throw LLMClient.LLMError.notConfigured }

        let system = """
        You read the transcript of a live cooking session and extract DURABLE kitchen facts
        a chef should remember about this specific cook and this cook's kitchen.

        Return JSON: {"facts": [{"kind": str, "text": str, "confidence": num}], "summary": str}

        Rules:
        - kind: one of "equipment", "technique", "pantryHabit", "preference", "outcome".
        - text: one sentence, third person ("Their stove runs hot", "They own a cast-iron skillet").
        - confidence: 0 to 1 — how sure you are the fact holds beyond this one session.
        - Only durable facts: equipment they own, how their appliances behave, techniques they
          struggle with or excel at, what they keep stocked, what they like, how their dishes
          tend to turn out.
        - Ignore one-off chatter, jokes, and anything specific to just this dish today.
        - Return an empty facts array when nothing durable came up.
        - summary: 2-3 sentences describing how this cook went, for the session log.
        """

        let user = """
        Recipe: \(recipeTitle)

        Transcript:
        \(transcript)
        """

        return try await llm(system, user)
    }

    /// Write extracted facts into on-device memory. Unknown kinds fall back
    /// to `.outcome`, confidence is clamped to 0...1, and fragments under
    /// 8 characters are dropped as noise. Dedup/reinforce lives in the store.
    static func apply(_ extraction: Extraction, recipeTitle: String, in context: ModelContext) {
        for fact in extraction.facts {
            guard fact.text.count >= 8 else { continue }
            let kind = MemoryKind(rawValue: fact.kind) ?? .outcome
            let confidence = min(max(fact.confidence, 0), 1)
            PollyMemoryStore.upsert(
                kind: kind,
                text: fact.text,
                confidence: confidence,
                sourceRecipeTitle: recipeTitle,
                in: context
            )
        }
    }
}
