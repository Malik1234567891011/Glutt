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

    /// Records one attempt at a watchable skill, and promotes the skill's state
    /// to match what just happened.
    ///
    /// Both writes live here for the reason the type comment gives: an attempt
    /// that advanced somebody to mastered and did not say so is a bug nobody
    /// notices for a week. A passing attempt also marks the skill learned, since
    /// being watched doing it correctly is a strictly stronger claim than
    /// tapping a button to say you can.
    @discardableResult
    static func recordAttempt(
        _ attempt: SkillAttempt,
        skill: Skill,
        in context: ModelContext
    ) -> Bool {
        context.insert(attempt)

        // Attempting it at all counts as starting, for a cook who went straight
        // to the check without reading the lesson first.
        let row: SkillProgress
        if let existing = self.row(for: skill.id, in: context) {
            row = existing
            if row.startedAt == nil { row.startedAt = attempt.startedAt }
        } else {
            row = SkillProgress(skillID: skill.id, startedAt: attempt.startedAt)
            context.insert(row)
        }

        var becameMastered = false
        if attempt.isPass {
            if row.masteredAt == nil {
                row.masteredAt = attempt.startedAt
                becameMastered = true
            }
            if row.learnedAt == nil {
                row.learnedAt = attempt.startedAt
                row.xpAwarded = skill.xp
                SkillStreak.recordLearned()
                Analytics.capture(.skillLearned, [
                    "category": skill.categoryID,
                    "difficulty": skill.difficulty.rawValue,
                    "challenge": skill.isChallenge,
                    "verified": true,
                ])
            }
        }

        try? context.save()
        return becameMastered
    }

    /// Every attempt at one skill, newest first.
    static func attempts(for skillID: String, in context: ModelContext) -> [SkillAttempt] {
        let descriptor = FetchDescriptor<SkillAttempt>(
            predicate: #Predicate { $0.skillID == skillID },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
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
