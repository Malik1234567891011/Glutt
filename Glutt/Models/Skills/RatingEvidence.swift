import Foundation
import SwiftData

/// One thing Glutt actually watched a cook do.
///
/// The rule the whole rating stands on: **lessons tell us what a cook has
/// learned, verified cooking tells us what they can do.** Reading a lesson and
/// pressing "I've got it" produces XP and no evidence. Being watched produces
/// evidence and no XP. The two systems never feed each other.
///
/// Replaces `TrialResult`, which could only be written by a mastery trial and
/// therefore made the rating unreachable for anybody who had not finished one.
/// An ordinary watchable node is thinner evidence than a trial, not *no*
/// evidence, and the difference is a weight rather than a gate.
///
/// # This is not a score
///
/// Nothing here asks a model how good the cooking was. The checking pipeline
/// answers narrow authored questions, the app decides what those answers mean,
/// and this records the decision. A node that establishes "the pinch grip is
/// correct" is one small piece of positive evidence, not an 84 out of 100.
///
/// # Uncertainty never costs anything
///
/// An unusable picture, a part nobody could see, or a check that came back
/// inconclusive writes NO ROW. Not a zero, not a low weight: nothing. The
/// model failing to see something is a fact about the photograph and must
/// never read as a fact about the cook.
@Model
final class RatingEvidence {

    var skillID: String
    /// Denormalised so a region's standing can be computed without walking the
    /// catalog per row, and so evidence survives a skill being re-homed.
    var categoryID: String

    /// Stored raw for SwiftData. See `kind`.
    var kindRaw: String
    /// Stored raw for SwiftData. See `credit`.
    var creditRaw: Double

    /// What this piece of evidence is worth before diminishing returns.
    ///
    /// Set at write time from the skill's difficulty and whether it was a
    /// trial, so retuning the table later cannot silently rewrite history.
    var weight: Double

    var occurredAt: Date

    /// Times the cook asked for help during a trial. Recorded, never deducted.
    var coachCalls: Int

    /// Parts of the technique nobody could see, so a result can say so out
    /// loud rather than quietly counting them against the cook.
    var unscored: [String]

    init(
        skillID: String,
        categoryID: String,
        kind: Kind,
        credit: Credit,
        weight: Double,
        occurredAt: Date = .now,
        coachCalls: Int = 0,
        unscored: [String] = []
    ) {
        self.skillID = skillID
        self.categoryID = categoryID
        self.kindRaw = kind.rawValue
        self.creditRaw = credit.rawValue
        self.weight = weight
        self.occurredAt = occurredAt
        self.coachCalls = coachCalls
        self.unscored = unscored
    }

    /// Where the evidence came from.
    enum Kind: String, Codable, Sendable {
        /// An ordinary watchable node. Narrow: it usually establishes one or
        /// two things about one technique.
        case skillCheck
        /// A mastery trial. Deliberately built as an assessment, combining
        /// several criteria, so it is worth several times a single check.
        case masteryTrial
    }

    /// How well it went, as the authored rubric saw it.
    ///
    /// Three states, not a hundred. The checking pipeline reports pass,
    /// correction or danger; anything less certain than that writes no row at
    /// all, so there is no state here for "we are not sure".
    enum Credit: Double, Codable, Sendable {
        /// Verified, nothing to fix.
        case clean = 1.0
        /// Done, with one authored correction to make.
        case corrected = 0.45
        /// A genuine safety failure, seen clearly. Counts as an event and
        /// earns nothing, which is different from not being seen at all.
        case unsafe = 0.0
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .skillCheck }
    var credit: Credit { Credit(rawValue: creditRaw) ?? .corrected }
    var wasIndependent: Bool { coachCalls == 0 }

    /// A short line for the history list.
    var spokenCredit: String {
        switch credit {
        case .clean: "Verified"
        case .corrected: "One fix"
        case .unsafe: "Stopped"
        }
    }
}

/// What a piece of evidence is worth, and when it exists at all.
///
/// Kept apart from the model so the table can be read, argued with and tested
/// without a database.
enum EvidenceWeight {

    /// Weight before diminishing returns.
    ///
    /// A mastery trial is worth five ordinary beginner checks because it is
    /// five-ish checks' worth of judgement in one sitting: several criteria,
    /// deliberately assessed together, on a technique that needs the earlier
    /// ones to already work. An advanced check sits between the two.
    static func weight(for skill: Skill) -> Double {
        if skill.isChallenge { return 5.0 }
        switch skill.difficulty {
        case .beginner: return 1.0
        case .intermediate: return 1.5
        case .advanced: return 2.2
        }
    }

    /// How much the nth piece of evidence on the SAME skill still counts.
    ///
    /// Halving each time, so passing one easy check twenty times is worth
    /// slightly less than passing it twice. Repetition is good practice and
    /// bad evidence: it says nothing new about what the cook can do, and
    /// without this the rating would be farmable by anyone willing to
    /// photograph their hand forty times.
    static func repeatFactor(priorCount: Int) -> Double {
        pow(0.5, Double(max(0, priorCount)))
    }

    /// The evidence a check outcome produces, or nil when it produces none.
    ///
    /// Nil is the important half. An inconclusive read, an unusable picture or
    /// the wrong knife tells us about the photograph rather than the cook, and
    /// must leave the rating exactly where it was.
    static func credit(for outcome: SkillAttemptOutcome) -> RatingEvidence.Credit? {
        switch outcome {
        case .passed: return .clean
        case .corrected: return .corrected
        case .stoppedForSafety: return .unsafe
        case .inconclusive, .wrongEquipment: return nil
        }
    }
}
