import XCTest
import SwiftData
@testable import Glutt

/// The rules that decide what a cook hears about their own hands.
///
/// All of this is deliberately reachable without a camera, a knife or a network,
/// because the failure mode that matters most here is a confident sentence about
/// a finger nobody saw, and that is a logic bug rather than a vision bug.
final class SkillVisualCoachingTests: XCTestCase {

    private let check = SkillVisualCheck.chefKnifeGrip

    // MARK: - Fixtures

    private func assessment(
        overall: SkillVisualAssessment.Overall,
        confidence: Double = 0.9,
        visible: Bool = true,
        issue: String? = nil,
        safety: Bool = false,
        safetyConfidence: Double = 0.95,
        supported: Bool = true,
        equipmentConfidence: Double = 0.9,
        equipment: String = "chef's knife",
        evidence: [String] = ["thumb on the blade face near the heel"]
    ) -> SkillVisualAssessment {
        var visibility: [String: SkillVisualAssessment.Visibility] = [:]
        for region in check.reportedVisibility {
            visibility[region.rawValue] = visible ? .sufficient : .insufficient
        }
        return SkillVisualAssessment(
            equipment: .init(
                reading: equipment, supported: supported, confidence: equipmentConfidence),
            visibility: visibility,
            safety: .init(
                immediateConcern: safety,
                description: safety ? "index finger resting on the cutting edge" : nil,
                confidence: safetyConfidence),
            overall: overall,
            confidence: confidence,
            primaryIssueKey: issue,
            observedEvidence: evidence)
    }

    // MARK: - Seeing comes before judging

    /// The distinction the whole feature rests on. A view we could not use must
    /// never come out as a criticism of the cook.
    func testAPoorViewIsNeverReportedAsAPoorGrip() {
        let blind = assessment(overall: .needsAdjustment, visible: false, issue: "pointerGrip")

        let outcome = SkillCoachDecision.decide(blind, check: check)

        guard case .cannotSee(let regions) = outcome else {
            return XCTFail("expected cannotSee, got \(outcome)")
        }
        // Every region she was asked about, not just the required two: naming
        // the thumb is useful to a cook even though a hidden thumb alone would
        // not have blocked the assessment.
        XCTAssertEqual(Set(regions), Set(check.reportedVisibility),
                       "and it should name what it could not see")
    }

    /// `cannotAssess` is the model's own way of saying it does not know, and it
    /// outranks anything else it happened to fill in.
    func testCannotAssessIsHonoured() {
        let unsure = assessment(overall: .cannotAssess, issue: "handleGrip")
        XCTAssertEqual(
            SkillCoachDecision.decide(unsure, check: check),
            .cannotSee(regions: []))
    }

    /// Below the rubric's floor she says she cannot see well enough, which is
    /// true, rather than a correction we would not stand behind.
    func testLowConfidenceIsTreatedAsNotSeeingRatherThanAsAFault() {
        let shaky = assessment(
            overall: .needsAdjustment,
            confidence: check.rubric.confidenceFloor - 0.01,
            issue: "pointerGrip")

        guard case .cannotSee = SkillCoachDecision.decide(shaky, check: check) else {
            return XCTFail("a low confidence reading must not become a correction")
        }
    }

    /// The complaint that came back from a real kitchen: "I am literally looking
    /// right at it and it says it cannot see."
    ///
    /// In a correct pinch grip the thumb and the index finger are on opposite
    /// faces of the blade, so from the cook's own eyes one of them is behind the
    /// steel. Requiring both made a perfect grip unassessable about half the
    /// time. Only the knife and the control point are required now.
    func testAHiddenFingerDoesNotMakeAGoodGripUnassessable() {
        var visibility: [String: SkillVisualAssessment.Visibility] = [
            "tool": .sufficient,
            "controlPoint": .sufficient,
            "thumb": .sufficient,
            "indexFinger": .insufficient,      // behind the blade, as it should be
            "remainingFingers": .partial,
            "wrist": .insufficient,
        ]
        let hidden = SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.9),
            visibility: visibility,
            overall: .ready,
            confidence: 0.9)

        XCTAssertTrue(hidden.sawEnough(for: check))
        XCTAssertEqual(SkillCoachDecision.decide(hidden, check: check), .passed(isVariation: false))

        // But losing the knife itself is still a real "I cannot see".
        visibility["tool"] = .insufficient
        let blind = SkillVisualAssessment(
            equipment: .init(reading: "unknown", supported: true, confidence: 0.2),
            visibility: visibility,
            overall: .ready,
            confidence: 0.9)
        XCTAssertFalse(blind.sawEnough(for: check))
    }

    /// A correction is a claim about a specific finger, so it needs that finger
    /// to have been seen. Inferring it from the shape of the hand and being
    /// wrong is the one error the cook can check in a second.
    func testAFingerNobodySawIsNotCorrected() {
        let inferred = SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.9),
            visibility: [
                "tool": .sufficient,
                "controlPoint": .sufficient,
                "thumb": .sufficient,
                "indexFinger": .insufficient,
                "remainingFingers": .sufficient,
                "wrist": .sufficient,
            ],
            overall: .needsAdjustment,
            confidence: 0.9,
            primaryIssueKey: "pointerGrip")   // a claim about the index finger

        XCTAssertEqual(
            SkillCoachDecision.decide(inferred, check: check),
            .cannotSee(regions: [.indexFinger]))
    }

    /// The one correction that only needs the control point still works when
    /// every finger is hidden, because "your whole hand is back on the handle"
    /// does not depend on seeing a thumb.
    func testTheGripLocationCorrectionSurvivesHiddenFingers() {
        let handleGrip = SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.9),
            visibility: [
                "tool": .sufficient,
                "controlPoint": .sufficient,
                "thumb": .insufficient,
                "indexFinger": .insufficient,
                "remainingFingers": .insufficient,
                "wrist": .insufficient,
            ],
            overall: .needsAdjustment,
            confidence: 0.9,
            primaryIssueKey: "handleGrip")

        XCTAssertEqual(
            SkillCoachDecision.decide(handleGrip, check: check),
            .correct(mistakeKey: "handleGrip", certainty: .confident))
    }

    // MARK: - Safety

    func testAVisibleDangerStopsEverything() {
        let dangerous = assessment(overall: .needsAdjustment, issue: "pointerGrip", safety: true)

        guard case .safetyStop(let reason) = SkillCoachDecision.decide(dangerous, check: check) else {
            return XCTFail("a finger on the edge outranks every other finding")
        }
        XCTAssertTrue(reason.contains("edge"))
    }

    /// A safety stop nobody believes is worse than none: it teaches the cook to
    /// ignore the next one.
    func testAnUnconfidentSafetyReadingDoesNotStopTheLesson() {
        let maybe = assessment(
            overall: .needsAdjustment, issue: "pointerGrip",
            safety: true, safetyConfidence: 0.4)

        guard case .correct = SkillCoachDecision.decide(maybe, check: check) else {
            return XCTFail("expected the ordinary correction path")
        }
    }

    // MARK: - Equipment

    func testTheWrongKnifeIsSaidRatherThanCoached() {
        let paring = assessment(
            overall: .unsupportedEquipment, supported: false, equipment: "paring knife")

        XCTAssertEqual(
            SkillCoachDecision.decide(paring, check: check),
            .unsupportedEquipment(reading: "paring knife"))
    }

    /// Every correction in this rubric is written for a chef's knife, so an
    /// unsure knife reading must not be enough to send a cook a chef's knife
    /// correction for a cleaver.
    func testAnUnsureKnifeReadingDoesNotTriggerTheWrongKnifeSpeech() {
        let unsure = assessment(
            overall: .needsAdjustment, issue: "handleGrip",
            supported: false, equipmentConfidence: 0.3)

        guard case .correct = SkillCoachDecision.decide(unsure, check: check) else {
            return XCTFail("a guess about the knife should not become an announcement")
        }
    }

    // MARK: - One correction, in our words

    func testACorrectionUsesTheAuthoredSentenceNotTheModels() {
        let outcome = SkillCoachDecision.decide(
            assessment(overall: .needsAdjustment, issue: "pointerGrip"), check: check)

        guard case .correct(let key, let certainty) = outcome else {
            return XCTFail("expected a correction, got \(outcome)")
        }
        XCTAssertEqual(certainty, .confident)
        let mistake = try? XCTUnwrap(SkillCoachDecision.mistake(for: key, in: check))
        XCTAssertTrue(mistake?.correction.contains("Curl it down") ?? false,
                      "the words the cook hears are the ones we wrote")
    }

    /// Medium confidence changes the register, not the verdict.
    func testMediumConfidenceHedges() {
        let outcome = SkillCoachDecision.decide(
            assessment(overall: .needsAdjustment, confidence: 0.6, issue: "handleGrip"),
            check: check)

        XCTAssertEqual(outcome, .correct(mistakeKey: "handleGrip", certainty: .tentative))
    }

    /// A key we do not have words for is treated as no issue at all. We would
    /// rather miss a correction than invent one.
    func testAnUnknownIssueKeyIsNotPassedThrough() {
        let outcome = SkillCoachDecision.decide(
            assessment(overall: .needsAdjustment, issue: "elbowTooHigh"), check: check)

        XCTAssertEqual(outcome, .passed(isVariation: false))
    }

    // MARK: - Passing

    /// The case that decides whether this feels like an instructor or a pose
    /// classifier: a grip that is not the reference but is in control.
    func testAnAcceptableVariationIsAPassAndNotACorrection() {
        let outcome = SkillCoachDecision.decide(
            assessment(overall: .acceptableVariation), check: check)

        XCTAssertEqual(outcome, .passed(isVariation: true))
    }

    func testNotesReadLikeSomethingAPersonWrote() {
        let passed = assessment(overall: .ready, evidence: ["three fingers wrapped on the handle"])
        let note = SkillCoachDecision.note(
            for: .passed(isVariation: false), assessment: passed, check: check)
        XCTAssertTrue(note.contains("Clean pinch grip"))
        XCTAssertTrue(note.contains("three fingers"))

        let blind = assessment(overall: .cannotAssess, visible: false)
        let blindNote = SkillCoachDecision.note(
            for: .cannotSee(regions: [.thumb]), assessment: blind, check: check)
        XCTAssertTrue(blindNote.contains("thumb"))
        XCTAssertFalse(blindNote.lowercased().contains("wrong"),
                       "a view we could not use is not the cook doing badly")
    }

    // MARK: - Decoding

    /// The model omits fields. A partial answer still lets us say "I could not
    /// see"; a thrown error lets us say nothing at all.
    func testAPartialAnswerDecodesRatherThanThrowing() throws {
        let json = #"{"overall":"cannotAssess"}"#
        let decoded = try JSONDecoder().decode(
            SkillVisualAssessment.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.overall, .cannotAssess)
        XCTAssertEqual(decoded.confidence, 0)
        XCTAssertTrue(decoded.observedEvidence.isEmpty)
    }

    /// Models emit the string "null" often enough that treating it as a real key
    /// would send cooks a correction named `null`.
    func testTheStringNullIsNotAnIssueKey() throws {
        let json = #"{"overall":"ready","primaryIssueKey":"null","confidence":0.9}"#
        let decoded = try JSONDecoder().decode(
            SkillVisualAssessment.self, from: Data(json.utf8))

        XCTAssertNil(decoded.primaryIssueKey)
    }

    func testPartialVisibilityStillCountsAsSeeingIt() {
        var visibility: [String: SkillVisualAssessment.Visibility] = [:]
        for region in check.requiredVisibility { visibility[region.rawValue] = .partial }
        let squinting = SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.9),
            visibility: visibility,
            overall: .ready,
            confidence: 0.9)

        XCTAssertTrue(squinting.sawEnough(for: check),
                      "demanding a perfect view of every finger would loop real cooks forever")
    }

    // MARK: - The rubric itself

    func testTheKnifeGripRubricIsCoherent() {
        let keys = check.rubric.rankedMistakes.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "duplicate keys make ranking meaningless")
        XCTAssertFalse(check.rubric.acceptableVariations.isEmpty,
                       "without these it is a pose classifier")
        XCTAssertTrue(
            check.rubric.notVisuallyAssessable.contains { $0.lowercased().contains("squeez") },
            "grip pressure is the thing a photo cannot show and she must not claim")
        XCTAssertTrue(
            check.rubric.unsupportedEquipment.contains("Paring knife"))
        // Required stays small on purpose. Adding a finger back here is how the
        // "I cannot see" complaint returns.
        XCTAssertEqual(check.requiredVisibility, [.tool, .controlPoint])
        XCTAssertTrue(check.helpfulVisibility.contains(.indexFinger))
        // And every correction names what it needs to have seen.
        for mistake in check.rubric.rankedMistakes {
            XCTAssertFalse(
                mistake.requiresVisible.isEmpty,
                "\(mistake.key) could be claimed about something nobody saw")
        }
        // The two habits this lesson is most likely to meet, in priority order.
        XCTAssertEqual(keys.first, "handleGrip")
        XCTAssertTrue(keys.contains("pointerGrip"))
        // Both are wrong-for-this-lesson rather than wrong, and the coaching has
        // to know the difference or it tells a fish cook they are holding a
        // knife incorrectly.
        for key in ["handleGrip", "pointerGrip"] {
            XCTAssertTrue(
                SkillCoachDecision.mistake(for: key, in: check)?.isContextual ?? false,
                "\(key) exists legitimately elsewhere")
        }
    }

    func testTheKnifeGripSkillIsWiredToTheCheck() throws {
        let skill = try XCTUnwrap(SkillCatalog.skill("knife.grip"))
        XCTAssertTrue(skill.isWatchable)
        XCTAssertEqual(skill.visualCheck?.id, "knife.grip.pinch")
    }

    // MARK: - The grip as parts

    /// A grip is one shape, not a sequence, and the parts have to map onto what
    /// the assessment already reports so nothing extra is asked of the model.
    func testEveryPartIsSomethingTheAssessorReportsOn() {
        XCTAssertFalse(check.parts.isEmpty)
        for part in check.parts {
            XCTAssertTrue(
                check.reportedVisibility.contains(part.region),
                "\(part.region.rawValue) is on screen but nobody looks for it")
            XCTAssertFalse(part.label.isEmpty)
        }
        // Four parts of one hand, not a wizard.
        XCTAssertLessThanOrEqual(check.parts.count, 5)
    }

    /// The grip lesson teaches the grip. It used to end with the rocking cut,
    /// which is a different skill and made four steps out of one gesture.
    func testTheGripLessonDoesNotTeachTheCut() throws {
        let skill = try XCTUnwrap(SkillCatalog.skill("knife.grip"))
        let steps = try XCTUnwrap(skill.lesson?.steps)

        XCTAssertLessThanOrEqual(steps.count, 3)
        for step in steps {
            let text = step.lowercased()
            XCTAssertFalse(text.contains("elbow"), "the cut is a later skill")
            XCTAssertFalse(text.contains("rises and falls"), "so is the rock")
        }
    }

    // The frame ring and the look-request parser were tested here. Both
    // belonged to the live coaching session, which watched through a pair of
    // Meta glasses and is removed on this branch. Everything below still
    // applies: the photo path runs the same assessor and the same decision
    // layer, so the rubric is held to exactly the same rules.

    // MARK: - Prompt

    /// The assessor is the model that has to name a key, so the keys go to it
    /// and not to the voice. The coach never sees them: it is handed a finished
    /// sentence, which is what stops it inventing a sixth mistake.
    func testTheAssessorPromptCarriesTheWholeRubric() {
        let prompt = SkillVisualAssessor.systemPrompt(check: check)

        for mistake in check.rubric.rankedMistakes {
            XCTAssertTrue(prompt.contains(mistake.key), "missing \(mistake.key)")
        }
        for variation in check.rubric.acceptableVariations {
            XCTAssertTrue(prompt.contains(variation), "an acceptable variation was dropped")
        }
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("at most ONE"),
                      "it must not return a list of five things to fix")
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("cannotAssess"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("false correction is worse"))
    }

}

/// Progress, which is the part a cook keeps.
@MainActor
final class SkillAttemptProgressTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([SkillProgress.self, SkillAttempt.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    override func tearDownWithError() throws { container = nil }

    private var skill: Skill {
        SkillCatalog.skill("knife.grip") ?? SkillCatalog.allSkills[0]
    }

    private func attempt(_ outcome: SkillAttemptOutcome, seconds: Double = 5) -> SkillAttempt {
        SkillAttempt(
            skillID: skill.id, checkID: "knife.grip.pinch", seconds: seconds,
            outcome: outcome, note: "note")
    }

    /// Being watched doing it correctly is a stronger claim than tapping a
    /// button, so it grants both.
    func testAPassMastersAndLearnsInOneGo() {
        let context = container.mainContext

        let mastered = SkillProgressStore.recordAttempt(
            attempt(.passed), skill: skill, in: context)

        XCTAssertTrue(mastered)
        let row = SkillProgressStore.row(for: skill.id, in: context)
        XCTAssertTrue(row?.isMastered ?? false)
        XCTAssertTrue(row?.isLearned ?? false)
        XCTAssertEqual(row?.xpAwarded, skill.xp)
    }

    /// XP is paid once no matter how many times they show her.
    func testPractisingAgainDoesNotPayTwice() {
        let context = container.mainContext
        SkillProgressStore.recordAttempt(attempt(.passed), skill: skill, in: context)

        let secondTime = SkillProgressStore.recordAttempt(
            attempt(.passed), skill: skill, in: context)

        XCTAssertFalse(secondTime, "already mastered")
        let row = SkillProgressStore.row(for: skill.id, in: context)
        XCTAssertEqual(row?.xpAwarded, skill.xp)
        XCTAssertEqual(SkillProgressStore.attempts(for: skill.id, in: context).count, 2)
    }

    /// An attempt Polly could not see says nothing about the cook, and must not
    /// quietly promote them.
    func testAnUnseenAttemptCountsAsPracticeAndNothingElse() {
        let context = container.mainContext

        SkillProgressStore.recordAttempt(attempt(.inconclusive), skill: skill, in: context)

        let row = SkillProgressStore.row(for: skill.id, in: context)
        XCTAssertFalse(row?.isMastered ?? true)
        XCTAssertFalse(row?.isLearned ?? true)
        XCTAssertNotNil(row?.startedAt, "but they did turn up and try")
        XCTAssertEqual(SkillProgressStore.attempts(for: skill.id, in: context).count, 1)
    }

    /// Practice time is what a later mastery rule will be built from, so the
    /// seconds have to survive.
    func testPracticeTimeAccumulates() {
        let context = container.mainContext
        SkillProgressStore.recordAttempt(attempt(.corrected, seconds: 5), skill: skill, in: context)
        SkillProgressStore.recordAttempt(attempt(.passed, seconds: 6), skill: skill, in: context)

        let total = SkillProgressStore.attempts(for: skill.id, in: context)
            .reduce(0) { $0 + $1.seconds }
        XCTAssertEqual(total, 11, accuracy: 0.01)
    }

    func testOutcomesKnowWhetherTheyReflectOnTheCook() {
        XCTAssertTrue(attempt(.passed).reflectsOnCook)
        XCTAssertTrue(attempt(.corrected).reflectsOnCook)
        XCTAssertFalse(attempt(.inconclusive).reflectsOnCook)
        XCTAssertFalse(attempt(.wrongEquipment).reflectsOnCook)
    }
}

// MARK: - The rubric model, once it stopped being knife shaped

/// The catalog is going from one watchable skill to sixty-odd, across pans,
/// eggs and sauces. These pin the parts of the model that exist only because a
/// professional instructor told us the knife-shaped version was wrong.
final class SkillRubricModelTests: XCTestCase {

    private func mistake(
        _ key: String,
        severity: SkillMistakeSeverity,
        floor: Double? = nil
    ) -> SkillCoachableMistake {
        SkillCoachableMistake(
            key: key,
            observation: "observation for \(key)",
            correction: "correction for \(key)",
            rationale: "rationale for \(key)",
            severity: severity,
            confidenceFloor: floor
        )
    }

    private func check(
        mistakes: [SkillCoachableMistake],
        mode: SkillAssessmentMode = .process,
        intent: SkillIntentBranch? = nil,
        tolerance: [String] = [],
        floor: Double = 0.55
    ) -> SkillVisualCheck {
        SkillVisualCheck(
            id: "test.check",
            assessmentMode: mode,
            framingInstruction: "look at it",
            requiredVisibility: [.tool],
            rubric: SkillVisualRubric(
                subject: "a test",
                targetTechnique: ["do the thing"],
                acceptableVariations: ["any way you like"],
                rankedMistakes: mistakes,
                confidenceFloor: floor,
                intentBranch: intent,
                outcomeTolerance: tolerance
            ),
            retryFraming: "try again"
        )
    }

    private func assessment(
        confidence: Double,
        issue: String?,
        regions: [SkillVisibilityRegion] = [.tool]
    ) -> SkillVisualAssessment {
        var visibility: [String: SkillVisualAssessment.Visibility] = [:]
        for region in regions { visibility[region.rawValue] = .sufficient }
        return SkillVisualAssessment(
            equipment: .init(reading: "a test", supported: true, confidence: 0.95),
            visibility: visibility,
            safety: .init(immediateConcern: false, description: nil, confidence: 0.1),
            overall: issue == nil ? .ready : .needsAdjustment,
            confidence: confidence,
            primaryIssueKey: issue,
            observedEvidence: ["saw a thing"]
        )
    }

    /// The reason severity exists at all. Author order is a hint, not the law:
    /// a cosmetic note written at the top of a rubric must never outrank a
    /// finger heading for the blade further down it.
    func testSafetyOutranksTheOrderTheRubricWasWrittenIn() {
        let c = check(mistakes: [
            mistake("cosmetic", severity: .cosmetic),
            mistake("efficiency", severity: .efficiency),
            mistake("danger", severity: .safety),
            mistake("ruins", severity: .irreversible),
        ])
        XCTAssertEqual(
            c.rubric.coachingOrder.map(\.key),
            ["danger", "ruins", "efficiency", "cosmetic"])
    }

    /// Equal severity keeps the instructor's ranking, which is the whole reason
    /// the deliverable numbers its mistakes.
    func testEqualSeverityFallsBackToAuthorOrder() {
        let c = check(mistakes: [
            mistake("first", severity: .outcomeCost),
            mistake("second", severity: .outcomeCost),
            mistake("third", severity: .outcomeCost),
        ])
        XCTAssertEqual(c.rubric.coachingOrder.map(\.key), ["first", "second", "third"])
    }

    /// A safety correction is worth saying on thinner evidence than a cosmetic
    /// one. Being wrong about a fingertip costs a moment; being silent about it
    /// costs a finger.
    func testASafetyMistakeCanBeRaisedOnEvidenceTooThinForACosmeticOne() {
        let c = check(mistakes: [
            mistake("danger", severity: .safety, floor: 0.4),
            mistake("fussy", severity: .cosmetic, floor: 0.9),
        ], floor: 0.55)

        // Below the rubric floor, nothing is said at all.
        if case .cannotSee = SkillCoachDecision.decide(
            assessment(confidence: 0.3, issue: "danger"), check: c) {} else {
            XCTFail("below the rubric floor should never produce a correction")
        }

        // Above the rubric floor but below the cosmetic mistake's own floor.
        if case .cannotSee = SkillCoachDecision.decide(
            assessment(confidence: 0.6, issue: "fussy"), check: c) {} else {
            XCTFail("a fussy correction on thin evidence should be withheld")
        }

        // Same confidence, safety mistake: said, because it set a lower bar.
        guard case .correct(let key, _) = SkillCoachDecision.decide(
            assessment(confidence: 0.6, issue: "danger"), check: c) else {
            return XCTFail("a safety correction should survive its own lower floor")
        }
        XCTAssertEqual(key, "danger")
    }

    /// Outcome skills are looked at completely differently from process ones,
    /// and the prompt has to say so. Telling a model judging a board of diced
    /// onion that "nobody can see both faces of a knife at once" is noise.
    func testOutcomeSkillsAreNotToldAboutKnifeGeometry() {
        let outcome = SkillVisualAssessor.systemPrompt(check: check(mistakes: [], mode: .outcome))
        XCTAssertTrue(outcome.contains("finished result"))
        XCTAssertFalse(outcome.contains("both faces"))

        let process = SkillVisualAssessor.systemPrompt(check: check(mistakes: [], mode: .process))
        XCTAssertTrue(process.contains("angles, not attempts"))
    }

    /// A skill may author its own note when the generic one is not enough. The
    /// knife grip is the case that produced this: its geometry paragraph used to
    /// be applied to every skill in the app.
    func testASkillCanOverrideTheViewingGuidance() {
        let prompt = SkillVisualAssessor.systemPrompt(check: .chefKnifeGrip)
        XCTAssertTrue(prompt.contains("both faces"))
    }

    /// The most repeated instruction in the whole deliverable: ask which version
    /// they meant before deciding they got it wrong.
    func testAnIntentBranchReachesThePromptWithItsDefault() {
        let branch = SkillIntentBranch(
            question: "soft and creamy, or firm and fluffy?",
            options: [
                SkillIntentOption(
                    key: "soft",
                    spokenLabel: "soft, creamy, French",
                    judgeAgainst: "small curds, no browning at all"),
                SkillIntentOption(
                    key: "fluffy",
                    spokenLabel: "fluffy, American",
                    judgeAgainst: "large curds, light colour is fine"),
            ],
            defaultKey: "soft")
        let prompt = SkillVisualAssessor.systemPrompt(
            check: check(mistakes: [], intent: branch))

        XCTAssertTrue(prompt.contains("soft and creamy, or firm and fluffy?"))
        XCTAssertTrue(prompt.contains("large curds"))
        XCTAssertTrue(prompt.contains("Never mark one branch wrong for not being another"))
    }

    /// Home tolerances, not culinary school ones. The deliverable is emphatic
    /// that holding a home cook to a 3mm julienne is how an instructor loses
    /// somebody who was doing fine.
    func testHomeTolerancesAreStatedAsTheStandard() {
        let prompt = SkillVisualAssessor.systemPrompt(check: check(
            mistakes: [],
            mode: .outcome,
            tolerance: ["most sticks around 2 to 4mm and similar enough to cook together"]))
        XCTAssertTrue(prompt.contains("2 to 4mm"))
        XCTAssertTrue(prompt.contains("looser than a"))
    }

    /// Nothing in a rubric may be omitted just because it is empty: a check with
    /// no intent branch and no tolerances must still build a clean prompt.
    func testAnUnadornedRubricStillBuildsAPrompt() {
        let prompt = SkillVisualAssessor.systemPrompt(check: check(mistakes: []))
        XCTAssertFalse(prompt.contains("more than one correct version"))
        XCTAssertFalse(prompt.contains("How close is close enough"))
        XCTAssertTrue(prompt.contains("The technique being taught"))
    }
}
