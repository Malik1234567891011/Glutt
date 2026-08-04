import Foundation

/// Imports an Instagram post or reel.
///
/// Instagram used to be the one social platform with no importer of its own,
/// left on the generic `og:`-tag scrape. That path has two problems that show up
/// as "the recipe imported with no picture":
///
/// 1. `og:description` is a **truncated** caption, so the recipe text is clipped
///    even when it parses — and food creators put the whole recipe in the caption.
/// 2. `og:image` points at a **signed CDN URL that expires** (measured with an
///    `oe=` expiry about nine days out). Store the URL and the picture dies; the
///    bytes have to be fetched while the signature is still valid.
///
/// The embed route below is a better source for both: it returns the full caption
/// and the media URLs, needs no token, and is stable enough that it's what every
/// embed on the web is built on. The generic scrape stays as the fallback.
enum InstagramImport {

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func canHandle(_ url: URL) -> Bool {
        (url.host ?? "").lowercased().contains("instagram") && shortcode(from: url) != nil
    }

    /// Post shortcode from any of Instagram's permalink shapes: `/p/` for photos
    /// and carousels, `/reel/` and `/reels/` for reels, `/tv/` for the old IGTV
    /// links that still circulate.
    static func shortcode(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        let kinds: Set<String> = ["p", "reel", "reels", "tv"]
        guard let kindIndex = parts.firstIndex(where: { kinds.contains($0.lowercased()) }),
              parts.indices.contains(kindIndex + 1) else { return nil }
        let code = parts[kindIndex + 1]
        guard !code.isEmpty,
              code.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return nil }
        return code
    }

    // MARK: - Import

    static func importFrom(url: URL) async throws -> ImportedRecipeDraft {
        guard let code = shortcode(from: url) else { throw ImportError.nothingFound }
        let html = try await fetchEmbed(shortcode: code)
        guard let parsed = parse(embedHTML: html) else { throw ImportError.nothingFound }
        return draft(from: parsed, sourceURL: url)
    }

    static func draft(from embed: Embed, sourceURL: URL) -> ImportedRecipeDraft {
        let caption = embed.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var draft = caption.count > 40
            ? TextRecipeParser.parse(text: caption)
            : ImportedRecipeDraft()

        if draft.title?.isEmpty != false {
            draft.title = SocialMediaImport.captionTitle(caption)
        }
        draft.caption = caption.isEmpty ? nil : caption
        draft.imageURL = draft.imageURL ?? embed.imageURL
        draft.creator = embed.author
        draft.sourceURL = sourceURL.absoluteString
        draft.platform = .instagram

        if draft.ingredientLines.isEmpty {
            draft.issues.append("The caption didn't include the full recipe")
        }
        return draft
    }

    // MARK: - Embed route

    struct Embed {
        var caption: String?
        var imageURL: String?
        var author: String?
    }

    private static func fetchEmbed(shortcode: String) async throws -> String {
        guard let url = URL(string: "https://www.instagram.com/p/\(shortcode)/embed/captioned/") else {
            throw ImportError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ImportError.fetchFailed
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        else { throw ImportError.fetchFailed }
        return html
    }

    /// The embed page carries the post as an escaped JSON blob in a script tag.
    /// Reaching into it with regexes rather than decoding the whole thing keeps
    /// this resilient to the surrounding structure changing, which it does.
    /// Exposed for tests.
    static func parse(embedHTML html: String) -> Embed? {
        var embed = Embed()
        embed.caption = jsonString(in: html, key: "edge_media_to_caption")
            .flatMap { unescape($0) }
            ?? captionFromMarkup(html)
        embed.imageURL = jsonString(in: html, key: "display_url").flatMap { unescape($0) }
            ?? firstCDNImage(html)
        embed.author = jsonString(in: html, key: "username").flatMap { unescape($0) }

        guard embed.caption != nil || embed.imageURL != nil else { return nil }
        return embed
    }

    /// First `"<key>": "<value>"` string in the blob. For `edge_media_to_caption`
    /// the caption sits a few keys deeper, so that one falls through to the
    /// nested `"text"` immediately after it.
    ///
    /// The blob is JSON serialised into a JSON string inside HTML, so every quote
    /// arrives behind an arbitrary run of backslashes (`\\"key\\":\\"value\\"`
    /// in the wild). Hence `\\*` around each quote rather than a fixed count.
    private static func jsonString(in html: String, key: String) -> String? {
        if key == "edge_media_to_caption" {
            guard let anchor = html.range(of: "edge_media_to_caption") else { return nil }
            let tail = String(html[anchor.upperBound...].prefix(30_000))
            return match(valuePattern(for: "text"), in: tail)
        }
        return match(valuePattern(for: key), in: html)
    }

    private static func valuePattern(for key: String) -> String {
        #"\\*"\#(key)\\*"\s*:\s*\\*"((?:[^"\\]|\\.)*?)\\*""#
    }

    private static func match(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let hit = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(hit.range(at: 1), in: text)
        else { return nil }
        let value = String(text[range])
        return value.isEmpty ? nil : value
    }

    /// The blob is JSON serialised into a JSON string, so values arrive escaped
    /// more than once and the depth isn't fixed: the same URL carries `\u0025`
    /// (escaped once) beside `\\\/` (escaped twice) in one string.
    ///
    /// So decode repeatedly until it stops changing rather than collapsing
    /// backslash runs by hand — halving a run of three leaves a stray escape
    /// behind, which is how `https:\/\/…` reaches the image loader and fails.
    private static func unescape(_ raw: String) -> String? {
        var current = raw
        for _ in 0..<4 {
            guard let decoded = jsonDecoded(current), decoded != current else { break }
            current = decoded
        }
        // A lone `\/` is legal JSON but not a legal escape once the surrounding
        // string has already been consumed, so the last pass can leave it.
        current = current.replacingOccurrences(of: "\\/", with: "/")
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func jsonDecoded(_ value: String) -> String? {
        guard let data = "\"\(value)\"".data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
    }

    /// The embed page also renders the caption as visible text, which survives
    /// when the JSON blob shape moves.
    private static func captionFromMarkup(_ html: String) -> String? {
        guard let raw = match(#"class="Caption"[^>]*>([\s\S]{0,8000}?)</div>"#, in: html) else {
            return nil
        }
        let stripped = raw
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let text = RecipeHTMLParser.decodeEntities(stripped)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func firstCDNImage(_ html: String) -> String? {
        match(#"(https://[^"'\\\s]*cdninstagram\.com[^"'\\\s]*\.jpg[^"'\\\s]*)"#, in: html)
            .flatMap { unescape($0) }
    }
}
