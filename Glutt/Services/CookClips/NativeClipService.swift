import Foundation

/// Fetches native step clips for Polly.
/// Production: signed progressive MP4s from Supabase Storage via the AI proxy.
/// Optional local override: Secrets `mediaPlaybackBaseURL` → media-worker serve-local.
actor NativeClipService {
    static let shared = NativeClipService()

    /// When set, prefer the local media-worker (simulator / LAN pilot).
    private var localBaseURL: String? = {
        guard let override = Secrets.mediaPlaybackBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !override.isEmpty else { return nil }
        return override.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }()

    private var proxyBaseURL: String {
        Secrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var proxyClientKey: String {
        Secrets.aiProxyClientKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let defaults = UserDefaults.standard

    /// Known pilot media ids (YouTube / TikTok) → local path (dev) + cache key.
    private static let pilots: [String: (localPath: String, cacheKey: String)] = [
        "gBJjRYk0yC0": ("/v1/pilot/eggs-benedict", "glutt.nativeClips.eggsBenedict.v9"),
        "Cyskqnp1j64": ("/v1/pilot/beef-wellington", "glutt.nativeClips.beefWellington.v5"),
        "7333706662634704161": ("/v1/pilot/tiktok-scrambled-eggs", "glutt.nativeClips.ttScramble.v3"),
    ]

    func pilotClips(mediaID: String, force: Bool = false) async throws -> NativePilotClipsResponse {
        guard let pilot = Self.pilots[mediaID] else {
            throw NSError(domain: "NativeClipService", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "no pilot for media id \(mediaID)",
            ])
        }
        if !force, let cached = loadCache(key: pilot.cacheKey) { return cached }

        let decoded: NativePilotClipsResponse
        if let local = localBaseURL {
            decoded = try await fetchLocalPilot(base: local, path: pilot.localPath)
            let rewritten = rewriteLocalhostURLs(in: decoded, using: local)
            saveCache(rewritten, key: pilot.cacheKey)
            return rewritten
        }

        decoded = try await fetchProxyClips(externalID: mediaID)
        saveCache(decoded, key: pilot.cacheKey)
        return decoded
    }

    /// Back-compat name — media id may be YouTube or TikTok.
    func pilotClips(youtubeID: String, force: Bool = false) async throws -> NativePilotClipsResponse {
        try await pilotClips(mediaID: youtubeID, force: force)
    }

    /// Back-compat for Eggs Benedict call sites / tests.
    func eggsBenedictPilot(force: Bool = false) async throws -> NativePilotClipsResponse {
        try await pilotClips(mediaID: "gBJjRYk0yC0", force: force)
    }

    static func supportsPilot(mediaID: String) -> Bool {
        pilots[mediaID] != nil
    }

    /// Back-compat alias.
    static func supportsPilot(youtubeID: String) -> Bool {
        supportsPilot(mediaID: youtubeID)
    }

    /// Score keyword hits — longer / more specific tokens win.
    /// Word-boundary matching avoids "seared"→sear and "unwrap"→wrap.
    func clipMatching(stepTitle: String, instruction: String, in response: NativePilotClipsResponse) -> NativeStepClip? {
        let hay = "\(stepTitle) \(instruction)".lowercased()
        var best: (clip: NativeStepClip, score: Int)?
        let bonus = [
            "muffin", "toast", "hollandaise", "poach", "parma", "prosciutto", "bacon",
            "sear", "fillet", "mustard", "horseradish", "mushroom", "duxelle", "pastry", "puff",
            "wellington", "wrap", "score", "egg wash",
            "crack", "cold", "stir", "custard", "creme", "fraiche", "chive", "scramble",
        ]
        for clip in response.clips {
            var score = 0
            for raw in clip.stepKeywords {
                let key = raw.lowercased()
                guard key.count >= 4, hayContainsKeyword(hay, key) else { continue }
                score += key.count
                if bonus.contains(key) { score += 10 }
            }
            if score > 0, best == nil || score > best!.score {
                best = (clip, score)
            }
        }
        return best?.clip
    }

    /// Phrase or token match with word boundaries (spaces/punctuation).
    /// "sear" → "sear the fillet" yes; "seared" no.
    /// "mushroom" → "mushrooms" yes (simple plural).
    /// "wrap" → "unwrap" no (left boundary).
    private func hayContainsKeyword(_ hay: String, _ key: String) -> Bool {
        if key.contains(" ") { return hay.contains(key) }
        let escaped = NSRegularExpression.escapedPattern(for: key)
        // Optional plural s/es only — not arbitrary suffixes like "ed".
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![a-z0-9])\(escaped)(?:es|s)?(?![a-z0-9])",
            options: []
        ) else {
            return hay.contains(key)
        }
        let range = NSRange(hay.startIndex..<hay.endIndex, in: hay)
        return regex.firstMatch(in: hay, options: [], range: range) != nil
    }

    // MARK: - Network

    private func fetchProxyClips(externalID: String) async throws -> NativePilotClipsResponse {
        guard !proxyBaseURL.isEmpty, !proxyClientKey.isEmpty else {
            throw NSError(domain: "NativeClipService", code: 503, userInfo: [
                NSLocalizedDescriptionKey: "AI proxy not configured (need Secrets.local.plist)",
            ])
        }
        guard var comps = URLComponents(string: "\(proxyBaseURL)/media/clips") else {
            throw URLError(.badURL)
        }
        comps.queryItems = [URLQueryItem(name: "external_id", value: externalID)]
        guard let url = comps.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(proxyClientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "NativeClipService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "native clips unavailable",
            ])
        }
        return try JSONDecoder().decode(NativePilotClipsResponse.self, from: data)
    }

    private func fetchLocalPilot(base: String, path: String) async throws -> NativePilotClipsResponse {
        guard let url = URL(string: "\(base)\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "NativeClipService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "local native clips unavailable",
            ])
        }
        return try JSONDecoder().decode(NativePilotClipsResponse.self, from: data)
    }

    private func rewriteLocalhostURLs(in response: NativePilotClipsResponse, using base: String) -> NativePilotClipsResponse {
        guard let baseURL = URL(string: base), let host = baseURL.host, host != "127.0.0.1", host != "localhost" else {
            return response
        }
        func rewrite(_ url: URL?) -> URL? {
            guard let url, let uhost = url.host, uhost == "127.0.0.1" || uhost == "localhost" else { return url }
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.host = host
            comps?.port = baseURL.port
            comps?.scheme = baseURL.scheme
            return comps?.url ?? url
        }
        let clips = response.clips.map { c in
            NativeStepClip(
                segmentID: c.segmentID,
                startSeconds: c.startSeconds,
                endSeconds: c.endSeconds,
                durationSeconds: c.durationSeconds,
                watchLabel: c.watchLabel,
                teachingLabel: c.teachingLabel,
                notice: c.notice,
                visualCue: c.visualCue,
                stepKeywords: c.stepKeywords,
                presentationMode: c.presentationMode,
                playbackURL: rewrite(c.playbackURL) ?? c.playbackURL,
                thumbnailURL: rewrite(c.thumbnailURL),
                masterURL: rewrite(c.masterURL),
                usesVirtualRange: c.usesVirtualRange,
                creatorAttribution: c.creatorAttribution
            )
        }
        return NativePilotClipsResponse(
            sourceAssetID: response.sourceAssetID,
            status: response.status,
            durationSeconds: response.durationSeconds,
            title: response.title,
            clips: clips
        )
    }

    private func loadCache(key: String) -> NativePilotClipsResponse? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NativePilotClipsResponse.self, from: data)
    }

    private func saveCache(_ value: NativePilotClipsResponse, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
