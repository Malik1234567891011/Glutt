import Foundation

/// Extracts a stable platform media id from a recipe `sourceURL`.
/// Used to look up native clip pilots (YouTube + TikTok for now).
enum MediaSourceID {
    static func from(sourceURL: String) -> String? {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let yt = YouTubeEmbed.videoId(from: trimmed) { return yt }
        return tiktokVideoId(from: trimmed)
    }

    /// `https://www.tiktok.com/@user/video/7333…` or `/video/7333…` paths.
    /// Short `vt.tiktok.com/XXXX` links are not numeric — store the canonical
    /// `/video/<id>` URL on the recipe after ingest resolve.
    static func tiktokVideoId(from urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString),
              let host = comps.host?.lowercased(),
              host.contains("tiktok.com") else { return nil }
        let parts = comps.path.split(separator: "/").map(String.init)
        if let idx = parts.firstIndex(of: "video"), parts.indices.contains(idx + 1) {
            let id = parts[idx + 1]
            if id.allSatisfy(\.isNumber) { return id }
        }
        return nil
    }
}
