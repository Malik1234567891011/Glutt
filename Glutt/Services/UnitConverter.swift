import Foundation

enum MeasurementSystem: String, CaseIterable {
    case original = "Original"
    case metric = "Metric"
    /// Converts volume measures (cups/tbsp/tsp) to grams for cooks who prefer to
    /// weigh everything. Uses per-ingredient density; leaves an amount unchanged
    /// when we can't convert it honestly.
    case weight = "Weights (g)"
}

/// Converts common cooking units to metric and formats quantities for display
/// (including recipe scaling and pretty fractions like ½ and ¼).
enum UnitConverter {

    // MARK: - Conversion

    /// Volume units -> milliliters, weight units -> grams.
    private static let toMetric: [String: (factor: Double, unit: String)] = [
        "cup": (240, "ml"), "cups": (240, "ml"),
        "tbsp": (15, "ml"), "tablespoon": (15, "ml"), "tablespoons": (15, "ml"),
        "tsp": (5, "ml"), "teaspoon": (5, "ml"), "teaspoons": (5, "ml"),
        "fl oz": (29.6, "ml"),
        "quart": (946, "ml"), "quarts": (946, "ml"),
        "pint": (473, "ml"), "pints": (473, "ml"),
        "oz": (28.3, "g"), "ounce": (28.3, "g"), "ounces": (28.3, "g"),
        "lb": (454, "g"), "lbs": (454, "g"), "pound": (454, "g"), "pounds": (454, "g"),
    ]

    /// Volume unit -> milliliters.
    private static let volumeToML: [String: Double] = [
        "cup": 240, "cups": 240,
        "tbsp": 15, "tablespoon": 15, "tablespoons": 15,
        "tsp": 5, "teaspoon": 5, "teaspoons": 5,
        "fl oz": 29.6, "quart": 946, "quarts": 946, "pint": 473, "pints": 473,
        "ml": 1, "l": 1000, "liter": 1000, "liters": 1000,
    ]

    /// Approx density (g per ml) for volume->weight, keyed by canonical-name
    /// fragment. First match wins; unlisted solids can't be converted safely.
    private static let density: [(key: String, gPerML: Double)] = [
        ("flour", 0.53), ("cocoa", 0.42), ("powdered sugar", 0.5), ("icing sugar", 0.5),
        ("brown sugar", 0.9), ("sugar", 0.85), ("salt", 1.2), ("rice", 0.78),
        ("oat", 0.4), ("honey", 1.42), ("maple", 1.32), ("butter", 0.96),
        ("olive oil", 0.92), ("oil", 0.92), ("milk", 1.03), ("yogurt", 1.03),
        ("sour cream", 1.0), ("cream", 1.0), ("water", 1.0), ("broth", 1.0),
        ("stock", 1.0), ("juice", 1.04), ("wine", 0.99), ("vinegar", 1.01),
        ("honey", 1.42),
    ]

    private static func densityForVolume(_ name: String?) -> Double? {
        guard let name = name?.lowercased(), !name.isEmpty else { return nil }
        for entry in density where name.contains(entry.key) { return entry.gPerML }
        // A liquid-sounding ingredient we didn't list: treat as water-like.
        if ["water", "juice", "milk", "broth", "stock", "wine", "sauce", "syrup"].contains(where: name.contains) {
            return 1.0
        }
        return nil
    }

    static func convert(
        quantity: Double,
        unit: String?,
        to system: MeasurementSystem,
        ingredientName: String? = nil
    ) -> (quantity: Double, unit: String?) {
        switch system {
        case .original:
            return (quantity, unit)
        case .weight:
            guard let unit,
                  let ml = volumeToML[unit.lowercased().trimmingCharacters(in: .whitespaces)],
                  let gPerML = densityForVolume(ingredientName)
            else { return (quantity, unit) }
            var grams = quantity * ml * gPerML
            if grams >= 1000 { return ((grams / 1000).rounded(toPlaces: 2), "kg") }
            grams = grams >= 100 ? grams.rounded() : grams.rounded(toPlaces: 1)
            return (grams, "g")
        case .metric:
            guard let unit,
                  let conversion = toMetric[unit.lowercased().trimmingCharacters(in: .whitespaces)]
            else { return (quantity, unit) }
            var value = quantity * conversion.factor
            // Promote to liters/kilograms when large.
            if conversion.unit == "ml", value >= 1000 {
                return ((value / 1000).rounded(toPlaces: 2), "l")
            }
            if conversion.unit == "g", value >= 1000 {
                return ((value / 1000).rounded(toPlaces: 2), "kg")
            }
            // Round to a sensible kitchen precision.
            value = value >= 100 ? value.rounded() : value.rounded(toPlaces: 1)
            return (value, conversion.unit)
        }
    }

    static func fahrenheitToCelsius(_ fahrenheit: Double) -> Double {
        ((fahrenheit - 32) * 5 / 9).rounded()
    }

    // MARK: - Display formatting

    private static let fractions: [(value: Double, glyph: String)] = [
        (0.25, "¼"), (0.333, "⅓"), (0.5, "½"), (0.666, "⅔"), (0.75, "¾"),
    ]

    /// "0.5 cup" -> "½ cup", "2.0" -> "2", "1.5 lbs" -> "1½ lbs"
    static func format(quantity: Double, unit: String? = nil) -> String {
        let whole = Int(quantity)
        let remainder = quantity - Double(whole)

        var numberPart: String
        if let fraction = fractions.first(where: { abs($0.value - remainder) < 0.05 }) {
            numberPart = whole > 0 ? "\(whole)\(fraction.glyph)" : fraction.glyph
        } else if remainder < 0.05 {
            numberPart = "\(whole)"
        } else {
            numberPart = quantity.formatted(.number.precision(.fractionLength(0...2)))
        }

        if let unit, !unit.isEmpty {
            return "\(numberPart) \(unit)"
        }
        return numberPart
    }

    /// Scale + convert + format an ingredient quantity in one call.
    static func display(
        quantity: Double?,
        unit: String?,
        scale: Double = 1,
        system: MeasurementSystem = .original,
        ingredientName: String? = nil
    ) -> String? {
        guard let quantity else { return nil }
        let scaled = quantity * scale
        let converted = convert(quantity: scaled, unit: unit, to: system, ingredientName: ingredientName)
        return format(quantity: converted.quantity, unit: converted.unit)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
