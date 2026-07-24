import XCTest
@testable import Glutt

final class PollySpeechClientTests: XCTestCase {

    func testSpeakPostsToPollySpeakAndReturnsBytes() async throws {
        let audio = Data([0x49, 0x44, 0x33]) // "ID3" sniff
        let client = PollySpeechClient(
            transport: { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertTrue(request.url?.absoluteString.hasSuffix("/polly/speak") == true)
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-glutt-proxy-key"), "test-key")
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
                XCTAssertEqual(body?["text"] as? String, "Quick rundown.")
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["Content-Type": "audio/mpeg"]
                )!
                return (audio, response)
            },
            baseURL: "https://example.test/api",
            clientKey: "test-key"
        )

        let data = try await client.speak("Quick rundown.")
        XCTAssertEqual(data, audio)
    }

    func testNotConfiguredThrows() async {
        let client = PollySpeechClient(
            transport: { _ in fatalError("should not call") },
            baseURL: "",
            clientKey: ""
        )
        do {
            _ = try await client.speak("hi")
            XCTFail("expected throw")
        } catch let error as PollySpeechClient.SpeechError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
