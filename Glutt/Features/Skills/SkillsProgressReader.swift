import Foundation
import SwiftData

/// Turns the `SkillProgress` rows into the handful of numbers the Skills
/// screens actually ask for.
///
/// A plain value built from a query result rather than an observable object:
/// the views already re-render when the `@Query` changes, so anything more is
/// machinery for its own sake.
struct SkillsProgressReader {
    let learnedIDs: Set<String>
    let inProgressIDs: Set<String>
    let totalXP: Int
    let streak: Int

    init(progress: [SkillProgress], today: Date = .now) {
        var learned: Set<String> = []
        var started: Set<String> = []
        var xp = 0
        for row in progress {
            if row.isLearned {
                learned.insert(row.skillID)
                xp += row.xpAwarded
            } else if row.isInProgress {
                started.insert(row.skillID)
            }
        }
        self.learnedIDs = learned
        self.inProgressIDs = started
        self.totalXP = xp
        self.streak = SkillStreak.current(today: today)
    }

    var learnedCount: Int { learnedIDs.count }
    var level: Int { SkillProgression.level(forXP: totalXP) }
    var levelProgress: (level: Int, into: Int, needed: Int) {
        SkillProgression.levelProgress(forXP: totalXP)
    }
    var hasStarted: Bool { !learnedIDs.isEmpty || !inProgressIDs.isEmpty }

    /// The skill the map points at, preferring to finish the region the cook
    /// was last working in.
    var recommended: Skill? {
        let lastCategory = inProgressIDs.compactMap(SkillCatalog.skill(_:)).first?.categoryID
        return SkillProgression.recommended(learnedIDs: learnedIDs, preferringCategory: lastCategory)
    }

    /// What "Continue learning" offers: something opened but unfinished, else
    /// whatever is recommended next.
    var continueTarget: (skill: Skill, isResuming: Bool)? {
        if let started = inProgressIDs.compactMap(SkillCatalog.skill(_:)).first {
            return (started, true)
        }
        if let next = recommended { return (next, false) }
        return nil
    }

    func state(for skill: Skill) -> SkillState {
        SkillProgression.state(
            for: skill,
            learnedIDs: learnedIDs,
            inProgressIDs: inProgressIDs,
            recommendedID: recommended?.id
        )
    }
}
