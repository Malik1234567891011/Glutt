import Foundation

/// Fetches Gemini-indexed YouTube step clips via the Vercel proxy.
/// Two-phase (segment → match) so each call fits Hobby's 60s limit.
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

        // Phase 1 — video segmentation (slow; YouTube URL → Gemini).
        let segmentJSON = try await postJSON([
            "phase": "segment",
            "youtube_url": youtubeURL,
            "recipe_title": recipeTitle,
            "force": force,
            "steps": stepPayload(cookSteps),
        ])
        let segmentDoc = try JSONSerialization.jsonObject(with: segmentJSON) as? [String: Any]
        let segments = segmentDoc?["segments"] as? [[String: Any]] ?? []

        // Phase 2 — match segments to CookPlan steps (pass segments explicitly;
        // Redis handoff is optional and may be unavailable on some deploys).
        var matchBody: [String: Any] = [
            "phase": "match",
            "youtube_url": youtubeURL,
            "recipe_title": recipeTitle,
            "force": force,
            "steps": stepPayload(cookSteps),
        ]
        if !segments.isEmpty {
            matchBody["segments"] = segments
        }
        let matchData = try await postJSON(matchBody)

        let decoded = try JSONDecoder().decode(StepClipIndexResponse.self, from: matchData)
        saveDisk(cacheKey, decoded)
        return decoded
    }

    func clip(forStepID stepID: String, in response: StepClipIndexResponse) -> StepClip? {
        response.clips.first { $0.stepID == stepID }
    }

    // MARK: - HTTP

    private func stepPayload(_ steps: [CookPlan.PlanStep]) -> [[String: Any]] {
        steps.map { step in
            [
                "id": step.id,
                "title": step.title,
                "instruction": step.instruction,
                "kind": step.kind.rawValue,
            ]
        }
    }

    private func postJSON(_ body: [String: Any]) async throws -> Data {
        guard !baseURL.isEmpty else { throw URLError(.badURL) }
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/cook/clips") else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        }
        request.timeoutInterval = 58
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "clip index failed"
            throw NSError(domain: "StepClipService", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }
        return data
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
