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

    /// How far back into the live stream a look may reach, in seconds.
    ///
    /// There is no hold. There was one, of five seconds, and it existed because
    /// the design assumed a camera that has to be opened; the glasses stream
    /// continuously from the moment the lesson starts, so the frames were never
    /// what anyone was waiting for. This is now simply the window of recent
    /// history a look is allowed to draw from, wide enough to cover the sentence
    /// the cook was speaking while they asked.
    let lookbackSeconds: Double

    /// How many views to send.
    ///
    /// Three, because they are angles rather than retries. A grip has two faces
    /// and one instant only ever shows one of them, so the extra images are what
    /// makes a whole assessment possible rather than insurance against a blurred
    /// one. Above three the latency is felt and the angles stop being distinct.
    let framesPerLook: Int

    /// The minimum needed to say anything at all. Missing one of these produces
    /// "I cannot see" rather than a criticism.
    ///
    /// Deliberately small. It was originally every region the rubric mentions,
    /// which turned out to be a demand the world cannot meet: in a pinch grip
    /// the thumb and the index finger are on OPPOSITE faces of the blade, so
    /// from the cook's own eyes one of them is behind the steel by definition.
    /// Requiring both meant a correct grip, held perfectly still, in good light,
    /// was reported as unseeable about half the time. A cook looking straight at
    /// their hand being told "I cannot see your hand" is the single fastest way
    /// to lose them.
    let requiredVisibility: [SkillVisibilityRegion]

    /// Regions that sharpen the assessment when visible and block nothing when
    /// they are not. Reported by the assessor, and used to decide what she is
    /// allowed to comment on: a finger nobody saw cannot be corrected.
    let helpfulVisibility: [SkillVisibilityRegion]

    /// Everything the assessor is asked to report on.
    var reportedVisibility: [SkillVisibilityRegion] { requiredVisibility + helpfulVisibility }

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
        lookbackSeconds: Double = 5,
        framesPerLook: Int = 3,
        requiredVisibility: [SkillVisibilityRegion],
        helpfulVisibility: [SkillVisibilityRegion] = [],
        rubric: SkillVisualRubric,
        retryFraming: String,
        maxUnusableViews: Int = 2
    ) {
        self.id = id
        self.framingInstruction = framingInstruction
        self.lookbackSeconds = lookbackSeconds
        self.framesPerLook = framesPerLook
        self.requiredVisibility = requiredVisibility
        self.helpfulVisibility = helpfulVisibility
        self.rubric = rubric
        self.retryFraming = retryFraming
        self.maxUnusableViews = maxUnusableViews
    }

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

    /// What the cook can physically do to bring this into view.
    ///
    /// Always a slow movement rather than a new pose to hold, because holding is
    /// what cannot work here: the thumb and the index finger are on opposite
    /// faces of the blade, so no single position shows both and asking somebody
    /// to freeze in the right one is asking for something that does not exist.
    /// Turning the hand is the only thing that puts every side in front of the
    /// camera, and the frames are read across the movement.
    ///
    /// The other reason this exists: "I cannot see" is a true sentence and a
    /// useless one. Naming what is missing AND the move that fixes it turns a
    /// dead end into an instruction, which is what an instructor would say.
    var howToBringIntoView: String {
        switch self {
        case .tool:
            "bring the knife up in front of you and turn it slowly so I can see it"
        case .controlPoint:
            "roll your hand slowly towards me so I can see where it meets the blade"
        case .thumb:
            "turn your hand slowly towards me and your thumb will come round"
        case .indexFinger:
            "roll your hand slowly the other way so the far side of the blade comes round"
        case .remainingFingers:
            "lower your hand and turn it a little so I can see your fingers on the handle"
        case .wrist:
            "pull back a touch and turn slowly so I get your wrist as well"
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

    /// What must have been visible for this to be sayable.
    ///
    /// "Your index finger is along the spine" is only a thing we get to say if
    /// somebody saw the index finger. Without this the model can infer a finger
    /// position from the shape of the hand and be confidently wrong about the
    /// one thing the cook can check for themselves.
    let requiresVisible: [SkillVisibilityRegion]

    init(
        key: String,
        observation: String,
        correction: String,
        rationale: String,
        isContextual: Bool = false,
        requiresVisible: [SkillVisibilityRegion] = []
    ) {
        self.key = key
        self.observation = observation
        self.correction = correction
        self.rationale = rationale
        self.isContextual = isContextual
        self.requiresVisible = requiresVisible
    }
}
