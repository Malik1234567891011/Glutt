import Foundation

/// Fetches Gemini-indexed YouTube step clips via the Vercel proxy.
/// Pipeline: ground (AV + duration) → refine (extend truncated continuous actions).
actor StepClipService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var baseURL: String = Secrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    var clientKey: String = Secrets.aiProxyClientKey.trimmingCharacters(in: .whitespacesAndNewlines)

    static let shared = StepClipService()

    private let defaults = UserDefaults.standard
    private let cachePrefix = "glutt.stepClips.v5."

    func clips(
        youtubeURL: String,
        recipeTitle: String,
        steps: [CookPlan.PlanStep],
        force: Bool = false
    ) async throws -> StepClipIndexResponse {
        let cookSteps = steps.filter { !CookPlan.isSetupStep($0) }
        let cacheKey = diskKey(youtubeURL: youtubeURL, steps: cookSteps)
        if !force, let cached = loadDisk(cacheKey) {
            // Discard stale truncated windows from the old 30s clamp era.
            if !containsTruncationSmell(cached) {
                return cached
            }
        }

        // Always bypass server Redis when local cache was truncation-smelly.
        let bypassServerCache = force || (loadDisk(cacheKey).map(containsTruncationSmell) ?? false)

        var groundBody: [String: Any] = [
            "phase": "ground",
            "youtube_url": youtubeURL,
            "recipe_title": recipeTitle,
            "force": bypassServerCache,
            "steps": stepPayload(cookSteps),
        ]
        if let duration = knownDuration(for: youtubeURL) {
            groundBody["duration_seconds"] = duration
        }

        let groundData = try await postJSON(groundBody)
        let grounded = try JSONDecoder().decode(StepClipIndexResponse.self, from: groundData)

        // Boundary refine — second AV pass expands truncated continuous actions.
        var refineBody: [String: Any] = [
            "phase": "refine",
            "youtube_url": youtubeURL,
            "recipe_title": recipeTitle,
            "force": bypassServerCache,
            "steps": stepPayload(cookSteps),
            "clips": grounded.clips.map { clip -> [String: Any] in
                [
                    "step_id": clip.stepID,
                    "start_seconds": clip.startSeconds,
                    "end_seconds": clip.endSeconds,
                    "duration_seconds": clip.durationSeconds,
                    "watch_label": clip.watchLabel,
                    "notice": clip.notice,
                    "confidence": clip.confidence,
                    "match_type": clip.matchType,
                ]
            },
        ]
        if let duration = knownDuration(for: youtubeURL) {
            refineBody["duration_seconds"] = duration
        }

        let refinedData = try await postJSON(refineBody)
        let decoded = try JSONDecoder().decode(StepClipIndexResponse.self, from: refinedData)
        saveDisk(cacheKey, decoded)
        return decoded
    }

    func clip(forStepID stepID: String, in response: StepClipIndexResponse) -> StepClip? {
        response.clips.first { $0.stepID == stepID }
    }

    // MARK: - HTTP

    /// Video length, so grounding cannot place a clip past the end.
    ///
    /// Worth more than it looks. Asked to ground the gnocchi video with no entry
    /// here, the model returned windows at 4:17 and 5:19 with confidence 1 on a
    /// video that is 3:56 long. Both would have played nothing. Anything added
    /// to `NativeClipService.localPaths` or shipped as a pilot belongs here too.
    private func knownDuration(for youtubeURL: String) -> Int? {
        switch YouTubeEmbed.videoId(from: youtubeURL) {
        case "gBJjRYk0yC0": return 274
        case "Cyskqnp1j64": return 471
        case "6tSdlo0r0Io": return 481
        case "3sUJwjvmzk8": return 236
        case "hDjK5C2aoSs": return 396
        default: return nil
        }
    }

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

    /// Old pipeline clamped every window to 30s. If every clip is ≤30s while
    /// cook steps look continuous, treat the cache as poisoned.
    private func containsTruncationSmell(_ response: StepClipIndexResponse) -> Bool {
        let clips = response.clips
        guard !clips.isEmpty else { return false }
        let allShort = clips.allSatisfy { $0.durationSeconds <= 30 }
        let anyClassicClamp = clips.contains { $0.startSeconds == 146 && $0.endSeconds == 176 }
            || clips.contains { $0.durationSeconds == 30 && $0.startSeconds >= 140 && $0.startSeconds <= 150 }
        return anyClassicClamp || (allShort && clips.count >= 3)
    }

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
