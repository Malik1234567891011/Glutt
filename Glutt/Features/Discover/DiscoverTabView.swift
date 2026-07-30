import SwiftData
import SwiftUI

/// The Discover tab, "recipe cards" design (`Glutt Screens.dc.html`): a warm cream
/// header ("Picked for you" / Discover + a streak chip) over the tactile photo-recipe
/// swipe **Deck** (Plates). A compact toggle flips to **Videos** — a feed of recipe
/// clips — kept off the mock's primary surface but one tap away. The deck stays
/// mounted when you visit Videos so you keep your place.
struct DiscoverTabView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case deck = "Deck"
        case videos = "Videos"
        var id: String { rawValue }
    }

    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var mode: Mode = .deck
    @State private var videosModel = DiscoverFeedViewModel()

    private var tasteTags: [String] {
        let counts = recipes
            // Bundled chef dishes are everyone's, so they say nothing about taste.
            .filter { $0.parentRecipe == nil && !$0.isChefRecipe }
            .flatMap { $0.tags }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                PlatesTabView(hidesTitle: true)
                    .opacity(mode == .deck ? 1 : 0)
                    .allowsHitTesting(mode == .deck)
                if mode == .videos { videosSurface }
            }
        }
        .background(Theme.Colors.background)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Picked for you")
                    .font(BrandFont.nunito(12, 800)).tracking(1.6).textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.accent)
                Text("Discover")
                    .font(BrandFont.bricolage(31, 700))
                    .foregroundStyle(Theme.Colors.heading)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    Haptics.selection()
                    mode = mode == .deck ? .videos : .deck
                } label: {
                    Text(mode == .deck ? "Videos" : "Deck")
                        .font(BrandFont.nunito(12, 800))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.Colors.accent.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(Theme.Colors.accent.opacity(0.22), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                streakChip
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var streakChip: some View {
        let days = max(1, PlatesStreak.current)
        return HStack(spacing: 6) {
            MS.fireFill.sized(16).foregroundStyle(Theme.Colors.coralBright)
            Text("^[\(days) day](inflect: true)")
                .font(BrandFont.nunito(13, 800)).foregroundStyle(Theme.Colors.amber)
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background(Capsule().fill(Theme.Colors.amberChip))
    }

    // MARK: Videos

    private var videosSurface: some View {
        ScrollView {
            DiscoverView(model: videosModel, tasteTags: tasteTags)
                .padding(.top, 12)
                .padding(.bottom, GluttTabBar.reservedHeight)
        }
    }
}
