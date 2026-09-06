import XCTest
@testable import Glutt

final class OnboardingFlowModelTests: XCTestCase {
    func testAdvanceBackAndClamping() {
        let m = OnboardingFlowModel()
        XCTAssertEqual(m.screen, 0)
        m.back()
        XCTAssertEqual(m.screen, 0, "clamped at 0")
        m.advance()
        XCTAssertEqual(m.screen, 1)
        m.go(99); m.advance()
        XCTAssertEqual(m.screen, OnboardingFlowModel.tutorialScreen, "clamped at the tutorial")
    }

    func testChromeVisibilityMatchesDesign() {
        let m = OnboardingFlowModel()
        // 8 is Skills, added once it became a pillar of the product; 9 is the
        // notifications ask, which moved down to make room for it.
        let expected: Set<Int> = [1, 2, 3, 4, 5, 7, 8, 9]
        for s in 0...OnboardingFlowModel.tutorialScreen {
            m.go(s)
            XCTAssertEqual(m.showsChrome, expected.contains(s), "screen \(s)")
        }
    }

    func testProgressIsScreenOverTheLastScreen() {
        let m = OnboardingFlowModel()
        m.go(3)
        XCTAssertEqual(m.progress, 3.0 / 10.0, accuracy: 0.0001)
        m.go(OnboardingFlowModel.tutorialScreen)
        XCTAssertEqual(m.progress, 1.0, accuracy: 0.0001, "the bar fills exactly at the end")
    }

    // The separate OS-permission page was folded into the soft-ask, so the
    // notifications screen proceeds straight to the tutorial.
    func testNotificationsProceedToTutorial() {
        let m = OnboardingFlowModel()
        m.go(9)
        m.skipToTutorial()
        XCTAssertEqual(m.screen, OnboardingFlowModel.tutorialScreen)
    }

    /// The saving lesson stays last on purpose: whatever onboarding ends on is
    /// what somebody still has in their head when it closes.
    func testTheImportTutorialIsTheLastScreen() {
        let m = OnboardingFlowModel()
        m.go(OnboardingFlowModel.tutorialScreen)
        m.advance()
        XCTAssertEqual(m.screen, OnboardingFlowModel.tutorialScreen)
        XCTAssertFalse(m.showsChrome, "the tutorial owns its own chrome")
    }

    func testTutorialPhaseMachine() {
        let m = OnboardingFlowModel()
        m.go(OnboardingFlowModel.tutorialScreen)
        XCTAssertEqual(m.tutPhase, 0, "entering the tutorial screen resets phase")
        XCTAssertFalse(m.tutorialTap()) // 0→1
        XCTAssertFalse(m.tutorialTap()) // 1→2
        XCTAssertTrue(m.tutorialTap(), "reaching phase 3 starts the import timer") // 2→3
        XCTAssertFalse(m.tutorialTap(), "taps ignored during import")
        XCTAssertEqual(m.tutPhase, 3)
        m.completeImport()
        XCTAssertEqual(m.tutPhase, 4)
        m.completeImport()
        XCTAssertEqual(m.tutPhase, 4, "idempotent")
    }
}
