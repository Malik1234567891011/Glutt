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
        m.go(10); m.advance()
        XCTAssertEqual(m.screen, 10, "clamped at 10")
    }

    func testChromeVisibilityMatchesDesign() {
        let m = OnboardingFlowModel()
        let expected: Set<Int> = [1, 2, 3, 4, 5, 7, 8, 9]
        for s in 0...10 {
            m.go(s)
            XCTAssertEqual(m.showsChrome, expected.contains(s), "screen \(s)")
        }
    }

    func testProgressIsScreenOverTen() {
        let m = OnboardingFlowModel()
        m.go(9)
        XCTAssertEqual(m.progress, 0.9, accuracy: 0.0001)
    }

    func testNotificationBranch() {
        let m = OnboardingFlowModel()
        m.go(8)
        m.toPermission()
        XCTAssertEqual(m.screen, 9)
        m.go(8)
        m.skipToTutorial()
        XCTAssertEqual(m.screen, 10)
    }

    func testTutorialPhaseMachine() {
        let m = OnboardingFlowModel()
        m.go(9)
        m.go(10)
        XCTAssertEqual(m.tutPhase, 0, "entering 10 resets phase")
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
