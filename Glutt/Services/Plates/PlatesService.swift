import Foundation

enum PlatesError: LocalizedError {
    case notConfigured
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "The recipe feed isn't available in this build."
        case .badResponse(let detail): "Couldn't load recipes: \(detail)"
        }
    }
}

/// Talks to the Glutt proxy's Plates endpoints. Mirrors `DiscoverService`'s
/// transport + auth, with an injectable `transport` so it is testable.
struct PlatesService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var baseURL: String = Secrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    var clientKey: String = Secrets.aiProxyClientKey.trimmingCharacters(in: .whitespacesAndNewlines)

    static let live = PlatesService()

    func daily() async throws -> PlatesResponse {
        try await get(path: "plates/deck", queryItems: [])
    }

    func search(query: String, pageToken: String?) async throws -> PlatesResponse {
        var items = [URLQueryItem(name: "q", value: query)]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await get(path: "plates/search", queryItems: items)
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> PlatesResponse {
        guard !baseURL.isEmpty else { throw PlatesError.notConfigured }
        guard var comps = URLComponents(string: "\(baseURL)/\(path)") else {
            throw PlatesError.badResponse("Bad URL")
        }
        comps.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = comps.url else { throw PlatesError.badResponse("Bad URL") }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"
        if !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        }

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PlatesError.badResponse("HTTP \(code)")
        }
        do {
            return try JSONDecoder().decode(PlatesResponse.self, from: data)
        } catch {
            throw PlatesError.badResponse("Unexpected response shape")
        }
    }
}
