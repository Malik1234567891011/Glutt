import Foundation

/// Fetches native (downloaded) step clips for Polly.
/// Pilot: local media-worker playback server; later: signed Stream via proxy.
actor NativeClipService {
    static let shared = NativeClipService()

    /// Simulator → Mac host. Override with Secrets `mediaPlaybackBaseURL` when set.
    var baseURL: String = {
        if let override = Secrets.mediaPlaybackBaseURL, !override.isEmpty {
            return override.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:8791"
        #else
        // Device: set Secrets.mediaPlaybackBaseURL to your Mac LAN IP while piloting.
        return "http://127.0.0.1:8791"
        #endif
    }()

    private let defaults = UserDefaults.standard

    /// Known local-pilot YouTube ids → playback path + cache key.
    private static let pilots: [String: (path: String, cacheKey: String)] = [
        "gBJjRYk0yC0": ("/v1/pilot/eggs-benedict", "glutt.nativeClips.eggsBenedict.v7"),
        "Cyskqnp1j64": ("/v1/pilot/beef-wellington", "glutt.nativeClips.beefWellington.v1"),
    ]

    func pilotClips(youtubeID: String, force: Bool = false) async throws -> NativePilotClipsResponse {
        guard let pilot = Self.pilots[youtubeID] else {
            throw NSError(domain: "NativeClipService", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "no local pilot for youtube id \(youtubeID)",
            ])
        }
        if !force, let cached = loadCache(key: pilot.cacheKey) { return cached }
        guard let url = URL(string: "\(baseURL)\(pilot.path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "NativeClipService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "native clips unavailable",
            ])
        }
        let decoded = try JSONDecoder().decode(NativePilotClipsResponse.self, from: data)
        saveCache(decoded, key: pilot.cacheKey)
        return decoded
    }

    /// Back-compat for Eggs Benedict call sites / tests.
    func eggsBenedictPilot(force: Bool = false) async throws -> NativePilotClipsResponse {
        try await pilotClips(youtubeID: "gBJjRYk0yC0", force: force)
    }

    static func supportsPilot(youtubeID: String) -> Bool {
        pilots[youtubeID] != nil
    }

    /// Score keyword hits — longer / more specific tokens win.
    /// Avoids "keep warm" matching a ham clip via the weak keyword "warm".
    func clipMatching(stepTitle: String, instruction: String, in response: NativePilotClipsResponse) -> NativeStepClip? {
        let hay = "\(stepTitle) \(instruction)".lowercased()
        var best: (clip: NativeStepClip, score: Int)?
        let bonus = [
            "muffin", "toast", "hollandaise", "poach", "parma", "prosciutto", "bacon",
            "sear", "fillet", "mustard", "mushroom", "duxelle", "pastry", "puff",
            "wellington", "wrap", "score",
        ]
        for clip in response.clips {
            var score = 0
            for raw in clip.stepKeywords {
                let key = raw.lowercased()
                guard key.count >= 4, hay.contains(key) else { continue }
                score += key.count
                if bonus.contains(key) { score += 10 }
            }
            if score > 0, best == nil || score > best!.score {
                best = (clip, score)
            }
        }
        return best?.clip
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
