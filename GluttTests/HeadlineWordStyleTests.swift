import SwiftUI
import XCTest
@testable import Glutt

final class HeadlineWordStyleTests: XCTestCase {
    func testForegroundMapping() {
        XCTAssertEqual(HeadlineWordStyle.green.foreground, Theme.Colors.accent)
        XCTAssertEqual(HeadlineWordStyle.amber.foreground, Theme.Colors.warning)
        XCTAssertEqual(HeadlineWordStyle.tomato.foreground, Theme.Colors.tomato)
        XCTAssertEqual(HeadlineWordStyle.plain.foreground, Theme.Colors.textPrimary)
    }

    func testBackgroundMapping() {
        XCTAssertEqual(HeadlineWordStyle.green.background, Theme.Colors.successTint)
        XCTAssertEqual(HeadlineWordStyle.amber.background, Theme.Colors.warningTint)
        XCTAssertEqual(HeadlineWordStyle.tomato.background, Theme.Colors.tomatoTint)
        XCTAssertNil(HeadlineWordStyle.plain.background)
    }
}
