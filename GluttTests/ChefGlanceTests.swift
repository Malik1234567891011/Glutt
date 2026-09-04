import XCTest
@testable import Glutt

/// The unprompted look, which is the only turn in the whole session that starts
/// with nobody having said anything. Everything here is about when it must NOT
/// fire, because a look that lands at the wrong moment is a voice in someone's
/// ear while they are holding a hot pan.
final class ChefGlanceTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_751_400_000)

    private func conditions(
        canSee: Bool = true,
        watchfulness: ChefWatchfulness = .watchful,
        isBusy: Bool = false,
        quietFor seconds: TimeInterval = 60,
        glancesThisStep: Int = 0
    ) -> ChefGlance.Conditions {
        ChefGlance.Conditions(
            canSee: canSee,
            watchfulness: watchfulness,
            isBusy: isBusy,
            now: t0,
            quietSince: t0.addingTimeInterval(-seconds),
            glancesThisStep: glancesThisStep)
    }

    private func step(
        id: String = "s4",
        title: String = "Sear the chicken",
        visualCheck: String? = "Deep brown with black at the edges, still raw in the middle.",
        recovery: String? = "If it is sitting in its own liquid the pan is crowded."
    ) -> CookPlan.PlanStep {
        CookPlan.PlanStep(
            id: id, index: 0, title: title, instruction: "Lay them in with a gap.",
            kind: .checkpoint, visualCheck: visualCheck, recovery: recovery)
    }

    // MARK: When it fires

    func testAQuietStepWithGlassesOnIsDue() {
        XCTAssertTrue(ChefGlance.isDue(conditions()))
    }

    func testTheIntervalIsTheOneTheLevelPromises() {
        for level in [ChefWatchfulness.perfectionist, .watchful] {
            let interval = level.glanceInterval!
            XCTAssertFalse(
                ChefGlance.isDue(conditions(watchfulness: level, quietFor: interval - 1)),
                "\(level.rawValue) looked early")
            XCTAssertTrue(
                ChefGlance.isDue(conditions(watchfulness: level, quietFor: interval)),
                "\(level.rawValue) never looked")
        }
    }

    // MARK: When it must not

    /// The whole feature is glasses only. A phone face down on the counter
    /// cannot support a look nobody asked for, and firing one would burn a turn
    /// describing the ceiling.
    func testItNeverFiresWithoutGlasses() {
        XCTAssertFalse(ChefGlance.isDue(conditions(canSee: false)))
    }

    func testHandsOffNeverLooks() {
        XCTAssertFalse(ChefGlance.isDue(conditions(watchfulness: .handsOff, quietFor: 3600)))
    }

    /// Speaking, thinking, listening, hard muted, or a clip playing. Each one
    /// means the cook's attention is already taken.
    func testItNeverFiresWhileSomethingElseIsHappening() {
        XCTAssertFalse(ChefGlance.isDue(conditions(isBusy: true, quietFor: 3600)))
    }

    /// The clock counts quiet, not wall time. She answered a question eight
    /// seconds ago, so a look now would read as her carrying on talking to
    /// herself.
    func testTalkingResetsTheClock() {
        XCTAssertFalse(ChefGlance.isDue(conditions(quietFor: 8)))
    }

    /// A step that has not opened yet has no clock to be late against. Starting
    /// one at distantPast would fire a look the instant the glasses connected.
    func testNoQuietStretchYetMeansNoLook() {
        var c = conditions()
        c.quietSince = nil
        XCTAssertFalse(ChefGlance.isDue(c))
    }

    /// The interval alone is not a limit: six minutes of reducing at twelve
    /// second intervals is thirty looks at a pan doing one thing.
    func testTheBudgetStopsALongStepSpendingEveryLook() {
        for level in [ChefWatchfulness.perfectionist, .watchful] {
            let budget = level.glanceBudgetPerStep
            XCTAssertTrue(
                ChefGlance.isDue(conditions(
                    watchfulness: level, quietFor: 3600, glancesThisStep: budget - 1)),
                "\(level.rawValue) stopped one look early")
            XCTAssertFalse(
                ChefGlance.isDue(conditions(
                    watchfulness: level, quietFor: 3600, glancesThisStep: budget)),
                "\(level.rawValue) went over budget")
        }
    }

    // MARK: What she is allowed to look at

    /// Same rule the tool layer uses to refuse an unseen `mark_step_done`: a
    /// step with a visualCheck is a step where something can go wrong on camera.
    /// It keeps her off Tools, Prep, and "put the rice on", where a look has
    /// nothing to be right or wrong about.
    func testOnlyStepsWithSomethingToJudgeAreLookedAt() {
        XCTAssertTrue(ChefGlance.canJudge(step()))
        XCTAssertFalse(ChefGlance.canJudge(step(visualCheck: nil)))
        XCTAssertFalse(ChefGlance.canJudge(step(visualCheck: "   ")))
    }

    // MARK: The brief

    func testTheBriefCarriesBothTheTargetAndTheFailure() throws {
        let brief = try XCTUnwrap(ChefGlance.brief(for: step(), number: 1))
        XCTAssertTrue(brief.contains("Sear the chicken"))
        XCTAssertTrue(brief.contains("Deep brown"), "what right looks like")
        XCTAssertTrue(brief.contains("crowded"), "and what wrong looks like")
        XCTAssertTrue(brief.contains("UNPROMPTED LOOK"),
                      "the durable rules live in the prompt, so the note has to point at them")
        XCTAssertTrue(brief.contains("did not ask"),
                      "she must know the cook is not waiting on an answer")
    }

    /// "Do not say the same thing twice" is impossible to obey without knowing
    /// you have already been here.
    func testALaterLookIsToldItIsALaterLook() throws {
        let first = try XCTUnwrap(ChefGlance.brief(for: step(), number: 1))
        XCTAssertFalse(first.localizedCaseInsensitiveContains("already looked"))
        let second = try XCTUnwrap(ChefGlance.brief(for: step(), number: 2))
        XCTAssertTrue(second.localizedCaseInsensitiveContains("already looked"))
        XCTAssertTrue(second.contains("1 time"))
        let third = try XCTUnwrap(ChefGlance.brief(for: step(), number: 3))
        XCTAssertTrue(third.contains("2 times"))
    }

    func testAStepWithNothingToJudgeHasNoBrief() {
        XCTAssertNil(ChefGlance.brief(for: step(visualCheck: nil), number: 1))
    }

    /// A step can name its target without naming a failure, and the note should
    /// simply not claim one.
    func testARecoveryFreeStepStillGetsABrief() throws {
        let brief = try XCTUnwrap(ChefGlance.brief(for: step(recovery: nil), number: 1))
        XCTAssertTrue(brief.contains("Right looks like"))
        XCTAssertFalse(brief.contains("Going wrong looks like"))
    }
}
