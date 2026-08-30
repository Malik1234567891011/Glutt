import Foundation

enum RealtimeTransportError: LocalizedError, Equatable {
    case notConnected
    case badURL
    case nonTextFrame
    /// The realtime endpoint refused the call, with what it said about it.
    ///
    /// Its own case because the status is the whole diagnosis and it used to be
    /// discarded: 401 is a bad token, 402 or 429 is the account, 5xx is theirs
    /// and worth retrying. All three read as "Chef isn't connected yet" before,
    /// which sent a real outage to the wrong place for an afternoon.
    case callRefused(status: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Chef isn't connected yet."
        case .badURL: "Couldn't build the realtime session URL."
        case .nonTextFrame: "Received an unreadable frame from the realtime session."
        case .callRefused(let status, let detail):
            switch status {
            case 401, 403: "Chef's session key was refused (\(status)). The key may have expired."
            case 402: "The Chef account is out of credit."
            case 429: "Chef is rate limited right now (429). Give it a minute."
            case 500...599: "Chef's provider is having trouble (\(status)). Worth trying again."
            default:
                detail.isEmpty
                    ? "Chef's session was refused (\(status))."
                    : "Chef's session was refused (\(status)): \(detail)"
            }
        }
    }
}

/// Seam over `URLSessionWebSocketTask` so the transport is testable
/// with a scripted fake (no network in tests).
protocol RealtimeSocket: Sendable {
    func send(text: String) async throws
    func receiveText() async throws -> String
    func close()
}

/// Production socket: a thin wrapper over `URLSessionWebSocketTask`.
/// `URLSessionTask` is documented thread-safe, hence `@unchecked Sendable`.
final class URLSessionWebSocket: RealtimeSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(request: URLRequest) {
        task = URLSession.shared.webSocketTask(with: request)
        task.resume()
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func receiveText() async throws -> String {
        while true {
            switch try await task.receive() {
            case .string(let text):
                return text
            case .data(let data):
                guard let text = String(data: data, encoding: .utf8) else {
                    throw RealtimeTransportError.nonTextFrame
                }
                return text
            @unknown default:
                continue
            }
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

/// Abstraction the session controller (Task 13) talks to; lets tests and the
/// reconnect path swap the whole transport, and a future WebRTC/LiveKit
/// transport slot in behind the same face.
protocol RealtimeTransporting: AnyObject, Sendable {
    func connect(token: String, model: String) async throws
    func send(_ event: RealtimeClientEvent) async throws
    var events: AsyncStream<RealtimeServerEvent> { get }
    func close() async
}

/// WebSocket transport for the OpenAI Realtime GA protocol.
/// `events` is single-consumer and created once in `init`; the receive loop
/// decodes every text frame via `RealtimeServerEvent.decode` and yields it.
/// On a receive failure it yields `.error(code: "transport", ...)` and
/// finishes the stream — reconnecting is the controller's decision.
actor RealtimeWebSocketTransport: RealtimeTransporting {
    /// Lock-guarded flag shared between the actor and its receive loop.
    /// `Task.isCancelled` is not atomic with a socket throw: a wire error can
    /// win the race against `close()`'s cancel and surface as a spurious
    /// "transport" failure mid-shutdown — which the controller would answer
    /// with a pointless reconnect. The flag is set BEFORE the socket is
    /// touched, so a close()-induced receive error is always suppressed.
    private final class ClosingFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    nonisolated let events: AsyncStream<RealtimeServerEvent>

    private let continuation: AsyncStream<RealtimeServerEvent>.Continuation
    private let socketFactory: @Sendable (URLRequest) -> RealtimeSocket
    private var socket: RealtimeSocket?
    private var receiveTask: Task<Void, Never>?
    private let isClosing = ClosingFlag()

    init(
        socketFactory: @escaping @Sendable (URLRequest) -> RealtimeSocket = { URLSessionWebSocket(request: $0) }
    ) {
        self.socketFactory = socketFactory
        let (stream, continuation) = AsyncStream.makeStream(of: RealtimeServerEvent.self)
        self.events = stream
        self.continuation = continuation
    }

    func connect(token: String, model: String) async throws {
        var comps = URLComponents()
        comps.scheme = "wss"
        comps.host = "api.openai.com"
        comps.path = "/v1/realtime"
        comps.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let url = comps.url else { throw RealtimeTransportError.badURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let socket = socketFactory(request)
        self.socket = socket
        let continuation = self.continuation
        let isClosing = self.isClosing
        receiveTask = Task {
            while !Task.isCancelled, !isClosing.isSet {
                do {
                    let text = try await socket.receiveText()
                    continuation.yield(RealtimeServerEvent.decode(Data(text.utf8)))
                } catch {
                    if !Task.isCancelled, !isClosing.isSet {
                        continuation.yield(.error(code: "transport", message: error.localizedDescription))
                    }
                    continuation.finish()
                    return
                }
            }
        }
    }

    func send(_ event: RealtimeClientEvent) async throws {
        guard let socket else { throw RealtimeTransportError.notConnected }
        let data = try event.encoded()
        try await socket.send(text: String(decoding: data, as: UTF8.self))
    }

    func close() {
        isClosing.set()
        receiveTask?.cancel()
        receiveTask = nil
        socket?.close()
        socket = nil
        continuation.finish()
    }
}
