import Foundation

/// Glutt's ears for video import — ElevenLabs Scribe v2 via the Vercel proxy.
///
/// Never talks to ElevenLabs directly (key stays on the server). Failures are
/// soft for the import pipeline: callers treat `nil` as "no speech evidence".
struct SpeechTranscriptionClient {

    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    enum TranscriptionError: LocalizedError {
        case notConfigured
        case badURL
        case upstream(String)
        case decode

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Speech transcription isn’t available in this build."
            case .badURL: "Bad transcription endpoint."
            case .upstream(let detail): "Couldn’t listen to the video: \(detail)"
            case .decode: "Couldn’t read the transcript response."
            }
        }
    }

    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var baseURL: String = LLMClient.proxyBaseURL
    var clientKey: String = LLMClient.proxyClientKey

    static let live = SpeechTranscriptionClient()

    /// Same gate as other AI features — empty proxy base URL disables speech.
    var isConfigured: Bool { !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Transcribes a TikTok / YouTube / hosted media URL. Returns nil-friendly
    /// via throwing — callers should catch and continue without speech.
    func transcribe(
        sourceURL: String,
        keyterms: [String] = [],
        timeout: TimeInterval = 55
    ) async throws -> VideoTranscript {
        guard isConfigured else { throw TranscriptionError.notConfigured }

        let root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/import/transcribe") else {
            throw TranscriptionError.badURL
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        }

        var body: [String: Any] = ["source_url": sourceURL]
        let terms = keyterms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !terms.isEmpty {
            body["keyterms"] = Array(terms.prefix(20))
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await transport(request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw TranscriptionError.upstream("timed out")
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.upstream("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(180) ?? ""
            throw TranscriptionError.upstream("HTTP \(http.statusCode) \(snippet)")
        }

        do {
            let decoded = try JSONDecoder().decode(ElevenLabsSTTResponse.self, from: data)
            let transcript = decoded.asVideoTranscript()
            if transcript.isEmpty { throw TranscriptionError.decode }
            return transcript
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.decode
        }
    }

    /// Cooking-aware keyterms derived from caption/title — optional Scribe boost.
    static func keyterms(from draft: ImportedRecipeDraft) -> [String] {
        let blob = [draft.title, draft.caption]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        var terms: [String] = [
            "tablespoon", "teaspoon", "fahrenheit", "celsius", "grams", "ounces",
            "cup", "cups", "pound", "pounds",
        ]

        // Pull likely ingredient-ish tokens from caption (length 4–24, no hashtags).
        let tokens = blob
            .split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" })
            .map(String.init)
            .filter { $0.count >= 4 && $0.count <= 24 && !$0.hasPrefix("#") }

        // Prefer rarer/longer tokens from the caption.
        for token in tokens where !terms.contains(token) {
            terms.append(token)
            if terms.count >= 20 { break }
        }
        return terms
    }
}
