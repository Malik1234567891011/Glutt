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
        evidence: [String] = ["thumb on the blade face near the heel"],
        // Two pictures reading the thumb on the handle, which is what a real
        // `handleGrip` answer now has to come with. Tests that care about the
        // gate itself pass their own.
        // `remainingFingers` is not decoration here: a pass is refused without
        // it, because a hand closed around the blade reads exactly like a pinch
        // grip on the thumb and index alone.
        observations: [[String: String]] = [
            ["thumb": "onHandle", "remainingFingers": "onHandle"],
            ["thumb": "onHandle", "remainingFingers": "onHandle"],
        ],
        // A real assessment names the picture the knife is in. Zero means none
        // of them had it, which is its own outcome and not the default here.
        toolPicture: Int = 1,
        // The collar straddled by the fist, which is what a correct pinch grip
        // looks like. Tests about the landmark itself pass their own.
        landmark: String? = "insideFist"
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
            observedEvidence: evidence,
            observations: observations,
            toolPicture: toolPicture,
            landmark: landmark)
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
            confidence: 0.9,
            observations: [["remainingFingers": "onHandle"]],
            toolPicture: 1,
            landmark: "insideFist")

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
            primaryIssueKey: "pointerGrip",   // a claim about the index finger
            toolPicture: 1,
            landmark: "insideFist")

        XCTAssertEqual(
            SkillCoachDecision.decide(inferred, check: check),
            .cannotSee(regions: [.indexFinger]))
    }

    /// Grip location is NOT judgeable without the thumb, and believing
    /// otherwise is what produced the bug this test was rewritten for.
    ///
    /// The old rule here was that "your whole hand is back on the handle" needs
    /// only the control point, since the fingers wrap the handle either way.
    /// That is true of the fingers and false of the thumb, and the thumb is the
    /// entire difference: in a pinch grip it is up on the flat of the blade, in
    /// a handle grip it is not. On a device archive she called a textbook pinch
    /// grip `handleGrip` at 0.85 confidence, which is what this shortcut looks
    /// like in a cook's hands. The rubric text already said "report it only when
    /// you can positively see that the thumb is NOT on the blade"; the code just
    /// was not enforcing what the rubric asked for.
    func testGripLocationIsNotJudgeableWithoutSeeingTheThumb() {
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
            primaryIssueKey: "handleGrip",
            toolPicture: 1)

        XCTAssertEqual(
            SkillCoachDecision.decide(handleGrip, check: check),
            .cannotSee(regions: [.thumb]),
            "a hidden thumb means no verdict, not a confident wrong one")
    }

    /// And with the thumb in view AND the pictures placing it on the handle it
    /// still corrects, so this is a narrower gate rather than a skill that
    /// stopped working.
    func testGripLocationStillCorrectsWhenTheThumbIsVisible() {
        let handleGrip = SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.9),
            visibility: [
                "tool": .sufficient,
                "controlPoint": .sufficient,
                "thumb": .sufficient,
                "indexFinger": .insufficient,
                "remainingFingers": .insufficient,
                "wrist": .insufficient,
            ],
            overall: .needsAdjustment,
            confidence: 0.9,
            primaryIssueKey: "handleGrip",
            observations: [["thumb": "onHandle"], ["thumb": "onHandle"]],
            toolPicture: 1,
            landmark: "insideFist")

        XCTAssertEqual(
            SkillCoachDecision.decide(handleGrip, check: check),
            .correct(mistakeKey: "handleGrip", certainty: .confident))
    }

    /// The gate that the archive asked for. She may say `handleGrip` all she
    /// likes; if her own reading of the pictures puts the thumb on the blade,
    /// the correction does not leave the building.
    ///
    /// Taken from a real look: a sharp, well framed close up of a textbook
    /// pinch grip came back `needsAdjustment` / `handleGrip` at 0.85, with the
    /// thumb plainly on the blade in the picture she was judging.
    func testAVerdictItsOwnPicturesContradictIsNotSaidOutLoud() {
        let contradicted = assessment(
            overall: .needsAdjustment, issue: "handleGrip",
            observations: [["thumb": "onBlade"], ["thumb": "onBlade"]])

        XCTAssertEqual(
            SkillCoachDecision.decide(contradicted, check: check),
            .cannotSee(regions: [.thumb]))
    }

    /// Two pictures of the same hand disagreeing is not a majority, and a coin
    /// toss is not grounds for telling somebody they are doing it wrong. Two
    /// near identical grips in one archived session got opposite verdicts,
    /// which is what this noise looks like from the cook's side.
    func testPicturesThatDisagreeAboutTheThumbBlockTheCorrection() {
        let split = assessment(
            overall: .needsAdjustment, issue: "handleGrip",
            observations: [["thumb": "onBlade"], ["thumb": "onHandle"]])

        XCTAssertEqual(
            SkillCoachDecision.decide(split, check: check),
            .cannotSee(regions: [.thumb]))
    }

    /// A thumb nobody could place is not permission either. This is the rule the
    /// rubric text always stated and the code was not enforcing.
    func testAThumbNoPictureCouldPlaceBlocksTheCorrection() {
        let unplaced = assessment(
            overall: .needsAdjustment, issue: "handleGrip",
            observations: [["thumb": "cannotTell"], ["thumb": "cannotTell"]])

        XCTAssertEqual(
            SkillCoachDecision.decide(unplaced, check: check),
            .cannotSee(regions: [.thumb]))
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
            outcome: outcome, note: "note", source: .showing)
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
            observedEvidence: ["saw a thing"],
            toolPicture: 1
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
    ///
    /// It happened for real: the proxy had not been redeployed, every read
    /// failed, and a cook watching the live panel fill with frames was told
    /// there was no view. They reset the app and tried again, because that is
    /// the only sensible thing to do when you are told the camera is not
    /// working and you can see that it is.
    func testADroppedRequestIsNotBlamedOnTheCamera() {
        let suggestion = VisualFrameRejection.lookRequestFailed.suggestion
        XCTAssertTrue(
            suggestion.localizedCaseInsensitiveContains("your problem and not theirs"),
            "it has to own the failure rather than imply the cook caused it")
        XCTAssertTrue(suggestion.localizedCaseInsensitiveContains("do not ask them to move"))
        XCTAssertTrue(
            suggestion.localizedCaseInsensitiveContains("do not say you cannot see"),
            "\"I cannot see\" is the exact sentence that sent a cook to check their glasses")
        XCTAssertNotEqual(
            VisualFrameRejection.lookRequestFailed.suggestion,
            VisualFrameRejection.noFrames.suggestion)
    }
}

/// The framing instruction, which was causing the failures it existed to
/// prevent.
final class SkillFramingInstructionTests: XCTestCase {

    /// "Rest the blade on your board, look down at your hand" puts the knife at
    /// counter level, at arm's length from a head mounted camera, low in the
    /// frame and often behind whichever hand is nearer. Measured across the
    /// archive the knife hand came out between 0.9% and 5.3% of the picture,
    /// and every look that passed had it held up and central.
    func testSheAsksForTheKnifeToBeHeldUp() {
        let live = SkillVisualCheck.chefKnifeGrip.framingInstruction
        XCTAssertTrue(live.localizedCaseInsensitiveContains("hold the knife up"))
        XCTAssertFalse(
            live.localizedCaseInsensitiveContains("rest the blade on your board"),
            "that instruction produced the framing that could not be judged")
        XCTAssertTrue(
            live.localizedCaseInsensitiveContains("turn your hand slowly"),
            "the two faces of the blade still need the movement")
    }

    /// A retry has to change something. Repeating the first instruction to
    /// somebody who just followed it is how a cook concludes it is broken.
    func testTheRetryAsksForSomethingDifferent() {
        let check = SkillVisualCheck.chefKnifeGrip
        XCTAssertNotEqual(check.retryFraming, check.framingInstruction)
        // It names what actually went wrong. Archived frames showed the cook's
        // hand falling off the bottom edge in all four pictures while the blade
        // filled the frame, because they were looking at the tip rather than at
        // their hand. "Bring it closer" would not have helped: it was already
        // close, it was just below where they were looking.
        XCTAssertTrue(check.retryFraming.localizedCaseInsensitiveContains("your hand"))
    }
}

/// The two faults that made a whole lesson go silent.
extension SkillVisualCoachingTests {

    /// No picture had the knife in it, so there is no grip to talk about.
    ///
    /// From a real look: the cropper sent a close up of the cook's empty fist
    /// while the knife was in their other hand at the edge of frame, and the
    /// verdict came back describing a blade that was not in the picture. She
    /// now names which picture holds the tool, and zero means none did.
    func testNoPictureWithTheToolMeansNoVerdict() {
        let noKnife = assessment(
            overall: .needsAdjustment, issue: "handleGrip", toolPicture: 0)

        XCTAssertEqual(
            SkillCoachDecision.decide(noKnife, check: check),
            .cannotSee(regions: [.tool]),
            "a grip verdict about a picture with no knife in it is the whole bug")
    }

    /// And naming a picture lets the ordinary path run, so this gate is narrow
    /// rather than a feature that stopped working.
    func testNamingThePictureLetsTheVerdictThrough() {
        XCTAssertEqual(
            SkillCoachDecision.decide(
                assessment(overall: .ready, toolPicture: 2), check: check),
            .passed(isVariation: false))
    }
}

/// The prompt has to ask about every picture it sends.
final class SkillObservationCountTests: XCTestCase {

    /// A look sent three pictures and got two readings back, and the picture it
    /// dropped was the only one where the cook's thumb was visible. The other
    /// two were a wide shot and a fist on a bare handle, both honestly
    /// `cannotTell`, so the majority came out empty and a clean pinch grip could
    /// not be judged. The answer was in the frame, in the request, and nobody
    /// ever asked about it.
    ///
    /// The cause was this schema printing exactly two example entries whatever
    /// it had been handed, and the model copying the shape it was shown.
    func testTheSchemaAsksAboutEveryPictureItSends() {
        for pictures in 1...5 {
            let prompt = SkillVisualAssessor.systemPrompt(
                check: .chefKnifeGrip, pictures: pictures)
            let entries = prompt.components(separatedBy: "\"picture\":").count - 1
            XCTAssertEqual(
                entries, pictures,
                "sent \(pictures) pictures but asked for \(entries) readings")
            XCTAssertTrue(
                prompt.contains("exactly \(pictures) entries"),
                "the count has to be stated, not just implied by the example")
        }
    }

    /// And the numbering has to run 1...n, because the readings are matched to
    /// pictures by position and an off-by-one here is invisible downstream.
    func testThePicturesAreNumberedInOrder() {
        let prompt = SkillVisualAssessor.systemPrompt(check: .chefKnifeGrip, pictures: 4)
        for n in 1...4 {
            XCTAssertTrue(prompt.contains("\"picture\": \(n)"), "picture \(n) is missing")
        }
        XCTAssertFalse(prompt.contains("\"picture\": 5"))
    }

    /// One clear view outranks two that could not tell. `cannotTell` must never
    /// vote, or a good look gets outvoted by the wide shot and a bad angle.
    func testAClearReadingIsNotOutvotedByPicturesThatCouldNotTell() {
        let assessment = SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.9),
            overall: .ready,
            confidence: 0.9,
            observations: [
                ["thumb": "cannotTell"],
                ["thumb": "cannotTell"],
                ["thumb": "onBlade"],
            ],
            toolPicture: 3)
        let thumb = SkillVisualCheck.chefKnifeGrip.observations.first { $0.region == .thumb }!
        XCTAssertEqual(assessment.reading(for: thumb), "onBlade")
    }
}

/// The worst thing this feature has done.
///
/// A cook held a chef's knife with their whole hand wrapped around the BLADE,
/// every finger across the cutting edge, and was told "yep, that's it, looks
/// perfect" at 0.90 confidence. Her written evidence claimed the remaining
/// fingers were around the handle. They were plainly on the steel.
final class SkillDangerousGripTests: XCTestCase {

    private let check = SkillVisualCheck.chefKnifeGrip

    private func reading(
        _ thumb: String, _ index: String, _ rest: String,
        overall: SkillVisualAssessment.Overall = .ready
    ) -> SkillVisualAssessment {
        SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.95),
            visibility: Dictionary(uniqueKeysWithValues:
                check.reportedVisibility.map { ($0.rawValue, .sufficient) }),
            overall: overall,
            confidence: 0.9,
            observations: [
                ["thumb": thumb, "indexFinger": index, "remainingFingers": rest],
                ["thumb": thumb, "indexFinger": index, "remainingFingers": rest],
            ],
            toolPicture: 2,
            landmark: "insideFist")
    }

    /// The exact reading that came back as `ready`. Thumb and index on the
    /// blade is a correct pinch grip AND a hand closed around the steel; the
    /// only thing separating them is where the other three fingers went.
    /// Asked, not asserted.
    ///
    /// Across six archived looks this reading caught both hands that really
    /// were closed around a blade and also flagged both textbook pinch grips.
    /// Every rephrasing traded that away for something worse: the collar based
    /// variants missed the real blade grips, which is the failure that costs a
    /// finger. So the signal stays, and it asks the one person who can settle it
    /// in a second rather than stopping somebody who is doing it right.
    func testAHandClosedAroundTheBladeIsQueried() {
        let outcome = SkillCoachDecision.decide(
            reading("onBlade", "onBlade", "onBlade"), check: check)

        guard case .confirmWithCook(_, let question) = outcome else {
            return XCTFail("fingers reading onBlade must be checked with them, got \(outcome)")
        }
        XCTAssertTrue(question.contains("blade"))
        XCTAssertTrue(question.hasSuffix("?"), "it has to be a question they can answer")
    }

    /// And it is never silently passed, whatever else she concluded.
    func testItIsNeverJustPassed() {
        XCTAssertNotEqual(
            SkillCoachDecision.decide(
                reading("onBlade", "onBlade", "onBlade"), check: check),
            .passed(isVariation: false))
    }

    /// It outranks a confident pass, which is the case that actually happened.
    func testItOutranksHerOwnVerdict() {
        let outcome = SkillCoachDecision.decide(
            reading("onBlade", "onBlade", "onBlade", overall: .ready), check: check)
        XCTAssertNotEqual(outcome, .passed(isVariation: false))
    }

    /// A real pinch grip still passes, so this is a narrower gate and not a
    /// feature that stopped working.
    func testARealPinchGripStillPasses() {
        XCTAssertEqual(
            SkillCoachDecision.decide(
                reading("onBlade", "onBlade", "onHandle"), check: check),
            .passed(isVariation: false))
    }

    /// And a pass she cannot support is not a pass. Fingers she could not place
    /// might be around the handle or might be across the edge, and "let me see
    /// that again" is the only honest thing to say.
    func testShePassesNobodyOnFingersSheCouldNotSee() {
        XCTAssertEqual(
            SkillCoachDecision.decide(
                reading("onBlade", "onBlade", "cannotTell"), check: check),
            .cannotSee(regions: [.remainingFingers]))
    }
}

/// The collar question was measured WORSE than a plain one and removed.
///
/// Asked where the collar sat relative to the fist, Sonnet answered
/// `insideFist` on a hand wrapped right around the blade, which reads as a
/// correct pinch grip and would have passed it. Asked plainly whether the
/// middle, ring and little fingers were on the steel or the handle, the same
/// model on the same frame answered `onBlade`, and answered `onHandle` on a
/// genuine pinch grip. Cleverness lost to a direct question.
final class SkillLandmarkRemovedTests: XCTestCase {

    func testTheKnifeCheckAsksPlainlyRatherThanAboutACollar() {
        XCTAssertNil(
            SkillVisualCheck.chefKnifeGrip.landmark,
            "the collar question passed a hand that was wrapped around the blade")

        let question = SkillVisualCheck.chefKnifeGrip.observations
            .first { $0.region == .remainingFingers }?.question ?? ""
        XCTAssertTrue(question.contains("STEEL BLADE"))
        XCTAssertTrue(question.contains("HANDLE"))
    }

    /// The gates it feeds are the ones that were already there, so removing the
    /// landmark must not have removed the stop.
    func testTheDangerAndPassGatesStillHangOffThatAnswer() {
        let check = SkillVisualCheck.chefKnifeGrip
        XCTAssertEqual(check.dangerousReadings[.remainingFingers], ["onBlade"])
        XCTAssertEqual(check.passRequires[.remainingFingers], ["onHandle"])
    }
}

/// The deciding question is asked in its own request, and its answer wins.
///
/// Measured on the same model and the same two pictures of a hand closed around
/// a knife blade: asked inside the full fourteen thousand character prompt it
/// answered `onHandle`; asked on its own, `onBlade`. On a genuine pinch grip the
/// small request answered `onHandle`, so it discriminates rather than panicking.
final class SkillDecisiveReadingTests: XCTestCase {

    private let check = SkillVisualCheck.chefKnifeGrip

    private func assessment(saying rubric: String, aloneSays alone: String?)
    -> SkillVisualAssessment {
        var a = SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.95),
            visibility: Dictionary(uniqueKeysWithValues:
                check.reportedVisibility.map { ($0.rawValue, .sufficient) }),
            overall: .ready, confidence: 0.9,
            observations: [["remainingFingers": rubric], ["remainingFingers": rubric]],
            toolPicture: 2)
        if let alone {
            a.decisive = .init(region: "remainingFingers", answer: alone)
        }
        return a
    }

    func testTheSeparateAnswerOverridesTheRubricOne() {
        let outcome = SkillCoachDecision.decide(
            assessment(saying: "onHandle", aloneSays: "onBlade"), check: check)
        guard case .confirmWithCook = outcome else {
            return XCTFail("the answer asked on its own has to win, got \(outcome)")
        }
    }

    /// And it can rescue a pass too, so this is not a one way alarm.
    func testItAlsoOverridesInTheSafeDirection() {
        XCTAssertEqual(
            SkillCoachDecision.decide(
                assessment(saying: "onBlade", aloneSays: "onHandle"), check: check),
            .passed(isVariation: false))
    }

    /// When the separate request fails there is nothing to override with, and
    /// the rubric answer stands rather than the look being lost.
    func testAFailedSeparateRequestFallsBackRatherThanBreaking() {
        XCTAssertEqual(
            SkillCoachDecision.decide(
                assessment(saying: "onHandle", aloneSays: nil), check: check),
            .passed(isVariation: false))
    }

    /// `cannotTell` from the separate request is not a pass.
    func testCannotTellOnItsOwnIsNotAPass() {
        XCTAssertNotEqual(
            SkillCoachDecision.decide(
                assessment(saying: "onHandle", aloneSays: "cannotTell"), check: check),
            .passed(isVariation: false))
    }

    /// The knife check must actually ask for this, or none of the above runs.
    func testTheKnifeCheckNamesItsDecisiveQuestion() {
        XCTAssertEqual(check.decisiveRegion, .remainingFingers)
        XCTAssertTrue(check.observations.contains { $0.region == .remainingFingers })
    }
}

/// Two faults the cook noticed that the archive could never have shown.
@MainActor
final class DeletedCollectionSurvivalTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Recipe.self, RecipeCollection.self, MealPlan.self, MealPlanLine.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// The guard the launch tab needs: a plan whose collection is gone
    /// contributes nothing rather than taking the process with it.
    func testAPlanPointingAtADeletedCollectionIsSkipped() throws {
        let context = try makeContext()
        let collection = RecipeCollection(name: "This Week")
        let plan = MealPlan(name: "This Week", mealCount: 5)
        plan.collection = collection
        context.insert(collection)
        context.insert(plan)
        try context.save()

        context.delete(collection)
        try context.save()

        // What `plannedRecipeIDs` does: resolve only against collections that
        // are genuinely still there.
        let live = Set(
            (try context.fetch(FetchDescriptor<RecipeCollection>())).map(\.persistentModelID))
        let plans = try context.fetch(FetchDescriptor<MealPlan>())
        let resolved = plans.compactMap { plan -> RecipeCollection? in
            guard let collection = plan.collection,
                  live.contains(collection.persistentModelID) else { return nil }
            return collection
        }
        XCTAssertTrue(resolved.isEmpty, "a deleted collection must not be followed")
    }

    /// And the cause, not just the symptom: deleting a collection clears the
    /// plans that point at it, so nothing is left dangling in the first place.
    func testDeletingACollectionClearsThePlansPointingAtIt() throws {
        let context = try makeContext()
        let collection = RecipeCollection(name: "This Week")
        let plan = MealPlan(name: "This Week", mealCount: 5)
        plan.collection = collection
        context.insert(collection)
        context.insert(plan)
        try context.save()

        // Exactly what the delete button now does, before deleting.
        let doomed = collection.persistentModelID
        for candidate in try context.fetch(FetchDescriptor<MealPlan>())
        where candidate.collection?.persistentModelID == doomed {
            candidate.collection = nil
        }
        context.delete(collection)
        try context.save()

        let plans = try context.fetch(FetchDescriptor<MealPlan>())
        XCTAssertEqual(plans.count, 1, "the plan itself survives, only the link goes")
        XCTAssertNil(plans.first?.collection)
    }
}

/// What a cook can take in at a glance, and whether they can tell she heard them.
///
/// From watching a real cook through the butter chicken: he said "Chef", could
/// not tell if it landed, walked over to look at the phone, and often had to say
/// it again. Then at nearly every step he tapped "view more" and read the whole
/// paragraph, because the card showed the same prose she had just spoken, cut
/// off after three lines.
final class CookGlanceTests: XCTestCase {

    private func butterChicken() throws -> CookPlan {
        let url = try XCTUnwrap(Bundle.main.url(
            forResource: "CookPlan-butter-chicken", withExtension: "json"))
        return try JSONDecoder().decode(CookPlan.self, from: Data(contentsOf: url))
    }

    /// Every step has to be readable in one look, with hands full.
    func testEveryStepIsGlanceable() throws {
        for step in try butterChicken().steps {
            let lines = step.glanceLines
            XCTAssertFalse(lines.isEmpty, "\(step.id) has nothing to show at a glance")
            XCTAssertLessThanOrEqual(
                lines.count, 5,
                "\(step.id) has \(lines.count) lines, which is the wall we removed")
            for line in lines {
                XCTAssertLessThanOrEqual(
                    line.count, 60,
                    "\(step.id) line is a sentence, not a glance: \(line)")
            }
        }
    }

    /// The amounts have to be on the card. Seven of twelve cooks in the study
    /// stopped to ask for a quantity mid-step because the step said "add the
    /// yogurt" and the amount lived in a list they could not see.
    func testTheAmountsAreOnTheCardWhereTheyAreNeeded() throws {
        let plan = try butterChicken()
        let marinate = try XCTUnwrap(plan.steps.first { $0.id == "s1" })
        let amounts = plan.mise.filter {
            marinate.ingredientNames.map { $0.lowercased() }.contains($0.name.lowercased())
        }
        XCTAssertFalse(amounts.isEmpty, "the step names ingredients the mise does not")
        XCTAssertTrue(
            amounts.contains { $0.amount?.isEmpty == false },
            "no amounts to show, so the cook still has to go and look")
    }

    /// A plan compiled before `glance` existed still has to produce something
    /// readable, because plans are cached and cooks will be mid-recipe on one.
    func testAnOlderPlanStillGetsLinesRatherThanAWall() {
        let old = CookPlan.PlanStep(
            id: "x", index: 0, title: "Sear",
            instruction: "Heat the pan over medium-high. Add the chicken in one layer. "
                + "Leave it two minutes without touching it.",
            kind: .active)
        let lines = old.glanceLines
        XCTAssertGreaterThan(lines.count, 1, "prose has to be broken up, not shown whole")
        XCTAssertLessThanOrEqual(lines.count, 5)
    }

    /// The hint should say what she is for. "Say Chef to talk" tells a cook the
    /// mechanism and not the offer, and people who do not know they can ask
    /// stay stuck on things she would happily have answered.
    func testTheHintSaysWhatSheIsFor() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Glutt/Features/Polly/PollyAdaptiveCanvasView.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("if you need anything"))
        XCTAssertFalse(
            source.contains("Tap to view more"),
            "nothing on a cook card should be hidden behind a tap")
    }

    /// The deaf window after she stops talking, which is exactly when a person
    /// naturally speaks.
    func testTheWakeWordIsNotDeafWhenPeopleActuallySpeak() {
        XCTAssertLessThanOrEqual(
            PollyConfig.wakeSuppressionTailSeconds, 0.6,
            "a longer tail swallows the Chef said the moment she stops")
        XCTAssertGreaterThan(
            PollyConfig.wakeSuppressionTailSeconds, 0.2,
            "some tail is needed or her own trailing words wake her")
    }

    /// A bare "Chef" has to interrupt her, because mid-sentence is exactly when
    /// somebody wants to.
    func testABareChefInterruptsHer() {
        XCTAssertTrue(ConversationalGate.isClearInterruption("chef"))
        XCTAssertTrue(ConversationalGate.isClearInterruption("chef wait"))
        XCTAssertTrue(ConversationalGate.isClearInterruption("hey chef"))
    }
}

/// The listening sound, which a cook hears more often than anything else in the
/// app and never sees.
@MainActor
final class ListeningEarconTests: XCTestCase {

    /// Short enough that it can never talk over anybody, long enough to ring
    /// rather than click.
    func testItIsShortEnoughToLiveWith() {
        let samples = ListeningEarcon.samples()
        let seconds = Double(samples.count) / 44_100
        XCTAssertGreaterThan(seconds, 0.3, "any shorter and a warm tone reads as a thud")
        XCTAssertLessThan(seconds, 1.0, "it plays every time the cook speaks")
    }

    /// Quiet. It plays over an extractor fan, thirty times a session, and an
    /// assertive noise at that rate is worse than no noise at all.
    func testItIsQuietAndDoesNotClip() {
        let peak = ListeningEarcon.samples().map { abs($0) }.max() ?? 0
        XCTAssertLessThanOrEqual(peak, 0.35, "too loud to hear this often")
        XCTAssertGreaterThan(peak, 0.15, "too quiet to hear over a kitchen")
    }

    /// The detail that separates a struck object from a synthesiser: it has to
    /// actually decay, and decay from the front.
    func testItDecaysLikeSomethingStruck() {
        let samples = ListeningEarcon.samples()
        let third = samples.count / 3
        func energy(_ slice: ArraySlice<Float>) -> Float {
            slice.reduce(0) { $0 + abs($1) } / Float(slice.count)
        }
        let start = energy(samples[0..<third])
        let end = energy(samples[(third * 2)...])
        XCTAssertGreaterThan(
            start, end * 3,
            "a sound that does not die away is a tone, not a struck bar")
    }

    /// No click at either end. A hard edge on a waveform is the small ugliness
    /// that starts to grate on the twentieth hearing.
    func testItStartsAndEndsSoftly() {
        let samples = ListeningEarcon.samples()
        XCTAssertLessThan(abs(samples[0]), 0.02, "a hard start is a click")
        XCTAssertLessThan(abs(samples[samples.count - 1]), 0.02, "a hard stop is a click")
    }
}
