import Foundation

/// Extracts a recipe from a web page.
/// Strategy 1: schema.org Recipe JSON-LD (most recipe sites publish this).
/// Strategy 2: OpenGraph meta tags + caption text parsing (social pages, blogs without markup).
enum RecipeHTMLParser {

    static func parse(html: String, sourceURL: URL) -> ImportedRecipeDraft {
        if var draft = parseJSONLD(html: html, sourceURL: sourceURL) {
            draft.platform = ImportedRecipeDraft.platform(for: sourceURL)

            // A Recipe node can be well-formed and still carry no recipe: some
            // SEO plugins emit an empty `recipeIngredient` and text-less
            // `HowToStep`s. Finding the node is not the same as finding a
            // recipe, so fill the gaps from the page's own markup.
            if draft.ingredientLines.isEmpty || draft.stepTexts.isEmpty {
                let body = RecipeBodyParser.parse(html: html)
                if draft.ingredientLines.isEmpty { draft.ingredientLines = body.ingredientLines }
                if draft.stepTexts.isEmpty { draft.stepTexts = body.stepTexts }
                if draft.servings == nil { draft.servings = body.servings }
            }

            if !draft.ingredientLines.isEmpty || !draft.stepTexts.isEmpty {
                annotateIssues(&draft)
                return draft
            }
            // Hollow JSON-LD and nothing in the markup either. Fall through so
            // the meta path still gets its shot rather than returning a title
            // with no recipe under it.
        }
        return parseMetaFallback(html: html, sourceURL: sourceURL)
    }

    // MARK: - JSON-LD

    private static func parseJSONLD(html: String, sourceURL: URL) -> ImportedRecipeDraft? {
        for blob in jsonLDBlocks(in: html) {
            guard let data = blob.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data)
            else { continue }
            if let recipe = findRecipeObject(in: json) {
                return draft(from: recipe, sourceURL: sourceURL)
            }
        }
        return nil
    }

    private static func jsonLDBlocks(in html: String) -> [String] {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let blockRange = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[blockRange])
        }
    }

    /// Walks JSON that may be a single object, an array, or use "@graph".
    private static func findRecipeObject(in json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            if isRecipeType(dict["@type"]) { return dict }
            if let graph = dict["@graph"] {
                return findRecipeObject(in: graph)
            }
            return nil
        }
        if let array = json as? [Any] {
            for element in array {
                if let found = findRecipeObject(in: element) { return found }
            }
        }
        return nil
    }

    private static func isRecipeType(_ type: Any?) -> Bool {
        if let single = type as? String { return single == "Recipe" }
        if let multiple = type as? [String] { return multiple.contains("Recipe") }
        return false
    }

    private static func draft(from recipe: [String: Any], sourceURL: URL) -> ImportedRecipeDraft {
        var draft = ImportedRecipeDraft()
        draft.sourceURL = sourceURL.absoluteString

        draft.title = (recipe["name"] as? String).map { cleanTitle(decodeEntities($0)) }
        draft.summary = (recipe["description"] as? String).map(decodeEntities)
        draft.imageURL = imageURLString(recipe["image"])
        draft.creator = authorName(recipe["author"])

        draft.ingredientLines = (recipe["recipeIngredient"] as? [String])?.map(decodeEntities) ?? []
        draft.stepTexts = instructionTexts(recipe["recipeInstructions"])

        draft.prepMinutes = isoDurationMinutes(recipe["prepTime"] as? String)
        draft.cookMinutes = isoDurationMinutes(recipe["cookTime"] as? String)
        if draft.prepMinutes == nil, draft.cookMinutes == nil,
           let total = isoDurationMinutes(recipe["totalTime"] as? String) {
            draft.cookMinutes = total
        }

        draft.servings = yieldCount(recipe["recipeYield"])
        // Sites stuff dozens of SEO keywords in here; keep it scannable.
        draft.tags = Array(keywordTags(recipe["keywords"]).prefix(6))

        if let nutrition = recipe["nutrition"] as? [String: Any] {
            draft.calories = leadingInt(nutrition["calories"] as? String)
            draft.proteinGrams = leadingInt(nutrition["proteinContent"] as? String)
        }

        return draft
    }

    /// Runs after the markup fallback, so a gap the page itself filled never
    /// shows up as a warning on the review screen.
    private static func annotateIssues(_ draft: inout ImportedRecipeDraft) {
        if draft.title == nil { draft.issues.append("Couldn't find a title") }
        if draft.ingredientLines.isEmpty { draft.issues.append("No ingredients found. Add them manually.") }
        if draft.stepTexts.isEmpty { draft.issues.append("No steps found. Add them manually.") }
        if draft.servings == nil { draft.issues.append("Servings were guessed") }
        if draft.prepMinutes == nil, draft.cookMinutes == nil { draft.issues.append("No timing information") }
    }

    // MARK: - JSON-LD field helpers

    private static func imageURLString(_ value: Any?) -> String? {
        if let direct = value as? String { return direct }
        if let array = value as? [Any] { return array.compactMap { imageURLString($0) }.first }
        if let object = value as? [String: Any] { return object["url"] as? String }
        return nil
    }

    private static func authorName(_ value: Any?) -> String? {
        if let direct = value as? String { return direct }
        if let object = value as? [String: Any] { return object["name"] as? String }
        if let array = value as? [Any] { return array.compactMap { authorName($0) }.first }
        return nil
    }

    private static func instructionTexts(_ value: Any?) -> [String] {
        if let text = value as? String {
            return text
                .components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        guard let array = value as? [Any] else { return [] }
        return array.flatMap { element -> [String] in
            if let text = element as? String { return [decodeEntities(text)] }
            guard let object = element as? [String: Any] else { return [] }
            if let type = object["@type"] as? String, type == "HowToSection" {
                return instructionTexts(object["itemListElement"])
            }
            if let text = object["text"] as? String { return [decodeEntities(text)] }
            return []
        }
    }

    /// "PT1H30M" -> 90
    static func isoDurationMinutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
        else { return nil }
        var minutes = 0
        if let hoursRange = Range(match.range(at: 1), in: value), let hours = Int(value[hoursRange]) {
            minutes += hours * 60
        }
        if let minutesRange = Range(match.range(at: 2), in: value), let mins = Int(value[minutesRange]) {
            minutes += mins
        }
        return minutes > 0 ? minutes : nil
    }

    private static func yieldCount(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let text = value as? String { return leadingInt(text) }
        if let array = value as? [Any] { return array.compactMap { yieldCount($0) }.first }
        return nil
    }

    private static func keywordTags(_ value: Any?) -> [String] {
        if let csv = value as? String {
            return csv.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let array = value as? [String] { return array }
        return []
    }

    private static func leadingInt(_ text: String?) -> Int? {
        guard let text else { return nil }
        let digits = text.prefix { $0.isNumber }
        return Int(digits)
    }

    /// Strips site-name suffixes: "Glossy Fudge Brownies Recipe | BraveTart" -> "Glossy Fudge Brownies Recipe".
    static func cleanTitle(_ title: String) -> String {
        var cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" | ", " — ", " – ", " :: "] {
            if let range = cleaned.range(of: separator, options: .backwards) {
                let before = cleaned[..<range.lowerBound]
                if before.count >= 8 {
                    cleaned = String(before)
                }
            }
        }
        // " - Site Name" only when the tail looks like a short brand, not part of the dish.
        if let range = cleaned.range(of: " - ", options: .backwards) {
            let before = cleaned[..<range.lowerBound]
            let after = cleaned[range.upperBound...]
            if before.count >= 8, after.count <= 25, !after.lowercased().contains("recipe") {
                cleaned = String(before)
            }
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    static func decodeEntities(_ text: String) -> String {
        var decoded = decodeNumericEntities(text)
        for (entity, replacement) in [
            ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "),
            ("&lt;", "<"), ("&gt;", ">"),
            ("&rsquo;", "'"), ("&lsquo;", "'"), ("&ldquo;", "\""), ("&rdquo;", "\""),
            ("&hellip;", "..."), ("&frac12;", "½"), ("&frac14;", "¼"), ("&frac34;", "¾"),
            ("&deg;", "°"),
        ] {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }
        // Last, so "&amp;lt;" decodes to "&lt;" and not to "<".
        return decoded.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// WordPress writes curly quotes and fractions as `&#8217;` / `&#189;`, which
    /// otherwise survive into ingredient lines as literal entity text.
    private static func decodeNumericEntities(_ text: String) -> String {
        guard text.contains("&#") else { return text }
        let source = text as NSString
        let matches = numericEntityRegex.matches(
            in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }

        var decoded = ""
        var cursor = 0
        for match in matches {
            decoded += source.substring(
                with: NSRange(location: cursor, length: match.range.location - cursor))
            let isHex = match.range(at: 1).length > 0
            let digits = source.substring(with: match.range(at: 2))
            if let code = UInt32(digits, radix: isHex ? 16 : 10),
               let scalar = Unicode.Scalar(code) {
                decoded.append(Character(scalar))
            } else {
                decoded += source.substring(with: match.range)  // leave malformed entities alone
            }
            cursor = match.range.location + match.range.length
        }
        decoded += source.substring(from: cursor)
        return decoded
    }

    private static let numericEntityRegex = try! NSRegularExpression(
        pattern: "&#(x)?([0-9A-Fa-f]{1,6});", options: .caseInsensitive)

    // MARK: - Meta tag fallback (social pages, unmarked blogs)

    private static func parseMetaFallback(html: String, sourceURL: URL) -> ImportedRecipeDraft {
        let title = metaContent(html: html, property: "og:title")
        let description = metaContent(html: html, property: "og:description")
        let image = metaContent(html: html, property: "og:image")

        // Captions on TikTok/Instagram often contain the whole recipe as text.
        var draft: ImportedRecipeDraft
        if let description, description.count > 80 {
            draft = TextRecipeParser.parse(text: description)
        } else {
            draft = ImportedRecipeDraft()
        }

        if draft.title == nil || draft.title?.isEmpty == true {
            draft.title = title.map { cleanTitle(decodeEntities($0)) }
        }
        draft.imageURL = draft.imageURL ?? image
        draft.caption = description
        draft.sourceURL = sourceURL.absoluteString
        draft.platform = ImportedRecipeDraft.platform(for: sourceURL)

        if draft.ingredientLines.isEmpty {
            draft.issues.append("Couldn't extract ingredients from this page. Paste them manually, or try the screenshot import.")
        }
        if draft.stepTexts.isEmpty {
            draft.issues.append("No steps found")
        }
        return draft
    }

    private static func metaContent(html: String, property: String) -> String? {
        // Handles both property="og:x" content="..." and content="..." property="og:x"
        let patterns = [
            #"<meta[^>]*property\s*=\s*["']\#(property)["'][^>]*content\s*=\s*["']([^"']*)["']"#,
            #"<meta[^>]*content\s*=\s*["']([^"']*)["'][^>]*property\s*=\s*["']\#(property)["']"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let contentRange = Range(match.range(at: 1), in: html) {
                let content = String(html[contentRange])
                if !content.isEmpty { return content }
            }
        }
        return nil
    }
}
