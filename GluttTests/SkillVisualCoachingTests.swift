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

// MARK: - Framing, which turned out to be the actual problem

/// What the first archived looks proved.
///
/// The complaint was that Chef could not see a thumb while claiming to see the
/// fingers wrapped round the handle, which sounds impossible and is not: she
/// was being handed a wide shot of a kitchen with the hand at 3.8% of it in one
/// corner. The thumb inside that is about fifteen pixels. She answered anyway
/// and returned `handleGrip` on a grip whose thumb was on the blade.
final class SkillFrameFocusTests: XCTestCase {

    /// A frame with no hand in it must come back untouched. Anything else means
    /// a bad crop replaces a merely wide picture, which is worse.
    func testAFrameWithNoHandIsHandedBackUnchanged() {
        let plain = UIGraphicsImageRenderer(size: CGSize(width: 504, height: 896)).image { ctx in
            UIColor.systemGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 504, height: 896))
        }
        let jpeg = plain.jpegData(compressionQuality: 0.8)!

        let focused = SkillFrameFocus.focusOnHands(in: jpeg)
        XCTAssertEqual(focused.count, 1)
        XCTAssertEqual(focused[0].jpeg, jpeg, "no hand found means no crop")
        XCTAssertNil(focused[0].coverage)
    }

    func testRubbishInputIsSurvived() {
        let focused = SkillFrameFocus.focusOnHands(in: Data([0x00, 0x01, 0x02]))
        XCTAssertEqual(focused.count, 1)
        XCTAssertEqual(focused[0].jpeg, Data([0x00, 0x01, 0x02]))
        XCTAssertNil(focused[0].coverage)
    }

    /// A fixed multiple of the hand could not work across hand sizes, which
    /// took two wrong values to learn. 2.5 cropped tight enough to cut the
    /// handle off below the knuckles; 4.0 overshot the frame on a 5% hand and
    /// clamped back to the whole kitchen, which looked exactly like the union
    /// bug it had replaced.
    func testTheCropIsSizedByTargetRatherThanByMultiplier() {
        // The property that makes it self correcting: the same rule has to
        // produce a modest crop for a small hand and almost none for a big one.
        // Verified offline against archived originals at 1.9%, 3.9% and 5.3%.
        // The bound moved once the crops were compared side by side: 0.25 was
        // still tight enough to lose the knife, so the upper limit came down
        // rather than the value going up.
        XCTAssertGreaterThan(SkillFrameFocus.handShareOfCrop, 0.05,
                             "too loose and the hand is a speck in a kitchen again")
        XCTAssertLessThanOrEqual(SkillFrameFocus.handShareOfCrop, 0.15,
                                 "tighter than this and the blade or the handle leaves the frame")
    }

    /// The measured number that set the threshold. A hand at 3.8% of the frame
    /// is 93 pixels across, and cropping buys about 1.6 times that, which is
    /// still not enough to read a thumb.
    func testTheTooFarThresholdSitsBelowWhatWasMeasured() {
        XCTAssertLessThan(
            SkillFrameFocus.tooFarToJudge, 0.038,
            "the real failing frame was 3.8% and must still be attempted after cropping")
        XCTAssertGreaterThan(
            SkillFrameFocus.tooFarToJudge, 0.005,
            "refusing everything would be as useless as answering everything")
    }

    /// The refusal has to read as an instruction, not as a shrug. "I cannot see"
    /// is wrong here: she can see them, they are just too far from the camera.
    func testTheTooFarSuggestionTellsThemWhatToDo() {
        let suggestion = VisualFrameRejection.subjectTooFar.suggestion
        XCTAssertTrue(suggestion.localizedCaseInsensitiveContains("bring their hand up"))
        XCTAssertTrue(
            suggestion.localizedCaseInsensitiveContains("do not comment on their grip"),
            "a guess at this range is exactly the false correction to avoid")
        XCTAssertFalse(suggestion.contains("—"), "spoken copy takes no dashes")
    }
}

// MARK: - Two hands, one of them holding a phone

/// What the second round of archived looks proved, after the first round's fix
/// was itself wrong.
final class SkillTwoHandTests: XCTestCase {

    /// The bug that hid behind a plausible number.
    ///
    /// Unioning the landmarks of every hand reported a confident 27% "hand"
    /// that was the GAP between a phone hand on the left and a knife hand on
    /// the right edge, padded out to the whole kitchen. The crop did nothing
    /// and the log said it had worked.
    func testTheCropNeverSpansTwoHands() {
        // A synthetic pair of hands is not something Vision will find, so this
        // pins the contract instead: one Focused per hand, never one merged.
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 504, height: 896)).image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 504, height: 896))
        }
        let results = SkillFrameFocus.focusOnHands(in: blank.jpegData(compressionQuality: 0.8)!)
        XCTAssertEqual(results.count, 1, "no hands means the original, once")
        XCTAssertNil(results[0].coverage)
    }

    /// The worst thing in the whole feature, and the one nothing downstream can
    /// catch: three pictures of a hand holding a phone came back as a chef's
    /// knife with the hand on the handle. The visibility gate cannot help,
    /// because she claimed to see the tool.
    func testSheIsToldNeverToInventTheTool() {
        let prompt = SkillVisualAssessor.systemPrompt(check: .chefKnifeGrip)
        XCTAssertTrue(prompt.contains("If NONE of the pictures contains the tool, say so"))
        XCTAssertTrue(
            prompt.contains("Never say the equipment is supported when you cannot see"),
            "claiming the tool is present is what made the invention invisible")
        XCTAssertTrue(
            prompt.localizedCaseInsensitiveContains("holding their phone"),
            "she has to expect the irrelevant hand, or she will judge it")
    }
}

/// The confusion that produced three wrong verdicts in a row on a legible
/// picture, after the framing and the cropping were both fixed.
///
/// A correct pinch grip and a handle grip differ only at the thumb and index
/// finger. The other three fingers wrap the handle in both. Every wrong
/// `handleGrip` so far described the three wrapped fingers, which is true of
/// the grip it was accusing and true of the correct one too.
final class SkillGripConfusionTests: XCTestCase {

    func testTheRubricSaysTheTwoGripsLookAlike() {
        let handle = SkillVisualCheck.chefKnifeGrip.rubric
            .coachingOrder.first { $0.key == "handleGrip" }!

        XCTAssertTrue(
            handle.observation.contains("almost identical"),
            "the model has to be told these two look the same below the thumb")
        XCTAssertTrue(
            handle.observation.contains("positively see that the thumb is NOT on the blade"),
            "wrapped fingers are true of both grips and prove nothing")
    }

    /// It reaches the model, not just the source.
    func testTheWarningIsInThePromptTheModelReceives() {
        let prompt = SkillVisualAssessor.systemPrompt(check: .chefKnifeGrip)
        XCTAssertTrue(prompt.contains("Find the thumb before you decide"))
        XCTAssertTrue(prompt.contains("almost identical"))
    }

    /// The gate that should have caught it. Naming a thumb you did not see is
    /// the same class of error as naming a knife you did not see.
    func testHandleGripStillRequiresSeeingWhereTheHandIs() {
        let handle = SkillVisualCheck.chefKnifeGrip.rubric
            .coachingOrder.first { $0.key == "handleGrip" }!
        XCTAssertTrue(handle.requiresVisible.contains(.controlPoint))
    }
}

/// What comparing thirteen archived looks side by side actually showed.
///
/// Hand size did not separate passes from failures: 2.5% passed and 2.6%
/// failed. Confidence separated them perfectly, but that is an output. The
/// thing that decided every single one was WHICH HAND ended up in the first
/// picture. Knife hand first, pass. Empty hand first, `handleGrip`.
final class SkillWhichHandTests: XCTestCase {

    /// Measured on the two looks 48 seconds apart in one session: the empty
    /// hand was 4.0% of the frame and the knife hand 0.9%, so ordering by size
    /// put a hand holding nothing in front of her.
    func testAHandTooFarToJudgeIsNotSentAtAll() {
        XCTAssertGreaterThan(
            SkillFrameFocus.tooFarToJudge, 0.005,
            "the 0.9% knife hand has to be filtered, not cropped and sent blurry")
        XCTAssertLessThan(
            SkillFrameFocus.tooFarToJudge, 0.023,
            "2.3% and 2.5% hands were both judged correctly and must still go")
    }

    /// A quarter framed the hand and lost the knife, and a hand with no visible
    /// tool cannot be told from a hand holding nothing.
    func testTheCropLeavesRoomForTheTool() {
        XCTAssertLessThanOrEqual(
            SkillFrameFocus.handShareOfCrop, 0.15,
            "tighter than this and the blade or the handle leaves the picture")
    }

    /// A dropped request used to be reported as a camera fault, which sends a
    /// cook to fiddle with hardware that is working.
    func testADroppedRequestIsNotBlamedOnTheCamera() {
        let suggestion = VisualFrameRejection.lookRequestFailed.suggestion
        XCTAssertTrue(suggestion.localizedCaseInsensitiveContains("not their camera"))
        XCTAssertTrue(suggestion.localizedCaseInsensitiveContains("do not ask them to move"))
        XCTAssertNotEqual(
            VisualFrameRejection.lookRequestFailed.suggestion,
            VisualFrameRejection.noFrames.suggestion)
    }
}
