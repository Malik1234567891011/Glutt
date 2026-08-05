import Foundation

/// Extracts ingredients and steps from the page's own markup.
///
/// Some SEO plugins publish a schema.org Recipe node that is structurally valid
/// but carries no content: `recipeIngredient` is an empty array and every
/// `HowToStep` has a position and nothing else. WPSSO does this, so maangchi.com
/// and other WordPress food blogs would otherwise import as a title with no
/// recipe under it. This reads the HTML a person actually sees instead.
///
/// Deliberately heading-driven rather than class-driven: recipe card plugins
/// (WPRM, Tasty) publish good JSON-LD already, so the pages that reach here are
/// hand-rolled blog markup where `<h2>Ingredients</h2>` is the only reliable
/// landmark.
enum RecipeBodyParser {

    struct Result {
        var ingredientLines: [String] = []
        var stepTexts: [String] = []
        var servings: Int?
    }

    static func parse(html: String) -> Result {
        let body = contentMarkup(in: html)
        let found = headings(in: body)
        var result = Result()

        if let region = region(matching: isIngredientHeading, in: found, body: body) {
            result.ingredientLines = entries(in: region, maxLength: 220)
            result.servings = servingCount(in: region)
        }
        if let region = region(matching: isStepHeading, in: found, body: body) {
            result.stepTexts = entries(in: region, maxLength: 1200)
        }
        return result
    }

    // MARK: - Regions

    private struct Heading {
        let level: Int
        let text: String
        /// Where the `<hN>` tag opens, so a region can stop just before it.
        let tagStart: String.Index
        /// Just past `</hN>`, where the section's content begins.
        let contentStart: String.Index
    }

    /// A section runs from its heading to the next heading of the same or higher
    /// rank, so `<h3>` sub-groups ("For the sauce:") stay inside their `<h2>`.
    /// A stop heading also closes it, because blogs bury newsletter and comment
    /// blocks at the same depth as the recipe's own sub-headings.
    private static func region(
        matching predicate: (String) -> Bool,
        in headings: [Heading],
        body: String
    ) -> String? {
        guard let index = headings.firstIndex(where: { predicate($0.text) }) else { return nil }
        let start = headings[index]
        let end = headings[(index + 1)...].first {
            $0.level <= start.level || isStopHeading($0.text)
        }
        return String(body[start.contentStart..<(end?.tagStart ?? body.endIndex)])
    }

    private static func isIngredientHeading(_ text: String) -> Bool {
        text.lowercased().contains("ingredient") && !isStopHeading(text)
    }

    private static func isStepHeading(_ text: String) -> Bool {
        let lower = text.lowercased()
        let match = ["direction", "instruction", "method", "preparation", "how to make", "step"]
            .contains { lower.contains($0) }
        return match && !isStopHeading(text)
    }

    /// Ends the recipe: storefronts, newsletters, comment threads, related rails.
    /// "Buy this recipe's ingredients online" is why the ingredient check needs it.
    private static func isStopHeading(_ text: String) -> Bool {
        let lower = text.lowercased()
        return [
            "comment", "leave a reply", "buy", "shop", "amazon", "substack",
            "newsletter", "subscribe", "related", "you might", "more recipes",
            "cookbook", "print", "nutrition facts", "similar",
        ].contains { lower.contains($0) }
    }

    // MARK: - Extraction

    /// `<li>` when the section is a real list, `<p>` for prose-style method
    /// sections. Two items is the bar for "this is a list", so a single stray
    /// bullet in a prose section doesn't win over the paragraphs around it.
    private static func entries(in region: String, maxLength: Int) -> [String] {
        let items = captures(listItemRegex, in: region)
        let source = items.count >= 2 ? items : captures(paragraphRegex, in: region)
        var seen = Set<String>()
        return source
            .map(plainText)
            .filter { $0.count >= 2 && $0.count <= maxLength }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private static func servingCount(in region: String) -> Int? {
        let text = plainText(region)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = servingsRegex.firstMatch(in: text, range: range),
              let digits = Range(match.range(at: 1), in: text),
              let value = Int(text[digits]), value > 0
        else { return nil }
        return value
    }

    private static func plainText(_ markup: String) -> String {
        let stripped = markup.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression)
        return RecipeHTMLParser.decodeEntities(stripped)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            // Ingredient lines wrap words in <a> links, and blanking those tags
            // leaves "shiitake mushrooms , washed" and "or swerve )".
            .replacingOccurrences(of: " +([,.;:!?)])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([(]) +", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Scripts carry ad configs that name recipe CSS classes, and comments carry
    /// old markup. Both produce phantom sections if left in.
    private static func contentMarkup(in html: String) -> String {
        var body = html
        for pattern in [
            "<script[^>]*>.*?</script\\s*>",
            "<style[^>]*>.*?</style\\s*>",
            "<noscript[^>]*>.*?</noscript\\s*>",
            "<!--.*?-->",
        ] {
            body = body.replacingOccurrences(
                of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return body
    }

    private static func headings(in body: String) -> [Heading] {
        let range = NSRange(body.startIndex..., in: body)
        return headingRegex.matches(in: body, range: range).compactMap { match in
            guard let whole = Range(match.range, in: body),
                  let levelRange = Range(match.range(at: 1), in: body),
                  let textRange = Range(match.range(at: 2), in: body),
                  let level = Int(body[levelRange])
            else { return nil }
            return Heading(
                level: level,
                text: plainText(String(body[textRange])),
                tagStart: whole.lowerBound,
                contentStart: whole.upperBound
            )
        }
    }

    private static func captures(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let captured = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captured])
        }
    }

    // MARK: - Patterns

    private static let headingRegex = regex("<h([1-4])[^>]*>(.*?)</h\\1\\s*>")
    private static let listItemRegex = regex("<li[^>]*>(.*?)</li\\s*>")
    private static let paragraphRegex = regex("<p[^>]*>(.*?)</p\\s*>")
    private static let servingsRegex = regex("\\b(?:serves|makes|yields?)\\b[^0-9]{0,12}(\\d{1,3})")

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals owned by this file; a failure here is a build-time
        // typo, not something a page can trigger.
        try! NSRegularExpression(
            pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
    }
}
