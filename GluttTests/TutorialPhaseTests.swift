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

        // the chain is connected end-to-end and terminates at .cta
        var phase: TutorialPhase = .intro
        var hops = 0
        while let next = phase.next {
            phase = next
            hops += 1
            XCTAssertLessThan(hops, 10, "phase chain did not terminate")
        }
        XCTAssertEqual(phase, .cta)
    }

    func testOnlyCtaIsTerminal() {
        for phase in TutorialPhase.allCases where phase != .cta {
            XCTAssertFalse(phase.isTerminal, "\(phase) should not be terminal")
        }
        XCTAssertTrue(TutorialPhase.cta.isTerminal)
    }
}
