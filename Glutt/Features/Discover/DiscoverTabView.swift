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
    @State private var videoQuery = ""
    @FocusState private var videoSearchFocused: Bool

    private var tasteTags: [String] {
        let counts = recipes
            // Bundled chef and restaurant dishes are everyone's, so they say
            // nothing about this cook's taste.
            .filter { $0.parentRecipe == nil && !$0.isCuratedRecipe }
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
        // Outside the ScrollView on purpose: a proxy inside one measures the
        // content, which is exactly the runaway height being corrected here.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    videoSearchField
                    DiscoverView(
                        model: videosModel,
                        tasteTags: tasteTags,
                        playerMaxHeight: playerMaxHeight(viewport: proxy.size.height)
                    )
                }
                .padding(.top, 12)
                .padding(.bottom, GluttTabBar.reservedHeight)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// Height left for the player once everything that must stay visible with it
    /// is accounted for: the search field, the title and creator lines, the
    /// button row, the gaps between them, and the tab bar the scroll view runs
    /// underneath. The floor keeps the player watchable on the smallest phones,
    /// where scrolling a little is the better trade.
    private func playerMaxHeight(viewport: CGFloat) -> CGFloat {
        let chrome: CGFloat = 50 + 76 + 44 + 70 + GluttTabBar.reservedHeight
        return max(260, viewport - chrome)
    }

    private var videoSearchField: some View {
        HStack(spacing: 10) {
            MS.search.sized(20).foregroundStyle(Theme.Colors.muted)
            TextField("miso salmon, birria tacos…", text: $videoQuery)
                .font(BrandFont.nunito(15, 600))
                .foregroundStyle(Theme.Colors.heading)
                .tint(Theme.Colors.accent)
                .focused($videoSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { runVideoSearch() }
            if !videoQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    videoQuery = ""
                    videoSearchFocused = false
                    Task { await videosModel.loadSuggested(tags: tasteTags) }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 50)
        .background(Capsule().fill(Theme.Colors.card))
        .overlay(Capsule().strokeBorder(Theme.Colors.textPrimary.opacity(0.07), lineWidth: 1.5))
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func runVideoSearch() {
        let trimmed = videoQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        videoSearchFocused = false
        Task {
            if trimmed.isEmpty {
                await videosModel.loadSuggested(tags: tasteTags)
            } else {
                await videosModel.search(trimmed)
            }
        }
    }
}
