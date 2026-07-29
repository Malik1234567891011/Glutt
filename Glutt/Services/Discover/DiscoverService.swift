import Foundation

enum DiscoverError: LocalizedError {
    case notConfigured
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Discovery isn't available in this build."
        case .badResponse(let detail): "Couldn't load videos: \(detail)"
        }
    }
}

/// Talks to the Glutt proxy's Discover endpoints. Mirrors `LLMClient`'s
/// transport + auth, but takes an injectable `transport` so it is testable.
struct DiscoverService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var baseURL: String = Secrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    var clientKey: String = Secrets.aiProxyClientKey.trimmingCharacters(in: .whitespacesAndNewlines)

    static let live = DiscoverService()

    func search(query: String, pageToken: String?) async throws -> DiscoverResponse {
        var items = [URLQueryItem(name: "q", value: query)]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await get(path: "discover/search", queryItems: items)
    }

    func suggested(tags: [String]) async throws -> DiscoverResponse {
        var items: [URLQueryItem] = []
        if !tags.isEmpty { items.append(URLQueryItem(name: "tags", value: tags.joined(separator: ","))) }
        return try await get(path: "discover/suggested", queryItems: items)
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> DiscoverResponse {
        guard !baseURL.isEmpty else { throw DiscoverError.notConfigured }
        guard var comps = URLComponents(string: "\(baseURL)/\(path)") else {
            throw DiscoverError.badResponse("Bad URL")
        }
        comps.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = comps.url else { throw DiscoverError.badResponse("Bad URL") }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"
        if !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        }
        // Attributes the proxy's ai_usage row to this install. Identifies a
        // device for cost accounting, never a person.
        request.setValue(InstallID.current, forHTTPHeaderField: "x-glutt-device-id")

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DiscoverError.badResponse("HTTP \(code)")
        }
        do {
            return try JSONDecoder().decode(DiscoverResponse.self, from: data)
        } catch {
            throw DiscoverError.badResponse("Unexpected response shape")
        }
    }
}
