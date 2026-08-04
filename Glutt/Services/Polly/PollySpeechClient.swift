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
            case .notConfigured: "Chef speech isn’t available in this build."
            case .badURL: "Bad Chef speech endpoint."
            case .upstream(let detail): "Couldn’t synthesize Chef speech: \(detail)"
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
    /// Per-line ElevenLabs delivery overrides. Nil — which is every ordinary
    /// line — leaves the proxy's pinned settings alone, so one shouted line
    /// can't drag the rest of the session with it.
    struct Delivery: Equatable {
        /// Lower is more expressive and less predictable between generations.
        let stability: Double
        /// Higher exaggerates the delivery. Costs a little latency.
        let style: Double
    }

    /// Audio plus the id needed to stitch the NEXT line onto this one.
    struct Spoken {
        let audio: Data
        /// ElevenLabs request id, when a cloned voice rendered it. Feed back as
        /// `previousRequestIds` so tone carries across utterances.
        let requestID: String?
    }

    /// Convenience for callers that don't chain (the briefing renders whole).
    func speak(
        _ text: String,
        instructions: String? = nil,
        speed: Double = 1.2,
        elevenLabsVoiceID: String? = nil,
        timeout: TimeInterval = 40
    ) async throws -> Data {
        try await speakWithContinuity(
            text, instructions: instructions, speed: speed,
            elevenLabsVoiceID: elevenLabsVoiceID, timeout: timeout).audio
    }

    /// - Parameters:
    ///   - previousText: the line spoken immediately before this one.
    ///   - previousRequestIds: up to 3 completed ElevenLabs request ids.
    ///
    /// Both exist because each synthesis is otherwise an independent generation
    /// with no memory of the last, so tone and energy drift line to line and the
    /// cook hears a slightly different person every turn. This is ElevenLabs'
    /// documented fix for it.
    func speakWithContinuity(
        _ text: String,
        instructions: String? = nil,
        speed: Double = 1.2,
        elevenLabsVoiceID: String? = nil,
        previousText: String? = nil,
        previousRequestIds: [String] = [],
        delivery: Delivery? = nil,
        timeout: TimeInterval = 40
    ) async throws -> Spoken {
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

        // Every caller funnels through here — the live cloned voice and the
        // pre-cook briefing both — so this is the one place recipe shorthand has
        // to become words. "2 tbsp" otherwise reaches the voice as "t-b-s-p".
        var body: [String: Any] = ["text": SpokenText.forSpeech(text), "speed": speed]
        if let instructions, !instructions.isEmpty {
            body["instructions"] = instructions
        }
        if let elevenLabsVoiceID, !elevenLabsVoiceID.isEmpty {
            body["elevenLabsVoiceId"] = elevenLabsVoiceID
        }
        if let previousText, !previousText.isEmpty {
            // Conditioned on what was actually spoken, not what was written.
            body["previousText"] = SpokenText.forSpeech(previousText)
        }
        if !previousRequestIds.isEmpty {
            body["previousRequestIds"] = previousRequestIds
        }
        if let delivery {
            body["stability"] = delivery.stability
            body["style"] = delivery.style
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
        let requestID = http.value(forHTTPHeaderField: "x-glutt-tts-request-id")
        return Spoken(audio: data, requestID: requestID?.isEmpty == false ? requestID : nil)
    }
}
