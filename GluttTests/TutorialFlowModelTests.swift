import XCTest
@testable import Glutt

final class TutorialFlowModelTests: XCTestCase {

    func testStartsAtFirstWalkthroughStep() {
        let m = TutorialFlowModel()
        XCTAssertEqual(m.phase, .walkthrough(0))
        XCTAssertEqual(m.currentStep?.id, 0)
        XCTAssertEqual(m.steps.count, 3)
    }

    func testTapHotspotAdvancesThroughEveryPhase() {
        let m = TutorialFlowModel()
        m.tapHotspot(); XCTAssertEqual(m.phase, .walkthrough(1))
        m.tapHotspot(); XCTAssertEqual(m.phase, .walkthrough(2))
        m.tapHotspot(); XCTAssertEqual(m.phase, .importing)   // last step -> importing
        m.tapHotspot(); XCTAssertEqual(m.phase, .success)
        m.tapHotspot(); XCTAssertEqual(m.phase, .cta)
        m.tapHotspot(); XCTAssertEqual(m.phase, .cta)         // cta is terminal
    }

    func testTapMissNudgesWithoutAdvancing() {
        let m = TutorialFlowModel()
        XCTAssertEqual(m.nudgeToken, 0)
        m.tapMiss()
        XCTAssertEqual(m.phase, .walkthrough(0))
        XCTAssertEqual(m.nudgeToken, 1)
        m.tapMiss()
        XCTAssertEqual(m.nudgeToken, 2)
    }

    func testCurrentStepIsNilOncePastWalkthrough() {
        let m = TutorialFlowModel()
        m.tapHotspot(); m.tapHotspot(); m.tapHotspot() // into importing
        XCTAssertNil(m.currentStep)
    }

    func testHeadlineTracksPhase() {
        let m = TutorialFlowModel()
        XCTAssertEqual(m.headline, "Found a recipe you love?")
        m.tapHotspot()
        XCTAssertEqual(m.headline, "Just tap Share → Glutt")
        m.tapHotspot(); m.tapHotspot() // importing
        XCTAssertEqual(m.headline, "Pulling out the recipe…")
        m.tapHotspot() // success
        XCTAssertEqual(m.headline, "That's it — it's saved. ✨")
    }
}
