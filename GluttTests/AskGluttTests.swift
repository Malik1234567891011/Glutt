import XCTest
@testable import Glutt

final class AskGluttTests: XCTestCase {

    func testReorderPutsPicksFirstThenRemainderInOriginalOrder() {
        let items = ["a", "b", "c", "d"]
        let picks = [
            AskGlutt.Pick(index: 2, reason: "r2", badge: "B2"),
            AskGlutt.Pick(index: 0, reason: "r0", badge: nil),
        ]
        let out = AskGlutt.reorder(items, picks: picks)
        XCTAssertEqual(out.map(\.item), ["c", "a", "b", "d"])
        XCTAssertEqual(out[0].reason, "r2")
        XCTAssertEqual(out[0].badge, "B2")
        XCTAssertEqual(out[1].reason, "r0")
        XCTAssertNil(out[1].badge)
        XCTAssertNil(out[2].reason)   // "b" was not picked
        XCTAssertNil(out[3].reason)   // "d" was not picked
    }

    func testReorderSkipsOutOfRangeAndDuplicatePicks() {
        let items = ["a", "b"]
        let picks = [
            AskGlutt.Pick(index: 5, reason: "x", badge: nil),   // out of range
            AskGlutt.Pick(index: 1, reason: "r1", badge: nil),
            AskGlutt.Pick(index: 1, reason: "dup", badge: nil), // duplicate
        ]
        let out = AskGlutt.reorder(items, picks: picks)
        XCTAssertEqual(out.map(\.item), ["b", "a"])
        XCTAssertEqual(out[0].reason, "r1")
    }

    func testReorderWithNoPicksKeepsOriginalOrderAndNoAnnotations() {
        let out = AskGlutt.reorder(["a", "b", "c"], picks: [])
        XCTAssertEqual(out.map(\.item), ["a", "b", "c"])
        XCTAssertTrue(out.allSatisfy { $0.reason == nil && $0.badge == nil })
    }
}
