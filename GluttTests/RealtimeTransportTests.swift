import XCTest
@testable import Glutt

/// Scripted stand-in for the production socket. Serves a queue of incoming
/// frames, records outgoing sends, and — once the script is exhausted —
/// either throws (`throwsWhenExhausted: true`) or suspends until `close()`.
final class FakeSocket: RealtimeSocket, @unchecked Sendable {
    struct ScriptExhausted: Error {}

    private let lock = NSLock()
    private let throwsWhenExhausted: Bool
    private var script: [String]
    private var sentLines: [String] = []
    private var closeCount = 0
    private var waiter: CheckedContinuation<String, Error>?

    init(script: [String], throwsWhenExhausted: Bool) {
        self.script = script
        self.throwsWhenExhausted = throwsWhenExhausted
    }

    var sent: [String] { lock.withLock { sentLines } }
    var isClosed: Bool { lock.withLock { closeCount > 0 } }

    func send(text: String) async throws {
        lock.withLock { sentLines.append(text) }
    }

    func receiveText() async throws -> String {
        let next: String? = lock.withLock { script.isEmpty ? nil : script.removeFirst() }
        if let next { return next }
        if throwsWhenExhausted { throw ScriptExhausted() }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiter = continuation }
        }
    }

    func close() {
        let pending: CheckedContinuation<String, Error>? = lock.withLock {
            closeCount += 1
            let current = waiter
            waiter = nil
            return current
        }
        pending?.resume(throwing: CancellationError())
    }
}

/// Thread-safe capture box for the URLRequest handed to the socket factory.
private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?
    var request: URLRequest? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class RealtimeTransportTests: XCTestCase {
    func testConnectPassesModelQueryAndBearerTokenToSocketFactory() async throws {
        let capture = RequestCapture()
        let socket = FakeSocket(script: [], throwsWhenExhausted: false)
        let transport = RealtimeWebSocketTransport(socketFactory: { request in
            capture.request = request
            return socket
        })

        try await transport.connect(token: "ek_test_123", model: "gpt-realtime-2")

        let request = try XCTUnwrap(capture.request)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.host, "api.openai.com")
        XCTAssertEqual(url.path, "/v1/realtime")
        XCTAssertEqual(url.query, "model=gpt-realtime-2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ek_test_123")
        await transport.close()
        XCTAssertTrue(socket.isClosed)
    }

    func testScriptedServerFramesArriveDecodedInOrder() async throws {
        let socket = FakeSocket(
            script: [
                #"{"type": "session.created"}"#,
                #"{"type": "input_audio_buffer.speech_started"}"#,
            ],
            throwsWhenExhausted: false
        )
        let transport = RealtimeWebSocketTransport(socketFactory: { _ in socket })
        try await transport.connect(token: "ek_test", model: "gpt-realtime-2")

        var iterator = transport.events.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        XCTAssertEqual(first, .sessionCreated)
        XCTAssertEqual(second, .speechStarted)
        await transport.close()
    }

    func testSendResponseCreateEncodesResponseCreateJSON() async throws {
        let socket = FakeSocket(script: [], throwsWhenExhausted: false)
        let transport = RealtimeWebSocketTransport(socketFactory: { _ in socket })
        try await transport.connect(token: "ek_test", model: "gpt-realtime-2")

        try await transport.send(.responseCreate)

        let sent = socket.sent
        XCTAssertEqual(sent.count, 1)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(sent[0].utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["type"] as? String, "response.create")
        await transport.close()
    }

    func testExhaustedScriptYieldsTransportErrorThenFinishesStream() async throws {
        let socket = FakeSocket(
            script: [#"{"type": "session.created"}"#],
            throwsWhenExhausted: true
        )
        let transport = RealtimeWebSocketTransport(socketFactory: { _ in socket })
        try await transport.connect(token: "ek_test", model: "gpt-realtime-2")

        var received: [RealtimeServerEvent] = []
        for await event in transport.events {   // exits only when the stream finishes
            received.append(event)
        }

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.first, .sessionCreated)
        let last = try XCTUnwrap(received.last)
        guard case .error(let code, let message) = last else {
            return XCTFail("Expected .error as the final event, got \(last)")
        }
        XCTAssertEqual(code, "transport")
        XCTAssertFalse(message.isEmpty)
        await transport.close()
    }

    func testSendBeforeConnectThrowsNotConnected() async {
        let transport = RealtimeWebSocketTransport(socketFactory: { _ in
            FakeSocket(script: [], throwsWhenExhausted: false)
        })
        do {
            try await transport.send(.responseCreate)
            XCTFail("expected throw")
        } catch let error as RealtimeTransportError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
