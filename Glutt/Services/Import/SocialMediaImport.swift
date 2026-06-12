import Foundation

/// Imports from video platforms, where the recipe lives in the caption or
/// description — not in page markup.
///
/// Why not scrape the page like we do for websites? tiktok.com serves a
/// JavaScript app shell (or a bot wall) to plain HTTP clients: there is no
/// recipe in the HTML at all. The official oEmbed endpoints, however, are
/// public, keyless, and return exactly what we need: the full caption,
/// the creator's name, and a thumbnail.
enum SocialMediaImport {

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    struct OEmbed: Decodable {
        let title: String?
        let authorName: String?
        let thumbnailUrl: String?

        enum CodingKeys: String, CodingKey {
            case title
            case authorName = "author_name"
            case thumbnailUrl = "thumbnail_url"
        }
    }

    /// TikTok and YouTube have public oEmbed. Instagram's requires a Meta
    /// app token, so it stays on the HTML-scrape + AI path.
    static func canHandle(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("tiktok") || host.contains("youtube") || host.contains("youtu.be")
    }

    static func importFrom(url: URL) async throws -> ImportedRecipeDraft {
        let host = (url.host ?? "").lowercased()
        if host.contains("tiktok") {
            return try await importTikTok(url: url)
        }
        return try await importYouTube(url: url)
    }

    // MARK: - TikTok

    /// oEmbed `title` is the full video caption — many food creators paste
    /// the entire recipe there. Works for vm.tiktok.com short links too.
    private static func importTikTok(url: URL) async throws -> ImportedRecipeDraft {
        let oembed = try await fetchOEmbed(endpoint: "https://www.tiktok.com/oembed", target: url)
        let caption = oembed.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var draft = caption.count > 40
            ? TextRecipeParser.parse(text: caption)
            : ImportedRecipeDraft()

        if draft.title?.isEmpty != false {
            draft.title = captionTitle(caption)
        }
        draft.caption = caption.isEmpty ? nil : caption
        draft.creator = oembed.authorName
        draft.imageURL = draft.imageURL ?? oembed.thumbnailUrl
        draft.sourceURL = url.absoluteString
        draft.platform = .tiktok

        if draft.ingredientLines.isEmpty {
            draft.issues.append("The caption didn't include the full recipe")
        }
        return draft
    }

    // MARK: - YouTube

    /// oEmbed gives identity (title/creator/thumbnail) but not the
    /// description — and the description is where recipes are pasted. The
    /// watch page embeds it as `"shortDescription"` in player JSON.
    private static func importYouTube(url: URL) async throws -> ImportedRecipeDraft {
        let description = try? await fetchYouTubeDescription(url: url)

        var draft: ImportedRecipeDraft
        if let description, description.count > 40 {
            draft = TextRecipeParser.parse(text: description)
            draft.caption = description
        } else {
            draft = ImportedRecipeDraft()
        }

        if let oembed = try? await fetchOEmbed(endpoint: "https://www.youtube.com/oembed", target: url) {
            if let videoTitle = oembed.title {
                draft.title = RecipeHTMLParser.cleanTitle(videoTitle)
            }
            draft.creator = oembed.authorName
            draft.imageURL = oembed.thumbnailUrl ?? draft.imageURL
        }

        draft.sourceURL = url.absoluteString
        draft.platform = .youtube

        guard draft.title != nil || draft.caption != nil else {
            throw ImportError.nothingFound
        }
        if draft.ingredientLines.isEmpty {
            draft.issues.append("The video description didn't include the full recipe")
        }
        return draft
    }

    private static func fetchYouTubeDescription(url: URL) async throws -> String? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8)
        else { return nil }
        return extractYouTubeDescription(html: html)
    }

    /// Pulls the full video description out of the watch page's embedded
    /// player JSON. Exposed for tests.
    static func extractYouTubeDescription(html: String) -> String? {
        let pattern = #""shortDescription"\s*:\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html)
        else { return nil }

        // The capture is a JSON string body; let JSONSerialization unescape it.
        let quoted = "\"\(html[range])\""
        guard let data = quoted.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
        else { return nil }

        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Shared

    private static func fetchOEmbed(endpoint: String, target: URL) async throws -> OEmbed {
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "url", value: target.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ImportError.fetchFailed
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportError.fetchFailed
        }
        return try JSONDecoder().decode(OEmbed.self, from: data)
    }

    /// First caption line, minus hashtags and @mentions, capped for a title.
    /// Exposed for tests.
    static func captionTitle(_ caption: String) -> String? {
        let firstLine = caption.components(separatedBy: .newlines).first ?? caption
        let words = firstLine.split(separator: " ").filter {
            !$0.hasPrefix("#") && !$0.hasPrefix("@")
        }
        var title = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        if title.count > 70 {
            title = String(title.prefix(70))
            if let lastSpace = title.lastIndex(of: " ") {
                title = String(title[..<lastSpace])
            }
            title += "…"
        }
        return title
    }
}
