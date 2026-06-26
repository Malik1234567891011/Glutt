import SwiftUI
import SwiftData

/// The immersive Plates feed: vertical paging between full-screen cards, a 3D
/// flip to each card's recipe, and horizontal swipe-to-save / swipe-to-skip
/// with button equivalents. Presented as a fullScreenCover from RootView.
struct RecipeFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var recipes: [Recipe]
    @Query private var pantryItems: [PantryItem]

    @State private var model = PlatesFeedViewModel()
    @State private var flippedID: String?
    @State private var dragX: CGFloat = 0

    private var prefs: UserPrefs { UserPrefs.current(in: context) }

    var body: some View {
        ZStack {
            Theme.Colors.textPrimary.ignoresSafeArea()

            switch model.phase {
            case .idle, .loading:
                ProgressView().tint(.white)
            case .failed(let message):
                EmptyStateView(
                    icon: "wifi.slash",
                    title: "Couldn't load Plates",
                    message: message,
                    actionLabel: "Retry"
                ) { Task { await load() } }
            case .empty:
                deckEndCard
            case .loaded:
                pager
            }

            topBar
        }
        .task { await load() }
        .onAppear { router.floatingButtonSuppressors += 1 }
        .onDisappear { router.floatingButtonSuppressors -= 1 }
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

    // MARK: Pager

    private var pager: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.recipes.enumerated()), id: \.element.id) { _, card in
                        cardPage(card)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(card.id)
                    }
                    deckEndCard
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
        }
        .ignoresSafeArea()
    }

    private func cardPage(_ card: PlateCard) -> some View {
        let isFlipped = Binding(
            get: { flippedID == card.id },
            set: { flippedID = $0 ? card.id : nil }
        )
        return FeedCardView(
            card: card,
            isSaved: model.savedIDs.contains(card.id),
            isCookableNow: cookableNow(card),
            onSave: { Task { await model.save(card, into: context); PlatesStreak.addSaved(1) } },
            onSkip: { model.skip(card) },
            isFlipped: isFlipped,
            reduceMotion: reduceMotion
        )
        .offset(x: flippedID == card.id ? 0 : dragX)
        .rotationEffect(.degrees(flippedID == card.id ? 0 : Double(dragX / 20)))
        .overlay(swipeStamp)
        .highPriorityGesture(flippedID == card.id ? nil : swipeGesture(card))
        .safeAreaInset(edge: .bottom) { actionBar(card) }
    }

    private func swipeGesture(_ card: PlateCard) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragX = value.translation.width
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 120
                if dragX > threshold {
                    commitSwipe(card, save: true)
                } else if dragX < -threshold {
                    commitSwipe(card, save: false)
                } else {
                    withAnimation(.spring) { dragX = 0 }
                }
            }
    }

    private func commitSwipe(_ card: PlateCard, save: Bool) {
        withAnimation(.spring) { dragX = save ? 600 : -600 }
        if save { Task { await model.save(card, into: context) } } else { model.skip(card) }
        dragX = 0
    }

    @ViewBuilder
    private var swipeStamp: some View {
        if dragX > 24 {
            stamp("SAVE", color: Theme.Colors.accent).opacity(Double(min(1, dragX / 120)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(40)
        } else if dragX < -24 {
            stamp("SKIP", color: Theme.Colors.tomato).opacity(Double(min(1, -dragX / 120)))
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

    private func actionBar(_ card: PlateCard) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            circleAction(Ph.x.bold, tint: Theme.Colors.tomato) { model.skip(card) }
            Button {
                flippedID = (flippedID == card.id) ? nil : card.id
                Haptics.impact(.medium)
            } label: {
                HStack(spacing: 6) {
                    Ph.bookOpen.fill.resizable().scaledToFit().frame(width: 16, height: 16)
                    Text("Recipe").font(.gluttCaption.weight(.heavy))
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.ultraThinMaterial).clipShape(Capsule())
            }
            circleAction(Ph.heart.fill, tint: Theme.Colors.accent) { Task { await model.save(card, into: context) } }
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    private func circleAction(_ icon: Image, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.resizable().scaledToFit().frame(width: 22, height: 22)
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial).clipShape(Circle())
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Ph.x.bold.resizable().scaledToFit().frame(width: 16, height: 16)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(.ultraThinMaterial).clipShape(Circle())
                }
                Spacer()
                if model.phase == .loaded, !model.recipes.isEmpty {
                    Text("\(min(model.index + 1, model.recipes.count)) / \(model.recipes.count)")
                        .font(.gluttCaption.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial).clipShape(Capsule())
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            Spacer()
        }
    }

    private var deckEndCard: some View {
        DeckEndCardView(
            explored: model.recipes.count + model.skippedIDs.count,
            saved: model.savedIDs.count,
            onDone: { dismiss() }
        )
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
