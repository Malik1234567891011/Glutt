import XCTest
@testable import Glutt

final class YouTubeEmbedTests: XCTestCase {
    func testHTMLEmbedsVideoIdWithInlineMutedAutoplay() {
        let html = YouTubeEmbed.html(videoId: "abc123")
        XCTAssertTrue(html.contains("abc123"))
        XCTAssertTrue(html.contains("playsinline=1"))
        XCTAssertTrue(html.contains("autoplay=1"))
        XCTAssertTrue(html.contains("mute=1"))
        XCTAssertTrue(html.contains("youtube.com/embed/abc123"))
    }
}
