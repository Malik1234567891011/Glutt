import XCTest
@testable import Glutt

/// The free tier's one metered feature. The cases that matter are the ones a
/// cook would notice and resent: being charged for an undo, losing the
/// allowance early, or the week never rolling over.
final class SwipeQuotaTests: XCTestCase {

    private var store: UserDefaults!
    private var suiteName: String!
    /// Fixed so the tests never depend on which weekday they are run.
    private let calendar = Calendar(identifier: .gregorian)
    /// A Wednesday, mid-week, so both edges of the window are reachable.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "SwipeQuotaTests.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        store = nil
        super.tearDown()
    }

    private func record(_ times: Int, isPro: Bool = false, at date: Date? = nil) {
        for _ in 0 ..< times {
            SwipeQuota.record(isPro: isPro, now: date ?? now, store: store, calendar: calendar)
        }
    }

    private func remaining(at date: Date? = nil) -> Int {
        SwipeQuota.remaining(now: date ?? now, store: store, calendar: calendar)
    }

    // MARK: - The allowance

    func testFreshCookHasTheFullAllowance() {
        XCTAssertEqual(remaining(), SwipeQuota.freeWeeklyLimit)
        XCTAssertTrue(SwipeQuota.hasSwipesLeft(now: now, store: store, calendar: calendar))
    }

    func testEachSwipeSpendsOne() {
        record(3)
        XCTAssertEqual(remaining(), SwipeQuota.freeWeeklyLimit - 3)
    }

    func testTheAllowanceRunsOutExactlyAtTheLimit() {
        record(SwipeQuota.freeWeeklyLimit - 1)
        XCTAssertTrue(SwipeQuota.hasSwipesLeft(now: now, store: store, calendar: calendar),
                      "the last swipe must still be allowed")
        record(1)
        XCTAssertEqual(remaining(), 0)
        XCTAssertFalse(SwipeQuota.hasSwipesLeft(now: now, store: store, calendar: calendar))
    }

    func testRemainingNeverGoesNegative() {
        record(SwipeQuota.freeWeeklyLimit + 5)
        XCTAssertEqual(remaining(), 0)
    }

    // MARK: - Undo

    func testUndoGivesTheSwipeBack() {
        record(4)
        SwipeQuota.refund(isPro: false, now: now, store: store, calendar: calendar)
        XCTAssertEqual(remaining(), SwipeQuota.freeWeeklyLimit - 3)
    }

    func testUndoWithNothingSpentIsHarmless() {
        SwipeQuota.refund(isPro: false, now: now, store: store, calendar: calendar)
        XCTAssertEqual(remaining(), SwipeQuota.freeWeeklyLimit)
    }

    func testUndoAtTheWallReopensTheDeck() {
        record(SwipeQuota.freeWeeklyLimit)
        XCTAssertFalse(SwipeQuota.hasSwipesLeft(now: now, store: store, calendar: calendar))
        SwipeQuota.refund(isPro: false, now: now, store: store, calendar: calendar)
        XCTAssertTrue(SwipeQuota.hasSwipesLeft(now: now, store: store, calendar: calendar))
    }

    // MARK: - The week

    func testTheAllowanceComesBackNextWeek() {
        record(SwipeQuota.freeWeeklyLimit)
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now)!
        XCTAssertEqual(remaining(at: nextWeek), SwipeQuota.freeWeeklyLimit)
    }

    func testSwipesLaterTheSameWeekStillCount() {
        record(6)
        // Same calendar week, a few hours on.
        let later = now.addingTimeInterval(6 * 3600)
        XCTAssertEqual(remaining(at: later), SwipeQuota.freeWeeklyLimit - 6)
    }

    func testTheAllowanceDoesNotComeBackJustBeforeTheWeekTurns() {
        record(SwipeQuota.freeWeeklyLimit)
        let justBefore = SwipeQuota.resetDate(now: now, calendar: calendar).addingTimeInterval(-60)
        XCTAssertEqual(remaining(at: justBefore), 0,
                       "a minute before the reset is still this week")
    }

    func testTheAllowanceIsBackTheMomentTheWeekTurns() {
        record(SwipeQuota.freeWeeklyLimit)
        let atReset = SwipeQuota.resetDate(now: now, calendar: calendar)
        XCTAssertEqual(remaining(at: atReset), SwipeQuota.freeWeeklyLimit)
    }

    func testResetDateIsTheStartOfTheFollowingWeek() {
        let reset = SwipeQuota.resetDate(now: now, calendar: calendar)
        XCTAssertEqual(reset, SwipeQuota.weekStart(for: reset, calendar: calendar),
                       "the reset must land on a week boundary, not mid-week")
        XCTAssertGreaterThan(reset, now)
    }

    // MARK: - Subscribers

    func testSubscribersAreNeverCounted() {
        record(50, isPro: true)
        XCTAssertEqual(remaining(), SwipeQuota.freeWeeklyLimit)
    }

    /// Someone who subscribes mid-week, swipes, then lapses must not find their
    /// free allowance already spent by the swiping they paid for.
    func testSwipingWhileSubscribedDoesNotSpendTheFreeAllowance() {
        record(2)
        record(30, isPro: true)
        XCTAssertEqual(remaining(), SwipeQuota.freeWeeklyLimit - 2)
    }
}
