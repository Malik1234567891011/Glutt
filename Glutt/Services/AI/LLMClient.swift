import Foundation

/// The cloud brain. Every AI feature in Glutt works without it —
/// heuristics first, LLM as an upgrade when configured.
/// Production path: backend proxy only (no direct provider keys in app).
///
/// A value type with an injectable `transport` so the request assembly and
/// every action's prompt-building are testable without a live network — the
/// same seam `DiscoverService` / `PlatesService` / `PollyTokenService` use.
/// The static surface (`isConfigured`, `LLMError`) stays for UI gates; the
/// call path (`chat` / `chatJSON`) lives on the injectable instance.
struct LLMClient {

    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    enum Keys {
        static let model = "glutt.llm.model"
    }

    // MARK: - Static config surface (UI feature gates read these)

    static var model: String {
        get { UserDefaults.standard.string(forKey: Keys.model) ?? "gpt-4o" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.model) }
    }

    static var proxyBaseURL: String {
        Secrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var proxyClientKey: String {
        Secrets.aiProxyClientKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether this build ships a proxy. UI features gate their visibility on
    /// this; actions gate on the per-instance `isConfigured` below.
    static var isConfigured: Bool {
        !proxyBaseURL.isEmpty
    }

    enum LLMError: LocalizedError {
        case notConfigured
        case timeout
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "AI cloud service is not configured for this build."
            case .timeout: "The AI took too long to respond."
            case .badResponse(let detail): "The AI response couldn't be read: \(detail)"
            }
        }
    }

    // MARK: - Injectable instance (the call path)

    /// The network hop. Injected in tests; defaults to the shared session.
    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var baseURL: String = LLMClient.proxyBaseURL
    var clientKey: String = LLMClient.proxyClientKey

    /// Per-instance configured check. A test client with a non-empty `baseURL`
    /// is "configured" even when the build's `Secrets` are not — so gated
    /// actions run their prompt-building under test.
    var isConfigured: Bool { !baseURL.isEmpty }

    /// The production client, reading the build's proxy settings.
    static let live = LLMClient()

    /// Single-turn chat completion. Keep prompts structured; parse strictly.
    /// Pass `imageData` (JPEG, pre-downscaled via `ImagePrep`) for vision calls.
    func chat(
        system: String,
        user: String,
        imageData: Data? = nil,
        temperature: Double = 0.4,
        jsonMode: Bool = false,
        timeout: TimeInterval = 30
    ) async throws -> String {
        guard isConfigured else { throw LLMError.notConfigured }
        let urlString = "\(baseURL)/chat/completions"
        guard let url = URL(string: urlString) else {
            throw LLMError.badResponse("Bad AI endpoint URL")
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        }

        let userContent: Any
        if let imageData {
            userContent = [
                ["type": "text", "text": user],
                ["type": "image_url", "image_url": [
                    "url": "data:image/jpeg;base64,\(imageData.base64EncodedString())",
                ]],
            ]
        } else {
            userContent = user
        }

        var body: [String: Any] = [
            "model": Self.model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await transport(request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw LLMError.timeout
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.badResponse("HTTP error: \(body.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw LLMError.badResponse("Unexpected response shape")
        }
        return content
    }

    /// JSON-mode chat decoded into a Decodable. The strictest, safest way
    /// to consume LLM output — anything malformed throws and callers fall
    /// back to heuristics.
    func chatJSON<T: Decodable>(
        _ type: T.Type,
        system: String,
        user: String,
        imageData: Data? = nil,
        temperature: Double = 0.2,
        timeout: TimeInterval = 30
    ) async throws -> T {
        let raw = try await chat(
            system: system,
            user: user,
            imageData: imageData,
            temperature: temperature,
            jsonMode: true,
            timeout: timeout
        )
        // Some providers wrap JSON in markdown fences despite json mode.
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.badResponse("Not UTF-8")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
