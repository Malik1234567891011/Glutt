import XCTest
@testable import Glutt

final class YouTubeEmbedTests: XCTestCase {
    func testHTMLUsesIFrameAPIWithOriginInlineMutedAutoplay() {
        let html = YouTubeEmbed.html(videoId: "abc123")
        XCTAssertTrue(html.contains("abc123"))
        // Uses the IFrame Player API (not a bare iframe) so WKWebView sends a
        // valid origin and YouTube doesn't reject embeddable videos (error 150-153).
        XCTAssertTrue(html.contains("iframe_api"))
        XCTAssertTrue(html.contains("onYouTubeIframeAPIReady"))
        XCTAssertTrue(html.contains("origin: 'https://www.youtube.com'"))
        XCTAssertTrue(html.contains("playsinline: 1"))
        XCTAssertTrue(html.contains("autoplay: 1"))
        XCTAssertTrue(html.contains("mute: 1"))
    }

    func testExtractsVideoIdFromWatchURL() {
        XCTAssertEqual(YouTubeEmbed.videoId(from: "https://www.youtube.com/watch?v=abc123"), "abc123")
        XCTAssertEqual(YouTubeEmbed.videoId(from: "https://youtu.be/xyz789"), "xyz789")
        XCTAssertNil(YouTubeEmbed.videoId(from: "https://example.com/foo"))
    }
}
