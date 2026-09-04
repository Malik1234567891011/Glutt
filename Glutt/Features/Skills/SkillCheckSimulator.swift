#if DEBUG
import Foundation
import SwiftData

/// Writes what a passed check would have written, without the check.
///
/// This exists so the rating can be driven without cooking, because the only
/// other way to see a placement, a provisional line, a rank change or a region
/// standard is to actually cook eight things and photograph them. Testing the
/// arithmetic should not cost an afternoon and a lot of onions.
///
/// **The whole file is behind `#if DEBUG`,** not one function inside it, and
/// `SkillCheckSimulatorTests` fails if that ever stops being true. The rating
/// only means anything because it cannot be awarded by tapping, so a way to
/// award it by tapping is exactly the thing that must not ship. Behind a
/// compiler flag rather than behind a comment saying to remove it later,
/// because comments like that are how things ship.
///
/// # Why it writes a full pass rather than a bare row
///
/// It goes through the same shapes the real path produces: an attempt tagged
/// `.showing`, then one piece of evidence carrying the skill's real weight and
/// its authored criteria. A simulator that wrote a simpler row than the real
/// path would test a code path that does not exist, which is worse than not
/// testing at all: it would come back green while the shipping path was broken.
@MainActor
enum SkillCheckSimulator {

    /// The note every simulated attempt carries.
    ///
    /// Spelled out in the history rather than hidden, so a row that was tapped
    /// can never be mistaken for a row that was earned while reading back a
    /// test run.
    static let note = "Marked without a check, debug only"

    /// Record a clean pass for a skill, as though Chef had watched it.
    ///
    /// Returns false for a skill with no visual check. Those produce no
    /// evidence on the real path either, and inventing some here would let the
    /// simulator place a cook on skills the app can never verify.
    @discardableResult
    static func recordPass(for skill: Skill, in context: ModelContext) -> Bool {
        guard let check = skill.visualCheck,
              let categoryID = SkillCatalog.category(of: skill)?.id
        else { return false }

        let attempt = SkillAttempt(
            skillID: skill.id,
            checkID: check.id,
            startedAt: .now,
            seconds: 0,
            outcome: .passed,
            note: note,
            source: .showing)
        _ = SkillProgressStore.recordAttempt(attempt, skill: skill, in: context)

        // Every authored criterion met, because a clean pass and a full count
        // are the same claim and a row where they disagreed would be a state
        // the real path cannot produce.
        //
        // Left at zero below `minimumCountableCriteria`, exactly as a real
        // check would, so the coarse credit carries it and the simulator does
        // not manufacture a score the shipping path would refuse to.
        let scoreable = check.observations.filter { $0.correct != nil }.count
        let counted = scoreable >= SkillVisualCheck.minimumCountableCriteria ? scoreable : 0

        context.insert(RatingEvidence(
            skillID: skill.id,
            categoryID: categoryID,
            kind: skill.isChallenge ? .masteryTrial : .skillCheck,
            credit: .clean,
            weight: EvidenceWeight.weight(for: skill),
            criteriaMet: counted,
            criteriaObservable: counted))
        return true
    }
}
#endif
