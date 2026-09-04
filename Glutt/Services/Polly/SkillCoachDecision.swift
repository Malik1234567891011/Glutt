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

        /// Something that might be dangerous and might be perfectly correct,
        /// where the cook can settle it instantly and we cannot.
        ///
        /// Measured on six archived looks, asking whether the lower fingers are
        /// on the steel or the handle: it caught both hands that really were
        /// closed around the blade, and it also flagged both textbook pinch
        /// grips. Every rephrasing traded that away for something worse, missing
        /// the real blade grips instead.
        ///
        /// A signal that fires on correct technique cannot be a stop. But it is
        /// far too good to throw away, because it never once missed a hand on a
        /// blade. So it becomes a question, and the person holding the knife
        /// answers it in a second, which is the one thing in this loop nobody
        /// has been asking.
        case confirmWithCook(confirmed: [SkillVisibilityRegion], question: String)
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

        // 3·0 The landmark decides, before anything the reader concluded.
        //
        //     Measured on a real frame with the cook's whole hand closed around
        //     the steel: nine different framings all came back "on the handle",
        //     including a bare one line prompt, the full frame, a free
        //     description with no schema, and two larger models. The one framing
        //     that worked asked it to LOCATE the collar, which it did correctly,
        //     and then it drew the opposite conclusion in the same sentence.
        //
        //     So the conclusion is drawn here instead, from the position alone.
        if let question = check.landmark, let answer = assessment.landmark {
            if answer == question.dangerous {
                return .safetyStop(
                    reason: "your hand is up on the blade rather than behind the handle")
            }
            if let mistake = question.mistake, answer == mistake.answer,
               check.rubric.coachingOrder.contains(where: { $0.key == mistake.key }) {
                return .correct(
                    mistakeKey: mistake.key,
                    certainty: assessment.confidence >= confidentThreshold ? .confident : .tentative)
            }
            // Anything else, including a collar it could not find, is not
            // permission to pass. It falls through to the gates below, which
            // require positive support before anyone is told they have it right.
        }

        // 3a. Fingers where the edge is. This outranks everything.
        //
        //     Placed above the tool check and the confidence floor deliberately:
        //     a hand closed around a blade is worth saying even from a picture
        //     we are otherwise unsure about, because the cost of being wrong is
        //     a moment of "actually that looks fine" and the cost of staying
        //     quiet is a cut hand. The model's own `safety.immediateConcern` did
        //     not fire on exactly this, which is why it is derived here from a
        //     narrow question instead of asked as a judgement.
        for (region, dangerous) in check.dangerousReadings {
            guard let observation = check.observations.first(where: { $0.region == region }),
                  let reading = assessment.reading(for: observation),
                  dangerous.contains(reading)
            else { continue }
            // Everything the pictures DID settle, so the cook hears what is
            // right before being asked about what is not.
            let settled = check.observations.compactMap { observation -> SkillVisibilityRegion? in
                guard observation.region != region,
                      let reading = assessment.reading(for: observation),
                      reading != observation.cannotTell
                else { return nil }
                return observation.region
            }
            return .confirmWithCook(
                confirmed: settled,
                question: "are your bottom fingers around the handle, or on the blade itself?")
        }

        // 3b. No picture had the tool in it, whatever else she went on to say.
        //
        //     The cropper sends one close up per hand and cannot know which hand
        //     holds what, so it is normal for one of them to be a fist, or a
        //     hand on the counter. `toolPicture` is where she names the one that
        //     actually shows the knife. Zero means none of them did, and a grip
        //     verdict about a picture with no knife in it is the failure mode
        //     that started all of this: a real look came back "the whole hand is
        //     behind the blade on the handle" describing a blade that was not in
        //     the frame.
        if check.requiredVisibility.contains(.tool), assessment.toolPicture == 0 {
            return .cannotSee(regions: [.tool])
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
           let mistake = check.rubric.coachingOrder.first(where: { $0.key == key }) {
            // Some corrections are worth saying on thinner evidence than
            // others. A fingertip in the blade path and a slightly bent wrist
            // are not the same bet: being wrong about the first costs a moment
            // of embarrassment, being silent about it costs a finger. Where a
            // mistake sets its own floor, it wins over the rubric's.
            if let floor = mistake.confidenceFloor, assessment.confidence < floor {
                return .cannotSee(regions: assessment.unseenRegions(for: check))
            }
            // And only if somebody actually saw the part it is about.
            //
            // "Your index finger is along the spine" is a claim about a finger,
            // and in a pinch grip that finger is often behind the blade. A model
            // can infer its position from the shape of the hand and be
            // confidently wrong about the one thing the cook can check for
            // themselves in a second, which is the fastest way to lose them.
            let sawWhatItIsAbout = mistake.requiresVisible.allSatisfy {
                assessment.visibility[$0.rawValue]?.isUsable ?? false
            }
            guard sawWhatItIsAbout else {
                return .cannotSee(regions: mistake.requiresVisible.filter {
                    assessment.visibility[$0.rawValue]?.isUsable != true
                })
            }

            // And only if the pictures actually say so.
            //
            // The gate above asks the model whether it could see the part, and
            // it answers yes every time, including on a frame that was an
            // unreadable smear. This one asks what it saw there, in a closed
            // set, per picture, and requires the majority to support the
            // correction. A reading it could not agree with itself about is not
            // grounds for telling somebody they are doing it wrong.
            let unsupported = mistake.impliedBy.filter { region, allowed in
                guard let observation = check.observations.first(where: { $0.region == region })
                else { return false }
                guard let reading = assessment.reading(for: observation) else { return true }
                return !allowed.contains(reading)
            }
            guard unsupported.isEmpty else {
                return .cannotSee(regions: unsupported.keys.sorted { $0.rawValue < $1.rawValue })
            }

            return .correct(
                mistakeKey: key,
                certainty: assessment.confidence >= confidentThreshold ? .confident : .tentative)
        }

        // 6. A pass is a claim, and it gets checked like one.
        //
        //    Every gate above this point protects against a false correction,
        //    because that is what makes a cook stop believing the coach. It
        //    left the opposite direction wide open, and that is the direction
        //    that hurts: a cook with their whole hand wrapped round the blade
        //    was told "yep, that's it, looks perfect" at 0.90, and her written
        //    evidence said the remaining fingers were around the handle when
        //    the picture plainly showed them across the steel.
        //
        //    So a pass now needs the same positive support a correction does.
        //    Where it is missing the cook is asked to turn their hand, which is
        //    a small cost against congratulating somebody who is about to cut
        //    themselves.
        // A pass needs the landmark to say so, when there is one. The reader
        //    saying `ready` is not evidence; on the frame that started this it
        //    said `ready` at 0.90 with the cook's hand around the blade.
        if let question = check.landmark, assessment.landmark != question.correct {
            return .cannotSee(regions: check.requiredVisibility)
        }

        let unconfirmed = check.passRequires.filter { region, allowed in
            guard let observation = check.observations.first(where: { $0.region == region })
            else { return false }
            guard let reading = assessment.reading(for: observation) else { return true }
            return !allowed.contains(reading)
        }
        guard unconfirmed.isEmpty else {
            return .cannotSee(regions: unconfirmed.keys.sorted { $0.rawValue < $1.rawValue })
        }

        //    `acceptableVariation` is still a pass on purpose: it is the case
        //    where a cook holds the knife their own way and has control of it,
        //    and correcting that is how an instructor loses someone.
        return .passed(isVariation: assessment.overall == .acceptableVariation)
    }

    /// The authored correction for a key, so the words the cook hears are ours.
    static func mistake(
        for key: String,
        in check: SkillVisualCheck
    ) -> SkillCoachableMistake? {
        check.rubric.coachingOrder.first { $0.key == key }
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
        case .confirmWithCook(_, let question):
            return "Asked them to confirm: \(question)"
        case .unsupportedEquipment(let reading):
            return "Wrong tool for this one. Looked like \(reading)."
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
                ? check.rubric.variationSummary
                : check.rubric.passSummary
            guard let evidence, !evidence.isEmpty else { return opener }
            return "\(opener) \(evidence)"
        }
    }
}

// MARK: - What an outcome means to the record

/// Shared by the live path and the photo path, which is the whole reason it
/// lives here rather than privately inside the session that happened to need it
/// first. Two copies of this mapping would drift, and the direction they would
/// drift in is one path quietly recording a pass the other would not.
extension SkillCoachDecision.Outcome {
    var attemptOutcome: SkillAttemptOutcome {
        switch self {
        case .safetyStop: .stoppedForSafety
        case .confirmWithCook: .inconclusive
        case .unsupportedEquipment: .wrongEquipment
        case .cannotSee: .inconclusive
        case .correct: .corrected
        case .passed: .passed
        }
    }

    var mistakeKey: String? {
        if case .correct(let key, _) = self { return key }
        return nil
    }
}
