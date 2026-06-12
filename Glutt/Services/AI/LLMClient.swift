import Foundation

/// Optional cloud brain. Every AI feature in Glutt works without it —
/// heuristics first, LLM as an upgrade when a key is configured.
/// OpenAI-compatible chat API (works with OpenAI, OpenRouter, local servers).
enum LLMClient {

    enum Keys {
        static let apiKey = "glutt.llm.apiKey"
        static let model = "glutt.llm.model"
        static let baseURL = "glutt.llm.baseURL"
    }

    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: Keys.apiKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.apiKey) }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: Keys.model) ?? "gpt-4o-mini" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.model) }
    }

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: Keys.baseURL) ?? "https://api.openai.com/v1" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.baseURL) }
    }

    static var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    enum LLMError: LocalizedError {
        case notConfigured
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "No AI key configured. Add one in Settings to enable this."
            case .badResponse(let detail): "The AI response couldn't be read: \(detail)"
            }
        }
    }

    /// Single-turn chat completion. Keep prompts structured; parse strictly.
    static func chat(system: String, user: String, temperature: Double = 0.4) async throws -> String {
        guard isConfigured else { throw LLMError.notConfigured }
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.badResponse("Bad base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
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
}
