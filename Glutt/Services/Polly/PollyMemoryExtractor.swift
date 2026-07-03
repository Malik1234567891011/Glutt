import Foundation
import SwiftData

// MARK: - Task 14 placeholder
//
// This is the MINIMAL surface Task 13 (`PollySessionController`) compiles
// against. Task 14 completes this file: it fills in `extract()` with the real
// one-shot LLM call and may move the custom `Decodable` conformances into an
// extension. Until then:
//   • `Fact` / `Extraction` carry the synthesized memberwise inits the tests use.
//   • `apply(_:recipeTitle:in:)` is FULLY implemented — the controller's `end()`
//     persistence test depends on it writing PollyMemory rows.
//   • `extract(transcript:recipeTitle:)` is a stub that throws; it exists only so
//     `PollySessionController.Dependencies.live` (a default-argument closure that
//     tests never invoke) type-checks. Do not rely on it before Task 14.

/// Turns a finished cook's transcript into durable kitchen facts + a summary.
enum PollyMemoryExtractor {
    /// One learned fact. `kind` is a `MemoryKind.rawValue`; unknown values are
    /// dropped by `apply`.
    struct Fact: Decodable, Equatable {
        var kind: String
        var text: String
        var confidence: Double
    }

    /// The extractor's full result: the facts to reinforce plus a one-line
    /// human summary of how the cook went.
    struct Extraction: Decodable, Equatable {
        var facts: [Fact]
        var summary: String
    }

    enum ExtractorError: LocalizedError {
        /// Task 14 replaces this with the real extraction call.
        case notImplemented

        var errorDescription: String? {
            switch self {
            case .notImplemented: "Memory extraction isn't wired up yet."
            }
        }
    }

    /// Reinforce each extracted fact into `PollyMemory` (dedup handled by the
    /// store's fuzzy upsert). Unknown `kind` strings are skipped. Caller owns
    /// saving the context — the controller's `end()` saves once for the whole
    /// teardown.
    static func apply(_ extraction: Extraction, recipeTitle: String, in context: ModelContext) {
        for fact in extraction.facts {
            guard let kind = MemoryKind(rawValue: fact.kind) else { continue }
            PollyMemoryStore.upsert(
                kind: kind,
                text: fact.text,
                confidence: fact.confidence,
                sourceRecipeTitle: recipeTitle,
                in: context)
        }
    }

    /// Placeholder — Task 14 implements the real LLM extraction. Present only so
    /// `Dependencies.live` compiles; the injected test deps never call it.
    static func extract(transcript: String, recipeTitle: String) async throws -> Extraction {
        throw ExtractorError.notImplemented
    }
}
