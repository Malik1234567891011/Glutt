import Foundation

/// Fetches Gemini-indexed YouTube step clips via the Vercel proxy.
/// Indexes once per (video, step-set); client disk-caches so Polly cooks stay snappy.
actor StepClipService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var baseURL: String = Secrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    var clientKey: String = Secrets.aiProxyClientKey.trimmingCharacters(in: .whitespacesAndNewlines)

    static let shared = StepClipService()

    private let defaults = UserDefaults.standard
    private let cachePrefix = "glutt.stepClips.v1."

    func clips(
        youtubeURL: String,
        recipeTitle: String,
        steps: [CookPlan.PlanStep],
        force: Bool = false
    ) async throws -> StepClipIndexResponse {
        let cookSteps = steps.filter { !CookPlan.isSetupStep($0) }
        let cacheKey = diskKey(youtubeURL: youtubeURL, steps: cookSteps)
        if !force, let cached = loadDisk(cacheKey) {
            return cached
        }

        guard !baseURL.isEmpty else {
            throw URLError(.badURL)
        }
        guard let url = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/cook/clips") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        }
        request.timeoutInterval = 55

        let body: [String: Any] = [
            "youtube_url": youtubeURL,
            "recipe_title": recipeTitle,
            "force": force,
            "steps": cookSteps.map { step -> [String: Any] in
                [
                    "id": step.id,
                    "title": step.title,
                    "instruction": step.instruction,
                    "kind": step.kind.rawValue,
                ]
            },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "clip index failed"
            throw NSError(domain: "StepClipService", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }

        let decoded = try JSONDecoder().decode(StepClipIndexResponse.self, from: data)
        saveDisk(cacheKey, decoded)
        return decoded
    }

    func clip(forStepID stepID: String, in response: StepClipIndexResponse) -> StepClip? {
        response.clips.first { $0.stepID == stepID }
    }

    // MARK: - Disk cache

    private func diskKey(youtubeURL: String, steps: [CookPlan.PlanStep]) -> String {
        let video = YouTubeEmbed.videoId(from: youtubeURL) ?? youtubeURL
        let sig = steps.map { "\($0.id)|\($0.title)|\($0.instruction)" }.joined(separator: "\n")
        return cachePrefix + video + "." + stableHash(sig)
    }

    private func stableHash(_ string: String) -> String {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private func loadDisk(_ key: String) -> StepClipIndexResponse? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StepClipIndexResponse.self, from: data)
    }

    private func saveDisk(_ key: String, _ value: StepClipIndexResponse) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
