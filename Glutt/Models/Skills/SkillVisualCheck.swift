import Foundation

/// What the camera is actually capable of judging about one skill.
///
/// Deliberately a separate thing from `SkillLesson`, which is what we *teach*.
/// The two answer different questions and change for different reasons: the
/// lesson changes when the technique is explained better, this changes when the
/// vision model gets better or worse at seeing a thumb. Folding them together
/// would mean a copy edit to a lesson could quietly alter what counts as a pass.
///
/// Static content like the rest of Skills, so authoring a check for a new skill
/// is a data edit with no migration. A skill with `visualCheck == nil` is simply
/// one Polly cannot watch yet, which is most of them.
struct SkillVisualCheck: Hashable, Sendable {
    /// Stable id, used on the attempt rows so history survives re-authoring.
    let id: String

    /// What Polly says to set the shot up, immediately before the hold starts.
    ///
    /// Written to be spoken, not read. It has one job the rest of the lesson
    /// does not: getting the cook's own hand into frame without asking them to
    /// wave a knife around.
    let framingInstruction: String

    /// How long the cook holds still. Five seconds is not a technical
    /// requirement, it is the ritual: it converts model latency from an
    /// embarrassed spinner into the part of the interaction where an instructor
    /// leans in and looks.
    let holdSeconds: Double

    /// Where inside the hold to grab frames, as fractions of `holdSeconds`.
    ///
    /// Several rather than one, because a single frame decides the result on
    /// whichever instant it happened to land on, and hands blur, blink out of
    /// frame and get occluded by the knife itself. Spread across the hold so a
    /// bad moment costs us one frame instead of the assessment.
    let captureAt: [Double]

    /// What has to be visible before any judgement is allowed. The assessor
    /// reports each of these separately, and a missing one produces "I cannot
    /// see" rather than a criticism.
    let requiredVisibility: [SkillVisibilityRegion]

    /// Everything the vision model needs to know about the technique itself.
    let rubric: SkillVisualRubric

    /// What Polly says when the view was not good enough. Not a failure message:
    /// the cook did nothing wrong, the camera did.
    let retryFraming: String

    /// After this many unusable views, stop asking and offer the way out.
    /// Two, because a third identical request is where a cook concludes the
    /// feature is broken and stops trusting the rest of it.
    let maxUnusableViews: Int

    init(
        id: String,
        framingInstruction: String,
        holdSeconds: Double = 5,
        captureAt: [Double] = [0.25, 0.55, 0.85],
        requiredVisibility: [SkillVisibilityRegion],
        rubric: SkillVisualRubric,
        retryFraming: String,
        maxUnusableViews: Int = 2
    ) {
        self.id = id
        self.framingInstruction = framingInstruction
        self.holdSeconds = holdSeconds
        self.captureAt = captureAt
        self.requiredVisibility = requiredVisibility
        self.rubric = rubric
        self.retryFraming = retryFraming
        self.maxUnusableViews = maxUnusableViews
    }

    /// Absolute seconds into the hold at which to grab each frame.
    var captureOffsets: [TimeInterval] { captureAt.map { $0 * holdSeconds } }
}

/// A part of the scene the assessor reports on separately.
///
/// Separate visibility per region, not one overall flag, because "I can see your
/// thumb but not your index finger" is a genuinely useful thing to say and a
/// single boolean cannot say it.
enum SkillVisibilityRegion: String, Hashable, Sendable, CaseIterable {
    case tool
    case controlPoint
    case thumb
    case indexFinger
    case remainingFingers
    case wrist

    /// How Polly refers to it out loud. Kept here rather than in the coach so
    /// the words match what the assessor was asked about.
    var spokenName: String {
        switch self {
        case .tool: "your knife"
        case .controlPoint: "where your hand meets the blade"
        case .thumb: "your thumb"
        case .indexFinger: "your index finger"
        case .remainingFingers: "your other fingers"
        case .wrist: "your wrist"
        }
    }
}

/// The curriculum, translated into terms a vision model can be held to.
///
/// Prose rather than flags on purpose. The thing being described is "what good
/// looks like and how much variation is fine", and every attempt to reduce that
/// to booleans produces a pose classifier that fails people for having small
/// hands. The model gets the reasoning; the app keeps control of what is done
/// with the answer.
struct SkillVisualRubric: Hashable, Sendable {
    /// One line naming what is being assessed, for the top of the prompt.
    let subject: String

    /// The technique we are teaching, as the assessor should understand it.
    let targetTechnique: [String]

    /// Differences that are NOT mistakes. This list is the difference between an
    /// instructor and a pedant, and it is the reason false criticism is rarer
    /// than it would otherwise be.
    let acceptableVariations: [String]

    /// Known wrong-for-this-lesson habits, most important first. The order is
    /// the coaching priority: when several are true, the cook hears about the
    /// first one and nothing else.
    let rankedMistakes: [SkillCoachableMistake]

    /// Configurations that stop the lesson immediately. Only things we would be
    /// confident about from a photograph.
    let safetySignals: [String]

    /// Equipment this lesson is written for.
    let supportedEquipment: [String]

    /// Equipment that needs a different lesson, and should be said so rather
    /// than coached badly.
    let unsupportedEquipment: [String]

    /// Things a photograph genuinely cannot establish, listed so the model is
    /// told not to try. Grip pressure is the canonical one: it looks identical
    /// at every force.
    let notVisuallyAssessable: [String]

    /// Below this, Polly does not critique. She says she cannot see well enough,
    /// which is a different sentence and a much better one.
    let confidenceFloor: Double
}

/// One habit worth correcting, with the words to correct it in.
///
/// The fix is authored rather than generated because this is the sentence the
/// whole feature is judged on. A model asked to invent it produces "remember to
/// use a pinch grip for better control", which is advice from a webpage. The
/// specific, physical instruction is the thing that makes a cook believe they
/// were actually seen.
struct SkillCoachableMistake: Hashable, Sendable {
    /// Matches `SkillGripFamily` or a criterion name the assessor returns.
    let key: String
    /// What the cook is doing, in the assessor's terms.
    let observation: String
    /// What Polly says. One instruction, physical, no preamble.
    let correction: String
    /// Why it matters, offered only if the cook asks.
    let rationale: String
    /// True when this is wrong for this lesson rather than wrong in general.
    /// Changes the language from "fix that" to "not for this one".
    let isContextual: Bool

    init(
        key: String,
        observation: String,
        correction: String,
        rationale: String,
        isContextual: Bool = false
    ) {
        self.key = key
        self.observation = observation
        self.correction = correction
        self.rationale = rationale
        self.isContextual = isContextual
    }
}
