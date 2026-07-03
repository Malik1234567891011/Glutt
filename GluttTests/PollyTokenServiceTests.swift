import XCTest
@testable import Glutt

final class PollyTokenServiceTests: XCTestCase {
    private func ok(_ json: String, url: URL) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    private let tokenJSON = #"{"value":"ek_abc","expiresAt":1751500000,"model":"gpt-realtime-2","voice":"marin"}"#

    func testMintBuildsRequestAndDecodes() async throws {
        var captured: URLRequest?
        let service = PollyTokenService(
            transport: { req in
                captured = req
                return self.ok(self.tokenJSON, url: req.url!)
            },
            baseURL: "https://example.test/api",
            clientKey: "secret-key"
        )
        let token = try await service.mint()
        XCTAssertEqual(
            token,
            PollySessionToken(value: "ek_abc", expiresAt: 1_751_500_000, model: "gpt-realtime-2", voice: "marin")
        )
        let request = try XCTUnwrap(captured)
        XCTAssertTrue(try XCTUnwrap(request.url).absoluteString.hasSuffix("/polly/session"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-glutt-proxy-key"), "secret-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8), "{}")
    }

    func testNon2xxThrowsBadResponse() async {
        let service = PollyTokenService(
            transport: { req in
                (Data("boom".utf8), HTTPURLResponse(url: req.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!)
            },
            baseURL: "https://example.test/api",
            clientKey: "k"
        )
        do { _ = try await service.mint(); XCTFail("expected throw") }
        catch let PollyTokenError.badResponse(detail) { XCTAssertTrue(detail.contains("502")) }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testMissingValueKeyThrowsBadResponse() async {
        let service = PollyTokenService(
            transport: { req in
                self.ok(#"{"expiresAt":1751500000,"model":"gpt-realtime-2","voice":"marin"}"#, url: req.url!)
            },
            baseURL: "https://example.test/api",
            clientKey: "k"
        )
        do { _ = try await service.mint(); XCTFail("expected throw") }
        catch let PollyTokenError.badResponse(detail) { XCTAssertEqual(detail, "Unexpected response shape") }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testEmptyBaseURLThrowsNotConfigured() async {
        let service = PollyTokenService(transport: { _ in (Data(), URLResponse()) }, baseURL: "", clientKey: "")
        do { _ = try await service.mint(); XCTFail("expected throw") }
        catch PollyTokenError.notConfigured {} catch { XCTFail("wrong error: \(error)") }
    }
}
