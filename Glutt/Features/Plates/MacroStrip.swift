import SwiftUI

/// The macro header: big calorie number + a tri-segment composition bar
/// (protein/carbs/fat by calorie share) + gram pills. Degrades to
/// calories+protein when carb/fat are missing. Honest "per serving".
struct MacroStrip: View {
    let breakdown: MacroBreakdown

    init(calories: Int?, protein: Int?, carbs: Int?, fat: Int?, isEstimated: Bool) {
        self.breakdown = MacroBreakdown(calories: calories, protein: protein,
                                        carbs: carbs, fat: fat, isEstimated: isEstimated)
    }

    init(recipe: Recipe) {
        self.init(calories: recipe.calories, protein: recipe.proteinGrams,
                  carbs: recipe.carbGrams, fat: recipe.fatGrams,
                  isEstimated: recipe.nutritionIsEstimated)
    }

    private var prefix: String { breakdown.isEstimated ? "~" : "" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                if let cal = breakdown.calories {
                    Text("\(prefix)\(cal)")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("cal")
                        .font(.gluttCaption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Text(breakdown.isEstimated ? "estimated · per serving" : "per serving")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if breakdown.hasFullMacros {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        segment(width: geo.size.width * breakdown.proteinFraction, color: Theme.Colors.accent)
                        segment(width: geo.size.width * breakdown.carbFraction, color: Theme.Colors.warning)
                        segment(width: geo.size.width * breakdown.fatFraction, color: Theme.Colors.tomato)
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
            }

            HStack(spacing: Theme.Spacing.sm) {
                gramPill("P", grams: breakdown.protein, color: Theme.Colors.accent)
                gramPill("C", grams: breakdown.carbs, color: Theme.Colors.warning)
                gramPill("F", grams: breakdown.fat, color: Theme.Colors.tomato)
            }
        }
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }

    @ViewBuilder
    private func gramPill(_ letter: String, grams: Int?, color: Color) -> some View {
        if let grams {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("\(letter) \(prefix)\(grams)g")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

#Preview("Full / degraded") {
    VStack(spacing: 24) {
        MacroStrip(calories: 620, protein: 48, carbs: 55, fat: 18, isEstimated: false)
        MacroStrip(calories: 400, protein: 30, carbs: nil, fat: nil, isEstimated: true)
    }
    .padding()
    .background(Theme.Colors.card)
}
