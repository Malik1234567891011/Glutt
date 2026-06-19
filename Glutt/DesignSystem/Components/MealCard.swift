import SwiftUI

/// A planned meal in the Today timeline or Plan week view.
struct MealCard: View {
    let meal: PlannedMeal

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.mealType.label)
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text(meal.displayTitle)
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.sm) {
                    if let time = meal.exactTime {
                        Text(time, style: .time)
                    }
                    if let recipe = meal.recipe {
                        Label(recipe.timeLabel, systemImage: "clock")
                    }
                }
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
                if meal.status == .planned, let start = meal.suggestedStartTime {
                    Label("Start cooking by \(start.formatted(date: .omitted, time: .shortened))", systemImage: "timer")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.warning)
                }
            }
            Spacer()
            statusBadge
        }
        .cardStyle()
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let recipe = meal.recipe ?? meal.leftover?.sourceRecipe {
            RecipeImageView(recipe: recipe)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Colors.accent.opacity(0.1))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: meal.leftover != nil ? "takeoutbag.and.cup.and.straw" : "fork.knife")
                        .foregroundStyle(Theme.Colors.accent.opacity(0.6))
                }
        }
    }

    private var statusBadge: some View {
        Group {
            switch meal.status {
            case .planned:
                Image(systemName: "circle.dashed")
                    .foregroundStyle(Theme.Colors.textSecondary)
            case .cooked:
                Image(systemName: "frying.pan")
                    .foregroundStyle(Theme.Colors.accent)
            case .eaten:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.accent)
            case .skipped:
                Image(systemName: "minus.circle")
                    .foregroundStyle(Theme.Colors.textSecondary)
            case .replaced:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        .font(.title3)
    }
}
