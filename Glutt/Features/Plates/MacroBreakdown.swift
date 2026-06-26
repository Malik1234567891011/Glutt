import Foundation

/// Pure macro math for the tri-segment bar. Segments are proportional to each
/// macro's *calorie* contribution (protein ×4, carbs ×4, fat ×9 cal/g), which
/// is what "composition" means — not raw grams.
struct MacroBreakdown {
    let calories: Int?
    let protein: Int?
    let carbs: Int?
    let fat: Int?
    let isEstimated: Bool

    init(calories: Int?, protein: Int?, carbs: Int?, fat: Int?, isEstimated: Bool) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.isEstimated = isEstimated
    }

    /// True only when all three macro grams are present and their calorie sum > 0.
    var hasFullMacros: Bool {
        guard let p = protein, let c = carbs, let f = fat else { return false }
        return (p * 4 + c * 4 + f * 9) > 0
    }

    private var totalMacroCalories: Double {
        let proteinCal = (protein ?? 0) * 4
        let carbCal = (carbs ?? 0) * 4
        let fatCal = (fat ?? 0) * 9
        return Double(proteinCal + carbCal + fatCal)
    }

    var proteinFraction: Double { fraction((protein ?? 0) * 4) }
    var carbFraction: Double { fraction((carbs ?? 0) * 4) }
    var fatFraction: Double { fraction((fat ?? 0) * 9) }

    private func fraction(_ macroCalories: Int) -> Double {
        let total = totalMacroCalories
        guard total > 0 else { return 0 }
        return Double(macroCalories) / total
    }
}
