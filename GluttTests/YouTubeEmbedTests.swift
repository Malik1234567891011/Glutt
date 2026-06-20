import XCTest
@testable import Glutt

final class YouTubeEmbedTests: XCTestCase {
    func testPlayerURLPointsToBackendPlayerWithVideoId() {
        // The WKWebView loads this URL directly so the page has a real https
        // origin (loadHTMLString's opaque origin makes YouTube reject embeds).
        let url = YouTubeEmbed.playerURL(videoId: "abc123", baseURL: "https://example.test/api")
        XCTAssertEqual(url?.absoluteString, "https://example.test/api/discover/player?v=abc123")
    }

    func testPlayerURLIsNilWhenBaseURLEmpty() {
        XCTAssertNil(YouTubeEmbed.playerURL(videoId: "abc123", baseURL: ""))
    }

    func testExtractsVideoIdFromWatchURL() {
        XCTAssertEqual(YouTubeEmbed.videoId(from: "https://www.youtube.com/watch?v=abc123"), "abc123")
        XCTAssertEqual(YouTubeEmbed.videoId(from: "https://youtu.be/xyz789"), "xyz789")
        XCTAssertNil(YouTubeEmbed.videoId(from: "https://example.com/foo"))
    }
}
