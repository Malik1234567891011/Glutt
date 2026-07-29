import Foundation
import SwiftData

/// What kind of kitchen fact Polly learned about the user.
enum MemoryKind: String, Codable, CaseIterable {
    case equipment, technique, pantryHabit, preference, outcome
}

/// A durable fact Polly learned during a cook ("stove runs hot", "owns cast
/// iron"). Facts are reinforced across cooks instead of duplicated — see
/// `PollyMemoryStore.upsert`. Schema is shaped to sync to Postgres later.
@Model
final class PollyMemory {
    /// `MemoryKind.rawValue`, stored raw so an unknown value written by a
    /// future app version still loads (the computed `kind` falls back).
    var kindRaw: String
    var text: String
    /// 0.0–1.0 confidence in the fact.
    var confidence: Double
    /// How many times separate cooks confirmed this fact.
    var timesReinforced: Int
    var createdAt: Date
    var updatedAt: Date
    /// Title of the recipe being cooked when the fact was first learned.
    var sourceRecipeTitle: String?

    var kind: MemoryKind { MemoryKind(rawValue: kindRaw) ?? .outcome }

    init(kind: MemoryKind, text: String, confidence: Double, sourceRecipeTitle: String?) {
        self.kindRaw = kind.rawValue
        self.text = text
        self.confidence = confidence
        self.timesReinforced = 1
        self.createdAt = .now
        self.updatedAt = .now
        self.sourceRecipeTitle = sourceRecipeTitle
    }
}

/// One Polly session's outcome record, written when the session ends.
/// Distinct from `CookSession` (the user's own rating/leftovers log):
/// this captures what Polly saw — progress, substitutions, and a summary.
@Model
final class PollyCookLog {
    var startedAt: Date
    var endedAt: Date?
    var recipe: Recipe?
    var summary: String
    var stepsCompleted: Int
    var stepsTotal: Int
    var substitutions: [String]
    var endedEarly: Bool
    /// Short phrases Polly logged via `record_polly_save` (or inferred).
    /// Default empty so older stores migrate lightly.
    var pollySaves: [String] = []

    init(startedAt: Date, recipe: Recipe?) {
        self.startedAt = startedAt
        self.recipe = recipe
        self.summary = ""
        self.stepsCompleted = 0
        self.stepsTotal = 0
        self.substitutions = []
        self.endedEarly = false
        self.pollySaves = []
    }
}
