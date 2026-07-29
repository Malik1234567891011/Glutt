import SwiftUI

/// Compact nutrition header for recipe detail: totals for the current serving
/// count, with an honest "for N servings" label and optional fiber callout.
struct RecipeNutritionBanner: View {
    let nutrition: RecipeNutrition

    private var prefix: String { nutrition.isEstimated ? "~" : "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                metric(value: "\(prefix)\(nutrition.calories)", unit: "cal")
                metric(value: "\(prefix)\(nutrition.proteinGrams)g", unit: "protein")
                if let carbs = nutrition.carbGrams, let fat = nutrition.fatGrams {
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

    private var servingLabel: String {
        let n = nutrition.servings
        if n == 1 {
            return "for 1 serving"
        }
        return "for \(n) servings · \(prefix)\(nutrition.perServingCalories) each"
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
