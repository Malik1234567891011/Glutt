import Foundation

enum MeasurementSystem: String, CaseIterable {
    case original = "Original"
    case metric = "Metric"
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

    static func convert(quantity: Double, unit: String?, to system: MeasurementSystem) -> (quantity: Double, unit: String?) {
        guard system == .metric,
              let unit,
              let conversion = toMetric[unit.lowercased().trimmingCharacters(in: .whitespaces)]
        else {
            return (quantity, unit)
        }
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
        system: MeasurementSystem = .original
    ) -> String? {
        guard let quantity else { return nil }
        let scaled = quantity * scale
        let converted = convert(quantity: scaled, unit: unit, to: system)
        return format(quantity: converted.quantity, unit: converted.unit)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
