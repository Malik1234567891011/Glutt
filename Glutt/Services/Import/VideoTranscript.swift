import Foundation

/// Word-level speech evidence from a video (ElevenLabs Scribe v2).
/// Kept on the import draft during the job — not persisted on the final Recipe.
struct TranscriptWord: Codable, Equatable, Sendable {
    var text: String
    /// Start time in seconds, when provided.
    var start: Double?
    /// End time in seconds, when provided.
    var end: Double?
    var speakerID: String?
    /// ElevenLabs type: word | spacing | audio_event
    var type: String?

    var isSpokenWord: Bool {
        let t = (type ?? "word").lowercased()
        return t == "word" || t.isEmpty
    }
}

/// Full transcript for one video URL.
struct VideoTranscript: Codable, Equatable, Sendable {
    var text: String
    var words: [TranscriptWord]
    var languageCode: String?
    var languageProbability: Double?

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !words.contains(where: \.isSpokenWord)
    }

    /// Plain transcript text, preferring the API's `text` field.
    var plainText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return words.filter(\.isSpokenWord).map(\.text).joined(separator: " ")
    }

    /// Timestamped lines for the recipe compiler, e.g. `[00:04.2] Cook four cloves…`
    /// Caps length so we stay inside LLM context budgets.
    func timestampedPlainText(maxCharacters: Int = 12_000) -> String {
        let spoken = words.filter(\.isSpokenWord)
        guard !spoken.isEmpty else {
            return String(plainText.prefix(maxCharacters))
        }

        var lines: [String] = []
        var currentStart: Double?
        var currentWords: [String] = []

        func flush() {
            guard !currentWords.isEmpty else { return }
            let stamp = formatTimestamp(currentStart ?? 0)
            lines.append("[\(stamp)] \(currentWords.joined(separator: " "))")
            currentWords = []
            currentStart = nil
        }

        for word in spoken {
            if currentStart == nil { currentStart = word.start }
            currentWords.append(word.text)
            // Break into ~clause-sized chunks on sentence punctuation or ~12 words.
            let endsClause = word.text.contains(where: { ".!?".contains($0) })
            if endsClause || currentWords.count >= 12 {
                flush()
            }
        }
        flush()

        var joined = lines.joined(separator: "\n")
        if joined.count > maxCharacters {
            joined = String(joined.prefix(maxCharacters))
        }
        return joined
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let mins = Int(total) / 60
        let secs = total.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%04.1f", mins, secs)
    }
}

// MARK: - ElevenLabs response decoding

/// Wire format from `POST /v1/speech-to-text` (single-channel sync response).
struct ElevenLabsSTTResponse: Decodable {
    var languageCode: String?
    var languageProbability: Double?
    var text: String?
    var words: [Word]?

    struct Word: Decodable {
        var text: String
        var start: Double?
        var end: Double?
        var type: String?
        var speakerId: String?

        enum CodingKeys: String, CodingKey {
            case text, start, end, type
            case speakerId = "speaker_id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case text, words
        case languageCode = "language_code"
        case languageProbability = "language_probability"
    }

    func asVideoTranscript() -> VideoTranscript {
        VideoTranscript(
            text: text ?? "",
            words: (words ?? []).map {
                TranscriptWord(
                    text: $0.text,
                    start: $0.start,
                    end: $0.end,
                    speakerID: $0.speakerId,
                    type: $0.type
                )
            },
            languageCode: languageCode,
            languageProbability: languageProbability
        )
    }
}
