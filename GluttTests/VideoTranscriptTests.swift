import XCTest
@testable import Glutt

final class VideoTranscriptTests: XCTestCase {

    func testDecodesElevenLabsWireFormat() throws {
        let json = """
        {
          "language_code": "eng",
          "language_probability": 0.98,
          "text": "Start with half a pound of rigatoni",
          "words": [
            {"text": "Start", "start": 1.8, "end": 2.1, "type": "word", "speaker_id": "speaker_0", "logprob": -0.1},
            {"text": " ", "start": 2.1, "end": 2.15, "type": "spacing", "logprob": -0.01},
            {"text": "with", "start": 2.15, "end": 2.3, "type": "word", "logprob": -0.2}
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ElevenLabsSTTResponse.self, from: json)
        let transcript = decoded.asVideoTranscript()
        XCTAssertEqual(transcript.languageCode, "eng")
        XCTAssertEqual(transcript.plainText, "Start with half a pound of rigatoni")
        XCTAssertEqual(transcript.words.count, 3)
        XCTAssertEqual(transcript.words[0].speakerID, "speaker_0")
        XCTAssertTrue(transcript.words[0].isSpokenWord)
        XCTAssertFalse(transcript.words[1].isSpokenWord)
    }

    func testTimestampedPlainTextChunksWords() {
        let words = (0..<15).map { i in
            TranscriptWord(
                text: i == 5 ? "butter." : "word\(i)",
                start: Double(i),
                end: Double(i) + 0.4,
                type: "word"
            )
        }
        let transcript = VideoTranscript(text: "", words: words)
        let stamped = transcript.timestampedPlainText()
        XCTAssertTrue(stamped.contains("[00:00.0]"))
        XCTAssertTrue(stamped.contains("butter."))
    }

    func testShouldCompileRequiresEnoughSpeech() {
        let thin = VideoTranscript(
            text: "hi",
            words: [TranscriptWord(text: "hi", start: 0, end: 0.2, type: "word")]
        )
        XCTAssertFalse(VideoRecipeCompiler.shouldCompile(transcript: thin))

        let words = (0..<12).map {
            TranscriptWord(text: "garlic", start: Double($0), end: Double($0) + 0.2, type: "word")
        }
        let rich = VideoTranscript(text: words.map(\.text).joined(separator: " "), words: words)
        XCTAssertTrue(VideoRecipeCompiler.shouldCompile(transcript: rich))
    }

    func testVerifyFlagsUnsupportedIngredientNames() {
        var draft = ImportedRecipeDraft()
        draft.usedSpeechTranscript = true
        draft.caption = "garlic pasta"
        draft.ingredientLines = ["4 cloves garlic", "2 cups unicorn dust"]
        draft.speechTranscript = "add the garlic to the pan"

        let checked = VideoRecipeCompiler.verify(draft, transcript: nil)
        XCTAssertTrue(checked.issues.contains(where: { $0.contains("unicorn") || $0.contains("Couldn’t clearly") }))
    }
}
