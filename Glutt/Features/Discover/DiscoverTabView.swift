import SwiftData
import SwiftUI

/// The Discover tab — one surface, two modes behind a floating toggle:
/// **Deck** is the full-screen photo-recipe swipe deck (Plates); **Videos** is a
/// feed of recipe video clips. The deck stays mounted (just hidden) when you
/// switch to Videos, so you keep your place; the video feed mounts only while
/// active so nothing plays in the background.
struct DiscoverTabView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case deck = "Deck"
        case videos = "Videos"
        var id: String { rawValue }
    }

    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var mode: Mode = .deck
    @State private var videosModel = DiscoverFeedViewModel()

    /// Taste hint for the suggested video feed: the most common tags across saved recipes.
    private var tasteTags: [String] {
        let counts = recipes
            .filter { $0.parentRecipe == nil }
            .flatMap { $0.tags }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Deck stays mounted so its position/feed survive a trip to Videos.
            PlatesTabView(hidesTitle: true)
                .opacity(mode == .deck ? 1 : 0)
                .allowsHitTesting(mode == .deck)

            if mode == .videos {
                videosSurface
            }

            modeToggle
        }
    }

    // MARK: Videos

    private var videosSurface: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                DiscoverView(model: videosModel, tasteTags: tasteTags)
                    .padding(.top, 72) // clear the floating toggle
                    .padding(.bottom, GluttTabBar.reservedHeight)
            }
        }
    }

    // MARK: Toggle

    private var modeToggle: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { m in
                let selected = mode == m
                Button {
                    Haptics.selection()
                    mode = m
                } label: {
                    Text(m.rawValue)
                        .font(.gluttCaption.weight(.heavy))
                        .foregroundStyle(selected ? Theme.Colors.textPrimary : .white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background { if selected { Capsule().fill(.white) } }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        // A dark translucent pill reads cleanly over both the dark deck and the
        // light video surface, so the toggle looks consistent in either mode.
        .background(.black.opacity(0.4), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .padding(.top, Theme.Spacing.sm)
    }
}
