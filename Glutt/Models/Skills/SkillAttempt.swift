import Foundation
import SwiftData

/// One time a cook stood there with a knife and let Polly look.
///
/// A row per attempt rather than a counter on `SkillProgress`, because the
/// interesting thing about practice is the shape of it: three attempts where the
/// index finger moved and then stayed put is a story, and `attempts: 3` is not.
/// It is also what "practised twelve times" and any later mastery rule will be
/// computed from, so throwing away the individual attempts now would mean
/// inventing that history later.
///
/// Keyed by `skillID` string for the same reason `SkillProgress` is: skills are
/// static content, and a row has to survive one being renamed or removed.
@Model
final class SkillAttempt {
    /// `Skill.id` from the static catalog.
    var skillID: String
    /// `SkillVisualCheck.id`, so re-authoring a check does not silently merge
    /// old attempts into a rubric they were never judged against.
    var checkID: String
    var startedAt: Date
    /// How long the cook actually held the pose. Sums into practice time.
    var seconds: Double

    /// What happened, as `SkillAttemptOutcome.rawValue`.
    ///
    /// Stored as a string rather than the enum so adding an outcome later is not
    /// a migration, which is the same reason `SkillProgress` stores an id
    /// instead of a relationship.
    var outcomeRaw: String

    /// The line the cook reads in their own history, written at the time.
    ///
    /// Denormalised on purpose. Regenerating it later from `mistakeKey` would
    /// mean an edit to a rubric silently rewriting what somebody was told three
    /// weeks ago, and the whole value of a history is that it is what happened.
    var note: String

    /// Which authored mistake this was, when it was one. Nil for passes, and
    /// for the outcomes where nothing was judged.
    var mistakeKey: String?

    /// What Polly thought the tool was. Kept because "you were using a santoku"
    /// is context that makes an old note make sense.
    var equipmentReading: String?

    /// The assessor's own confidence, 0 to 1. Stored so a run of low confidence
    /// attempts is visible as a camera problem rather than read as the cook
    /// being bad at this.
    var confidence: Double

    /// How Chef saw it: `SkillLearningMode.rawValue`.
    ///
    /// Optional with a default so it is a lightweight migration for anybody who
    /// already has attempts. Worth storing because the two are not the same
    /// evidence: a pass from two deliberate photographs and a pass from frames
    /// snatched out of a moving first person view are different claims, and a
    /// history that flattened them would be quietly overstating one of them.
    var sourceRaw: String?

    init(
        skillID: String,
        checkID: String,
        startedAt: Date = .now,
        seconds: Double = 0,
        outcome: SkillAttemptOutcome,
        note: String,
        mistakeKey: String? = nil,
        equipmentReading: String? = nil,
        confidence: Double = 0,
        source: SkillLearningMode = .watching
    ) {
        self.skillID = skillID
        self.checkID = checkID
        self.startedAt = startedAt
        self.seconds = seconds
        self.outcomeRaw = outcome.rawValue
        self.note = note
        self.mistakeKey = mistakeKey
        self.equipmentReading = equipmentReading
        self.confidence = confidence
        self.sourceRaw = source.rawValue
    }

    var outcome: SkillAttemptOutcome {
        SkillAttemptOutcome(rawValue: outcomeRaw) ?? .inconclusive
    }

    /// Older rows predate this and were all glasses, which is what they say.
    var source: SkillLearningMode {
        sourceRaw.flatMap(SkillLearningMode.init(rawValue:)) ?? .watching
    }

    /// Whether this attempt is the one that proves the cook can do it.
    var isPass: Bool { outcome == .passed }

    /// Whether the cook did anything wrong. An attempt Polly could not see is
    /// not a failed attempt, and the history should never imply it was.
    var reflectsOnCook: Bool {
        outcome == .passed || outcome == .corrected
    }
}

/// What came of one attempt.
enum SkillAttemptOutcome: String, Sendable, CaseIterable {
    /// Polly saw it and was happy with it.
    case passed
    /// Polly saw it and had one thing to fix.
    case corrected
    /// The view was not good enough to judge. Says nothing about the cook.
    case inconclusive
    /// Wrong tool for this lesson.
    case wrongEquipment
    /// Something visibly dangerous stopped the lesson.
    case stoppedForSafety

    var label: String {
        switch self {
        case .passed: "Got it"
        case .corrected: "One fix"
        case .inconclusive: "Could not see"
        case .wrongEquipment: "Different knife"
        case .stoppedForSafety: "Stopped"
        }
    }
}
