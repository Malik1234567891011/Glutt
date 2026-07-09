import XCTest
@testable import Glutt

@MainActor
final class PollyRouterTests: XCTestCase {

    func testDiscoverTabExistsThirdWithLabel() {
        XCTAssertEqual(AppTab.allCases.count, 6)
        XCTAssertEqual(AppTab.allCases[2], .discover)
        XCTAssertEqual(AppTab.discover.label, "Discover")
        XCTAssertEqual(
            AppTab.allCases.map(\.id),
            ["today", "recipes", "discover", "plan", "kitchen", "progress"]
        )
    }

    func testDiscoverDeepLinkSelectsTab() {
        let router = Router()
        router.handle(url: URL(string: "glutt://discover")!)
        XCTAssertEqual(router.selectedTab, .discover)
    }

    /// The legacy `glutt://polly` link still resolves — Polly now launches from
    /// a recipe, so its old deep link lands on the recipe list rather than 404ing.
    func testLegacyPollyDeepLinkFallsBackToRecipes() {
        let router = Router()
        router.handle(url: URL(string: "glutt://polly")!)
        XCTAssertEqual(router.selectedTab, .recipes)
    }

    /// Covers the `-tab discover` launch-argument hook: `Router.init()` resolves
    /// the argument through `AppTab(rawValue:)`, so a clean round-trip is the
    /// contract that hook relies on.
    func testDiscoverRawValueRoundTrips() {
        XCTAssertEqual(AppTab(rawValue: "discover"), .discover)
        XCTAssertEqual(AppTab.discover.rawValue, "discover")
    }
}
