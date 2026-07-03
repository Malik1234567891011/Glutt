import XCTest
@testable import Glutt

final class WatchModeSchedulerTests: XCTestCase {
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    func testDisabledNeverSends() {
        var scheduler = WatchModeScheduler(isEnabled: false, interval: 10)
        XCTAssertFalse(scheduler.shouldSendFrame(now: date(0)))
        XCTAssertFalse(scheduler.shouldSendFrame(now: date(100)))
        XCTAssertNil(scheduler.lastSent, "disabled calls must not record a send")
    }

    func testFirstCallWhenEnabledSends() {
        var scheduler = WatchModeScheduler(isEnabled: true, interval: 10)
        XCTAssertTrue(scheduler.shouldSendFrame(now: date(0)))
        XCTAssertEqual(scheduler.lastSent, date(0))
    }

    func testSecondCallInsideIntervalIsSuppressed() {
        var scheduler = WatchModeScheduler(isEnabled: true, interval: 10)
        XCTAssertTrue(scheduler.shouldSendFrame(now: date(0)))
        XCTAssertFalse(scheduler.shouldSendFrame(now: date(9.9)))
        XCTAssertEqual(scheduler.lastSent, date(0), "a suppressed call must not move lastSent")
    }

    func testCallAfterIntervalSendsAgain() {
        var scheduler = WatchModeScheduler(isEnabled: true, interval: 10)
        XCTAssertTrue(scheduler.shouldSendFrame(now: date(0)))
        XCTAssertTrue(scheduler.shouldSendFrame(now: date(10)), "exactly `interval` later is due (>=)")
        XCTAssertEqual(scheduler.lastSent, date(10))
    }

    func testReEnableKeepsLastSentGate() {
        var scheduler = WatchModeScheduler(isEnabled: true, interval: 10)
        XCTAssertTrue(scheduler.shouldSendFrame(now: date(0)))
        scheduler.isEnabled = false
        XCTAssertFalse(scheduler.shouldSendFrame(now: date(5)))
        scheduler.isEnabled = true
        XCTAssertFalse(scheduler.shouldSendFrame(now: date(5)), "re-enabling must not reset the gate")
        XCTAssertTrue(scheduler.shouldSendFrame(now: date(12)))
    }

    func testDefaultsMatchPollyConfig() {
        let scheduler = WatchModeScheduler()
        XCTAssertFalse(scheduler.isEnabled)
        XCTAssertEqual(scheduler.interval, PollyConfig.watchFrameInterval)
        XCTAssertNil(scheduler.lastSent)
    }
}
