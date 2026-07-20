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
            Theme.Colors.textPrimary.ignoresSafeArea()

            switch model.phase {
            case .idle, .loading:
                ProgressView().tint(.white)
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

            // Hide the header behind a flipped card so its light face reads cleanly.
            if flippedID == nil { header }
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
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
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
                    .scaleEffect(0.94)
                    .opacity(0.6)
                    .allowsHitTesting(false)
                }

                if let card = model.current {
                    topCard(card)
                } else {
                    exhaustedState
                }
            }
            .frame(maxHeight: .infinity)

            if model.current != nil, flippedID == nil {
                actionBar()
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        // Clear the custom tab bar: the feed fills the whole tab region, which
        // extends behind the bar, so the action row needs explicit clearance.
        .padding(.bottom, GluttTabBar.reservedHeight)
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
            ProgressView().tint(.white)
            Text("Finding more recipes…")
                .font(.gluttBody).foregroundStyle(.white.opacity(0.8))
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
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color, lineWidth: 3))
            .rotationEffect(.degrees(-12))
    }

    // MARK: Action bar (button equivalents for the gestures)

    private func actionBar() -> some View {
        let card = model.current
        let isSaved = card.map { model.savedIDs.contains($0.id) } ?? false
        return HStack(spacing: Theme.Spacing.lg) {
            circleAction(Ph.x.regular, fg: Theme.Colors.tomato, bg: .white, size: 56) {
                commitSwipe(save: false)
            }
            Button {
                if let card { flippedID = card.id; Haptics.impact(.medium) }
            } label: {
                HStack(spacing: 6) {
                    Ph.bookOpen.fill.resizable().scaledToFit().frame(width: 16, height: 16)
                    Text("Recipe").font(.gluttBody.weight(.heavy))
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            circleAction(
                isSaved ? Ph.check.bold : Ph.heart.fill,
                fg: .white, bg: Theme.Colors.accent, size: 56
            ) { commitSwipe(save: true) }
        }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private func circleAction(_ icon: Image, fg: Color, bg: Color, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            icon.resizable().scaledToFit().frame(width: size * 0.38, height: size * 0.38)
                .foregroundStyle(fg)
                .frame(width: size, height: size)
                .background(bg, in: Circle())
        }
    }

    // MARK: Top bar

    private var header: some View {
        VStack {
            HStack(alignment: .center) {
                if !hidesTitle {
                    Text("Discover")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
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
