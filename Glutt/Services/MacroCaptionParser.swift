import Foundation

/// Pulls calories / macros out of free text when a creator wrote them in a
/// caption or summary ("520 cal · 42g protein · 12g fiber"). Best-effort —
/// never invents numbers that aren't in the text.
enum MacroCaptionParser {

    struct Parsed: Equatable {
        var calories: Int?
        var proteinGrams: Int?
        var carbGrams: Int?
        var fatGrams: Int?
        var fiberGrams: Int?
    }

    static func parse(_ raw: String?) -> Parsed {
        guard let raw, !raw.isEmpty else { return Parsed() }
        let text = raw.lowercased()
        var result = Parsed()

        result.calories = firstInt(in: text, patterns: [
            #"(\d{2,4})\s*(?:k?cal(?:ories)?|kcals)\b"#,
            #"\bcalories?\s*[:=]?\s*(\d{2,4})\b"#,
        ])
        result.proteinGrams = firstInt(in: text, patterns: [
            #"(\d{1,3})\s*g(?:rams?)?\s*(?:of\s+)?protein\b"#,
            #"\bprotein\s*[:=]?\s*(\d{1,3})\s*g\b"#,
            #"\bp\s*[:=]\s*(\d{1,3})\s*g?\b"#,
        ])
        result.carbGrams = firstInt(in: text, patterns: [
            #"(\d{1,3})\s*g(?:rams?)?\s*(?:of\s+)?carb(?:s|ohydrates?)?\b"#,
            #"\bcarb(?:s|ohydrates?)?\s*[:=]?\s*(\d{1,3})\s*g\b"#,
            #"\bc\s*[:=]\s*(\d{1,3})\s*g?\b"#,
        ])
        result.fatGrams = firstInt(in: text, patterns: [
            #"(\d{1,3})\s*g(?:rams?)?\s*(?:of\s+)?fat\b"#,
            #"\bfat\s*[:=]?\s*(\d{1,3})\s*g\b"#,
            #"\bf\s*[:=]\s*(\d{1,3})\s*g?\b"#,
        ])
        result.fiberGrams = firstInt(in: text, patterns: [
            #"(\d{1,3})\s*g(?:rams?)?\s*(?:of\s+)?fib(?:re|er)\b"#,
            #"\bfib(?:re|er)\s*[:=]?\s*(\d{1,3})\s*g\b"#,
        ])

        return result
    }

    private static func firstInt(in text: String, patterns: [String]) -> Int? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let swiftRange = Range(match.range(at: 1), in: text),
                  let value = Int(text[swiftRange]),
                  value > 0
            else { continue }
            return value
        }
        return nil
    }
}
