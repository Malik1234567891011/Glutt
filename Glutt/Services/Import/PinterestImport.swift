import Foundation

/// Imports a Pinterest pin.
///
/// Scraping the pin page is not an option: pinterest.com serves a JavaScript
/// shell to plain HTTP clients, with an empty `<title>` and no `og:` tags at all
/// — the same wall TikTok puts up. What it does expose is the API its own web
/// front-end runs on, `/resource/PinResource/get/`, which needs no key, no token
/// and no cookie. Only one header, `x-pinterest-pws-handler`.
///
/// This deliberately runs on the phone rather than through the Vercel proxy.
/// Pinterest rate-limits by IP and is unfriendly to datacenter ranges; the proxy
/// would be a single address shared by every user, which is the shape of request
/// that gets blocked first.
enum PinterestImport {

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func canHandle(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("pinterest") || host == "pin.it" || host.hasSuffix(".pin.it")
    }

    // MARK: - Pin id

    /// Numeric pin id from a pin URL. Handles the country domains
    /// (`pinterest.ca`, `br.pinterest.com`, `pinterest.co.uk`) because the path
    /// shape is identical on all of them, plus the `/pin/<slug>--<id>/` form some
    /// shares still produce.
    ///
    /// Returns nil for `pin.it` short links, which carry no id until redirected,
    /// and for board or profile URLs, which aren't a single recipe.
    static func pinID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let pinIndex = parts.firstIndex(where: { $0.lowercased() == "pin" }),
              parts.indices.contains(pinIndex + 1) else { return nil }
        let candidate = parts[pinIndex + 1]

        if candidate.allSatisfy(\.isNumber), !candidate.isEmpty { return candidate }
        // `/pin/some-recipe-title--1234567890/`
        if let tail = candidate.components(separatedBy: "--").last,
           !tail.isEmpty, tail.allSatisfy(\.isNumber) {
            return tail
        }
        return nil
    }

    static func isShortLink(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host == "pin.it" || host.hasSuffix(".pin.it")
    }

    /// Follows a `pin.it` link to the real pin URL. `URLSession` follows
    /// redirects itself, so the resolved address is on the response.
    private static func resolveShortLink(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response.url ?? url
        } catch {
            throw ImportError.fetchFailed
        }
    }

    // MARK: - Import

    static func importFrom(url: URL) async throws -> ImportedRecipeDraft {
        let resolved = isShortLink(url) ? try await resolveShortLink(url) : url
        guard let id = pinID(from: resolved) else { throw ImportError.pinterestNeedsPin }

        let pin = try await fetchPin(id: id, sourceURL: resolved)

        // A pin that links out to a real recipe site is a signpost, not the
        // recipe. Following it gets JSON-LD with proper ingredients, steps,
        // times and servings — strictly better than any pin description. The
        // pin's own data is the fallback, never the first choice.
        if let outbound = pin.link.flatMap(URL.init(string:)),
           let followed = try? await RecipeImportService.importFrom(url: outbound),
           !followed.ingredientLines.isEmpty {
            var draft = followed
            draft.imageURL = draft.imageURL ?? pin.imageURL
            draft.title = draft.title ?? pin.title
            // Keep the pin as the recorded source: it's what the user shared, and
            // it's what dedup on re-import will compare against.
            draft.sourceURL = resolved.absoluteString
            draft.platform = .pinterest
            return draft
        }

        return draft(from: pin, sourceURL: resolved)
    }

    static func draft(from pin: Pin, sourceURL: URL) -> ImportedRecipeDraft {
        let description = pin.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Food pins routinely paste the whole recipe into the description —
        // measured at ~800 characters with a full ingredient list — which is
        // exactly what TextRecipeParser is for.
        var draft = description.count > 40
            ? TextRecipeParser.parse(text: description)
            : ImportedRecipeDraft()

        // The pin's own title beats anything inferred from the description. A
        // description usually opens with a sentence of marketing copy, so letting
        // the text parser name the recipe gives you "Rich and creamy chicken
        // tikka masala packed with bold Indian spices" instead of the actual name.
        // Used as-is, not through `cleanTitle`. That helper strips a trailing
        // "– Site Name" off an SEO page title, but a pin title is written by the
        // creator, so the same rule eats real words: "Best Ever Chicken Tikka
        // Masala – Better Than Takeout" came back as just "Best Ever Chicken
        // Tikka Masala". The `title` and `grid_title` fields are already clean;
        // it's `seo_title` that carries the keyword junk, and we don't read it.
        if let pinned = pin.title, !pinned.isEmpty {
            draft.title = pinned
        } else if draft.title?.isEmpty != false {
            draft.title = SocialMediaImport.captionTitle(description)
        }
        draft.caption = description.isEmpty ? nil : description
        draft.imageURL = draft.imageURL ?? pin.imageURL
        draft.creator = pin.creator
        draft.sourceURL = sourceURL.absoluteString
        draft.platform = .pinterest

        if draft.ingredientLines.isEmpty {
            draft.issues.append("This pin's description didn't include the full recipe")
        }
        return draft
    }

    // MARK: - Pinterest's web API

    struct Pin {
        var title: String?
        var description: String?
        var imageURL: String?
        var creator: String?
        /// Outbound URL to the original recipe site. Nil for pins uploaded
        /// straight to Pinterest.
        var link: String?
    }

    private static func fetchPin(id: String, sourceURL: URL) async throws -> Pin {
        let options: [String: Any] = ["id": id, "field_set_key": "auth_web_main_pin"]
        let payload: [String: Any] = ["options": options, "context": [:]]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let bodyString = String(data: body, encoding: .utf8)
        else { throw ImportError.fetchFailed }

        var components = URLComponents(string: "https://www.pinterest.com/resource/PinResource/get/")!
        components.queryItems = [
            URLQueryItem(name: "source_url", value: "/pin/\(id)/"),
            URLQueryItem(name: "data", value: bodyString),
        ]
        guard let endpoint = components.url else { throw ImportError.fetchFailed }

        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The one header Pinterest actually checks.
        request.setValue("www/index.js", forHTTPHeaderField: "x-pinterest-pws-handler")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ImportError.fetchFailed
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportError.fetchFailed
        }
        guard let pin = parsePin(json: data) else { throw ImportError.nothingFound }
        return pin
    }

    /// Maps the `PinResource` payload onto `Pin`. Hand-rolled rather than
    /// `Decodable` because the response is a few hundred loosely-typed fields
    /// that change without notice, and we want five of them.
    /// Exposed for tests.
    static func parsePin(json: Data) -> Pin? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let response = root["resource_response"] as? [String: Any],
              let data = response["data"] as? [String: Any]
        else { return nil }

        var pin = Pin()
        pin.title = firstNonEmpty(data, ["title", "grid_title", "closeup_unified_title"])
        pin.description = firstNonEmpty(
            data, ["closeup_unified_description", "description", "closeup_description"])
        pin.imageURL = bestImageURL(data["images"])
        pin.link = firstNonEmpty(data, ["link"])

        if let pinner = data["pinner"] as? [String: Any] ?? data["origin_pinner"] as? [String: Any] {
            pin.creator = firstNonEmpty(pinner, ["full_name", "username"])
        }

        guard pin.title != nil || pin.description != nil || pin.imageURL != nil else { return nil }
        return pin
    }

    private static func firstNonEmpty(_ object: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// Widest available rendition. `images` is a dictionary keyed by size name
    /// ("236x", "1200x", "orig"), each with a url and often width/height. `orig`
    /// usually omits width, so it's preferred explicitly rather than by measure.
    static func bestImageURL(_ value: Any?) -> String? {
        guard let sizes = value as? [String: Any] else { return nil }

        func url(_ key: String) -> String? {
            guard let entry = sizes[key] as? [String: Any] else { return nil }
            return (entry["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let original = url("orig"), !original.isEmpty { return original }

        let widest = sizes.compactMap { key, value -> (Int, String)? in
            guard let entry = value as? [String: Any],
                  let link = entry["url"] as? String, !link.isEmpty else { return nil }
            let width = (entry["width"] as? Int) ?? Int(key.prefix { $0.isNumber }) ?? 0
            return (width, link)
        }
        .max { $0.0 < $1.0 }
        return widest?.1
    }
}
