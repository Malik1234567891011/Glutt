import SwiftUI

/// Compact nutrition header for recipe detail. The big numbers are ONE serving,
/// which is what a cook wants when they glance at a recipe; the batch totals for
/// however many they're making are the subtext underneath, plus an optional
/// fiber callout.
struct RecipeNutritionBanner: View {
    let nutrition: RecipeNutrition

    private var prefix: String { nutrition.isEstimated ? "~" : "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                metric(value: "\(prefix)\(nutrition.perServingCalories)", unit: "cal")
                metric(value: "\(prefix)\(nutrition.perServingProtein)g", unit: "protein")
                if let carbs = nutrition.perServingCarbs, let fat = nutrition.perServingFat {
                    metric(value: "\(prefix)\(carbs)g", unit: "carbs")
                    metric(value: "\(prefix)\(fat)g", unit: "fat")
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text(servingLabel)
                    .font(BrandFont.nunito(12, 700))
                    .foregroundStyle(Theme.Colors.textSecondary)
                if nutrition.isEstimated {
                    Text("· estimated")
                        .font(BrandFont.nunito(12, 600))
                        .foregroundStyle(Theme.Colors.muted)
                }
                Spacer(minLength: 0)
                ForEach(nutrition.highlights) { highlight in
                    Text(highlight.label)
                        .font(BrandFont.nunito(11.5, 800))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Colors.greenTint))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                .strokeBorder(Theme.Colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
    }

    /// The big numbers are one plate. When the cook is making more than one, say
    /// what the whole batch comes to as well, so neither number can mislead.
    /// Internal so the units are unit-testable — mixing up "per serving" and
    /// "whole batch" here is the exact bug this line exists to prevent.
    var servingLabel: String {
        let n = nutrition.servings
        if n == 1 {
            return "per serving · makes 1 serving"
        }
        return "per serving · makes \(n) servings, \(prefix)\(nutrition.calories) cal"
    }

    private func metric(value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(BrandFont.bricolage(22, 700))
                .foregroundStyle(Theme.Colors.heading)
            Text(unit)
                .font(BrandFont.nunito(11, 700))
                .foregroundStyle(Theme.Colors.muted)
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }
}
