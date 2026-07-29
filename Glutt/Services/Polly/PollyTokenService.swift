import Foundation

/// Stable per-install identifier for the proxy's abuse cap.
///
/// Now a thin alias over `InstallID`, which promotes this value out of
/// UserDefaults into the Keychain so it survives a reinstall. Kept as a name
/// because the abuse cap and the cost attribution want the same identity —
/// splitting them would double-count a device.
enum GluttDeviceID {
    static var current: String { InstallID.current }
}

/// The short-lived OpenAI Realtime credential minted by the Glutt proxy.
/// Wire shape from `POST {proxy}/polly/session`:
/// `{"value": "ek_...", "expiresAt": 1751500000, "model": "...", "voice": "..."}`.
struct PollySessionToken: Decodable, Equatable {
    let value: String              // "ek_..."
    let expiresAt: Int?            // unix seconds
    let model: String
    let voice: String
}

enum PollyTokenError: LocalizedError, Equatable {
    case notConfigured
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Polly isn't available in this build."
        case .badResponse(let detail): "Couldn't start a Polly session: \(detail)"
        }
    }
}

/// Mints ephemeral Realtime tokens from the Glutt proxy's `/polly/session`
/// endpoint. Mirrors `PlatesService`'s transport + auth, with an injectable
/// `transport` so it is testable. The committed proxy key authenticates this
/// call only; the token it returns is the sole credential the socket sees.
struct PollyTokenService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var baseURL: String = Secrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    var clientKey: String = Secrets.aiProxyClientKey.trimmingCharacters(in: .whitespacesAndNewlines)

    static let live = PollyTokenService()

    func mint() async throws -> PollySessionToken {
        guard !baseURL.isEmpty else { throw PollyTokenError.notConfigured }
        guard let url = URL(string: "\(baseURL)/polly/session") else {
            throw PollyTokenError.badResponse("Bad URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        if !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        }
        request.setValue(GluttDeviceID.current, forHTTPHeaderField: "x-glutt-device-id")

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if code == 429 {
                throw PollyTokenError.badResponse("This device hit its monthly Polly limit.")
            }
            throw PollyTokenError.badResponse("HTTP \(code)")
        }
        do {
            return try JSONDecoder().decode(PollySessionToken.self, from: data)
        } catch {
            throw PollyTokenError.badResponse("Unexpected response shape")
        }
    }

    /// Reports how long a finished Realtime session ran, so the proxy can cost
    /// it. `/polly/session` only mints a token — the WebRTC session runs device
    /// to OpenAI and the proxy never sees a byte of it, so the app is the only
    /// party that knows the duration. OpenAI Realtime bills by audio second,
    /// which makes this the difference between Polly being measurable and not.
    ///
    /// Best-effort by design: never throws, never blocks a teardown. A dropped
    /// report shows up as a `polly_session` row with no matching
    /// `polly_realtime` row — i.e. a crash, force-quit, or lost network.
    func reportSessionEnd(duration: TimeInterval, model: String?, usage: RealtimeUsage?) async {
        guard !baseURL.isEmpty, duration > 0 else { return }
        guard let url = URL(string: "\(baseURL)/polly/usage") else { return }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        }
        request.setValue(GluttDeviceID.current, forHTTPHeaderField: "x-glutt-device-id")

        var payload: [String: Any] = ["durationMs": Int(duration * 1000)]
        if let model, !model.isEmpty { payload["model"] = model }
        if let usage, !usage.isEmpty {
            payload["textInputTokens"] = usage.textInputTokens
            payload["audioInputTokens"] = usage.audioInputTokens
            payload["textOutputTokens"] = usage.textOutputTokens
            payload["audioOutputTokens"] = usage.audioOutputTokens
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        _ = try? await transport(request)
    }
}
