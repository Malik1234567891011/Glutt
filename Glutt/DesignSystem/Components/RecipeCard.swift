import SwiftUI
import PhosphorSwift

/// The core recipe card: panel-tint media block with food photo, a tag pill,
/// a title/summary block, and a foundation StatPill row.
struct RecipeCard: View {
    let recipe: Recipe
    /// Pantry match (owned, total non-optional). Nil hides the indicator.
    var pantryMatch: (owned: Int, total: Int)?

    private var panelTint: Color {
        // stable per-recipe pick from the rotating decorative set
        abs(recipe.persistentModelID.hashValue) % 2 == 0 ? Theme.Colors.sagePanel : Theme.Colors.peachPanel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            mediaBlock
            Text(recipe.title)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
            if let summary = recipe.summary, !summary.isEmpty {
                Text(summary)
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            statRow
        }
        .padding(12)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous)
                .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Theme.Colors.textPrimary.opacity(0.07), radius: 10, x: 0, y: 3)
    }

    private var mediaBlock: some View {
        ZStack(alignment: .topTrailing) {
            panelTint
            HStack(spacing: 0) {
                RecipeImageView(recipe: recipe)
                    .containerRelativeFrame(.horizontal) { w, _ in w * 0.63 }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.photo, style: .continuous))
                Spacer(minLength: 0)
            }
            if let tag = recipe.tags.first {
                tagPill(tag)
                    .padding(8)
            }
        }
        .frame(height: 148)
        .frame(maxWidth: .infinity)
        .background(panelTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.photo, style: .continuous))
    }

    private func tagPill(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Ph.forkKnife.regular.resizable().scaledToFit().frame(width: 11, height: 11)
            Text(tag).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tag, style: .continuous))
    }

    @ViewBuilder private var statRow: some View {
        HStack(spacing: 8) {
            StatPill.time("\(recipe.estimatedMinutes) min")
            StatPill.difficulty(recipe.difficulty.label)
            if let rating = recipe.rating {
                StatPill.rating("\(rating)")
            }
            if let pantryMatch, pantryMatch.total > 0 {
                StatPill(icon: Ph.basket.fill,
                         text: "\(pantryMatch.owned)/\(pantryMatch.total)",
                         foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
            }
            Spacer(minLength: 0)
        }
    }
}
