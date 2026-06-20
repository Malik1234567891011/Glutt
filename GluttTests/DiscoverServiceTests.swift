import XCTest
@testable import Glutt

final class DiscoverServiceTests: XCTestCase {
    private func ok(_ json: String, url: URL) -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (json.data(using: .utf8)!, response)
    }

    func testSearchBuildsRequestAndDecodes() async throws {
        var captured: URLRequest?
        let service = DiscoverService(
            transport: { request in
                captured = request
                return self.ok(#"{ "videos": [ { "videoId": "v1", "title": "Tofu" } ], "nextPageToken": "N" }"#,
                               url: request.url!)
            },
            baseURL: "https://example.test/api",
            clientKey: "secret-key"
        )

        let result = try await service.search(query: "tofu stir fry", pageToken: "PAGE2")

        XCTAssertEqual(result.videos.first?.videoId, "v1")
        XCTAssertEqual(result.nextPageToken, "N")
        let url = try XCTUnwrap(captured?.url)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://example.test/api/discover/search"))
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(comps.queryItems?.first { $0.name == "q" }?.value, "tofu stir fry")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "pageToken" }?.value, "PAGE2")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "x-glutt-proxy-key"), "secret-key")
    }

    func testSuggestedSendsTags() async throws {
        var captured: URLRequest?
        let service = DiscoverService(
            transport: { request in
                captured = request
                return self.ok(#"{ "videos": [] }"#, url: request.url!)
            },
            baseURL: "https://example.test/api",
            clientKey: "k"
        )
        _ = try await service.suggested(tags: ["tofu", "high-protein"])
        let comps = URLComponents(url: captured!.url!, resolvingAgainstBaseURL: false)!
        XCTAssertTrue(comps.path.hasSuffix("/discover/suggested"))
        XCTAssertEqual(comps.queryItems?.first { $0.name == "tags" }?.value, "tofu,high-protein")
    }

    func testNon2xxThrowsBadResponse() async {
        let service = DiscoverService(
            transport: { request in
                let r = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return ("boom".data(using: .utf8)!, r)
            },
            baseURL: "https://example.test/api",
            clientKey: "k"
        )
        do {
            _ = try await service.search(query: "x", pageToken: nil)
            XCTFail("expected throw")
        } catch let DiscoverError.badResponse(detail) {
            XCTAssertTrue(detail.contains("500"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testEmptyBaseURLThrowsNotConfigured() async {
        let service = DiscoverService(transport: { _ in (Data(), URLResponse()) }, baseURL: "", clientKey: "")
        do {
            _ = try await service.search(query: "x", pageToken: nil)
            XCTFail("expected throw")
        } catch DiscoverError.notConfigured {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
