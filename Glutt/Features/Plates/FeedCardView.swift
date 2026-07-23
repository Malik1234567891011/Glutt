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

    // MARK: Front — cream "recipe card" (Glutt Screens.dc.html, Discover)

    private var front: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                heroImage.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                if isCookableNow { cookableBadge.padding(12) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                Text(card.title)
                    .font(BrandFont.bricolage(24, 700))
                    .foregroundStyle(Theme.Colors.heading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let creator = card.creator, !creator.isEmpty {
                    Text(creator)
                        .font(BrandFont.nunito(13, 700))
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(1)
                        .padding(.top, 5)
                }
                statStrip.padding(.top, 13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture { flip() }
    }

    private var heroImage: some View {
        Color.clear
            .overlay {
                AsyncImage(url: card.imageURL.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().interpolation(.high).antialiased(true).scaledToFill()
                    case .empty:
                        ZStack { Theme.Colors.surface2; ProgressView().tint(Theme.Colors.accent) }
                    default:
                        ZStack {
                            Theme.Colors.accent.opacity(0.10)
                            MS.restaurantFill.sized(46).foregroundStyle(Theme.Colors.accent.opacity(0.4))
                        }
                    }
                }
            }
            .clipped()
    }

    private var cookableBadge: some View {
        HStack(spacing: 6) {
            MS.checkCircleFill.sized(15).foregroundStyle(Theme.Colors.accent)
            Text("You can make this now")
                .font(BrandFont.nunito(12, 800)).foregroundStyle(Theme.Colors.accent)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Theme.Colors.card.opacity(0.85), in: Capsule())
    }

    private var statStrip: some View {
        HStack(spacing: 8) {
            if let cook = card.cookMinutes, cook > 0 {
                deckPill(MS.schedule, "\(cook) min", fg: Color(hex: 0x4A4238), bg: Theme.Colors.surface2, iconColor: Theme.Colors.textSecondary)
            }
            if let cal = card.macros?.caloriesInt {
                deckPill(MS.fireFill, "\(cal) cal", fg: Color(hex: 0x4A4238), bg: Theme.Colors.surface2, iconColor: Theme.Colors.coralBright)
            }
            if let protein = card.macros?.proteinInt {
                deckPill(MS.boltFill, "\(protein)g", fg: Theme.Colors.accent, bg: Theme.Colors.greenTint, iconColor: Theme.Colors.accent)
            }
        }
    }

    private func deckPill(_ icon: MS, _ text: String, fg: Color, bg: Color, iconColor: Color) -> some View {
        HStack(spacing: 5) {
            icon.sized(15).foregroundStyle(iconColor)
            Text(text).font(BrandFont.nunito(12.5, 800)).foregroundStyle(fg)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(bg))
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
