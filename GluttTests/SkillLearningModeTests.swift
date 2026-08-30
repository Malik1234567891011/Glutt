import SwiftData
import XCTest
@testable import Glutt

/// The rules that decide which lesson a cook gets.
///
/// The mode is not a capture setting, it is which of two different lessons runs,
/// so getting it wrong means somebody is told to look down at their own hand
/// while holding the phone they would need to do it.
final class SkillLearningModeTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: SkillLearningModeStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "glutt.tests.\(UUID().uuidString)")
        store = SkillLearningModeStore(defaults: defaults)
    }

    /// Photos, not glasses. The mode that works for everybody is the one to
    /// fall back to, and a cook with no glasses should never open the tab and
    /// find it set to hardware they do not own.
    func testDefaultsToPhotosBeforeAnythingIsKnown() {
        XCTAssertEqual(store.mode, .showing)
        XCTAssertFalse(store.hasChosen)
    }

    func testDetectionPicksTheOpeningGuess() {
        store.suggest(glassesAvailable: true)
        XCTAssertEqual(store.mode, .watching)
        XCTAssertFalse(store.hasChosen, "a guess is not a choice")

        let other = SkillLearningModeStore(defaults: defaults)
        other.suggest(glassesAvailable: false)
        XCTAssertEqual(other.mode, .showing, "a later guess may still move it")
    }

    /// The failure this exists to prevent: somebody deliberately picks photos,
    /// then walks past their glasses, and the app silently switches them back.
    func testDetectionNeverOverridesAChoice() {
        store.choose(.showing)
        XCTAssertTrue(store.hasChosen, "picking the mode you are already in still counts")

        store.suggest(glassesAvailable: true)
        XCTAssertEqual(store.mode, .showing)
    }

    func testChoiceSurvivesANewStoreOverTheSameDefaults() {
        store.choose(.watching)
        let reloaded = SkillLearningModeStore(defaults: defaults)
        XCTAssertEqual(reloaded.mode, .watching)
        XCTAssertTrue(reloaded.hasChosen)
    }

    func testForgettingHandsTheDecisionBack() {
        store.choose(.watching)
        store.forget()
        XCTAssertFalse(store.hasChosen)
        store.suggest(glassesAvailable: false)
        XCTAssertEqual(store.mode, .showing)
    }

    // MARK: - The lesson really does differ

    /// The sentence that started all of this. "Look down at your hand and turn
    /// it slowly" is impossible while holding the camera.
    func testTheKnifeGripAsksForSomethingCompletelyDifferentInEachMode() {
        let check = SkillVisualCheck.chefKnifeGrip
        let live = check.framing(for: .watching)
        let photo = check.framing(for: .showing)

        XCTAssertNotEqual(live, photo)
        XCTAssertTrue(live.contains("look down"), "live framing is first person")
        XCTAssertTrue(photo.contains("photo"), "photo framing asks for pictures")
        // The whole reason photos are not the lesser path here.
        XCTAssertTrue(
            photo.contains("other side"),
            "a phone can photograph both faces of the blade, which glasses never see at once")
    }

    /// Falls back rather than going blank, for the skills where looking down at
    /// a board really is the same instruction either way.
    func testAMissingPhotoFramingFallsBackToTheLiveOne() {
        let check = SkillVisualCheck.basicsSimmerVsBoil
        XCTAssertNil(check.photoFraming)
        XCTAssertEqual(check.framing(for: .showing), check.framingInstruction)
    }

    func testTheSetupLineNamesTheRightHardware() {
        let check = SkillVisualCheck.chefKnifeGrip
        XCTAssertTrue(check.setupLine(for: .watching).hasPrefix("Put your glasses on"))
        XCTAssertTrue(check.setupLine(for: .showing).hasPrefix("Have your phone to hand"))
        // Same tail either way, which is the point of storing only the tail.
        XCTAssertTrue(check.setupLine(for: .showing).contains("pick up your knife"))
    }

    // MARK: - The photo check

    private func assessment(
        overall: SkillVisualAssessment.Overall,
        issue: String? = nil,
        confidence: Double = 0.9
    ) -> SkillVisualAssessment {
        let check = SkillVisualCheck.chefKnifeGrip
        var visibility: [String: SkillVisualAssessment.Visibility] = [:]
        for region in check.reportedVisibility { visibility[region.rawValue] = .sufficient }
        return SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.95),
            visibility: visibility,
            safety: .init(immediateConcern: false, description: nil, confidence: 0.1),
            overall: overall,
            confidence: confidence,
            primaryIssueKey: issue,
            observedEvidence: ["thumb on the blade face"])
    }

    @MainActor
    func testItWillNotSendUntilThereAreEnoughPhotos() async {
        let model = SkillPhotoCheckModel(
            skill: SkillCatalog.skill("knife.grip")!,
            check: .chefKnifeGrip,
            assess: { _ in self.assessment(overall: .ready) })

        XCTAssertFalse(model.hasEnough)
        await model.send()
        XCTAssertEqual(model.phase, .collecting, "sending with no photos must do nothing")

        model.add(Data([0x01]))
        model.add(Data([0x02]))
        XCTAssertTrue(model.hasEnough)
    }

    /// A photo pass and a glasses pass go through the same decision layer and
    /// produce the same authored sentence. That equivalence is the feature.
    @MainActor
    func testAPhotoCorrectionUsesTheSameAuthoredSentenceAsTheLivePath() async {
        let model = SkillPhotoCheckModel(
            skill: SkillCatalog.skill("knife.grip")!,
            check: .chefKnifeGrip,
            assess: { _ in self.assessment(overall: .needsAdjustment, issue: "handleGrip") })
        model.add(Data([0x01]))
        model.add(Data([0x02]))
        await model.send()

        let authored = SkillVisualCheck.chefKnifeGrip.rubric
            .coachingOrder.first { $0.key == "handleGrip" }!
        XCTAssertEqual(model.verdictHeadline, authored.correction)
        XCTAssertFalse(model.didPass)
    }

    /// "I cannot see" has to stay an instruction rather than a dead end, in
    /// this mode as much as the live one.
    @MainActor
    func testCannotSeeNamesTheRegionAndTheMoveThatFixesIt() async {
        let check = SkillVisualCheck.chefKnifeGrip
        var visibility: [String: SkillVisualAssessment.Visibility] = [:]
        for region in check.reportedVisibility { visibility[region.rawValue] = .insufficient }
        let blind = SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.95),
            visibility: visibility,
            safety: .init(immediateConcern: false, description: nil, confidence: 0.1),
            overall: .cannotAssess,
            confidence: 0.9,
            primaryIssueKey: nil,
            observedEvidence: [])

        let model = SkillPhotoCheckModel(
            skill: SkillCatalog.skill("knife.grip")!,
            check: check,
            assess: { _ in blind })
        model.add(Data([0x01]))
        model.add(Data([0x02]))
        await model.send()

        XCTAssertEqual(model.verdictHeadline, "I cannot see enough to say")
        XCTAssertFalse(model.verdictDetail.isEmpty, "it must say what to do about it")
    }

    /// A network failure is ours. Telling a cook we could not see their photos
    /// blames them for a timeout.
    @MainActor
    func testATransportFailureIsNotReportedAsABadPhotograph() async {
        struct Boom: Error {}
        let model = SkillPhotoCheckModel(
            skill: SkillCatalog.skill("knife.grip")!,
            check: .chefKnifeGrip,
            assess: { _ in throw Boom() })
        model.add(Data([0x01]))
        model.add(Data([0x02]))
        await model.send()

        guard case .failed(let message) = model.phase else {
            return XCTFail("expected a failure phase")
        }
        XCTAssertFalse(message.lowercased().contains("cannot see"))
    }

    @MainActor
    func testRetryingThrowsTheOldPhotosAway() async {
        let model = SkillPhotoCheckModel(
            skill: SkillCatalog.skill("knife.grip")!,
            check: .chefKnifeGrip,
            assess: { _ in self.assessment(overall: .needsAdjustment, issue: "handleGrip") })
        model.add(Data([0x01]))
        model.add(Data([0x02]))
        await model.send()

        model.reset()
        XCTAssertTrue(model.photos.isEmpty, "a retry must not be judged on mixed evidence")
        XCTAssertEqual(model.phase, .collecting)
    }

    /// The history has to say which kind of evidence it was. Two deliberate
    /// photographs and a handful of frames off a moving head are not the same
    /// claim, and flattening them overstates one of them.
    func testAnAttemptRemembersHowItWasJudged() {
        let photographed = SkillAttempt(
            skillID: "knife.grip", checkID: "knife.grip.pinch",
            outcome: .passed, note: "ok", source: .showing)
        XCTAssertEqual(photographed.source, .showing)

        let watched = SkillAttempt(
            skillID: "knife.grip", checkID: "knife.grip.pinch",
            outcome: .passed, note: "ok")
        XCTAssertEqual(watched.source, .watching, "the default matches every row written so far")
    }

    // MARK: - Seeing it again without leaving

    /// The tool only exists for skills that actually have a clip. A tool she is
    /// given is a tool she will eventually call, and calling this one on a skill
    /// with no video would have her promise something that does not exist.
    func testSheIsOnlyOfferedTheVideoToolWhenThereIsAVideo() {
        let withVideo = SkillCatalog.skill("knife.grip")!
        XCTAssertNotNil(withVideo.animationAsset)
        XCTAssertTrue(
            SkillCoachPrompt.tools(for: withVideo).contains { $0.name == "show_the_video" })

        let without = SkillCatalog.skill("knife.claw")!
        XCTAssertNil(without.animationAsset)
        XCTAssertFalse(
            SkillCoachPrompt.tools(for: without).contains { $0.name == "show_the_video" })
    }

    /// Same rule for the words: no clip, no mention of one.
    func testThePromptOnlyTalksAboutTheVideoWhenThereIsOne() {
        let withVideo = SkillCoachPrompt.instructions(
            skill: SkillCatalog.skill("knife.grip")!,
            check: .chefKnifeGrip,
            seesContinuously: true)
        XCTAssertTrue(withVideo.contains("show_the_video"))
        XCTAssertTrue(
            withVideo.contains("OFFER it once"),
            "she may offer it after a correction, and only once")

        let without = SkillCoachPrompt.instructions(
            skill: SkillCatalog.skill("knife.claw")!,
            check: .knifeClawGrip,
            seesContinuously: true)
        XCTAssertFalse(without.contains("show_the_video"))
        XCTAssertFalse(without.contains("ten second clip"))
    }

    /// The three tools that were always there are still there.
    func testTheOriginalToolsSurviveTheSkillDependentList() {
        let names = Set(SkillCoachPrompt.tools(for: SkillCatalog.skill("knife.claw")!).map(\.name))
        XCTAssertEqual(names, ["check_the_hold", "focus_on", "finish_lesson"])
    }
}
