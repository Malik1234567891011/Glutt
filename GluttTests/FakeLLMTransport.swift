import Foundation
@testable import Glutt

/// Captures the request an `LLMClient` action builds and returns a canned
/// reply, so a prompt assertion is a one-liner:
///
///     let fake = FakeLLMTransport(replyJSON: adjustmentJSON)
///     _ = try await RecipeAdjuster.adjust(..., client: fake.client())
///     XCTAssertTrue(fake.user.contains("peanuts"))
///     XCTAssertTrue(fake.system.contains("Return JSON"))
///
/// Decodes the OpenAI chat body once. `user` flattens the vision
/// `[text, image_url]` content shape down to its text and sets `hasImage`.
final class FakeLLMTransport {
    /// The system prompt from the last captured request.
    private(set) var system = ""
    /// The user prompt text from the last captured request (image parts dropped).
    private(set) var user = ""
    /// Whether the last request attached an `image_url` part.
    private(set) var hasImage = false
    /// Whether the request asked for `response_format: json_object`.
    private(set) var jsonMode = false
    /// The `temperature` field of the last request, if present.
    private(set) var temperature: Double?
    /// How many requests this fake has seen.
    private(set) var callCount = 0
    /// The raw last request, for header/URL assertions.
    private(set) var lastRequest: URLRequest?

    /// The assistant message content the fake proxy returns.
    var reply: Data
    /// HTTP status to return (default 200). Set to a non-2xx to exercise errors.
    var status = 200

    init(reply: Data = Data("{}".utf8)) {
        self.reply = reply
    }

    convenience init(replyJSON: String) {
        self.init(reply: Data(replyJSON.utf8))
    }

    /// The transport closure to hand to `LLMClient(transport:)`. Wraps `reply`
    /// in the `choices[0].message.content` envelope `LLMClient` expects.
    var transport: LLMClient.Transport {
        { request in
            self.capture(request)
            let content = String(data: self.reply, encoding: .utf8) ?? ""
            let envelope: [String: Any] = ["choices": [["message": ["content": content]]]]
            let data = try JSONSerialization.data(withJSONObject: envelope)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: self.status, httpVersion: nil, headerFields: nil
            )!
            return (data, response)
        }
    }

    /// A client wired to this transport, "configured" via a non-empty test
    /// `baseURL` so gated actions run their prompt-building.
    func client(baseURL: String = "https://test.local", clientKey: String = "test-key") -> LLMClient {
        LLMClient(transport: transport, baseURL: baseURL, clientKey: clientKey)
    }

    private func capture(_ request: URLRequest) {
        callCount += 1
        lastRequest = request
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return }
        temperature = json["temperature"] as? Double
        jsonMode = (json["response_format"] as? [String: Any])?["type"] as? String == "json_object"
        guard let messages = json["messages"] as? [[String: Any]] else { return }
        system = messages.first { $0["role"] as? String == "system" }?["content"] as? String ?? ""
        guard let userContent = messages.first(where: { $0["role"] as? String == "user" })?["content"]
        else { return }
        switch userContent {
        case let text as String:
            user = text
        case let parts as [[String: Any]]:
            user = parts
                .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
            hasImage = parts.contains { $0["type"] as? String == "image_url" }
        default:
            break
        }
    }
}
