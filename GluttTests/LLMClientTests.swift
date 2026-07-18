import XCTest
@testable import Glutt

/// The transport seam made `LLMClient`'s own request assembly, response
/// parsing, and error mapping testable without a live network.
final class LLMClientTests: XCTestCase {

    private struct Probe: Decodable { let ok: Bool }

    /// A transport that returns `content` inside the chat-completions envelope
    /// `LLMClient` expects, capturing the request it was handed.
    private func envelope(_ content: String, status: Int = 200,
                          capture: ((URLRequest) -> Void)? = nil) -> LLMClient.Transport {
        { request in
            capture?(request)
            let json: [String: Any] = ["choices": [["message": ["content": content]]]]
            let data = try JSONSerialization.data(withJSONObject: json)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    func testChatJSONBuildsProxyRequest() async throws {
        var captured: URLRequest?
        let client = LLMClient(
            transport: envelope(#"{"ok": true}"#, capture: { captured = $0 }),
            baseURL: "https://proxy.test/v1",
            clientKey: "secret"
        )

        let probe = try await client.chatJSON(Probe.self, system: "SYS", user: "USR")
        XCTAssertTrue(probe.ok)

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://proxy.test/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-glutt-proxy-key"), "secret")

        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
        XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
        let messages = body["messages"] as! [[String: Any]]
        XCTAssertEqual(messages[0]["content"] as? String, "SYS")
        XCTAssertEqual(messages[1]["content"] as? String, "USR")
    }

    func testVisionCallAttachesImageContent() async throws {
        var captured: URLRequest?
        let client = LLMClient(
            transport: envelope(#"{"ok": true}"#, capture: { captured = $0 }),
            baseURL: "https://proxy.test", clientKey: ""
        )

        _ = try await client.chatJSON(Probe.self, system: "S", user: "look",
                                      imageData: Data([0xFF, 0xD8, 0xFF]))

        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(captured?.httpBody)) as! [String: Any]
        let messages = body["messages"] as! [[String: Any]]
        let parts = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, "look")
        let imageURL = (parts.last?["image_url"] as? [String: Any])?["url"] as? String
        XCTAssertEqual(imageURL?.hasPrefix("data:image/jpeg;base64,"), true)
        // No x-glutt-proxy-key header when clientKey is empty.
        XCTAssertNil(captured?.value(forHTTPHeaderField: "x-glutt-proxy-key"))
    }

    func testChatJSONStripsMarkdownFences() async throws {
        let client = LLMClient(
            transport: envelope("```json\n{\"ok\": true}\n```"),
            baseURL: "https://proxy.test", clientKey: ""
        )
        let probe = try await client.chatJSON(Probe.self, system: "s", user: "u")
        XCTAssertTrue(probe.ok)
    }

    func testTimeoutMapsToLLMError() async {
        let client = LLMClient(
            transport: { _ in throw URLError(.timedOut) },
            baseURL: "https://proxy.test", clientKey: ""
        )
        do {
            _ = try await client.chatJSON(Probe.self, system: "s", user: "u")
            XCTFail("expected throw")
        } catch LLMClient.LLMError.timeout {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testNon2xxThrowsBadResponse() async {
        let client = LLMClient(
            transport: envelope("nope", status: 503),
            baseURL: "https://proxy.test", clientKey: ""
        )
        do {
            _ = try await client.chatJSON(Probe.self, system: "s", user: "u")
            XCTFail("expected throw")
        } catch LLMClient.LLMError.badResponse {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testEmptyBaseURLThrowsNotConfigured() async {
        let client = LLMClient(transport: { _ in (Data(), URLResponse()) }, baseURL: "", clientKey: "")
        XCTAssertFalse(client.isConfigured)
        do {
            _ = try await client.chatJSON(Probe.self, system: "s", user: "u")
            XCTFail("expected throw")
        } catch LLMClient.LLMError.notConfigured {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
