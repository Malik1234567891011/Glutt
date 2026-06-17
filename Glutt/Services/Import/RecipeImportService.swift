import Foundation

enum ImportError: LocalizedError {
    case invalidURL
    case fetchFailed
    case unreadableImage
    case nothingFound
    case instagramBlocked

    var errorDescription: String? {
        switch self {
        case .invalidURL: "That doesn't look like a valid link."
        case .fetchFailed: "Couldn't load that page. Check the link and your connection."
        case .unreadableImage: "Couldn't read any text from that image."
        case .nothingFound: "Couldn't find a recipe there."
        case .instagramBlocked:
            "Instagram doesn't let apps read captions. Screenshot the caption (or the recipe) and use the screenshot import instead — it works great."
        }
    }
}

/// Orchestrates all import paths: web links, social links, and screenshots.
enum RecipeImportService {

    /// Browser-like user agent — many recipe sites block default URLSession agents.
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    // MARK: - Link import

    static func importFrom(urlString: String) async throws -> ImportedRecipeDraft {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { throw ImportError.invalidURL }
        if components.scheme == nil { components.scheme = "https" }
        guard let url = components.url, url.host != nil else { throw ImportError.invalidURL }
        return try await importFrom(url: url)
    }

    static func importFrom(url: URL) async throws -> ImportedRecipeDraft {
        // Video platforms: the recipe is in the caption/description, which
        // oEmbed serves cleanly. Scraping their HTML gets a JS shell instead.
        if SocialMediaImport.canHandle(url) {
            if let draft = try? await SocialMediaImport.importFrom(url: url),
               draft.title != nil || draft.caption != nil {
                return draft
            }
            // oEmbed failed (private/removed video, region block) —
            // fall through and give the HTML scrape a chance.
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ImportError.fetchFailed
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else {
            throw ImportError.fetchFailed
        }

        let finalURL = http.url ?? url
        let draft = RecipeHTMLParser.parse(html: html, sourceURL: finalURL)

        // Instagram's login wall usually strips every og: tag — if we got
        // literally nothing, say why honestly instead of "no recipe found".
        if draft.platform == .instagram,
           draft.title == nil, draft.ingredientLines.isEmpty,
           (draft.caption ?? "").isEmpty {
            throw ImportError.instagramBlocked
        }
        return draft
    }
}

