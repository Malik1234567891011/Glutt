import Foundation

/// Fetches Polly-voice audio (OpenAI gpt-4o-mini-tts, same `POLLY_VOICE` as
/// the live Realtime session) from the Vercel proxy. Used for the cook-trailer
/// briefing so the rundown sounds like Polly, not system TTS.
struct PollySpeechClient {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    enum SpeechError: LocalizedError, Equatable {
        case notConfigured
        case badURL
        case upstream(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Polly speech isn’t available in this build."
            case .badURL: "Bad Polly speech endpoint."
            case .upstream(let detail): "Couldn’t synthesize Polly speech: \(detail)"
            }
        }
    }

    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var baseURL: String = Secrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    var clientKey: String = Secrets.aiProxyClientKey.trimmingCharacters(in: .whitespacesAndNewlines)

    static let live = PollySpeechClient()

    var isConfigured: Bool { !baseURL.isEmpty }

    /// Returns MP3 bytes spoken in Polly's configured voice.
    /// `speed` > 1 makes the trailer feel snappier (proxy clamps 0.25…4).
    /// - Parameter elevenLabsVoiceID: when the picked chef has a cloned voice,
    ///   the proxy renders the briefing with it. The proxy falls back to OpenAI
    ///   TTS if ElevenLabs is unreachable, so the wrong voice is the worst case,
    ///   never a silent briefing.
    func speak(
        _ text: String,
        instructions: String? = nil,
        speed: Double = 1.2,
        elevenLabsVoiceID: String? = nil,
        timeout: TimeInterval = 40
    ) async throws -> Data {
        guard isConfigured else { throw SpeechError.notConfigured }

        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/polly/speak") else {
            throw SpeechError.badURL
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        }
        // Attributes the proxy's ai_usage row to this install. Identifies a
        // device for cost accounting, never a person.
        request.setValue(InstallID.current, forHTTPHeaderField: "x-glutt-device-id")

        var body: [String: Any] = ["text": text, "speed": speed]
        if let instructions, !instructions.isEmpty {
            body["instructions"] = instructions
        }
        if let elevenLabsVoiceID, !elevenLabsVoiceID.isEmpty {
            body["elevenLabsVoiceId"] = elevenLabsVoiceID
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else {
            throw SpeechError.upstream("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
            throw SpeechError.upstream("HTTP \(http.statusCode) \(snippet)")
        }
        guard !data.isEmpty else {
            throw SpeechError.upstream("empty audio")
        }
        return data
    }
}
