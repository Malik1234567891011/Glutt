import Foundation

/// Parses a free-text ingredient line ("2 cups basmati rice, rinsed")
/// into quantity, unit, name, and note. Used by every import path.
enum IngredientLineParser {

    struct Result: Equatable {
        var quantity: Double?
        var unit: String?
        var name: String
        var note: String?
    }

    private static let units: Set<String> = [
        "cup", "cups", "tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons",
        "g", "gram", "grams", "kg", "ml", "l", "liter", "liters", "litre", "litres",
        "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds",
        "clove", "cloves", "pinch", "pinches", "dash", "can", "cans", "jar", "jars",
        "slice", "slices", "piece", "pieces", "bunch", "bunches", "head", "heads",
        "stick", "sticks", "stalk", "stalks", "sprig", "sprigs", "package", "packages",
        "pack", "packs", "handful", "fillet", "fillets", "knob",
    ]

    private static let fractionGlyphs: [Character: Double] = [
        "¼": 0.25, "½": 0.5, "¾": 0.75, "⅓": 0.333, "⅔": 0.666, "⅛": 0.125,
    ]

    static func parse(_ line: String) -> Result {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip list bullets ("- ", "• ", "* ")
        while let first = text.first, ["-", "•", "*", "·"].contains(String(first)) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Pull a trailing note: parenthetical or after the first comma.
        var note: String?
        if let open = text.firstIndex(of: "("), let close = text.firstIndex(of: ")"), open < close {
            note = String(text[text.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            text.removeSubrange(open...close)
            text = text.trimmingCharacters(in: .whitespaces)
        } else if let comma = text.firstIndex(of: ",") {
            let after = String(text[text.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            if !after.isEmpty { note = after }
            text = String(text[..<comma])
        }

        var tokens = text.split(separator: " ").map(String.init)
        var quantity: Double?
        var unit: String?

        // Quantity: "2", "2.5", "1/2", "1 1/2", "1½", "½"
        if let first = tokens.first, let parsed = parseNumber(first) {
            quantity = parsed
            tokens.removeFirst()
            // Compound fraction: "1 1/2" or "1 ½"
            if let second = tokens.first, let fraction = parseFraction(second), parsed == parsed.rounded() {
                quantity = parsed + fraction
                tokens.removeFirst()
            }
        }

        // Unit must directly follow the quantity.
        if quantity != nil, let first = tokens.first, units.contains(first.lowercased()) {
            unit = first.lowercased()
            tokens.removeFirst()
        }

        // Drop a leading "of" ("2 cups of rice").
        if tokens.first?.lowercased() == "of" {
            tokens.removeFirst()
        }

        let name = tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return Result(quantity: quantity, unit: unit, name: name.isEmpty ? line : name, note: note)
    }

    private static func parseNumber(_ token: String) -> Double? {
        if let direct = Double(token) { return direct }
        if let fraction = parseFraction(token) { return fraction }
        // "1½" — digits followed by a fraction glyph
        if let last = token.last, let glyph = fractionGlyphs[last] {
            let wholePart = String(token.dropLast())
            if wholePart.isEmpty { return glyph }
            if let whole = Double(wholePart) { return whole + glyph }
        }
        return nil
    }

    private static func parseFraction(_ token: String) -> Double? {
        if token.count == 1, let glyph = token.first, let value = fractionGlyphs[glyph] { return value }
        let parts = token.split(separator: "/")
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 {
            return numerator / denominator
        }
        return nil
    }
}
