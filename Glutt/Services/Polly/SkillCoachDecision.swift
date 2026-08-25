import Foundation

/// What to do about what the model saw.
///
/// Pure, synchronous, and separate from both the model and the voice on
/// purpose. Everything that decides whether a cook gets praised, corrected or
/// asked to move their hand happens here, in one readable function, where it can
/// be tested without a camera, a knife or a network.
///
/// The alternative was letting the model's prose drive the conversation, which
/// is how you end up with an assistant that criticises a finger it never saw
/// because the sentence flowed better that way.
enum SkillCoachDecision {

    /// How sure we are, which changes the words rather than the verdict.
    enum Certainty: Equatable {
        /// Say it plainly.
        case confident
        /// Hedge, and offer to look again. "It looks like your index finger may
        /// be on the spine" is a different promise from "it is".
        case tentative
    }

    enum Outcome: Equatable {
        /// Stop everything. Something visible is dangerous.
        case safetyStop(reason: String)
        /// Wrong tool for this lesson.
        case unsupportedEquipment(reading: String)
        /// We could not see enough to say anything. NOT a failure by the cook.
        case cannotSee(regions: [SkillVisibilityRegion])
        /// One thing to fix, and only one.
        case correct(mistakeKey: String, certainty: Certainty)
        /// Good enough. Includes the variation case, which is also a pass.
        case passed(isVariation: Bool)
    }

    /// Anything at or above this is stated plainly; below it, and above the
    /// rubric's floor, is hedged. Not tuned against data yet, and deliberately
    /// generous: the failure we care about is confident wrongness, and the cost
    /// of hedging when we were right is one extra "let me look again".
    static let confidentThreshold = 0.78

    static func decide(
        _ assessment: SkillVisualAssessment,
        check: SkillVisualCheck
    ) -> Outcome {
        // 1. Safety first, and only when we actually believe it. A safety stop
        //    on a hallucinated finger teaches the cook to ignore safety stops.
        if assessment.safety.immediateConcern,
           assessment.safety.confidence >= confidentThreshold,
           let reason = assessment.safety.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            return .safetyStop(reason: reason)
        }

        // 2. Wrong knife. Said before anything else, because every correction
        //    below is written for a chef's knife and would be wrong advice.
        if assessment.overall == .unsupportedEquipment
            || (!assessment.equipment.supported
                && assessment.equipment.confidence >= confidentThreshold) {
            return .unsupportedEquipment(reading: assessment.equipment.reading)
        }

        // 3. Could we see it at all? This runs before the verdict, not after,
        //    so a poor view can never be reported as a poor grip.
        if assessment.overall == .cannotAssess || !assessment.sawEnough(for: check) {
            return .cannotSee(regions: assessment.unseenRegions(for: check))
        }

        // 4. Low confidence is the same answer as not seeing it. The cook hears
        //    "I cannot see well enough", which is true, rather than a criticism
        //    we do not stand behind.
        guard assessment.confidence >= check.rubric.confidenceFloor else {
            return .cannotSee(regions: assessment.unseenRegions(for: check))
        }

        // 5. A correction, if the model named one we know how to coach. An
        //    unrecognised key is treated as no issue rather than passed through:
        //    we only ever say sentences we wrote.
        if assessment.overall == .needsAdjustment,
           let key = assessment.primaryIssueKey,
           check.rubric.rankedMistakes.contains(where: { $0.key == key }) {
            return .correct(
                mistakeKey: key,
                certainty: assessment.confidence >= confidentThreshold ? .confident : .tentative)
        }

        // 6. Everything else is a pass. `acceptableVariation` is a pass on
        //    purpose: it is the case where a cook holds the knife their own way
        //    and has control of it, and correcting that is how an instructor
        //    loses someone.
        return .passed(isVariation: assessment.overall == .acceptableVariation)
    }

    /// The authored correction for a key, so the words the cook hears are ours.
    static func mistake(
        for key: String,
        in check: SkillVisualCheck
    ) -> SkillCoachableMistake? {
        check.rubric.rankedMistakes.first { $0.key == key }
    }

    /// A one line record of the attempt, for the cook's own history.
    ///
    /// Written to be read weeks later by the person who did it, so it says what
    /// happened rather than what the model returned: "Held it with the handle
    /// grip, moved the hand forward" beats `needsAdjustment / handleGrip`.
    static func note(
        for outcome: Outcome,
        assessment: SkillVisualAssessment,
        check: SkillVisualCheck
    ) -> String {
        switch outcome {
        case .safetyStop(let reason):
            return "Stopped for safety: \(reason)"
        case .unsupportedEquipment(let reading):
            return "Not a chef's knife. Looked like \(reading)."
        case .cannotSee(let regions):
            let names = regions.map(\.spokenName).joined(separator: ", ")
            return regions.isEmpty
                ? "Could not see well enough to judge it."
                : "Could not see \(names)."
        case .correct(let key, _):
            guard let mistake = mistake(for: key, in: check) else {
                return "Needed one adjustment."
            }
            return mistake.observation
        case .passed(let isVariation):
            let evidence = assessment.observedEvidence.first
            let opener = isVariation
                ? "Own variation on the pinch grip, and in control of the knife."
                : "Clean pinch grip."
            guard let evidence, !evidence.isEmpty else { return opener }
            return "\(opener) \(evidence)"
        }
    }
}
