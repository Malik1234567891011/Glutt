import Foundation

/// Imports recipes from Reddit posts (r/recipes and friends).
///
/// New Reddit serves a JS shell to plain scrapers, so we never parse the HTML
/// app. Instead we:
/// 1. Resolve short links (`redd.it`) and require a concrete `/comments/{id}` post
/// 2. Fetch the post (+ top comments) as JSON — on-device first, then the Glutt
///    proxy, then the public PullPush archive as a last resort
/// 3. Run `TextRecipeParser` on title + selftext + promising comments
/// 4. If the post is mostly a link out to a recipe site / YouTube, follow that URL
enum RedditImport {

    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    /// Descriptive UA — Reddit asks for `platform:appid:version (by /u/name)`.
    private static let redditUserAgent =
        "ios:com.omarlahmimi.glutt:v1.1 (by /u/GluttApp)"

    private static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    // MARK: - Public

    static func canHandle(_ url: URL) -> Bool {
        isRedditHost(url.host)
    }

    static func importFrom(
        url: URL,
        transport: Transport = { try await URLSession.shared.data(for: $0) },
        followExternal: ((URL) async throws -> ImportedRecipeDraft)? = nil
    ) async throws -> ImportedRecipeDraft {
        let resolved = try await resolveRedirects(url, transport: transport)
        switch classify(resolved) {
        case .subreddit, .other:
            throw ImportError.redditNeedsPost
        case .post:
            break
        }

        guard let postID = postID(from: resolved) else {
            throw ImportError.redditNeedsPost
        }

        let payload = try await fetchPayload(
            postID: postID,
            postURL: resolved,
            transport: transport
        )
        var draft = draft(from: payload, sourceURL: resolved)

        // Link / image posts often put the real recipe on an external page.
        if draft.ingredientLines.isEmpty,
           let external = externalRecipeURL(from: payload) {
            let follower = followExternal ?? defaultFollowExternal
            if let linked = try? await follower(external),
               linked.title != nil || !linked.ingredientLines.isEmpty || linked.caption != nil {
                draft = mergeExternal(into: draft, linked: linked, external: external)
            }
        }

        if draft.title == nil, draft.caption == nil, draft.ingredientLines.isEmpty {
            throw ImportError.nothingFound
        }
        if draft.ingredientLines.isEmpty {
            draft.issues.append("Couldn't find a clear ingredient list in the Reddit post")
        }
        return draft
    }

    // MARK: - URL helpers (testable)

    static func isRedditHost(_ host: String?) -> Bool {
        let h = (host ?? "").lowercased()
        return h == "redd.it"
            || h.hasSuffix(".redd.it")
            || h == "reddit.com"
            || h.hasSuffix(".reddit.com")
    }

    enum URLKind: Equatable {
        case post
        case subreddit
        case other
    }

    /// `/r/{sub}/comments/{id}/…` → post; `/r/{sub}` (hot/new/…) → subreddit.
    static func classify(_ url: URL) -> URLKind {
        guard isRedditHost(url.host) else { return .other }
        let path = url.path.lowercased()
        if path.contains("/comments/") { return .post }
        // Short links are posts even before redirect resolution.
        let host = (url.host ?? "").lowercased()
        if (host == "redd.it" || host.hasSuffix(".redd.it")), postID(from: url) != nil {
            return .post
        }
        // /r/recipes, /r/recipes/, /r/recipes/hot, /r/recipes/top/?t=week
        if path.range(of: #"^/r/[^/]+(?:/(?:hot|new|top|rising|best|controversial))?(?:/)?$"#,
                      options: .regularExpression) != nil {
            return .subreddit
        }
        if path.hasPrefix("/r/") { return .subreddit }
        return .other
    }

    static func postID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        // ["r", "{sub}", "comments", "{id}", …] or short /comments/{id}
        if let idx = parts.firstIndex(of: "comments"), parts.index(after: idx) < parts.endIndex {
            let id = parts[parts.index(after: idx)]
            if id.range(of: #"^[a-z0-9]+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return id.lowercased()
            }
        }
        // redd.it/{id}
        if (url.host ?? "").lowercased().hasSuffix("redd.it"),
           let first = parts.first,
           first.range(of: #"^[a-z0-9]+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return first.lowercased()
        }
        return nil
    }

    static func jsonURL(forPost url: URL) -> URL? {
        guard classify(url) == .post else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = (components?.host ?? "www.reddit.com").lowercased()
            .replacingOccurrences(of: "old.", with: "www.")
            .replacingOccurrences(of: "np.", with: "www.")
            .replacingOccurrences(of: "amp.", with: "www.")
            .replacingOccurrences(of: "m.", with: "www.")
        components?.host = host.hasPrefix("www.") ? host : "www.reddit.com"
        components?.scheme = "https"
        components?.query = nil
        components?.fragment = nil
        var path = components?.path ?? url.path
        if path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix(".json") { path += ".json" }
        components?.path = path
        components?.queryItems = [URLQueryItem(name: "raw_json", value: "1")]
        return components?.url
    }

    // MARK: - Payload → draft (testable)

    struct Comment: Equatable {
        var author: String
        var body: String
        var score: Int
        var isSubmitter: Bool
        var stickied: Bool
    }

    struct Payload: Equatable {
        var title: String
        var author: String
        var selftext: String
        var permalink: String
        var url: String
        var isSelf: Bool
        var imageURL: String?
        var subreddit: String?
        var comments: [Comment]
    }

    static func draft(from payload: Payload, sourceURL: URL) -> ImportedRecipeDraft {
        let text = recipeText(from: payload)
        var draft = text.count > 40
            ? TextRecipeParser.parse(text: text)
            : ImportedRecipeDraft()

        let cleanedTitle = RecipeHTMLParser.cleanTitle(payload.title)
        if draft.title?.isEmpty != false || (draft.title?.count ?? 0) < 4 {
            draft.title = cleanedTitle.isEmpty ? nil : cleanedTitle
        }
        draft.caption = text.isEmpty ? nil : text
        draft.creator = payload.author.isEmpty || payload.author == "[deleted]"
            ? nil
            : "u/\(payload.author)"
        draft.imageURL = draft.imageURL ?? payload.imageURL
        draft.sourceURL = sourceURL.absoluteString
        draft.platform = .reddit
        if let sub = payload.subreddit, !sub.isEmpty {
            draft.tags = Array(Set(draft.tags + ["reddit", "r/\(sub)"])).sorted()
        }
        return draft
    }

    /// Title + selftext, then stickied / OP / high-scoring comments that look
    /// like they contain the recipe (common when the post is just a photo).
    static func recipeText(from payload: Payload) -> String {
        var chunks: [String] = []
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = sanitizedBody(payload.selftext)
        if !title.isEmpty { chunks.append(title) }
        if !body.isEmpty { chunks.append(body) }

        let candidates = payload.comments
            .map { ($0, sanitizedBody($0.body)) }
            .filter { !$0.1.isEmpty && $0.1.count >= 80 }
            .filter { looksLikeRecipeText($0.1) }
            .sorted { lhs, rhs in
                scoreComment(lhs.0) > scoreComment(rhs.0)
            }

        for (comment, text) in candidates.prefix(3) {
            let who = comment.isSubmitter ? "OP" : "comment"
            chunks.append("[\(who)]\n\(text)")
        }
        return chunks.joined(separator: "\n\n")
    }

    static func payload(fromRedditListing data: Data) throws -> Payload {
        // Post pages return [listing_posts, listing_comments].
        // Some endpoints return a single listing.
        let root = try JSONSerialization.jsonObject(with: data)
        let listings: [[String: Any]]
        if let array = root as? [Any] {
            listings = array.compactMap { $0 as? [String: Any] }
        } else if let one = root as? [String: Any] {
            listings = [one]
        } else {
            throw ImportError.fetchFailed
        }

        guard let postListing = listings.first,
              let postData = postListing["data"] as? [String: Any],
              let children = postData["children"] as? [[String: Any]],
              let first = children.first,
              let post = first["data"] as? [String: Any]
        else {
            throw ImportError.nothingFound
        }

        var comments: [Comment] = []
        if listings.count > 1,
           let commentListing = listings[1]["data"] as? [String: Any],
           let commentChildren = commentListing["children"] as? [[String: Any]] {
            comments = flattenComments(commentChildren, limit: 25)
        }

        return payload(fromPostDict: post, comments: comments)
    }

    static func payload(fromProxyJSON data: Data) throws -> Payload {
        // Normalized shape from /api/import/reddit
        struct WireComment: Decodable {
            var author: String?
            var body: String?
            var score: Int?
            var is_submitter: Bool?
            var stickied: Bool?
        }
        struct Wire: Decodable {
            var title: String?
            var author: String?
            var selftext: String?
            var permalink: String?
            var url: String?
            var is_self: Bool?
            var image_url: String?
            var subreddit: String?
            var comments: [WireComment]?
        }
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        guard let title = wire.title, !title.isEmpty else { throw ImportError.nothingFound }
        return Payload(
            title: title,
            author: wire.author ?? "",
            selftext: wire.selftext ?? "",
            permalink: wire.permalink ?? "",
            url: wire.url ?? "",
            isSelf: wire.is_self ?? false,
            imageURL: wire.image_url,
            subreddit: wire.subreddit,
            comments: (wire.comments ?? []).map {
                Comment(
                    author: $0.author ?? "",
                    body: $0.body ?? "",
                    score: $0.score ?? 0,
                    isSubmitter: $0.is_submitter ?? false,
                    stickied: $0.stickied ?? false
                )
            }
        )
    }

    // MARK: - Fetch chain

    private static func fetchPayload(
        postID: String,
        postURL: URL,
        transport: Transport
    ) async throws -> Payload {
        // 1) Direct Reddit .json (works on most home/cellular IPs).
        //    For redd.it short links, synthesize a comments JSON URL from the id.
        let directJSON = jsonURL(forPost: postURL)
            ?? URL(string: "https://www.reddit.com/comments/\(postID).json?raw_json=1")
        if let jsonURL = directJSON,
           let data = try? await getData(jsonURL, accept: "application/json",
                                         userAgent: redditUserAgent, transport: transport),
           looksLikeJSON(data),
           let payload = try? payload(fromRedditListing: data) {
            return payload
        }

        // 2) Glutt proxy (OAuth / PullPush) — same auth as other AI features.
        if let proxied = try? await fetchViaProxy(postURL: postURL, transport: transport) {
            return proxied
        }

        // 3) Public archive by id (last resort; may lag on brand-new posts).
        if let archived = try? await fetchViaPullPush(postID: postID, transport: transport) {
            return archived
        }

        throw ImportError.fetchFailed
    }

    private static func fetchViaProxy(postURL: URL, transport: Transport) async throws -> Payload {
        let root = LLMClient.proxyBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !root.isEmpty, let endpoint = URL(string: "\(root)/import/reddit") else {
            throw ImportError.fetchFailed
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = LLMClient.proxyClientKey
        if !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-glutt-proxy-key")
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["source_url": postURL.absoluteString]
        )
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportError.fetchFailed
        }
        return try payload(fromProxyJSON: data)
    }

    private static func fetchViaPullPush(postID: String, transport: Transport) async throws -> Payload {
        guard let subURL = URL(
            string: "https://api.pullpush.io/reddit/search/submission/?ids=\(postID)"
        ) else { throw ImportError.fetchFailed }

        let (subData, subResponse) = try await getDataResponse(
            subURL, accept: "application/json",
            userAgent: "Glutt/1.1 (recipe-import)", transport: transport
        )
        guard let http = subResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportError.fetchFailed
        }
        guard let root = try JSONSerialization.jsonObject(with: subData) as? [String: Any],
              let rows = root["data"] as? [[String: Any]],
              let post = rows.first
        else {
            throw ImportError.nothingFound
        }

        var comments: [Comment] = []
        if let cURL = URL(
            string: "https://api.pullpush.io/reddit/search/comment/?link_id=t3_\(postID)&size=25&sort=score"
        ),
           let cData = try? await getData(
            cURL, accept: "application/json",
            userAgent: "Glutt/1.1 (recipe-import)", transport: transport
           ),
           let cRoot = try? JSONSerialization.jsonObject(with: cData) as? [String: Any],
           let cRows = cRoot["data"] as? [[String: Any]] {
            comments = cRows.compactMap { row in
                let body = (row["body"] as? String) ?? ""
                guard !body.isEmpty, body != "[removed]", body != "[deleted]" else { return nil }
                return Comment(
                    author: (row["author"] as? String) ?? "",
                    body: body,
                    score: (row["score"] as? Int) ?? 0,
                    isSubmitter: (row["is_submitter"] as? Bool) ?? false,
                    stickied: (row["stickied"] as? Bool) ?? false
                )
            }
        }

        return payload(fromPostDict: post, comments: comments)
    }

    // MARK: - External link follow

    private static func defaultFollowExternal(_ url: URL) async throws -> ImportedRecipeDraft {
        if SocialMediaImport.canHandle(url) {
            return try await SocialMediaImport.importFrom(url: url)
        }
        // Inline HTML scrape (avoid re-entering RecipeImportService → Reddit).
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else {
            throw ImportError.fetchFailed
        }
        return RecipeHTMLParser.parse(html: html, sourceURL: http.url ?? url)
    }

    private static func externalRecipeURL(from payload: Payload) -> URL? {
        let candidates = [payload.url] + markdownLinks(in: payload.selftext)
        for raw in candidates {
            guard let url = URL(string: raw), let host = url.host?.lowercased(),
                  url.scheme?.hasPrefix("http") == true,
                  !isRedditHost(host),
                  !host.contains("i.redd.it"),
                  !host.contains("v.redd.it"),
                  !host.contains("preview.redd.it"),
                  !host.contains("redd.it")
            else { continue }
            return url
        }
        return nil
    }

    private static func mergeExternal(
        into draft: ImportedRecipeDraft,
        linked: ImportedRecipeDraft,
        external: URL
    ) -> ImportedRecipeDraft {
        var merged = draft
        if merged.title?.isEmpty != false { merged.title = linked.title }
        if merged.summary == nil { merged.summary = linked.summary }
        if merged.imageURL == nil { merged.imageURL = linked.imageURL }
        if merged.ingredientLines.isEmpty { merged.ingredientLines = linked.ingredientLines }
        if merged.stepTexts.isEmpty { merged.stepTexts = linked.stepTexts }
        if merged.servings == nil { merged.servings = linked.servings }
        if merged.prepMinutes == nil { merged.prepMinutes = linked.prepMinutes }
        if merged.cookMinutes == nil { merged.cookMinutes = linked.cookMinutes }
        if merged.caption == nil { merged.caption = linked.caption }
        merged.platform = .reddit
        merged.issues.append("Recipe details pulled from the linked page (\(external.host ?? "site"))")
        // Keep Reddit as the share source the user tapped.
        return merged
    }

    // MARK: - Internals

    private static func resolveRedirects(_ url: URL, transport: Transport) async throws -> URL {
        var current = url
        // Only short/share links need a hop to the canonical /comments/ URL.
        let host = (current.host ?? "").lowercased()
        let needsResolve = host == "redd.it"
            || host.hasSuffix(".redd.it")
            || current.path.lowercased().contains("/s/")
        guard needsResolve else { return current }

        var request = URLRequest(url: current, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(redditUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/json", forHTTPHeaderField: "Accept")
        let (_, response) = try await transport(request)
        if let final = response.url { current = final }
        return current
    }

    private static func payload(fromPostDict post: [String: Any], comments: [Comment]) -> Payload {
        let previewURL: String? = {
            if let preview = post["preview"] as? [String: Any],
               let images = preview["images"] as? [[String: Any]],
               let source = images.first?["source"] as? [String: Any],
               let url = source["url"] as? String {
                return url.replacingOccurrences(of: "&amp;", with: "&")
            }
            if let thumb = post["thumbnail"] as? String,
               thumb.hasPrefix("http") {
                return thumb
            }
            if let url = post["url"] as? String,
               url.contains("i.redd.it") || url.contains("preview.redd.it") {
                return url
            }
            return nil
        }()

        return Payload(
            title: (post["title"] as? String) ?? "",
            author: (post["author"] as? String) ?? "",
            selftext: (post["selftext"] as? String) ?? "",
            permalink: (post["permalink"] as? String) ?? "",
            url: (post["url"] as? String) ?? "",
            isSelf: (post["is_self"] as? Bool) ?? false,
            imageURL: previewURL,
            subreddit: post["subreddit"] as? String,
            comments: comments
        )
    }

    private static func flattenComments(_ children: [[String: Any]], limit: Int) -> [Comment] {
        var out: [Comment] = []
        func walk(_ nodes: [[String: Any]]) {
            for node in nodes {
                guard out.count < limit else { return }
                let kind = (node["kind"] as? String) ?? ""
                guard kind == "t1", let data = node["data"] as? [String: Any] else { continue }
                let body = (data["body"] as? String) ?? ""
                if !body.isEmpty, body != "[removed]", body != "[deleted]" {
                    out.append(Comment(
                        author: (data["author"] as? String) ?? "",
                        body: body,
                        score: (data["score"] as? Int) ?? 0,
                        isSubmitter: (data["is_submitter"] as? Bool) ?? false,
                        stickied: (data["stickied"] as? Bool) ?? false
                    ))
                }
                if let replies = data["replies"] as? [String: Any],
                   let rData = replies["data"] as? [String: Any],
                   let rChildren = rData["children"] as? [[String: Any]] {
                    walk(rChildren)
                }
            }
        }
        walk(children)
        return out
    }

    private static func scoreComment(_ c: Comment) -> Int {
        var s = c.score
        if c.stickied { s += 1000 }
        if c.isSubmitter { s += 500 }
        if looksLikeRecipeText(c.body) { s += 200 }
        return s
    }

    private static func looksLikeRecipeText(_ text: String) -> Bool {
        let lower = text.lowercased()
        let signals = ["ingredient", "instructions", "directions", "method", "prep",
                       "cup ", "tbsp", "tsp", "tablespoon", "teaspoon", "oven", "preheat",
                       "minutes", "bake", "simmer", "saute", "sauté"]
        let hits = signals.filter { lower.contains($0) }.count
        if hits >= 2 { return true }
        // Quantity-looking lines.
        let lines = text.split(whereSeparator: \.isNewline)
        let qty = lines.filter { IngredientLineParser.parse(String($0)).quantity != nil }.count
        return qty >= 3
    }

    private static func sanitizedBody(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "&amp;", with: "&")
        // Reddit spoilers / markdown noise.
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "$1 ($2)",
            options: .regularExpression
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "[removed]" || text == "[deleted]" { return "" }
        return text
    }

    private static func markdownLinks(in text: String) -> [String] {
        let pattern = #"\]\((https?://[^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { match -> String? in
                guard match.numberOfRanges > 1 else { return nil }
                return ns.substring(with: match.range(at: 1))
            }
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        guard let first = data.first else { return false }
        // Reddit listing is `[` or `{`; Cloudflare HTML starts with `<`.
        return first == UInt8(ascii: "[") || first == UInt8(ascii: "{")
    }

    private static func getData(
        _ url: URL,
        accept: String,
        userAgent: String,
        transport: Transport
    ) async throws -> Data {
        let (data, _) = try await getDataResponse(
            url, accept: accept, userAgent: userAgent, transport: transport
        )
        return data
    }

    private static func getDataResponse(
        _ url: URL,
        accept: String,
        userAgent: String,
        transport: Transport
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return try await transport(request)
    }
}
