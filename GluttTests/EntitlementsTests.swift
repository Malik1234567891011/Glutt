import XCTest
@testable import Glutt

/// The freemium decision table. Glutt always runs; what changes with a
/// subscription is whether the Pro features are crowned. `tier` must fail
/// **closed**: anything short of a genuine entitlement (or a dev bypass) is
/// `.free`, and the only non-free, non-pro state is the brief window before
/// entitlement resolves — which itself falls to `.free` once it times out.
final class EntitlementsTests: XCTestCase {

    func testActiveEntitlementIsPro() {
        XCTAssertEqual(
            Entitlements.tier(isActive: true, isUnknown: false, timedOut: false, bypass: false),
            .pro
        )
    }

    func testInactiveIsFree() {
        XCTAssertEqual(
            Entitlements.tier(isActive: false, isUnknown: false, timedOut: false, bypass: false),
            .free
        )
    }

    func testUnknownShowsSplashBeforeTimeout() {
        XCTAssertEqual(
            Entitlements.tier(isActive: false, isUnknown: true, timedOut: false, bypass: false),
            .resolving
        )
    }

    func testUnknownFailsClosedToFreeAfterTimeout() {
        // A resolve that never lands must not strand the user on the splash,
        // and must not hand them Pro on the way out.
        XCTAssertEqual(
            Entitlements.tier(isActive: false, isUnknown: true, timedOut: true, bypass: false),
            .free
        )
    }

    func testBypassIsProWhenInactive() {
        XCTAssertEqual(
            Entitlements.tier(isActive: false, isUnknown: false, timedOut: false, bypass: true),
            .pro
        )
    }

    func testBypassIsProWhileUnknown() {
        // A dev bypass never strands the user on the resolving splash.
        XCTAssertEqual(
            Entitlements.tier(isActive: false, isUnknown: true, timedOut: false, bypass: true),
            .pro
        )
    }

    // MARK: - `-freeTier`

    /// The whole point of the flag: a Debug build unlocks everything by default,
    /// so without this the free tier is the one configuration that cannot be
    /// tested on the machine it is written on.
    func testForcedFreeBeatsTheDebugBypass() {
        XCTAssertEqual(
            Entitlements.tier(isActive: false, isUnknown: false, timedOut: false,
                              bypass: true, forcedFree: true),
            .free
        )
    }

    /// It has to beat a real subscription too, or it can only be used on a
    /// machine that has never signed into a subscribed Apple ID.
    func testForcedFreeBeatsARealEntitlement() {
        XCTAssertEqual(
            Entitlements.tier(isActive: true, isUnknown: false, timedOut: false,
                              bypass: false, forcedFree: true),
            .free
        )
    }

    /// And it resolves immediately: forcing the free tier must not park the app
    /// on the splash waiting for an entitlement whose answer is already decided.
    func testForcedFreeResolvesImmediately() {
        XCTAssertEqual(
            Entitlements.tier(isActive: false, isUnknown: true, timedOut: false,
                              bypass: false, forcedFree: true),
            .free
        )
    }
}
