import SwiftUI

/// One plate in the Discover feed: an inset, rounded hero card. The front is a
/// framed photo (title + stat strip + a tap-for-recipe hint); tapping flips it
/// to the recipe back (macros + servings + ingredients + steps + save). Being
/// inset with rounded corners — rather than raw edge-to-edge — keeps the photo
/// looking intentional instead of cropped and unformatted.
struct FeedCardView: View {
    let card: PlateCard
    let isSaved: Bool
    let isCookableNow: Bool
    let onSave: () -> Void
    let onSkip: () -> Void
    @Binding var isFlipped: Bool
    var reduceMotion: Bool = false

    @State private var displayServings: Int = 2

    private let cardRadius: CGFloat = Theme.Radius.sheet

    private var scale: Double {
        guard let base = card.servings, base > 0 else { return 1 }
        return Double(displayServings) / Double(base)
    }

    var body: some View {
        ZStack {
            if reduceMotion {
                if isFlipped { back } else { front }
            } else {
                front
                    .opacity(isFlipped ? 0 : 1)
                    .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                back
                    .opacity(isFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
        .onAppear { displayServings = card.servings ?? 2 }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.8), value: isFlipped)
    }

    // MARK: Front

    private var front: some View {
        ZStack(alignment: .bottomLeading) {
            heroImage

            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if isCookableNow { cookableBadge }

                Text(card.title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)

                if let creator = card.creator, !creator.isEmpty {
                    Text(creator)
                        .font(.gluttCaption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }

                statStrip
                flipHint
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .onTapGesture { flip() }
    }

    private var heroImage: some View {
        // Color.clear fixes the frame to the card; the image draws into the
        // overlay and `scaledToFill` overflow is clipped to that frame (a bare
        // AsyncImage + scaledToFill reports the photo's huge intrinsic size and
        // spills past the card edges).
        Color.clear
            .overlay {
                AsyncImage(url: card.imageURL.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ZStack {
                            Theme.Colors.card
                            ProgressView().tint(Theme.Colors.accent)
                        }
                    default:
                        ZStack {
                            Theme.Colors.accent.opacity(0.12)
                            Ph.forkKnife.fill
                                .resizable().scaledToFit()
                                .frame(width: 48, height: 48)
                                .foregroundStyle(Theme.Colors.accent.opacity(0.4))
                        }
                    }
                }
            }
            .clipped()
    }

    private var cookableBadge: some View {
        HStack(spacing: 4) {
            Ph.basket.fill.resizable().scaledToFit().frame(width: 13, height: 13)
            Text("You can make this now")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.Colors.accent)
        .clipShape(Capsule())
    }

    private var statStrip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let cook = card.cookMinutes, cook > 0 {
                StatPill.time("\(cook) min")
            }
            if let cal = card.macros?.caloriesInt {
                StatPill(icon: Ph.flame.fill, text: "\(cal) cal",
                         foreground: Theme.Colors.tomato, background: Theme.Colors.tomatoTint)
            }
            if let protein = card.macros?.proteinInt {
                StatPill(icon: Ph.barbell.fill, text: "\(protein)g protein")
            }
        }
    }

    private var flipHint: some View {
        HStack(spacing: 6) {
            Ph.bookOpen.fill.resizable().scaledToFit().frame(width: 15, height: 15)
            Text("Tap for recipe").font(.gluttCaption.weight(.heavy))
            Ph.caretRight.regular.resizable().scaledToFit().frame(width: 10, height: 10)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.top, 2)
    }

    // MARK: Back

    private var back: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HStack(alignment: .top) {
                        Text(card.title).font(.gluttTitle).foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Button { flip() } label: {
                            Ph.x.regular.resizable().scaledToFit().frame(width: 14, height: 14)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.border.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if let m = card.macros {
                        MacroStrip(calories: m.caloriesInt, protein: m.proteinInt,
                                   carbs: m.carbsInt, fat: m.fatInt, isEstimated: m.estimated)
                    }

                    HStack {
                        Text("Servings").font(.gluttHeadline)
                        Spacer()
                        GluttStepper(value: $displayServings, in: 1...24, step: 1) { "\($0)" }
                    }

                    if !card.ingredients.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionLabel(text: "Ingredients")
                            ForEach(Array(card.ingredients.enumerated()), id: \.offset) { _, ing in
                                Text("• \(scaledLine(ing))")
                                    .font(.gluttBody)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                        }
                    }

                    if !card.steps.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionLabel(text: "Steps")
                            ForEach(Array(card.steps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                    Text("\(i + 1)")
                                        .font(.gluttCaption.weight(.heavy))
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Theme.Colors.accent)
                                        .clipShape(Circle())
                                    Text(step).font(.gluttBody).foregroundStyle(Theme.Colors.textPrimary)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }

            Button {
                Haptics.celebrate()
                onSave()
            } label: {
                Text(isSaved ? "Saved ✓" : "Save to cookbook").frame(maxWidth: .infinity)
            }
            .buttonStyle(.gluttPrimary)
            .disabled(isSaved)
            .padding(Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
    }

    private func scaledLine(_ ing: PlateIngredient) -> String {
        guard let qty = ing.quantity else { return ing.raw }
        let scaled = qty * scale
        let qtyText = scaled == scaled.rounded() ? String(Int(scaled)) : String(format: "%.1f", scaled)
        let unit = (ing.unit?.isEmpty == false) ? " \(ing.unit!)" : ""
        let name = ing.name ?? ing.raw
        return "\(qtyText)\(unit) \(name)"
    }

    private func flip() {
        if !reduceMotion { Haptics.impact(.medium) }
        isFlipped.toggle()
    }
}
