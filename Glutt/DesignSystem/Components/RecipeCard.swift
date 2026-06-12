import SwiftUI

/// The core recipe card: image, title, source, time, difficulty, tags,
/// and a slot for the pantry-match indicator ("You have 6/9 ingredients").
struct RecipeCard: View {
    let recipe: Recipe
    /// Pantry match (owned, total non-optional). Nil hides the indicator.
    var pantryMatch: (owned: Int, total: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            recipeImage
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(recipe.title)
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: Theme.Spacing.sm) {
                    if let creator = recipe.sourceCreator {
                        Text(creator)
                    } else {
                        Text(recipe.sourcePlatform.label)
                    }
                    Text("·")
                    Label("\(recipe.totalMinutes) min", systemImage: "clock")
                    Text("·")
                    Text(recipe.difficulty.label)
                }
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)

                if !recipe.tags.isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(recipe.tags.prefix(3), id: \.self) { tag in
                            Chip(label: tag)
                        }
                    }
                }

                if let pantryMatch {
                    ingredientMatchIndicator(owned: pantryMatch.owned, total: pantryMatch.total)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Theme.Colors.textPrimary.opacity(0.07), radius: 10, x: 0, y: 3)
    }

    private var recipeImage: some View {
        RecipeImageView(recipe: recipe)
            .frame(height: 170)
    }

    private func ingredientMatchIndicator(owned: Int, total: Int) -> some View {
        let hasAll = owned >= total && total > 0
        return HStack(spacing: 4) {
            Image(systemName: hasAll ? "checkmark.circle.fill" : "basket")
                .font(.caption)
            Text(total > 0 ? "You have \(owned)/\(total) ingredients" : "No ingredients listed")
                .font(.gluttCaption.weight(.medium))
        }
        .foregroundStyle(hasAll ? Theme.Colors.accent : Theme.Colors.warning)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(hasAll ? Theme.Colors.successTint : Theme.Colors.warningTint)
        .clipShape(Capsule())
    }
}
