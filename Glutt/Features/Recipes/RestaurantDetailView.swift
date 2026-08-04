import SwiftData
import SwiftUI

/// A restaurant's page: logo header plus its signature plates, as the same feed
/// cards the home screen uses. Pushed inside the Recipes tab, so the tab bar
/// stays put. The visual twin of `ChefDetailView`, with two deliberate
/// differences — an "Inspired by" pill instead of the chefs' "Official", and a
/// footnote — because these dishes are reconstructions rather than the
/// kitchen's own published recipes, and the page must not imply otherwise.
struct RestaurantDetailView: View {
    let restaurant: Restaurant

    @Environment(\.dismiss) private var dismiss
    @Query private var allRecipes: [Recipe]
    @Query private var pantryItems: [PantryItem]

    /// Followed restaurants, by slug. Persisted so the heart means something
    /// across launches; nothing else keys off it yet.
    @AppStorage("glutt.followedRestaurants") private var followedRestaurants = ""

    private var isFollowed: Bool {
        followedRestaurants.split(separator: ",").contains(Substring(restaurant.id))
    }

    private var ranked: [RestaurantContent.RankedDish] {
        RestaurantContent.ranked(for: restaurant, in: allRecipes)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.top, 50)
                    blurb
                    SectionLabel(text: "Signature plates")
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
                            .zoomCard(ZoomCardID(entry.recipe.persistentModelID, slot: "restaurant"))
                            .hapticTap()
                        }
                    }
                    .padding(.horizontal, 20)
                    reconstructionNote
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
                .accessibilityLabel(
                    isFollowed ? "Unfollow \(restaurant.name)" : "Follow \(restaurant.name)")
            }
        }
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            RestaurantLogo(restaurant: restaurant, size: 66, shadowOpacity: 0.12)
            VStack(alignment: .leading, spacing: 0) {
                inspiredPill.padding(.bottom, 4)
                Text(restaurant.name)
                    .font(BrandFont.bricolage(27, 700))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.Colors.heading)
                    .lineLimit(2)
                Text("\(restaurant.credit) · ^[\(ranked.count) dish](inflect: true)")
                    .font(BrandFont.nunito(13, 700))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.horizontal, 20)
    }

    /// Deliberately NOT the chefs' "Official" badge. Claiming a restaurant
    /// endorsed recipes it has never seen is the one thing this page must not do.
    private var inspiredPill: some View {
        HStack(spacing: 4) {
            MS.restaurantFill.sized(13).foregroundStyle(Theme.Colors.amber)
            Text("Inspired by")
                .font(BrandFont.nunito(11, 800))
                .foregroundStyle(Theme.Colors.amber)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.Colors.amberChip))
    }

    private var blurb: some View {
        Text(restaurant.blurb)
            .font(BrandFont.nunito(14, 600))
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.top, 14)
    }

    private var reconstructionNote: some View {
        Text("Reconstructed from \(restaurant.name)'s menu, plating and reviews — "
             + "not the restaurant's own published recipes.")
            .font(BrandFont.nunito(12, 600))
            .foregroundStyle(Theme.Colors.muted)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.top, 18)
    }

    // MARK: - Actions

    private func toggleFollow() {
        var slugs = followedRestaurants.split(separator: ",").map(String.init)
        if let index = slugs.firstIndex(of: restaurant.id) {
            slugs.remove(at: index)
        } else {
            slugs.append(restaurant.id)
        }
        followedRestaurants = slugs.joined(separator: ",")
    }

    private var shareText: String {
        var lines = ["🍽️ \(restaurant.name) on Glutt", restaurant.credit, ""]
        for entry in ranked {
            lines.append("\(entry.rank). \(entry.dish.title) · \(entry.recipe.timeLabel)")
        }
        return lines.joined(separator: "\n")
    }
}
