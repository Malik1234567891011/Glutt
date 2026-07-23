import SwiftUI
import SwiftData

/// The Discover tab: an endless, full-screen feed of photo recipes. Vertical
/// paging browses; a tap flips a card to its recipe; a horizontal swipe saves
/// (right) or skips (left), with button equivalents in the action bar. New
/// pages stream in as you near the end, so the feed never dead-ends.
struct PlatesTabView: View {
    /// When embedded in the Discover tab (behind the Deck|Videos toggle), the
    /// toggle serves as the header, so the deck hides its own "Discover" title.
    var hidesTitle = false

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var recipes: [Recipe]
    @Query private var pantryItems: [PantryItem]

    @State private var model = PlatesFeedViewModel()
    @State private var flippedID: String?
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0

    private var prefs: UserPrefs { UserPrefs.current(in: context) }

    /// The card queued right behind the top one (peeks through as it swipes off).
    private var nextCard: PlateCard? {
        let n = model.index + 1
        return model.recipes.indices.contains(n) ? model.recipes[n] : nil
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            switch model.phase {
            case .idle, .loading:
                ProgressView().tint(Theme.Colors.accent)
            case .failed(let message):
                EmptyStateView(
                    icon: "wifi.slash",
                    title: "Couldn't load Discover",
                    message: message,
                    actionLabel: "Retry"
                ) { Task { await load() } }
                .padding(Theme.Spacing.lg)
            case .empty:
                EmptyStateView(
                    icon: "sparkles",
                    title: "Nothing new right now",
                    message: "Come back in a bit for a fresh batch of recipes to swipe through."
                )
                .padding(Theme.Spacing.lg)
            case .loaded:
                deck
            }

            // Standalone use keeps the in-deck title; embedded in the Discover tab
            // the parent owns the "Discover" header, so hide this one.
            if flippedID == nil, !hidesTitle { header }
        }
        .task { if model.phase == .idle { await load() } }
        .alert("Couldn't save", isPresented: Binding(
            get: { model.saveError != nil }, set: { if !$0 { model.clearSaveError() } }
        )) { Button("OK", role: .cancel) {} } message: { Text(model.saveError ?? "") }
    }

    private func load() async {
        await model.loadDaily(
            rules: prefs.dietaryRules,
            allergies: prefs.allergies,
            savedSourceURLs: Set(recipes.compactMap(\.sourceURL))
        )
        PlatesStreak.recordOpen()
        PlatesStreak.addDiscovered(model.recipes.count)
    }

    // MARK: Deck (single-card swipe)

    private var deck: some View {
        VStack(spacing: 14) {
            ZStack {
                if let card = model.current {
                    deckBackers
                    // The next card peeks behind so it's revealed as the top swipes away.
                    if let next = nextCard {
                        FeedCardView(
                            card: next,
                            isSaved: model.savedIDs.contains(next.id),
                            isCookableNow: cookableNow(next),
                            onSave: {}, onSkip: {},
                            isFlipped: .constant(false),
                            reduceMotion: true
                        )
                        .scaleEffect(0.985)
                        .allowsHitTesting(false)
                    }
                    topCard(card)
                } else {
                    exhaustedState
                }
            }
            .frame(maxHeight: .infinity)

            if model.current != nil, flippedID == nil {
                Text("Swipe right to save, left to skip")
                    .font(BrandFont.nunito(12.5, 700))
                    .foregroundStyle(Theme.Colors.muted)
                actionBar()
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, GluttTabBar.reservedHeight)
    }

    /// Two tilted cream cards peeking behind the top card for a tactile "deck" look.
    private var deckBackers: some View {
        ZStack {
            deckBacker(rotation: 4, scale: 0.965)
            deckBacker(rotation: -3.5, scale: 0.982)
        }
    }

    private func deckBacker(rotation: Double, scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Theme.Colors.card)
            .shadow(color: Theme.Colors.textPrimary.opacity(0.09), radius: 12, y: 10)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .allowsHitTesting(false)
    }

    private func topCard(_ card: PlateCard) -> some View {
        let isFlipped = Binding(
            get: { flippedID == card.id },
            set: { flippedID = $0 ? card.id : nil }
        )
        let flipped = flippedID == card.id
        return FeedCardView(
            card: card,
            isSaved: model.savedIDs.contains(card.id),
            isCookableNow: cookableNow(card),
            onSave: { commitSwipe(save: true) },
            onSkip: { commitSwipe(save: false) },
            isFlipped: isFlipped,
            reduceMotion: reduceMotion
        )
        .frame(maxHeight: .infinity)
        .offset(x: flipped ? 0 : dragX, y: flipped ? 0 : dragY)
        .rotationEffect(.degrees(flipped ? 0 : Double(dragX / 22)))
        .overlay(swipeStamp)
        .gesture(flipped ? nil : swipeGesture)
    }

    private var exhaustedState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView().tint(Theme.Colors.accent)
            Text("Finding more recipes…")
                .font(.gluttBody).foregroundStyle(Theme.Colors.textSecondary)
        }
        .task { await model.loadMoreIfNeeded(currentIndex: model.index) }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragX = value.translation.width
                dragY = value.translation.height * 0.35
            }
            .onEnded { value in
                let threshold: CGFloat = 110
                let tx = value.translation.width
                let ty = value.translation.height
                if abs(tx) >= abs(ty) {
                    if tx > threshold { commitSwipe(save: true) }
                    else if tx < -threshold { commitSwipe(save: false) }
                    else { springBack() }
                } else if ty < -threshold {
                    commitSwipe(save: false)   // swipe up = skip to next
                } else {
                    springBack()
                }
            }
    }

    private func springBack() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            dragX = 0
            dragY = 0
        }
    }

    /// Flies the top card off, then advances to the next one (via the view
    /// model, which auto-advances on save/skip) and drops the offset back to
    /// center so the revealed card sits correctly.
    private func commitSwipe(save: Bool) {
        guard let card = model.current else { return }
        Haptics.impact(.medium)
        withAnimation(.easeIn(duration: 0.22)) {
            dragX = save ? 700 : -700
            dragY = 0
        }
        Task {
            try? await Task.sleep(for: .seconds(0.22))
            flippedID = nil
            if save {
                await model.save(card, into: context)
                PlatesStreak.addSaved(1)
            } else {
                model.skip(card)
            }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                dragX = 0
                dragY = 0
            }
            await model.loadMoreIfNeeded(currentIndex: model.index)
        }
    }

    @ViewBuilder
    private var swipeStamp: some View {
        if dragX > 24 {
            stamp("SAVE", color: Theme.Colors.accent).opacity(Double(min(1, dragX / 110)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(40)
        } else if dragX < -24 {
            stamp("SKIP", color: Theme.Colors.tomato).opacity(Double(min(1, -dragX / 110)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(40)
        }
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(BrandFont.bricolage(24, 700))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color, lineWidth: 3))
            .rotationEffect(.degrees(-12))
    }

    // MARK: Action bar (button equivalents for the gestures)

    private func actionBar() -> some View {
        let card = model.current
        let isSaved = card.map { model.savedIDs.contains($0.id) } ?? false
        return HStack(spacing: 18) {
            circleAction(MS.undo, glyph: Theme.Colors.amber, bg: Theme.Colors.card, size: 46, bordered: true) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.undo() }
            }
            circleAction(MS.closeIcon, glyph: Theme.Colors.coralBright, bg: Theme.Colors.card, size: 60, bordered: false) {
                commitSwipe(save: false)
            }
            circleAction(isSaved ? MS.checkFill : MS.favoriteFill, glyph: Theme.Colors.creamText,
                         bg: Theme.Colors.accent, size: 68, bordered: false) {
                commitSwipe(save: true)
            }
            circleAction(MS.menuBookFill, glyph: Theme.Colors.accent, bg: Theme.Colors.card, size: 46, bordered: true) {
                if let card { flippedID = card.id; Haptics.impact(.medium) }
            }
        }
    }

    private func circleAction(_ icon: MS, glyph: Color, bg: Color, size: CGFloat, bordered: Bool,
                              action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            icon.sized(size * 0.42).foregroundStyle(glyph)
                .frame(width: size, height: size)
                .background(Circle().fill(bg))
                .overlay(bordered ? Circle().strokeBorder(Theme.Colors.textPrimary.opacity(0.10), lineWidth: 1.5) : nil)
                .shadow(color: Theme.Colors.textPrimary.opacity(bordered ? 0.05 : 0.14),
                        radius: bordered ? 10 : 18, y: bordered ? 4 : 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: Top bar

    private var header: some View {
        VStack {
            HStack(alignment: .center) {
                if !hidesTitle {
                    Text("Discover")
                        .font(BrandFont.bricolage(22, 700))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                }
                Spacer()
                if model.phase == .loaded, !model.recipes.isEmpty {
                    // Endless feed: show a running tally, not "X of N" (which
                    // wrongly implies the deck is finite and about to run out).
                    HStack(spacing: 4) {
                        Ph.sparkle.fill.resizable().scaledToFit().frame(width: 11, height: 11)
                        Text("\(model.index + 1)")
                    }
                    .font(.gluttCaption.weight(.heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial).clipShape(Capsule())
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            Spacer()
        }
    }

    // MARK: Cookable-now

    private func cookableNow(_ card: PlateCard) -> Bool {
        let available = pantryItems.filter { $0.roughQuantity != .out }
        let required = card.ingredients.filter { ($0.name ?? $0.raw).isEmpty == false }
        guard !required.isEmpty else { return false }
        let missing = required.filter { ing in
            let canonical = IngredientCanonicalizer.canonicalize(ing.name ?? ing.raw)
            return !PantryMatcher.owns(ingredientNamed: canonical, available: available)
        }
        return missing.count <= 1
    }
}
