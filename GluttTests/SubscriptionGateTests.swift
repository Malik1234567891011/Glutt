import XCTest
@testable import Glutt

/// The hard-paywall decision table. Glutt is unusable without a live
/// subscription, so `access` must **fail closed**: only a genuine entitlement
/// (or an Xcode-scheme dev bypass) unlocks. The only non-locked, non-unlocked
/// state is unresolved entitlement during the brief cold-launch window — and
/// even that falls to `.locked` once the resolve times out.
final class SubscriptionGateTests: XCTestCase {

    func testActiveEntitlementUnlocks() {
        XCTAssertEqual(
            SubscriptionGate.access(isActive: true, isUnknown: false, timedOut: false, bypass: false),
            .unlocked
        )
    }

    func testInactiveLocks() {
        XCTAssertEqual(
            SubscriptionGate.access(isActive: false, isUnknown: false, timedOut: false, bypass: false),
            .locked
        )
    }

    func testUnknownShowsSplashBeforeTimeout() {
        XCTAssertEqual(
            SubscriptionGate.access(isActive: false, isUnknown: true, timedOut: false, bypass: false),
            .resolving
        )
    }

    func testUnknownFailsClosedAfterTimeout() {
        XCTAssertEqual(
            SubscriptionGate.access(isActive: false, isUnknown: true, timedOut: true, bypass: false),
            .locked
        )
    }

    func testBypassUnlocksWhenInactive() {
        XCTAssertEqual(
            SubscriptionGate.access(isActive: false, isUnknown: false, timedOut: false, bypass: true),
            .unlocked
        )
    }

    func testBypassUnlocksWhileUnknown() {
        // A dev bypass never strands the user on the resolving splash.
        XCTAssertEqual(
            SubscriptionGate.access(isActive: false, isUnknown: true, timedOut: false, bypass: true),
            .unlocked
        )
    }
}
