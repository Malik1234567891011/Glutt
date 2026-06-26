import SwiftUI

/// One full-screen plate: hero photo front (title + stat strip + flip handle)
/// and a 3D-flip back (macros + servings + ingredients + steps + CTAs).
struct FeedCardView: View {
    let card: PlateCard
    let isSaved: Bool
    let isCookableNow: Bool
    let onSave: () -> Void
    let onSkip: () -> Void
    @Binding var isFlipped: Bool
    var reduceMotion: Bool = false

    @State private var displayServings: Int = 2

    private var scale: Double {
        guard let base = card.servings, base > 0 else { return 1 }
        return Double(displayServings) / Double(base)
    }

    var body: some View {
        ZStack {
            if reduceMotion {
                // Cross-fade instead of 3D rotation when Reduce Motion is on.
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
        .onAppear { displayServings = card.servings ?? 2 }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.8), value: isFlipped)
    }

    // MARK: Front

    private var front: some View {
        ZStack(alignment: .bottomLeading) {
            heroImage
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if isCookableNow {
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

                Text(card.title)
                    .font(.gluttLargeTitle)
                    .foregroundStyle(.white)
                    .lineLimit(3)

                if let creator = card.creator {
                    Text(creator)
                        .font(.gluttCaption)
                        .foregroundStyle(.white.opacity(0.85))
                }

                statStrip

                flipHandle
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, 80)  // clear the action bar
        }
        .contentShape(Rectangle())
        .onTapGesture { flip() }
    }

    private var heroImage: some View {
        GeometryReader { geo in
            AsyncImage(url: card.imageURL.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default:
                    Theme.Colors.accent.opacity(0.08)
                        .overlay(Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(Theme.Colors.accent.opacity(0.35)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
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

    private var flipHandle: some View {
        HStack(spacing: 6) {
            Ph.bookOpen.fill.resizable().scaledToFit().frame(width: 16, height: 16)
            Text("Recipe").font(.gluttCaption.weight(.heavy))
            Ph.caretRight.bold.resizable().scaledToFit().frame(width: 11, height: 11)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .onTapGesture { flip() }
        .accessibilityLabel("Show recipe")
    }

    // MARK: Back

    private var back: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text(card.title).font(.gluttTitle).foregroundStyle(Theme.Colors.textPrimary)

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
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
        .padding(Theme.Spacing.sm)
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
