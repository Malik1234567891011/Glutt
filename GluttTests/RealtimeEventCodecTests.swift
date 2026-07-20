import XCTest
@testable import Glutt

final class RealtimeEventCodecTests: XCTestCase {

    // MARK: - Helpers

    /// Encodes the event and parses it back so assertions compare
    /// dictionaries, not JSON strings (key order must not matter).
    private func encodedDictionary(_ event: RealtimeClientEvent) throws -> [String: Any] {
        let data = try event.encoded()
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any], "top-level JSON must be an object")
    }

    private func decode(_ fixture: String) -> RealtimeServerEvent {
        RealtimeServerEvent.decode(Data(fixture.utf8))
    }

    private var startTimerTool: RealtimeToolDefinition {
        RealtimeToolDefinition(
            name: "start_timer",
            description: "Start a countdown timer for a cooking step.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "label": .object(["type": .string("string")]),
                    "seconds": .object(["type": .string("number")])
                ]),
                "required": .array([.string("label"), .string("seconds")])
            ]))
    }

    private var config: RealtimeSessionConfig {
        RealtimeSessionConfig(
            instructions: "You are Polly, a warm live cooking coach.",
            tools: [startTimerTool],
            voice: "marin",
            model: "gpt-realtime-2",
            transcribeInput: true)
    }

    // MARK: - JSONValue

    func testJSONValueRoundTripsThroughCodable() throws {
        let original = JSONValue.object([
            "name": .string("polly"),
            "count": .number(3),
            "enabled": .bool(true),
            "note": .null,
            "steps": .array([.string("prep"), .number(2.5), .bool(false)])
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testJSONValueDecodesRawJSON() throws {
        let raw = #"{"type":"object","properties":{"seconds":{"type":"number"}},"required":["seconds"],"default":null,"max":15,"strict":true}"#
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
        XCTAssertEqual(decoded, .object([
            "type": .string("object"),
            "properties": .object(["seconds": .object(["type": .string("number")])]),
            "required": .array([.string("seconds")]),
            "default": .null,
            "max": .number(15),
            "strict": .bool(true)
        ]))
    }

    // MARK: - Client events: session.update

    func testSessionUpdateEncodesGAShape() throws {
        let payload = try encodedDictionary(.sessionUpdate(config))
        XCTAssertEqual(payload["type"] as? String, "session.update")

        let session = try XCTUnwrap(payload["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "realtime")
        XCTAssertEqual(session["output_modalities"] as? [String], ["audio"])
        XCTAssertEqual(session["instructions"] as? String, "You are Polly, a warm live cooking coach.")
        XCTAssertEqual(session["tool_choice"] as? String, "auto")

        let tools = try XCTUnwrap(session["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["type"] as? String, "function")
        XCTAssertEqual(tools[0]["name"] as? String, "start_timer")
        XCTAssertEqual(tools[0]["description"] as? String, "Start a countdown timer for a cooking step.")
        let parameters = try XCTUnwrap(tools[0]["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual(parameters["required"] as? [String], ["label", "seconds"])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        let seconds = try XCTUnwrap(properties["seconds"] as? [String: Any])
        XCTAssertEqual(seconds["type"] as? String, "number")

        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let inputFormat = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(inputFormat["type"] as? String, "audio/pcm")
        XCTAssertEqual(inputFormat["rate"] as? Int, 24000)
        let turnDetection = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(turnDetection["type"] as? String, "semantic_vad")
        XCTAssertEqual(turnDetection["eagerness"] as? String, "low",
                       "default eagerness let speaker echo/noise interrupt Polly mid-sentence")
        let noiseReduction = try XCTUnwrap(input["noise_reduction"] as? [String: Any])
        XCTAssertEqual(noiseReduction["type"] as? String, "far_field")
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-4o-transcribe")
        XCTAssertEqual(transcription["language"] as? String, "en",
                       "no language hint made noise transcribe as German/Greek words")
        let output = try XCTUnwrap(audio["output"] as? [String: Any])
        let outputFormat = try XCTUnwrap(output["format"] as? [String: Any])
        XCTAssertEqual(outputFormat["type"] as? String, "audio/pcm")
        // The server REQUIRES output rate; without it the whole session.update
        // is rejected and the session runs unconfigured (live-call bug).
        XCTAssertEqual(outputFormat["rate"] as? Int, 24000)
        XCTAssertEqual(output["voice"] as? String, "marin")

        let truncation = try XCTUnwrap(session["truncation"] as? [String: Any])
        XCTAssertEqual(truncation["type"] as? String, "retention_ratio")
        let ratio = try XCTUnwrap(truncation["retention_ratio"] as? Double)
        XCTAssertEqual(ratio, 0.8, accuracy: 0.0001)
        // Byte-level: a Double 0.8 serializes as 0.80000000000000004 and the
        // server rejects the whole session.update (17 decimal places > 16).
        let raw = String(decoding: try RealtimeClientEvent.sessionUpdate(config).encoded(), as: UTF8.self)
        XCTAssertFalse(raw.contains("0.8000000"), "retention_ratio must serialize as exactly 0.8")
        let tokenLimits = try XCTUnwrap(truncation["token_limits"] as? [String: Any])
        XCTAssertEqual(tokenLimits["post_instructions"] as? Int, 16000)
    }

    func testSessionUpdateOmitsTranscriptionWhenDisabled() throws {
        var silent = config
        silent.transcribeInput = false
        let payload = try encodedDictionary(.sessionUpdate(silent))
        let session = try XCTUnwrap(payload["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        XCTAssertNil(input["transcription"])
        XCTAssertNotNil(input["turn_detection"])
        XCTAssertNotNil(input["format"])
    }

    // MARK: - Client events: everything else

    func testAppendAudioEncodes() throws {
        let payload = try encodedDictionary(.appendAudio(base64: "UENNMTZBVURJTw=="))
        XCTAssertEqual(payload["type"] as? String, "input_audio_buffer.append")
        XCTAssertEqual(payload["audio"] as? String, "UENNMTZBVURJTw==")
        XCTAssertEqual(payload.count, 2)
    }

    func testCreateUserTextEncodes() throws {
        let payload = try encodedDictionary(.createUserText("How hot should the pan be?"))
        XCTAssertEqual(payload["type"] as? String, "conversation.item.create")
        let item = try XCTUnwrap(payload["item"] as? [String: Any])
        XCTAssertEqual(item["type"] as? String, "message")
        XCTAssertEqual(item["role"] as? String, "user")
        let content = try XCTUnwrap(item["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"] as? String, "input_text")
        XCTAssertEqual(content[0]["text"] as? String, "How hot should the pan be?")
    }

    func testCreateUserImageEncodesWithItemId() throws {
        let payload = try encodedDictionary(
            .createUserImage(dataURI: "data:image/jpeg;base64,AAAA", itemId: "wf_3"))
        XCTAssertEqual(payload["type"] as? String, "conversation.item.create")
        let item = try XCTUnwrap(payload["item"] as? [String: Any])
        XCTAssertEqual(item["id"] as? String, "wf_3")
        XCTAssertEqual(item["type"] as? String, "message")
        XCTAssertEqual(item["role"] as? String, "user")
        let content = try XCTUnwrap(item["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"] as? String, "input_image")
        XCTAssertEqual(content[0]["image_url"] as? String, "data:image/jpeg;base64,AAAA")
    }

    func testCreateUserImageOmitsIdWhenNil() throws {
        let payload = try encodedDictionary(
            .createUserImage(dataURI: "data:image/jpeg;base64,BBBB", itemId: nil))
        let item = try XCTUnwrap(payload["item"] as? [String: Any])
        XCTAssertNil(item["id"])
        let content = try XCTUnwrap(item["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "input_image")
    }

    func testCreateFunctionOutputEncodes() throws {
        let payload = try encodedDictionary(
            .createFunctionOutput(callId: "call_1", output: #"{"ok":true}"#))
        XCTAssertEqual(payload["type"] as? String, "conversation.item.create")
        let item = try XCTUnwrap(payload["item"] as? [String: Any])
        XCTAssertEqual(item["type"] as? String, "function_call_output")
        XCTAssertEqual(item["call_id"] as? String, "call_1")
        XCTAssertEqual(item["output"] as? String, #"{"ok":true}"#)
    }

    func testDeleteItemEncodes() throws {
        let payload = try encodedDictionary(.deleteItem(itemId: "wf_2"))
        XCTAssertEqual(payload["type"] as? String, "conversation.item.delete")
        XCTAssertEqual(payload["item_id"] as? String, "wf_2")
        XCTAssertEqual(payload.count, 2)
    }

    func testResponseCreateEncodes() throws {
        let payload = try encodedDictionary(.responseCreate)
        XCTAssertEqual(payload["type"] as? String, "response.create")
        XCTAssertEqual(payload.count, 1)
    }

    func testResponseCreateSpeechOnlyEncodesToolChoiceNone() throws {
        let payload = try encodedDictionary(.responseCreateSpeechOnly)
        XCTAssertEqual(payload["type"] as? String, "response.create")
        let response = payload["response"] as? [String: Any]
        XCTAssertEqual(response?["tool_choice"] as? String, "none")
    }

    func testResponseCancelEncodes() throws {
        let payload = try encodedDictionary(.responseCancel)
        XCTAssertEqual(payload["type"] as? String, "response.cancel")
        XCTAssertEqual(payload.count, 1)
    }

    func testTruncateItemEncodes() throws {
        let payload = try encodedDictionary(.truncateItem(itemId: "item_9", audioEndMs: 1500))
        XCTAssertEqual(payload["type"] as? String, "conversation.item.truncate")
        XCTAssertEqual(payload["item_id"] as? String, "item_9")
        XCTAssertEqual(payload["content_index"] as? Int, 0)
        XCTAssertEqual(payload["audio_end_ms"] as? Int, 1500)
    }

    // MARK: - Server events

    func testDecodesSessionCreated() {
        let fixture = #"{"type": "session.created", "event_id": "event_1", "session": {"id": "sess_1"}}"#
        XCTAssertEqual(decode(fixture), .sessionCreated)
    }

    func testDecodesSpeechStarted() {
        let fixture = #"{"type": "input_audio_buffer.speech_started", "event_id": "event_2", "audio_start_ms": 120, "item_id": "item_2"}"#
        XCTAssertEqual(decode(fixture), .speechStarted)
    }

    func testDecodesRemainingSimpleEvents() {
        XCTAssertEqual(decode(#"{"type": "session.updated", "session": {}}"#), .sessionUpdated)
        XCTAssertEqual(
            decode(#"{"type": "input_audio_buffer.speech_stopped", "audio_end_ms": 900, "item_id": "item_2"}"#),
            .speechStopped)
        XCTAssertEqual(decode(#"{"type": "response.cancelled", "response_id": "resp_7"}"#), .responseCancelled)
    }

    func testDecodesInputTranscriptionCompleted() {
        let fixture = #"""
        {"type": "conversation.item.input_audio_transcription.completed",
         "event_id": "event_3", "item_id": "item_2", "content_index": 0,
         "transcript": "Should I flip the salmon now?"}
        """#
        XCTAssertEqual(decode(fixture), .inputTranscript("Should I flip the salmon now?"))
    }

    func testDecodesOutputAudioDelta() {
        let fixture = #"""
        {"type": "response.output_audio.delta", "event_id": "event_5",
         "response_id": "resp_1", "item_id": "item_3",
         "output_index": 0, "content_index": 0, "delta": "UENNQVVESU8="}
        """#
        XCTAssertEqual(decode(fixture), .outputAudioDelta(itemId: "item_3", base64: "UENNQVVESU8="))
    }

    func testDecodesOutputTranscriptDelta() {
        let fixture = #"""
        {"type": "response.output_audio_transcript.delta", "event_id": "event_6",
         "response_id": "resp_1", "item_id": "item_3",
         "output_index": 0, "content_index": 0, "delta": "Nice sear"}
        """#
        XCTAssertEqual(decode(fixture), .outputTranscriptDelta(itemId: "item_3", delta: "Nice sear"))
    }

    func testDecodesResponseDoneExtractsFunctionCalls() throws {
        let fixture = #"""
        {"type": "response.done", "event_id": "event_7",
         "response": {
           "id": "resp_2",
           "status": "completed",
           "output": [
             {"type": "message", "id": "item_4", "role": "assistant",
              "content": [{"type": "output_audio", "transcript": "On it."}]},
             {"type": "function_call", "id": "item_5", "name": "start_timer",
              "call_id": "call_1", "arguments": "{\"label\":\"pasta\",\"seconds\":480}"},
             {"type": "function_call", "id": "item_6", "name": "check_pantry",
              "call_id": "call_2", "arguments": "{\"names\":[\"butter\"]}"}
           ],
           "usage": {"total_tokens": 900}}}
        """#
        guard case .responseDone(let status, let calls) = decode(fixture) else {
            return XCTFail("expected .responseDone")
        }
        XCTAssertEqual(status, "completed")
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls, [
            RealtimeFunctionCall(name: "start_timer", callId: "call_1",
                                 argumentsJSON: #"{"label":"pasta","seconds":480}"#),
            RealtimeFunctionCall(name: "check_pantry", callId: "call_2",
                                 argumentsJSON: #"{"names":["butter"]}"#)
        ])
    }

    func testDecodesError() {
        let fixture = #"""
        {"type": "error", "event_id": "event_9",
         "error": {"type": "invalid_request_error", "code": "invalid_value",
                   "message": "Audio format not supported.", "param": null}}
        """#
        XCTAssertEqual(decode(fixture), .error(code: "invalid_value", message: "Audio format not supported."))
    }

    func testUnknownTypeIsUnhandled() {
        let fixture = #"{"type": "rate_limits.updated", "rate_limits": []}"#
        XCTAssertEqual(decode(fixture), .unhandled(type: "rate_limits.updated"))
    }

    func testMalformedPayloadsAreUnhandled() {
        XCTAssertEqual(RealtimeServerEvent.decode(Data([0xFF, 0x00, 0x13, 0x37])),
                       .unhandled(type: "malformed"))
        XCTAssertEqual(decode(#"{"no_type": true}"#), .unhandled(type: "malformed"))
        XCTAssertEqual(decode(#"[1, 2, 3]"#), .unhandled(type: "malformed"))
    }
}
