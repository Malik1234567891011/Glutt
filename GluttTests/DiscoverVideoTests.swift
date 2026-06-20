import XCTest
@testable import Glutt

final class DiscoverVideoTests: XCTestCase {
    func testDecodesResponseAndBuildsWatchURL() throws {
        let json = """
        {
          "videos": [
            { "videoId": "abc123", "title": "Crispy Tofu", "creator": "Wok Wed",
              "thumbnailURL": "https://i.ytimg.com/vi/abc123/hqdefault.jpg", "durationSeconds": 187 }
          ],
          "nextPageToken": "CAUQAA"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DiscoverResponse.self, from: json)

        XCTAssertEqual(response.videos.count, 1)
        XCTAssertEqual(response.nextPageToken, "CAUQAA")
        let video = response.videos[0]
        XCTAssertEqual(video.videoId, "abc123")
        XCTAssertEqual(video.title, "Crispy Tofu")
        XCTAssertEqual(video.creator, "Wok Wed")
        XCTAssertEqual(video.durationSeconds, 187)
        XCTAssertEqual(video.id, "abc123")
        XCTAssertEqual(video.watchURL.absoluteString, "https://www.youtube.com/watch?v=abc123")
    }

    func testDecodesWithMissingOptionalFields() throws {
        let json = """
        { "videos": [ { "videoId": "x1", "title": "Plain" } ] }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(DiscoverResponse.self, from: json)
        XCTAssertNil(response.nextPageToken)
        XCTAssertNil(response.videos[0].creator)
        XCTAssertNil(response.videos[0].durationSeconds)
    }
}
