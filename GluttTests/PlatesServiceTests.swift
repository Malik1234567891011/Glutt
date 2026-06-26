import XCTest
@testable import Glutt

final class PlatesServiceTests: XCTestCase {
    private func ok(_ json: String, url: URL) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func testDailyBuildsRequestAndDecodes() async throws {
        var captured: URLRequest?
        let service = PlatesService(
            transport: { req in
                captured = req
                return self.ok(#"{ "deckTitle": "Today's Plate", "recipes": [], "nextPageToken": null }"#, url: req.url!)
            },
            baseURL: "https://example.test/api",
            clientKey: "secret-key"
        )
        let resp = try await service.daily()
        XCTAssertEqual(resp.deckTitle, "Today's Plate")
        let url = try XCTUnwrap(captured?.url)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://example.test/api/plates/deck"))
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "x-glutt-proxy-key"), "secret-key")
    }

    func testSearchSendsQueryAndPageToken() async throws {
        var captured: URLRequest?
        let service = PlatesService(
            transport: { req in
                captured = req
                return self.ok(#"{ "recipes": [], "nextPageToken": "12" }"#, url: req.url!)
            },
            baseURL: "https://example.test/api",
            clientKey: "k"
        )
        let resp = try await service.search(query: "tofu bowl", pageToken: "12")
        XCTAssertEqual(resp.nextPageToken, "12")
        let comps = URLComponents(url: captured!.url!, resolvingAgainstBaseURL: false)!
        XCTAssertTrue(comps.path.hasSuffix("/plates/search"))
        XCTAssertEqual(comps.queryItems?.first { $0.name == "q" }?.value, "tofu bowl")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "pageToken" }?.value, "12")
    }

    func testNon2xxThrowsBadResponse() async {
        let service = PlatesService(
            transport: { req in
                ("boom".data(using: .utf8)!, HTTPURLResponse(url: req.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!)
            },
            baseURL: "https://example.test/api",
            clientKey: "k"
        )
        do { _ = try await service.daily(); XCTFail("expected throw") }
        catch let PlatesError.badResponse(detail) { XCTAssertTrue(detail.contains("502")) }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testEmptyBaseURLThrowsNotConfigured() async {
        let service = PlatesService(transport: { _ in (Data(), URLResponse()) }, baseURL: "", clientKey: "")
        do { _ = try await service.daily(); XCTFail("expected throw") }
        catch PlatesError.notConfigured {} catch { XCTFail("wrong error: \(error)") }
    }
}
