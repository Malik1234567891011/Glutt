import Foundation

// MARK: - JSONValue

/// Minimal JSON tree used for Realtime tool schemas and function-call
/// arguments. Fully `Codable` in both directions so schemas can be declared
/// in Swift and payloads decoded straight off the wire.
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Bridge to a `JSONSerialization`-compatible object tree.
    var jsonObject: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .array(let values): return values.map(\.jsonObject)
        case .object(let values): return values.mapValues(\.jsonObject)
        }
    }
}

// MARK: - Session configuration

/// A Realtime function tool advertised via `session.update`.
struct RealtimeToolDefinition: Encodable, Equatable {
    let type = "function"
    let name: String
    let description: String
    let parameters: JSONValue      // JSON Schema as a JSONValue tree
}

/// Everything the initial `session.update` needs. Built once per session.
/// `model` rides along for the WS connect URL — the GA protocol does not
/// put it inside the `session.update` payload.
struct RealtimeSessionConfig: Equatable {
    var instructions: String
    var tools: [RealtimeToolDefinition]
    var voice: String              // PollyConfig.voice
    var model: String              // PollyConfig.realtimeModel
    var transcribeInput: Bool      // true -> audio.input.transcription = {model: "gpt-4o-transcribe"}
}

/// A function call the model asked us to run, lifted out of `response.done`.
struct RealtimeFunctionCall: Equatable {
    let name: String
    let callId: String
    let argumentsJSON: String
}

// MARK: - Client -> server events

/// The subset of OpenAI Realtime GA client events Polly sends.
/// `encoded()` emits the exact wire JSON documented in the plan's
/// protocol reference.
enum RealtimeClientEvent: Equatable {
    case sessionUpdate(RealtimeSessionConfig)
    case appendAudio(base64: String)
    case createUserText(String)
    case createUserImage(dataURI: String, itemId: String?)  // itemId lets us delete stale watch frames
    case createFunctionOutput(callId: String, output: String)
    case deleteItem(itemId: String)
    case responseCreate
    /// Greeting / speech-only turn: `tool_choice: "none"` so the model can't
    /// call a tool mid-opening and then re-speak the same first line on the
    /// follow-up response.create after tool results.
    case responseCreateSpeechOnly
    case responseCancel
    case truncateItem(itemId: String, audioEndMs: Int)

    func encoded() throws -> Data {
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    private var payload: [String: Any] {
        switch self {
        case .sessionUpdate(let config):
            return ["type": "session.update", "session": Self.sessionPayload(config)]
        case .appendAudio(let base64):
            return ["type": "input_audio_buffer.append", "audio": base64]
        case .createUserText(let text):
            return ["type": "conversation.item.create",
                    "item": ["type": "message", "role": "user",
                             "content": [["type": "input_text", "text": text]]]]
        case .createUserImage(let dataURI, let itemId):
            var item: [String: Any] = ["type": "message", "role": "user",
                                       "content": [["type": "input_image", "image_url": dataURI]]]
            if let itemId { item["id"] = itemId }
            return ["type": "conversation.item.create", "item": item]
        case .createFunctionOutput(let callId, let output):
            return ["type": "conversation.item.create",
                    "item": ["type": "function_call_output", "call_id": callId, "output": output]]
        case .deleteItem(let itemId):
            return ["type": "conversation.item.delete", "item_id": itemId]
        case .responseCreate:
            return ["type": "response.create"]
        case .responseCreateSpeechOnly:
            return ["type": "response.create",
                    "response": ["tool_choice": "none"]]
        case .responseCancel:
            return ["type": "response.cancel"]
        case .truncateItem(let itemId, let audioEndMs):
            return ["type": "conversation.item.truncate", "item_id": itemId,
                    "content_index": 0, "audio_end_ms": audioEndMs]
        }
    }

    private static func sessionPayload(_ config: RealtimeSessionConfig) -> [String: Any] {
        var input: [String: Any] = [
            "format": ["type": "audio/pcm", "rate": 24000],
            // eagerness low: at kitchen speaker volume, residual echo of
            // Polly's own voice ("I'm here.") and noise ("akademik", "Οξάνα")
            // tripped default VAD and cut her off mid-sentence on every turn.
            // Low waits for clearer evidence of real speech before barging in.
            "turn_detection": ["type": "semantic_vad", "eagerness": "low"],
            // The phone sits on a counter an arm's length away — far-field
            // noise reduction cleans sizzle/fan noise before VAD sees it.
            "noise_reduction": ["type": "far_field"]
        ]
        if config.transcribeInput {
            input["transcription"] = ["model": "gpt-4o-transcribe", "language": "en"]
        }
        let tools: [[String: Any]] = config.tools.map {
            ["type": $0.type, "name": $0.name, "description": $0.description,
             "parameters": $0.parameters.jsonObject]
        }
        return [
            "type": "realtime",
            "output_modalities": ["audio"],
            "instructions": config.instructions,
            "tools": tools,
            "tool_choice": "auto",
            "audio": [
                "input": input,
                // rate is REQUIRED here: omitting it makes the server reject
                // the whole session.update (missing_required_parameter) and
                // the session silently runs as a default assistant — no
                // instructions, no tools, no Polly.
                "output": ["format": ["type": "audio/pcm", "rate": 24000], "voice": config.voice]
            ],
            // NSDecimalNumber, not a Double literal: 0.8 has no exact binary
            // representation, so JSONSerialization emits 0.80000000000000004
            // (17 decimal places) and the server rejects the WHOLE
            // session.update (decimal_max_decimal_places_exceeded) — the
            // session then runs as a default assistant with no Polly persona.
            "truncation": ["type": "retention_ratio",
                           "retention_ratio": NSDecimalNumber(string: "0.8"),
                           "token_limits": ["post_instructions": 16000]]
        ]
    }
}

// MARK: - Server -> client events

/// The subset of OpenAI Realtime GA server events Polly reacts to.
enum RealtimeServerEvent: Equatable {
    case sessionCreated
    case sessionUpdated
    case speechStarted                       // input_audio_buffer.speech_started
    case speechStopped
    case inputTranscript(String)             // conversation.item.input_audio_transcription.completed
    case outputAudioDelta(itemId: String, base64: String)
    case outputTranscriptDelta(itemId: String, delta: String)
    case responseDone(status: String, calls: [RealtimeFunctionCall])
    case responseCancelled
    case error(code: String?, message: String)
    case unhandled(type: String)

    /// Never throws: anything unparseable becomes `.unhandled` so a weird
    /// frame can never take the session down.
    static func decode(_ data: Data) -> RealtimeServerEvent {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else {
            return .unhandled(type: "malformed")
        }
        switch type {
        case "session.created":
            return .sessionCreated
        case "session.updated":
            return .sessionUpdated
        case "input_audio_buffer.speech_started":
            return .speechStarted
        case "input_audio_buffer.speech_stopped":
            return .speechStopped
        case "conversation.item.input_audio_transcription.completed":
            return .inputTranscript(object["transcript"] as? String ?? "")
        case "response.output_audio.delta":
            guard let itemId = object["item_id"] as? String,
                  let delta = object["delta"] as? String else { return .unhandled(type: type) }
            return .outputAudioDelta(itemId: itemId, base64: delta)
        case "response.output_audio_transcript.delta":
            guard let itemId = object["item_id"] as? String,
                  let delta = object["delta"] as? String else { return .unhandled(type: type) }
            return .outputTranscriptDelta(itemId: itemId, delta: delta)
        case "response.done":
            let response = object["response"] as? [String: Any] ?? [:]
            let output = response["output"] as? [[String: Any]] ?? []
            let calls: [RealtimeFunctionCall] = output.compactMap { item in
                guard item["type"] as? String == "function_call",
                      let name = item["name"] as? String,
                      let callId = item["call_id"] as? String else { return nil }
                return RealtimeFunctionCall(name: name, callId: callId,
                                            argumentsJSON: item["arguments"] as? String ?? "{}")
            }
            return .responseDone(status: response["status"] as? String ?? "unknown", calls: calls)
        case "response.cancelled":
            return .responseCancelled
        case "error":
            let error = object["error"] as? [String: Any] ?? [:]
            return .error(code: error["code"] as? String,
                          message: error["message"] as? String ?? "Unknown realtime error")
        default:
            return .unhandled(type: type)
        }
    }
}
