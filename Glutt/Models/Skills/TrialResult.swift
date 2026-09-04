import Foundation
import SwiftData

/// One judged attempt at a mastery trial.
///
/// The mastery challenges already had a different shape on the map, a diamond
/// rather than a circle, and were already the moment a region asks you to put
/// the pieces together. This is what makes them count: a trial is scored, kept,
/// and it is the only thing that moves a cook's rating.
///
/// Ordinary lessons still award XP and still mark themselves learned. They do
/// not touch this. Reading is not doing.
@Model
final class TrialResult {

    /// The mastery skill this was an attempt at.
    var skillID: String
    /// Denormalised so a rating can be computed without walking the catalog for
    /// every row, and so a result survives a skill being re-homed.
    var categoryID: String

    /// 0 to 100, from the rubric. See `TrialScore`.
    var score: Int
    var finishedAt: Date

    /// How many times the cook asked for help during the attempt.
    ///
    /// Recorded rather than punished. A result that says "independent" means
    /// something precisely because the alternative is stated rather than
    /// silently deducted, and deducting arbitrary points for asking a question
    /// would make this feel designed as a game rather than as cooking.
    var coachCalls: Int

    /// What the rubric could not see, so the result can say so.
    ///
    /// Admitted uncertainty reads as more trustworthy than invented precision,
    /// and it stops a trial being marked down for something nobody could judge.
    var unscored: [String]

    init(
        skillID: String,
        categoryID: String,
        score: Int,
        finishedAt: Date = .now,
        coachCalls: Int = 0,
        unscored: [String] = []
    ) {
        self.skillID = skillID
        self.categoryID = categoryID
        self.score = score
        self.finishedAt = finishedAt
        self.coachCalls = coachCalls
        self.unscored = unscored
    }

    var wasIndependent: Bool { coachCalls == 0 }

    /// How this result moved the cook's rating.
    ///
    /// Centred on 75, so a solid pass nudges up and a poor one nudges down, and
    /// a cook cannot climb by repeatedly scraping through. Capped both ways so
    /// one exceptional or one disastrous attempt never dominates a history.
    var ratingDelta: Int {
        let raw = Double(score - 75) * 0.9
        let bounded = max(-25.0, min(30.0, raw))
        // Independence is worth something real, but as a bonus on a good
        // result rather than a penalty on a helped one.
        let bonus = wasIndependent && score >= 75 ? 4.0 : 0
        return Int((bounded + bonus).rounded())
    }
}

/// Turning what the assessor saw into a number.
///
/// The rule this follows, and the reason the number is worth printing: **the
/// model observes, the system interprets, an authored rubric scores.** Never
/// "ask the model for a mark out of a hundred". Everything here is derived from
/// evidence the check pipeline already produces and already gates on, which is
/// the same discipline that stops a grip verdict being a guess.
enum TrialScore {

    /// Where a clean pass lands before anything is taken off.
    static let passBaseline = 88
    /// Where a corrected attempt starts.
    static let correctedBaseline = 68

    /// Score one attempt.
    ///
    /// - Parameters:
    ///   - outcomes: what each check in the trial came back as, in order.
    ///   - unscored: parts nobody could see, which neither help nor hurt.
    static func score(
        outcomes: [SkillAttemptOutcome],
        unscored: [String] = []
    ) -> Int {
        let judged = outcomes.filter { $0 != .inconclusive }
        // Nothing was actually seen, so there is nothing to score. The caller
        // is expected to treat this as "not scored" rather than as a zero,
        // because a zero is a claim about the cooking and this is a claim
        // about the pictures.
        guard !judged.isEmpty else { return 0 }

        var total = 0
        for outcome in judged {
            switch outcome {
            case .passed:
                total += passBaseline
            case .corrected:
                total += correctedBaseline
            case .stoppedForSafety:
                // A hand on the blade is not a low score, it is a failure. The
                // lesson stops for it, and the trial should say so plainly.
                total += 30
            case .wrongEquipment, .inconclusive:
                continue
            }
        }
        let mean = Double(total) / Double(judged.count)

        // Being sure of less is worth less. A trial judged on one of four
        // checks is a thinner result than one judged on all four, and saying
        // 91 from a single glance would be inventing precision.
        let coverage = Double(judged.count) / Double(max(outcomes.count, 1))
        let confidence = 0.85 + 0.15 * coverage

        return max(0, min(100, Int((mean * confidence).rounded())))
    }
}
