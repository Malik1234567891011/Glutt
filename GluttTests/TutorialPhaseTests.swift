import XCTest
@testable import Glutt

final class TutorialPhaseTests: XCTestCase {

    func testPhaseOrder() {
        XCTAssertEqual(TutorialPhase.allCases,
                       [.intro, .showPost, .coachTapShare, .shareSheet, .importing, .success, .cta])
    }

    func testNextAdvancesUntilTerminal() {
        XCTAssertEqual(TutorialPhase.intro.next, .showPost)
        XCTAssertEqual(TutorialPhase.success.next, .cta)
        XCTAssertNil(TutorialPhase.cta.next)
    }

    func testOnlyCtaIsTerminal() {
        for phase in TutorialPhase.allCases where phase != .cta {
            XCTAssertFalse(phase.isTerminal, "\(phase) should not be terminal")
        }
        XCTAssertTrue(TutorialPhase.cta.isTerminal)
    }
}
