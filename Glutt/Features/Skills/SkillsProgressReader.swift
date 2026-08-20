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
    /// The skill they opened most recently and did not finish.
    ///
    /// Kept separately because `inProgressIDs` is a `Set` and a set has no
    /// order. Reading "the region they were last working in" off `.first` of a
    /// set meant the recommendation could point at a different region on every
    /// launch, with Polly walking off to whichever one Swift happened to hash
    /// first. `startedAt` is the only honest answer to "where were they".
    let lastStartedID: String?

    /// The skill they last did anything with, opened **or** learned.
    ///
    /// Distinct from `lastStartedID` because they answer different questions.
    /// "Where are they working" has to count finishing a lesson as activity: a
    /// cook who just learned the eighth of nine skills in a region, and who
    /// once opened something in another region and wandered off, was being sent
    /// to that other region with one node left in this one. Whether to *resume*
    /// is still `lastStartedID`, because a finished lesson is nothing to
    /// resume.
    let lastTouchedID: String?
    let totalXP: Int
    let streak: Int

    init(progress: [SkillProgress], today: Date = .now) {
        var learned: Set<String> = []
        var started: Set<String> = []
        var mostRecent: (id: String, at: Date)?
        var mostRecentTouch: (id: String, at: Date)?
        var xp = 0
        for row in progress {
            if row.isLearned {
                learned.insert(row.skillID)
                xp += row.xpAwarded
            } else if row.isInProgress {
                started.insert(row.skillID)
                if let at = row.startedAt, at > (mostRecent?.at ?? .distantPast) {
                    mostRecent = (row.skillID, at)
                }
            }
            // Whichever end of this row is later. A learned row keeps its
            // `startedAt`, so taking the max is what makes finishing count as
            // activity rather than the moment they first opened it.
            let touched = [row.startedAt, row.learnedAt].compactMap { $0 }.max()
            if let touched, touched > (mostRecentTouch?.at ?? .distantPast) {
                mostRecentTouch = (row.skillID, touched)
            }
        }
        self.learnedIDs = learned
        self.inProgressIDs = started
        self.lastStartedID = mostRecent?.id
        self.lastTouchedID = mostRecentTouch?.id
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
        let lastCategory = lastTouchedID.flatMap(SkillCatalog.skill(_:))?.categoryID
        return SkillProgression.recommended(learnedIDs: learnedIDs, preferringCategory: lastCategory)
    }

    /// What "Continue learning" offers: something opened but unfinished, else
    /// whatever is recommended next.
    var continueTarget: (skill: Skill, isResuming: Bool)? {
        if let started = lastStartedID.flatMap(SkillCatalog.skill(_:)) {
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
