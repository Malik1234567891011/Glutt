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

    // MARK: - Which frames a look uses

    /// Two things at once, and both have bitten.
    ///
    /// Frames used to be ranked by encoded size, on the theory that the biggest
    /// file held the most detail. JPEG size tracks how BUSY a scene is, so a
    /// hand and a knife on a board lost every time to a cluttered counter and
    /// the model was shown the moment the cook glanced away.
    ///
    /// And taking the newest two is barely better, because two frames a fifth of
    /// a second apart are the same photograph twice. You cannot see both faces
    /// of a knife at once, so views have to be spread in TIME, which is the only
    /// way to be spread in angle.
    @MainActor
    func testALookSpreadsAcrossTheWindowRatherThanPickingFavourites() {
        let ring = makeRing(now: 100)
        // Ten frames over five seconds. The big one is a glance at the kitchen.
        ring.preload([
            (Data(count: 90_000), Date(timeIntervalSince1970: 95.5)),
            (Data(count: 11_000), Date(timeIntervalSince1970: 96.0)),
            (Data(count: 11_100), Date(timeIntervalSince1970: 96.5)),
            (Data(count: 11_200), Date(timeIntervalSince1970: 97.0)),
            (Data(count: 11_300), Date(timeIntervalSince1970: 97.5)),
            (Data(count: 11_400), Date(timeIntervalSince1970: 98.0)),
            (Data(count: 11_500), Date(timeIntervalSince1970: 98.5)),
            (Data(count: 11_600), Date(timeIntervalSince1970: 99.0)),
            (Data(count: 11_700), Date(timeIntervalSince1970: 99.5)),
            (Data(count: 11_800), Date(timeIntervalSince1970: 100.0)),
        ])

        let chosen = ring.spread(3, within: 5)

        XCTAssertEqual(chosen.count, 3)
        XCTAssertEqual(chosen.first?.count, 11_800, "the newest is the moment they meant")
        // Spread, not clustered: the three must not all come from the last second.
        XCTAssertEqual(Set(chosen.map(\.count)).count, 3, "three distinct moments")
        let oldest = chosen.map(\.count).min() ?? 0
        XCTAssertLessThan(
            oldest, 11_400,
            "the views have to reach back through the window, or they are one angle three times")
    }

    @MainActor
    func testALookWillNotReachBackPastTheWindow() {
        let ring = makeRing(now: 100)
        ring.preload([
            (Data(count: 10), Date(timeIntervalSince1970: 80)),   // ancient
            (Data(count: 20), Date(timeIntervalSince1970: 99)),
        ])

        XCTAssertEqual(ring.spread(3, within: 5).map(\.count), [20])
    }

    @MainActor
    private func makeRing(now: TimeInterval) -> SkillFrameRing {
        SkillFrameRing(
            visuals: PollyVisualSourceCoordinator(
                phone: PhoneCameraVisualSource(camera: PollyCameraController())),
            clock: { Date(timeIntervalSince1970: now) })
    }

    // MARK: - Asking to be looked at

    /// Reading the request ourselves is what lets the looking start before she
    /// has answered, which is most of the seventeen seconds that used to sit
    /// between the question and the verdict.
    func testWhatCountsAsAskingToBeSeen() {
        for asked in [
            "does this look right?",
            "Chef, how does this look",
            "like this?",
            "is that better",
            "can you check my grip",
            "have a look at this",
            "I fixed it, how about now",
            "watch me do it",
            "am I holding it right",
            "tell me how it looks",
        ] {
            XCTAssertTrue(
                SkillLookRequest.isAskingToBeSeen(asked), "should have started looking: \(asked)")
        }

        for notAsked in [
            "this feels really awkward",
            "my hand hurts a bit",
            "why am I touching the blade",
            "okay",
            "I usually just hold the handle because that is how my dad did it and he cooked "
                + "every night for about twenty years",
        ] {
            XCTAssertFalse(
                SkillLookRequest.isAskingToBeSeen(notAsked),
                "should not have burned a look on: \(notAsked)")
        }
    }

    /// A long sentence that names looking is still a request; a long sentence
    /// that merely mentions "this" is a story.
    func testLengthOnlyMattersWithoutALookVerb() {
        XCTAssertTrue(SkillLookRequest.isAskingToBeSeen(
            "can you look at my hand and tell me whether the thumb is anywhere near right"))
        XCTAssertFalse(SkillLookRequest.isAskingToBeSeen(
            "is this the kind of thing my grandmother would have done when she was teaching "
                + "me to cook on a Sunday"))
    }

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

    func testTheCoachPromptIsAboutDeliveryRatherThanJudgement() throws {
        let skill = try XCTUnwrap(SkillCatalog.skill("knife.grip"))
        let prompt = SkillCoachPrompt.instructions(
            skill: skill, check: check, seesContinuously: true)

        XCTAssertTrue(prompt.contains("check_the_hold"))
        XCTAssertTrue(prompt.contains("finish_lesson"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("never give two corrections"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("never say a technique is"),
                      "she must not certify safety from a photograph")
        // The lesson's own steps, so she teaches what the screen says.
        for step in skill.lesson?.steps ?? [] {
            XCTAssertTrue(prompt.contains(step), "the written lesson must reach her")
        }
        // And none of the internal keys, which are not words anybody says.
        for mistake in check.rubric.rankedMistakes {
            XCTAssertFalse(prompt.contains(mistake.key),
                           "\(mistake.key) is an assessor key, not something to say out loud")
        }
    }

    /// Without glasses she is told plainly that she cannot look, because the
    /// alternative is an instructor who pretends to have watched.
    func testWithoutGlassesShePromisesNothing() throws {
        let skill = try XCTUnwrap(SkillCatalog.skill("knife.grip"))
        let prompt = SkillCoachPrompt.instructions(
            skill: skill, check: check, seesContinuously: false)

        XCTAssertTrue(prompt.contains("You cannot see them"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not pretend"))
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
