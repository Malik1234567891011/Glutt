import SwiftData
import SwiftUI

/// A chef's page: portrait header plus their five most popular recipes, as the
/// same feed cards the home screen uses. Pushed inside the Recipes tab, so the
/// tab bar stays put.
struct ChefDetailView: View {
    let chef: Chef

    @Environment(\.dismiss) private var dismiss
    @Query private var allRecipes: [Recipe]
    @Query private var pantryItems: [PantryItem]

    /// Followed chefs, by slug. Persisted so the heart means something across
    /// launches; nothing else keys off it yet.
    @AppStorage("glutt.followedChefs") private var followedChefs = ""

    private var isFollowed: Bool {
        followedChefs.split(separator: ",").contains(Substring(chef.id))
    }

    private var ranked: [ChefContent.RankedDish] {
        ChefContent.ranked(for: chef, in: allRecipes)
    }

    var body: some View {
        // No top bar: one continuous surface, with the back/share/heart circles
        // floating over it so the cards scroll straight through underneath.
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.top, 50)
                    SectionLabel(text: "Most popular")
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                        .padding(.bottom, 12)
                    LazyVStack(spacing: 16) {
                        ForEach(ranked) { entry in
                            NavigationLink(value: entry.recipe) {
                                FeedRecipeCard(
                                    recipe: entry.recipe,
                                    match: PantryMatcher.match(recipe: entry.recipe, pantry: pantryItems),
                                    rank: entry.rank
                                )
                            }
                            .zoomCard(ZoomCardID(entry.recipe.persistentModelID, slot: "chef"))
                            .hapticTap()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, GluttTabBar.reservedHeight + 44)
                }
            }
            topBar
        }
        .background(Theme.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                Haptics.impact(.light); dismiss()
            } label: {
                circleButton { MS.arrowBack.sized(22).foregroundStyle(Color(hex: 0x3A342C)) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()

            HStack(spacing: 9) {
                ShareLink(item: shareText) {
                    circleButton { MS.iosShare.sized(21).foregroundStyle(Color(hex: 0x3A342C)) }
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.impact(.medium); toggleFollow()
                } label: {
                    circleButton {
                        (isFollowed ? MS.favoriteFill : MS.favorite).sized(21)
                            .foregroundStyle(Theme.Colors.tomato)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFollowed ? "Unfollow \(chef.name)" : "Follow \(chef.name)")
            }
        }
        // 8, not the board's 56: the board measures from the top of the screen,
        // this sits below the pushed view's safe area inset already.
        .padding(.top, 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func circleButton(@ViewBuilder _ glyph: () -> some View) -> some View {
        glyph()
            .frame(width: 42, height: 42)
            .background(Circle().fill(Theme.Colors.card))
            .overlay(Circle().strokeBorder(Theme.Colors.textPrimary.opacity(0.07), lineWidth: 1.5))
            .shadow(color: Theme.Colors.textPrimary.opacity(0.05), radius: 10, y: 3)
    }

    // MARK: - Chef header

    private var header: some View {
        HStack(spacing: 14) {
            ChefPortrait(chef: chef, size: 66, shadowOpacity: 0.12)
            VStack(alignment: .leading, spacing: 0) {
                officialPill.padding(.bottom, 4)
                Text(chef.name)
                    .font(BrandFont.bricolage(27, 700))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.Colors.heading)
                    .lineLimit(2)
                Text("\(chef.credit) · ^[\(ranked.count) recipe](inflect: true)")
                    .font(BrandFont.nunito(13, 700))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.horizontal, 20)
    }

    private var officialPill: some View {
        HStack(spacing: 4) {
            MS.verifiedFill.sized(13).foregroundStyle(Theme.Colors.accent)
            Text("Official")
                .font(BrandFont.nunito(11, 800))
                .foregroundStyle(Theme.Colors.accent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.Colors.greenTint))
    }

    // MARK: - Actions

    private func toggleFollow() {
        var slugs = followedChefs.split(separator: ",").map(String.init)
        if let index = slugs.firstIndex(of: chef.id) {
            slugs.remove(at: index)
        } else {
            slugs.append(chef.id)
        }
        followedChefs = slugs.joined(separator: ",")
    }

    private var shareText: String {
        var lines = ["🍳 \(chef.name) on Glutt", chef.credit, ""]
        for entry in ranked {
            lines.append("\(entry.rank). \(entry.dish.title) · \(entry.recipe.timeLabel)")
        }
        return lines.joined(separator: "\n")
    }
}
