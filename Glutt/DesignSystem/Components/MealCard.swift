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
                        HStack(spacing: 4) {
                            Ph.clock.regular
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11, height: 11)
                            Text(recipe.timeLabel)
                        }
                    }
                }
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
                if meal.status == .planned, let start = meal.suggestedStartTime {
                    HStack(spacing: 4) {
                        Ph.timer.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 11, height: 11)
                        Text("Start cooking by \(start.formatted(date: .omitted, time: .shortened))")
                    }
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
                    Group {
                        if meal.leftover != nil {
                            Ph.bowlFood.regular
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        } else {
                            Ph.forkKnife.regular
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        }
                    }
                    .foregroundStyle(Theme.Colors.accent.opacity(0.6))
                }
        }
    }

    private var statusBadge: some View {
        Group {
            switch meal.status {
            case .planned:
                Ph.circleDashed.regular
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.Colors.textSecondary)
            case .cooked:
                Ph.cookingPot.regular
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.Colors.accent)
            case .eaten:
                Ph.checkCircle.fill
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.Colors.accent)
            case .skipped:
                Ph.minusCircle.regular
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.Colors.textSecondary)
            case .replaced:
                Ph.arrowsClockwise.regular
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        .frame(width: 24, height: 24)
    }
}
