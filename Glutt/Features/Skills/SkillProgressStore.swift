import Foundation
import SwiftData

/// The two writes Skills ever makes: a lesson was opened, and a skill was
/// learned. Kept in one place so the XP snapshot and the streak can never be
/// updated by one caller and forgotten by another.
@MainActor
enum SkillProgressStore {

    static func row(for skillID: String, in context: ModelContext) -> SkillProgress? {
        let descriptor = FetchDescriptor<SkillProgress>(
            predicate: #Predicate { $0.skillID == skillID }
        )
        return try? context.fetch(descriptor).first
    }

    /// Called when a lesson is opened. Makes the skill "in progress" so
    /// Continue Learning has something to offer if the cook leaves.
    static func markOpened(_ skill: Skill, in context: ModelContext) {
        if let existing = row(for: skill.id, in: context) {
            if existing.startedAt == nil { existing.startedAt = .now }
        } else {
            context.insert(SkillProgress(skillID: skill.id))
        }
        try? context.save()
    }

    /// Marks a skill learned, awards its XP and advances the streak.
    ///
    /// Idempotent: tapping "I've got it" twice must not pay twice, which is
    /// easy to do by accident with a sheet that can be reopened.
    @discardableResult
    static func markLearned(_ skill: Skill, in context: ModelContext) -> Bool {
        let existing = row(for: skill.id, in: context)
        if let existing, existing.isLearned { return false }

        let awarded = skill.xp
        if let existing {
            existing.learnedAt = .now
            existing.xpAwarded = awarded
        } else {
            context.insert(SkillProgress(skillID: skill.id, learnedAt: .now, xpAwarded: awarded))
        }
        try? context.save()
        SkillStreak.recordLearned()
        Analytics.capture(.skillLearned, [
            "category": skill.categoryID,
            "difficulty": skill.difficulty.rawValue,
            "challenge": skill.isChallenge,
        ])
        return true
    }
}
