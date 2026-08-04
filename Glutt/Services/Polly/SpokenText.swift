import Foundation

/// Rewrites recipe shorthand into words a voice reads correctly.
///
/// "Add 2 tbsp olive oil" is the right thing to put on screen and the wrong
/// thing to hand a text-to-speech engine: it comes out as "two t-b-s-p". The
/// model can't be trusted to remember a formatting rule on every turn, and the
/// step text it reads from the plan carries the same abbreviations anyway, so
/// this runs at the synthesis boundary instead — captions keep the compact form
/// and only her mouth gets the long one.
enum SpokenText {
    /// Abbreviation → spoken forms. Order matters: the alternation is tried in
    /// sequence, so "tbsp" has to precede "tbs" and "lbs" has to precede "lb"
    /// or the shorter one matches first and leaves a stray letter behind.
    private static let units: [(abbrev: String, singular: String, plural: String)] = [
        ("tbsps", "tablespoon", "tablespoons"),
        ("tbsp", "tablespoon", "tablespoons"),
        ("tbs", "tablespoon", "tablespoons"),
        ("tbl", "tablespoon", "tablespoons"),
        ("tsps", "teaspoon", "teaspoons"),
        ("tsp", "teaspoon", "teaspoons"),
        ("kgs", "kilogram", "kilograms"),
        ("kg", "kilogram", "kilograms"),
        ("mg", "milligram", "milligrams"),
        ("gr", "gram", "grams"),
        ("g", "gram", "grams"),
        ("mls", "milliliter", "milliliters"),
        ("ml", "milliliter", "milliliters"),
        ("lbs", "pound", "pounds"),
        ("lb", "pound", "pounds"),
        ("ozs", "ounce", "ounces"),
        ("oz", "ounce", "ounces"),
        ("mins", "minute", "minutes"),
        ("min", "minute", "minutes"),
        ("hrs", "hour", "hours"),
        ("hr", "hour", "hours"),
        ("secs", "second", "seconds"),
        ("sec", "second", "seconds"),
        ("cms", "centimeter", "centimeters"),
        ("cm", "centimeter", "centimeters"),
        ("mm", "millimeter", "millimeters"),
        ("qts", "quart", "quarts"),
        ("qt", "quart", "quarts"),
        ("pts", "pint", "pints"),
        ("pt", "pint", "pints"),
        ("l", "liter", "liters"),
    ]

    /// Optional spacing, ordinary or non-breaking. Kept as a constant because
    /// these patterns must be interpolated strings, not raw ones: inside `#"…"#`
    /// the `\u{00A0}` escape is never expanded, the regex fails to compile, and
    /// `try?` silently returns the text unchanged.
    private static let gap = "[ \u{00A0}]*"

    private static let fractionChars = "½¼¾⅓⅔⅛"

    /// A count: mixed ("1½"), whole, decimal, "1/2", or a lone fraction. Mixed
    /// comes first so "1½ tbsp" is captured whole — matching just the "½" would
    /// put a digit right before it and trip the lookbehind. Every unit match
    /// requires a count, which keeps "big" from becoming "bi gram" and a bare
    /// "2 c flour" from turning into Celsius.
    private static let count =
        "\\d+\(gap)[\(fractionChars)]"
        + "|\\d+(?:[.,]\\d+)?(?:\(gap)/\(gap)\\d+)?"
        + "|[\(fractionChars)]"

    /// `alone` is the phrase on its own, `beforeUnit` the one used when a unit
    /// follows ("half a teaspoon" rather than "half teaspoon"), and `mixed` the
    /// tail of a mixed number ("one and a half").
    private static let fractionWords: [(symbol: String, alone: String, beforeUnit: String, mixed: String)] = [
        ("½", "half", "half a", "a half"),
        ("¼", "a quarter", "a quarter of a", "a quarter"),
        ("¾", "three quarters", "three quarters of a", "three quarters"),
        ("⅓", "a third", "a third of a", "a third"),
        ("⅔", "two thirds", "two thirds of a", "two thirds"),
        ("⅛", "an eighth", "an eighth of a", "an eighth"),
        ("1/2", "half", "half a", "a half"),
        ("1/4", "a quarter", "a quarter of a", "a quarter"),
        ("3/4", "three quarters", "three quarters of a", "three quarters"),
        ("1/3", "a third", "a third of a", "a third"),
        ("2/3", "two thirds", "two thirds of a", "two thirds"),
        ("1/8", "an eighth", "an eighth of a", "an eighth"),
    ]

    /// Units as they read aloud, for spotting "half a <unit>". Longest first so
    /// the alternation can't match "cup" inside "cups".
    private static let spokenUnits: String = {
        var words = Set<String>()
        for unit in units {
            words.insert(unit.singular)
            words.insert(unit.plural)
        }
        words.formUnion(["cup", "cups", "stick", "sticks", "clove", "cloves"])
        return words
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
    }()

    static func forSpeech(_ raw: String) -> String {
        var text = expandUnits(in: raw)
        text = expandTemperatures(in: text)
        text = expandFractions(in: text)
        return text
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Passes

    private static func expandUnits(in text: String) -> String {
        let abbrevs = units
            .map { NSRegularExpression.escapedPattern(for: $0.abbrev) }
            .joined(separator: "|")
        // No letter or digit may precede the count, and no letter may follow the
        // abbreviation, so "v1kg" and "mining" are both left alone.
        let pattern = "(?<![A-Za-z0-9])(\(count))\(gap)(\(abbrevs))(?![A-Za-z])"
        return replace(pattern, in: text, options: [.caseInsensitive]) { groups in
            guard let number = groups[1], let abbrev = groups[2]?.lowercased(),
                  let unit = units.first(where: { $0.abbrev == abbrev })
            else { return nil }
            let word = isSingular(number) ? unit.singular : unit.plural
            return "\(number) \(word)"
        }
    }

    private static func expandTemperatures(in text: String) -> String {
        var text = replace("(\\d+)\(gap)°\(gap)C\\b", in: text, options: [.caseInsensitive]) {
            $0[1].map { "\($0) degrees Celsius" }
        }
        text = replace("(\\d+)\(gap)°\(gap)F\\b", in: text, options: [.caseInsensitive]) {
            $0[1].map { "\($0) degrees Fahrenheit" }
        }
        text = replace("(\\d+)\(gap)°", in: text) {
            $0[1].map { "\($0) degrees" }
        }
        // Case-sensitive on purpose: "180 C" is an oven, but "2 c flour" is cups.
        text = replace("(\\d+)\(gap)C\\b", in: text) {
            $0[1].map { "\($0) degrees Celsius" }
        }
        return replace("(\\d+)\(gap)F\\b", in: text) {
            $0[1].map { "\($0) degrees Fahrenheit" }
        }
    }

    private static func expandFractions(in text: String) -> String {
        var text = text
        for fraction in fractionWords {
            let symbol = NSRegularExpression.escapedPattern(for: fraction.symbol)
            // "1½ tablespoons" reads as "1 and a half tablespoons".
            text = replace("(\\d+)\(gap)\(symbol)(?![\\d/])", in: text) { groups in
                groups[1].map { "\($0) and \(fraction.mixed)" }
            }
            // Units run first, so by now the unit is a word: "half a teaspoon".
            text = replace(
                "(?<![\\d/])\(symbol) (\(spokenUnits))\\b", in: text
            ) { groups in
                groups[1].map { "\(fraction.beforeUnit) \($0)" }
            }
            text = replace("(?<![\\d/])\(symbol)(?![\\d/])", in: text) { _ in fraction.alone }
        }
        return text
    }

    // MARK: - Helpers

    private static func isSingular(_ number: String) -> Bool {
        let compact = number.replacingOccurrences(of: " ", with: "")
        if compact == "1" { return true }
        if compact.contains(where: { fractionChars.contains($0) }) {
            // A lone fraction is part of one thing ("half a teaspoon"), but a
            // mixed number is more than one ("one and a half tablespoons").
            // The digit test has to be ASCII-only: `isNumber` is true for "½".
            return !compact.contains { $0.isASCII && $0.isNumber }
        }
        if compact.contains("/") { return true }
        return false
    }

    /// Regex replace where the transform sees the captured groups and can bail
    /// out by returning nil, leaving that match untouched.
    private static func replace(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [],
        transform: ([String?]) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let groups = (0..<match.numberOfRanges).map { index -> String? in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
            }
            guard let replacement = transform(groups) else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += replacement
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}
