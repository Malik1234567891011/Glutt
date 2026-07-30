import SwiftUI

/// The Feed home's big single-column recipe card: a 180pt photo with a solid tag
/// pill, then title, one-line summary, and a stat-pill row
/// (time · difficulty · rating · pantry match). Source: `Glutt Main Page.dc.html`,
/// direction B feed cards. Favoriting lives on the detail screen, not here.
struct FeedRecipeCard: View {
    let recipe: Recipe
    let match: PantryMatcher.MatchResult
    /// Chef pages put the recipe's rank in that chef's top five where the tag
    /// pill normally sits.
    var rank: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RecipeImageView(recipe: recipe)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
                if let rank {
                    rankPill(rank).padding(11)
                } else if let tag = recipe.tags.first {
                    tagPill(tag).padding(11)
                }
            }
            .frame(height: 180)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                Text(recipe.title)
                    .font(BrandFont.bricolage(20, 600))
                    .foregroundStyle(Theme.Colors.heading)
                    .lineLimit(2)
                if let summary = recipe.summary, !summary.isEmpty {
                    Text(summary)
                        .font(BrandFont.nunito(13, 600))
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(1)
                        .padding(.top, 4)
                }
                statRow.padding(.top, 12)
            }
            .padding(.horizontal, 15)
            .padding(.top, 13)
            .padding(.bottom, 15)
        }
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous)
            .strokeBorder(Theme.Colors.textPrimary.opacity(0.05), lineWidth: 1))
        .shadow(color: Theme.Colors.textPrimary.opacity(0.06), radius: 18, y: 10)
    }

    // MARK: Media overlays

    /// "Number 1" and up, in the tag pill's slot. Only the top spot gets a flame.
    private func rankPill(_ rank: Int) -> some View {
        HStack(spacing: 5) {
            if rank == 1 {
                MS.fireFill.sized(14).foregroundStyle(Theme.Colors.tomato)
            }
            Text("Number \(rank)").font(BrandFont.nunito(12, 800)).foregroundStyle(Theme.Colors.heading)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(Theme.Colors.card))
    }

    private func tagPill(_ tag: String) -> some View {
        let style = Self.tagStyle(tag)
        return HStack(spacing: 5) {
            style.icon.sized(14).foregroundStyle(style.color)
            Text(tag).font(BrandFont.nunito(12, 800)).foregroundStyle(Theme.Colors.heading)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(Theme.Colors.card))
    }

    // MARK: Stat row

    private var statRow: some View {
        HStack(spacing: 7) {
            pill(icon: MS.schedule, text: recipe.timeLabel,
                 fg: Color(hex: 0x4A4238), bg: Theme.Colors.surface2, iconColor: Theme.Colors.textSecondary)
            pill(icon: nil, text: recipe.difficulty.label,
                 fg: Color(hex: 0x4A4238), bg: Theme.Colors.surface2, iconColor: .clear)
            if let rating = recipe.rating {
                pill(icon: MS.starFill, text: "\(rating)",
                     fg: Theme.Colors.amber, bg: Theme.Colors.amberChip, iconColor: Theme.Colors.amber)
            }
            pantryPill
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var pantryPill: some View {
        let haveAll = match.totalCount > 0 && match.ownedCount >= match.totalCount
        if match.totalCount > 0 {
            if haveAll {
                pill(icon: MS.checkCircleFill, text: "Have it all",
                     fg: Theme.Colors.accent, bg: Theme.Colors.greenTint, iconColor: Theme.Colors.accent)
            } else {
                let short = match.totalCount - match.ownedCount
                let needy = Double(match.ownedCount) / Double(match.totalCount) < 0.75
                pill(icon: MS.shoppingBasketFill,
                     text: "\(match.ownedCount)/\(match.totalCount)",
                     fg: needy ? Theme.Colors.amber : Theme.Colors.accent,
                     bg: needy ? Theme.Colors.amberChip : Theme.Colors.greenTint,
                     iconColor: needy ? Theme.Colors.amber : Theme.Colors.accent)
                    .accessibilityLabel("\(match.ownedCount) of \(match.totalCount) in pantry, need \(short)")
            }
        }
    }

    private func pill(icon: MS?, text: String, fg: Color, bg: Color, iconColor: Color) -> some View {
        HStack(spacing: 5) {
            if let icon { icon.sized(14).foregroundStyle(iconColor) }
            Text(text).font(BrandFont.nunito(12, 800)).foregroundStyle(fg)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(bg))
    }

    // MARK: Tag → icon + color

    static func tagStyle(_ tag: String) -> (icon: MS, color: Color) {
        let t = tag.lowercased()
        if t.contains("spic") || t.contains("hot") { return (.fireFill, Theme.Colors.tomato) }
        if t.contains("protein") { return (.boltFill, Theme.Colors.accent) }
        if t.contains("prep") || t.contains("batch") { return (.lunchDiningFill, Theme.Colors.accent) }
        if t.contains("veg") || t.contains("plant") || t.contains("green") { return (.ecoFill, Theme.Colors.accent) }
        if t.contains("omega") || t.contains("fish") || t.contains("seafood") { return (.restaurantFill, Theme.Colors.accent) }
        return (.restaurantFill, Theme.Colors.accent)
    }
}
