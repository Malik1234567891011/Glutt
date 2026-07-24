import XCTest
@testable import Glutt

final class SpeechTranscriptionClientTests: XCTestCase {

    func testTranscribeDecodesProxyResponse() async throws {
        let payload = """
        {
          "language_code": "eng",
          "text": "Add one cup of cream",
          "words": [
            {"text": "Add", "start": 0.0, "end": 0.2, "type": "word", "logprob": -0.1},
            {"text": "one", "start": 0.2, "end": 0.4, "type": "word", "logprob": -0.1}
          ]
        }
        """.data(using: .utf8)!

        let client = SpeechTranscriptionClient(
            transport: { request in
                XCTAssertTrue(request.url?.absoluteString.contains("/import/transcribe") == true)
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-glutt-proxy-key"), "test-key")
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
                XCTAssertEqual(body?["source_url"] as? String, "https://www.tiktok.com/@x/video/1")
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                return (payload, response)
            },
            baseURL: "https://test.local/api",
            clientKey: "test-key"
        )

        let transcript = try await client.transcribe(sourceURL: "https://www.tiktok.com/@x/video/1")
        XCTAssertEqual(transcript.plainText, "Add one cup of cream")
        XCTAssertEqual(transcript.words.count, 2)
    }

    func testKeytermsPullFromCaption() {
        var draft = ImportedRecipeDraft()
        draft.title = "Gochujang chicken"
        draft.caption = "Crispy gochujang chicken with garam masala vibes #dinner"
        let terms = SpeechTranscriptionClient.keyterms(from: draft)
        XCTAssertTrue(terms.contains("tablespoon"))
        XCTAssertTrue(terms.contains(where: { $0.contains("gochujang") || $0.contains("garam") || $0.contains("chicken") }))
    }

    func testNotConfiguredThrows() async {
        let client = SpeechTranscriptionClient(baseURL: "", clientKey: "")
        do {
            _ = try await client.transcribe(sourceURL: "https://youtube.com/watch?v=1")
            XCTFail("expected notConfigured")
        } catch let error as SpeechTranscriptionClient.TranscriptionError {
            guard case .notConfigured = error else { return XCTFail("\(error)") }
        } catch {
            XCTFail("\(error)")
        }
    }
}
