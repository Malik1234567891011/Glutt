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

    func testExtractsVideoIdFromWatchURL() {
        XCTAssertEqual(YouTubeEmbed.videoId(from: "https://www.youtube.com/watch?v=abc123"), "abc123")
        XCTAssertEqual(YouTubeEmbed.videoId(from: "https://youtu.be/xyz789"), "xyz789")
        XCTAssertNil(YouTubeEmbed.videoId(from: "https://example.com/foo"))
    }
}
