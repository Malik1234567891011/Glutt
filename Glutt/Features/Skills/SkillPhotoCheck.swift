import Foundation
import SwiftData
import SwiftUI

/// Running a skill check from photographs instead of a live camera.
///
/// Almost none of the intelligence is here, and that is the point. The rubric,
/// the ranked mistakes, the confidence floors, the visibility gating and every
/// authored correction are the same objects the glasses path uses.
/// `SkillVisualAssessor.assess(check:frames:)` takes `[Data]` and has never
/// cared where the bytes came from, so a cook photographing their own hand gets
/// judged against exactly the same standard as a cook wearing glasses, and hears
/// exactly the same sentence when something is wrong.
///
/// What IS different is the evidence. Two deliberate photographs beat a handful
/// of frames grabbed out of a moving first person view on almost every count:
/// they are sharp, they are lit, they are framed, and for the knife grip they
/// can show both faces of the blade, which the glasses physically cannot. This
/// is not the degraded path.
@MainActor
@Observable
final class SkillPhotoCheckModel {

    enum Phase: Equatable {
        /// Choosing and reviewing photos.
        case collecting
        /// Sent, waiting on the assessor.
        case assessing
        /// Chef has answered.
        case answered(SkillCoachDecision.Outcome)
        /// Something went wrong that was ours, not the cook's.
        case failed(String)
    }

    let skill: Skill
    let check: SkillVisualCheck

    private(set) var phase: Phase = .collecting
    /// JPEG bytes, in the order they were taken.
    private(set) var photos: [Data] = []
    private(set) var assessment: SkillVisualAssessment?

    private let startedAt = Date()
    private let assess: ([Data]) async throws -> SkillVisualAssessment

    init(
        skill: Skill,
        check: SkillVisualCheck,
        assess: (([Data]) async throws -> SkillVisualAssessment)? = nil
    ) {
        self.skill = skill
        self.check = check
        self.assess = assess ?? { frames in
            try await SkillVisualAssessor.assess(check: check, frames: frames)
        }
    }

    var needed: Int { check.photosNeeded }
    var hasEnough: Bool { photos.count >= needed }

    /// What Chef asks for, which is a different sentence from the live one.
    var framing: String { check.framing(for: .showing) }

    func add(_ jpeg: Data) {
        guard photos.count < needed else { return }
        photos.append(jpeg)
    }

    func remove(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
    }

    /// Throw them all away and start again. Used by "take them again" after a
    /// verdict, so a retry is never judged on a mix of old and new evidence.
    func reset() {
        photos.removeAll()
        assessment = nil
        phase = .collecting
    }

    func send() async {
        guard hasEnough, phase != .assessing else { return }
        phase = .assessing
        do {
            let answer = try await assess(photos)
            assessment = answer
            phase = .answered(SkillCoachDecision.decide(answer, check: check))
        } catch {
            // Ours, not theirs. The copy has to say so, because "could not see"
            // reads as a criticism of the photographs and a timeout is not one.
            phase = .failed("I could not get a look at that just now. Try sending them again.")
        }
    }

    /// The sentence Chef says about the verdict, from the authored rubric.
    var verdictHeadline: String {
        guard case .answered(let outcome) = phase else { return "" }
        switch outcome {
        case .passed(let isVariation):
            return isVariation ? "That works" : "That is it"
        case .correct(let key, _):
            return SkillCoachDecision.mistake(for: key, in: check)?.correction ?? "One thing to fix"
        case .cannotSee:
            return "I cannot see enough to say"
        case .unsupportedEquipment:
            return "That is not the tool this lesson is for"
        case .safetyStop:
            return "Stop for a second"
        case .confirmWithCook:
            return "One thing I want to check"
        }
    }

    /// The supporting line, which is where a "cannot see" turns from a dead end
    /// into an instruction. Naming the region AND the move is the whole
    /// difference between a useful answer and a shrug.
    var verdictDetail: String {
        guard case .answered(let outcome) = phase else { return "" }
        switch outcome {
        case .passed:
            return assessment?.observedEvidence.first ?? ""
        case .correct(let key, _):
            return SkillCoachDecision.mistake(for: key, in: check)?.rationale ?? ""
        case .cannotSee(let regions):
            guard let first = regions.first else { return check.retryFraming }
            return "I could not make out \(first.spokenName). \(first.howToBringIntoView.capitalizedFirst)."
        case .unsupportedEquipment(let reading):
            return "It looked like \(reading). This lesson is written for something else."
        case .safetyStop(let reason):
            return reason
        case .confirmWithCook(_, let question):
            // Asked, not asserted. The reading behind this catches every hand
            // that really is on the blade and also flags correct pinch grips,
            // so the cook settles it rather than being told.
            return question.capitalizedFirst
        }
    }

    var didPass: Bool {
        if case .answered(.passed) = phase { return true }
        return false
    }

    /// Write the attempt, exactly as the live path does, tagged with how it was
    /// judged so the history does not pretend the two are the same evidence.
    func record(in context: ModelContext) {
        guard case .answered(let outcome) = phase, let assessment else { return }
        let attempt = SkillAttempt(
            skillID: skill.id,
            checkID: check.id,
            startedAt: startedAt,
            seconds: Date().timeIntervalSince(startedAt),
            outcome: outcome.attemptOutcome,
            note: SkillCoachDecision.note(for: outcome, assessment: assessment, check: check),
            mistakeKey: outcome.mistakeKey,
            equipmentReading: assessment.equipment.reading,
            confidence: assessment.confidence,
            source: .showing)
        _ = SkillProgressStore.recordAttempt(attempt, skill: skill, in: context)

        // Every verified check is evidence, not only the mastery trials.
        //
        // This used to write a row for challenges alone, which made the rating
        // unreachable: five of the seven trials in the catalog can be scored,
        // and each sits behind three to five prerequisite lessons. An ordinary
        // watchable node is thinner evidence than a trial, not no evidence, and
        // the difference belongs in the weight rather than in a gate.
        //
        // Nothing is written when the checker could not see. An inconclusive
        // read or the wrong knife is a fact about the photograph, and it must
        // leave the rating exactly where it was.
        guard let categoryID = SkillCatalog.category(of: skill)?.id,
              let credit = EvidenceWeight.credit(for: outcome.attemptOutcome)
        else { return }
        let counted = check.criteria(met: assessment)

        context.insert(RatingEvidence(
            skillID: skill.id,
            categoryID: categoryID,
            kind: skill.isChallenge ? .masteryTrial : .skillCheck,
            credit: credit,
            // Captured at write time from the skill's difficulty, so retuning
            // the table later cannot silently rewrite a cook's history.
            weight: EvidenceWeight.weight(for: skill),
            unscored: assessment.unseenRegions(for: check).map(\.spokenName),
            criteriaMet: counted?.met ?? 0,
            criteriaObservable: counted?.observable ?? 0))
    }

    /// How many authored criteria this attempt met, out of how many could be
    /// seen. Nil when the check has no per-criterion questions to count.
    ///
    /// The same arithmetic the write path does, so the number a cook is shown
    /// and the number stored against their rating cannot drift apart.
    var criteria: (met: Int, observable: Int)? {
        guard case .answered = phase, let assessment else { return nil }
        return check.criteria(met: assessment)
    }

    /// Parts of the technique nobody could see, so the result can say so
    /// rather than quietly marking them down for it.
    var unscoredParts: [String]? {
        guard case .answered = phase, let assessment else { return nil }
        return assessment.unseenRegions(for: check).map(\.spokenName)
    }

}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
