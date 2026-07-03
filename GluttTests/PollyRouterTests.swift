import XCTest
@testable import Glutt

@MainActor
final class PollyRouterTests: XCTestCase {

    func testPollyTabExistsThirdWithLabel() {
        XCTAssertEqual(AppTab.allCases.count, 6)
        XCTAssertEqual(AppTab.allCases[2], .polly)
        XCTAssertEqual(AppTab.polly.label, "Polly")
        XCTAssertEqual(
            AppTab.allCases.map(\.id),
            ["today", "recipes", "polly", "plan", "kitchen", "progress"]
        )
    }

    func testPollyDeepLinkSelectsTab() {
        let router = Router()
        router.handle(url: URL(string: "glutt://polly")!)
        XCTAssertEqual(router.selectedTab, .polly)
    }

    /// Covers the `-tab polly` launch-argument hook: `Router.init()` resolves
    /// the argument through `AppTab(rawValue:)`, so a clean round-trip is the
    /// contract that hook relies on.
    func testPollyRawValueRoundTrips() {
        XCTAssertEqual(AppTab(rawValue: "polly"), .polly)
        XCTAssertEqual(AppTab.polly.rawValue, "polly")
    }
}
