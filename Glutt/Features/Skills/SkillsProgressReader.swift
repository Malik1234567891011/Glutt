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

    /// `evidence` defaults to empty so every existing caller and test keeps
    /// working: a cook nobody has watched yet is simply unranked, which is the
    /// correct answer rather than a special case.
    init(progress: [SkillProgress], evidence: [RatingEvidence] = [], today: Date = .now) {
        self.evidence = evidence
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

    /// Everything Glutt has actually watched this cook do: verified skill
    /// checks and mastery trials alike. Empty until they have been seen once.
    let evidence: [RatingEvidence]

    /// What they have demonstrated, or nil while unranked.
    ///
    /// Separate from `levelProgress` on purpose, and the separation is the
    /// point: a level says how much of the world you have walked, a rating says
    /// what you have shown. Reading every lesson and pressing "I've got it"
    /// moves one and not the other.
    var cookRating: Int? { CookRating.rating(from: evidence) }

    var cookRank: CookRank? { cookRating.map(CookRank.rank(for:)) }

    /// A region's demonstrated standard, nil where there is nothing to measure
    /// or not enough of it yet.
    func rating(for category: SkillCategory) -> Int? {
        RegionRating.rating(for: category, evidence: evidence)
    }

    /// The best a cook has ever scored on one trial, for the mark under its
    /// node on the map.
    /// How many times this skill has been verified, for the mark under a
    /// mastery node on the map.
    ///
    /// A count rather than a best score, because evidence is no longer a score:
    /// the checking pipeline answers narrow authored questions and the app
    /// decides what they mean, so "verified three times" is a claim we can
    /// stand behind where "best 91" was not.
    func verifiedCount(for skillID: String) -> Int {
        evidence.filter { $0.skillID == skillID && $0.credit == .clean }.count
    }

    /// True while the rating rests on too little to present as settled.
    var isRatingProvisional: Bool { CookRating.isProvisional(evidence) }
    var hasStarted: Bool { !learnedIDs.isEmpty || !inProgressIDs.isEmpty }

    /// The skill the map points at, preferring to finish the region the cook
    /// was last working in.
    var recommended: Skill? {
        // Where they were working, unless what they have shown says otherwise.
        //
        // Weakness only overrides once there is real evidence of it: a region
        // has to be rated, which takes judged trials, and it has to be
        // meaningfully behind the cook's own average rather than merely lowest.
        // Without that guard this would yank somebody out of the region they
        // are halfway through on the strength of one bad afternoon.
        //
        // Nothing new appears on screen for this. Polly simply walks to a
        // different node, which is the recommendation already working: the
        // behaviour of a thing already in the world says it, rather than a card
        // announcing that it has personalised something.
        let lastCategory = lastTouchedID.flatMap(SkillCatalog.skill(_:))?.categoryID
        let target = weakestDemonstratedRegion ?? lastCategory
        return SkillProgression.recommended(learnedIDs: learnedIDs, preferringCategory: target)
    }

    /// How far behind a region has to be before it pulls the recommendation.
    private static let weaknessGap = 8

    /// The region a cook is measurably worst at, when that is worth acting on.
    var weakestDemonstratedRegion: String? {
        let rated = SkillCatalog.categories.compactMap { category -> (String, Int)? in
            guard let score = rating(for: category) else { return nil }
            return (category.id, score)
        }
        // Two rated regions is the minimum for "worst" to mean anything.
        guard rated.count >= 2, let weakest = rated.min(by: { $0.1 < $1.1 }) else { return nil }
        let average = rated.reduce(0) { $0 + $1.1 } / rated.count
        guard average - weakest.1 >= Self.weaknessGap else { return nil }
        // Only if there is actually something left to learn there.
        let hasWork = SkillCatalog.categories
            .first { $0.id == weakest.0 }?
            .skills.contains { !learnedIDs.contains($0.id) } ?? false
        return hasWork ? weakest.0 : nil
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
