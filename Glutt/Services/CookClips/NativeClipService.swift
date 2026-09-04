import Foundation

/// Fetches native step clips for Polly by media `external_id` (YouTube / TikTok).
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

    /// Optional local playback paths when `mediaPlaybackBaseURL` is set (dev only).
    private static let localPaths: [String: String] = [
        "gBJjRYk0yC0": "/v1/pilot/eggs-benedict",
        "Cyskqnp1j64": "/v1/pilot/beef-wellington",
        "6tSdlo0r0Io": "/v1/pilot/creme-brulee",
        "7333706662634704161": "/v1/pilot/tiktok-scrambled-eggs",
        "3sUJwjvmzk8": "/v1/pilot/gnocchi-brown-butter",
        "hDjK5C2aoSs": "/v1/pilot/butter-chicken",
    ]

    /// v2: v1 entries held signed URLs with no expiry and are not salvageable.
    /// Bump whenever a pilot's segments change in ANY way the app reads, not
    /// only when the URL shape does. That includes `step_keywords` and
    /// `visual_cue`: assignment is computed FROM those, so a stale entry is not
    /// a stale caption, it is the wrong video on the wrong step. A phone holding
    /// an old entry once matched "minutes" in a boil step against a garlic
    /// segment's keywords and played the garlic clip there.
    ///
    /// The rule was then learned twice more on the same dish. v3: the gnocchi
    /// pilot gained a segment, the pan coming up to heat, and cached v2
    /// responses kept serving the old list, so the pan-test step went on
    /// borrowing the frying clip. v4: boil and lift merged into one clip, a
    /// cached v3 still held the separate lift segment, and the merged step
    /// matched that instead, so "boil the gnocchi, then lift them out" played a
    /// slotted spoon over a step that now uses a sieve.
    private func cacheKey(for mediaID: String) -> String {
        "glutt.nativeClips.\(mediaID).v4"
    }

    /// Re-sign this long before the URLs lapse — a cook can sit on one step for
    /// a while, and a clip that 403s mid-session looks like the feature broke.
    private static let signatureSafetyMargin: TimeInterval = 10 * 60
    private static let fallbackTTL: TimeInterval = 55 * 60

    private struct CachedClips: Codable {
        var fetchedAt: Date
        var expiresIn: Double?
        var response: NativePilotClipsResponse
    }

    /// Fetch clips for any media id. Throws on network/404 — caller falls back.
    func clips(forMediaID mediaID: String, force: Bool = false) async throws -> NativePilotClipsResponse {
        let key = cacheKey(for: mediaID)
        if !force, let cached = loadCache(key: key) { return cached }

        // The local media-worker is a dev convenience, not a dependency.
        //
        // This used to `try` straight out of the function, so a laptop that had
        // changed Wi-Fi, gone to sleep, or simply been closed did not fall back
        // to the proxy: it threw, and the caller's only remaining option was the
        // YouTube path. That is a real cook watching a worse version of the
        // feature because a machine they do not own moved network. Prefer local,
        // then the proxy, and only then let the caller reach for YouTube.
        if let local = localBaseURL, let path = Self.localPaths[mediaID] {
            do {
                let decoded = try await fetchLocalPilot(base: local, path: path)
                let rewritten = rewriteLocalhostURLs(in: decoded, using: local)
                saveCache(rewritten, key: key)
                return rewritten
            } catch {
                PollyDebugLog.shared.log(
                    "clips: local media-worker unreachable (\(error.localizedDescription)) — trying the proxy")
            }
        }

        let decoded = try await fetchProxyClips(externalID: mediaID)
        // Never cache an empty pilot — a transient 200/empty (or a bad deploy)
        // would pin "no clips" until the app was deleted.
        if !decoded.clips.isEmpty {
            saveCache(decoded, key: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        return decoded
    }

    /// Back-compat name used by Polly session.
    func pilotClips(mediaID: String, force: Bool = false) async throws -> NativePilotClipsResponse {
        try await clips(forMediaID: mediaID, force: force)
    }

    func pilotClips(youtubeID: String, force: Bool = false) async throws -> NativePilotClipsResponse {
        try await clips(forMediaID: youtubeID, force: force)
    }

    func eggsBenedictPilot(force: Bool = false) async throws -> NativePilotClipsResponse {
        try await clips(forMediaID: "gBJjRYk0yC0", force: force)
    }

    /// Always true when we have a media id — proxy may still 404 until ready.
    static func supportsPilot(mediaID: String) -> Bool {
        !mediaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func supportsPilot(youtubeID: String) -> Bool {
        supportsPilot(mediaID: youtubeID)
    }

    /// Score keyword hits — longer / more specific tokens win.
    /// Word-boundary matching avoids "seared"→sear and "unwrap"→wrap.
    ///
    /// - Parameter excluding: segment ids already given to another step. Without
    ///   this, shared words ("vanilla", "cream", "sugar", "custard") make the
    ///   same clip win for three steps in a row on desserts like Crème Brûlée.
    func clipMatching(
        stepTitle: String,
        instruction: String,
        in response: NativePilotClipsResponse,
        excluding: Set<String> = []
    ) -> NativeStepClip? {
        let hay = "\(stepTitle) \(instruction)".lowercased()
        var best: (clip: NativeStepClip, score: Int)?
        let bonus = [
            "muffin", "toast", "hollandaise", "poach", "parma", "prosciutto", "bacon",
            "sear", "fillet", "mustard", "horseradish", "mushroom", "duxelle", "pastry", "puff",
            "wellington", "wrap", "score", "egg wash",
            "crack", "cold", "stir", "custard", "creme", "fraiche", "chive", "scramble",
            "torch", "brulee", "ramekin", "vanilla", "caramel", "water bath",
        ]
        for clip in response.clips {
            guard !excluding.contains(clip.segmentID) else { continue }
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

    /// One clip per cook step, never reused. Keyword match first (skipping
    /// already-taken segments), then fill gaps from leftover clips in pilot order.
    func assignClips(
        to cookSteps: [(id: String, title: String, instruction: String)],
        from response: NativePilotClipsResponse,
        pinned: [String: String] = [:]
    ) -> [String: NativeStepClip] {
        var map: [String: NativeStepClip] = [:]
        var used = Set<String>()

        // A plan that names its clips is not a hint, it is the answer.
        //
        // Keyword scoring is what you do when nobody knows the pairing. For a
        // bundled dish somebody does, and letting the scorer overrule them costs
        // exactly what it cost here: the word "minutes" in the boil step outscored
        // "float", the boil step played the garlic clip, and the garlic step
        // played nothing. So when any step is pinned the whole plan is treated as
        // specified — an unpinned step plays nothing rather than being handed a
        // leftover, and a pinned step whose segment is missing plays nothing
        // rather than the next best guess.
        if !pinned.isEmpty {
            let bySegment = Dictionary(
                response.clips.map { ($0.segmentID, $0) }, uniquingKeysWith: { first, _ in first })
            for step in cookSteps {
                guard let wanted = pinned[step.id], let clip = bySegment[wanted] else { continue }
                guard used.insert(clip.segmentID).inserted else {
                    PollyDebugLog.shared.log(
                        "clips: step \(step.id) pinned to \(wanted), already used — left empty")
                    continue
                }
                map[step.id] = clip
            }
            return map
        }

        for step in cookSteps {
            guard let clip = clipMatching(
                stepTitle: step.title,
                instruction: step.instruction,
                in: response,
                excluding: used
            ) else { continue }
            map[step.id] = clip
            used.insert(clip.segmentID)
        }
        // A step with no keyword match gets NO clip.
        //
        // This used to hand every leftover clip to every unmatched step in list
        // order, on the theory that an unused clip is a waste. It is not: the
        // canvas plays the assigned clip full screen AND shows that clip's
        // `visual_cue` as the step's description, so a wrong assignment is not a
        // slightly-off illustration, it is a step that shows the wrong video and
        // reads as the wrong instruction. "Water on" was being taught to look
        // for garlic that is "pale gold at the edges and must not go brown".
        //
        // Some steps genuinely have nothing to show. Filling a pan with water is
        // one. Silence is the correct output.
        return map
    }

    private func hayContainsKeyword(_ hay: String, _ key: String) -> Bool {
        if key.contains(" ") { return hay.contains(key) }
        let escaped = NSRegularExpression.escapedPattern(for: key)
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
            clips: clips,
            expiresIn: response.expiresIn
        )
    }

    private func loadCache(key: String) -> NativePilotClipsResponse? {
        guard let data = defaults.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedClips.self, from: data) else { return nil }
        // Playback URLs are signed and short-lived, so a cache hit past their
        // lifetime hands back links that 403. Drop it and re-sign.
        let ttl = cached.expiresIn ?? Self.fallbackTTL
        let usableFor = max(60, ttl - Self.signatureSafetyMargin)
        guard Date.now.timeIntervalSince(cached.fetchedAt) < usableFor else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return cached.response
    }

    private func saveCache(_ value: NativePilotClipsResponse, key: String) {
        let envelope = CachedClips(fetchedAt: .now, expiresIn: value.expiresIn, response: value)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        defaults.set(data, forKey: key)
    }
}
