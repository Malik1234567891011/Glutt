import SwiftUI

/// A planned meal in the Today timeline or Plan week view.
struct MealCard: View {
    let meal: PlannedMeal

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.mealType.label)
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text(meal.displayTitle)
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if let time = meal.exactTime {
                    Text(time, style: .time)
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer()
            statusBadge
        }
        .cardStyle()
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
