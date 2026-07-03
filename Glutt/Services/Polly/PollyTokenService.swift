import Foundation

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

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PollyTokenError.badResponse("HTTP \(code)")
        }
        do {
            return try JSONDecoder().decode(PollySessionToken.self, from: data)
        } catch {
            throw PollyTokenError.badResponse("Unexpected response shape")
        }
    }
}
