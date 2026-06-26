import XCTest
@testable import Glutt

final class PlatesStreakTests: XCTestCase {
    private func store() -> UserDefaults {
        let d = UserDefaults(suiteName: "plates.streak.test")!
        d.removePersistentDomain(forName: "plates.streak.test")
        return d
    }
    private func day(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.date(from: s)!
    }

    func testFirstOpenStartsAtOne() {
        XCTAssertEqual(PlatesStreak.recordOpen(today: day("2026-06-26"), store: store()), 1)
    }

    func testConsecutiveDaysIncrement() {
        let s = store()
        _ = PlatesStreak.recordOpen(today: day("2026-06-26"), store: s)
        XCTAssertEqual(PlatesStreak.recordOpen(today: day("2026-06-27"), store: s), 2)
    }

    func testSameDayIsIdempotent() {
        let s = store()
        _ = PlatesStreak.recordOpen(today: day("2026-06-26"), store: s)
        XCTAssertEqual(PlatesStreak.recordOpen(today: day("2026-06-26"), store: s), 1)
    }

    func testGapResetsToOne() {
        let s = store()
        _ = PlatesStreak.recordOpen(today: day("2026-06-26"), store: s)
        XCTAssertEqual(PlatesStreak.recordOpen(today: day("2026-06-29"), store: s), 1)
    }
}
