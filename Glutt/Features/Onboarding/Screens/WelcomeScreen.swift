import SwiftUI

/// Screen 0 — full-bleed masonry of recipe photos under a rising cream scrim,
/// wordmark + H1 + social-proof pill + Start. Values from the design HTML.
struct WelcomeScreen: View {
    let onStart: () -> Void

    /// 11 tiles; spans from the HTML (tiles 1 & 5 span 3 rows, rest span 2).
    private static let tiles: [(asset: String, span: Int)] = [
        ("hotHoneyChickenRice", 3), ("greenGoddessSteakPlate", 2), ("chickenRiceBowl", 2),
        ("greekYogurtBowl", 2), ("garlicButterSteakPotatoBowl", 3), ("koftaFlatbreadWrap", 2),
        ("lemonDillSalmonBowl", 2), ("beefWrapWithWedges", 2), ("koreanBeefMealPrep", 2),
        ("pestoGnocchiMealPrep", 2), ("steakFajitaSalad", 2),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            masonry
                .padding(.horizontal, 12)
                // BOTH bounds so the frame clamps to the screen proposal — with
                // only maxHeight, the taller-than-screen marquee stacks inflate
                // the frame (and the ZStack), shoving the bottom-aligned
                // content ~1400pt below the visible screen.
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
                .ignoresSafeArea(edges: .top) // tiles run under the Dynamic Island

            scrim
            content
        }
        .background(OnboardingTheme.cream)
        .ignoresSafeArea(edges: .bottom)
    }

    /// 3-column masonry, 76pt row unit, 9pt gaps — columns match the design
    /// HTML's auto-placement ({0,5,7,10}, {1,3,6,9}, {2,4,8}), each drifting
    /// downward in a seamless loop at its own speed (SketchAR-style ambience).
    private var masonry: some View {
        HStack(alignment: .top, spacing: 9) {
            MarqueeColumn(indices: [0, 5, 7, 10], speed: 12, direction: .up)
            MarqueeColumn(indices: [1, 3, 6, 9], speed: 16, direction: .down)
            MarqueeColumn(indices: [2, 4, 8], speed: 10, direction: .up)
        }
    }

    /// One endlessly-looping column: its tile stack is drawn three times and
    /// slid by exactly one copy-height, so the wrap seam is invisible and the
    /// screen stays covered even for columns shorter than the display.
    /// Alternating columns drift in opposite directions. Static under Reduce
    /// Motion (parked mid-loop, ≈ the old still composition).
    private struct MarqueeColumn: View {
        enum Direction { case up, down }

        let indices: [Int]
        let speed: Double // pt/sec drift
        let direction: Direction
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var slid = false

        private static let unit: CGFloat = 76, gap: CGFloat = 9
        private static func h(_ span: Int) -> CGFloat {
            CGFloat(span) * unit + CGFloat(span - 1) * gap
        }

        /// Height of one copy plus the seam gap — the exact loop period.
        private var loopHeight: CGFloat {
            indices.reduce(0) { $0 + Self.h(WelcomeScreen.tiles[$1].span) }
                + CGFloat(indices.count) * Self.gap
        }

        private var offsetY: CGFloat {
            if reduceMotion { return -loopHeight / 2 }
            switch direction {
            case .up: return slid ? -loopHeight : 0
            case .down: return slid ? 0 : -loopHeight
            }
        }

        var body: some View {
            VStack(spacing: Self.gap) {
                copy
                copy
                copy
            }
            .offset(y: offsetY)
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .onAppear {
                guard !reduceMotion else { return }
                // withAnimation (not .animation(value:)) so the coordinator's
                // screen-transition animation can't override the loop.
                withAnimation(.linear(duration: loopHeight / speed).repeatForever(autoreverses: false)) {
                    slid = true
                }
            }
        }

        private var copy: some View {
            VStack(spacing: Self.gap) {
                ForEach(indices, id: \.self) { i in
                    tile(i)
                }
            }
        }

        private func tile(_ i: Int) -> some View {
            // GeometryReader contains scaledToFill's oversized reported width
            // (see git history: it otherwise leaks up and widens the screen).
            GeometryReader { geo in
                Image(WelcomeScreen.tiles[i].asset)
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .frame(height: Self.h(WelcomeScreen.tiles[i].span))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 20).fill(OnboardingTheme.tileBase))
            .shadow(color: OnboardingTheme.warmBlack(0.06), radius: 8, y: 6)
        }
    }

    /// Full-height gradient: solid enough at the bottom for legible copy, but
    /// translucent so the drifting photos ghost through behind the headline
    /// and CTA (the reference's background effect).
    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: OnboardingTheme.cream, location: 0),
            .init(color: OnboardingTheme.cream, location: 0.28),
            .init(color: OnboardingTheme.cream.opacity(0.88), location: 0.48),
            .init(color: OnboardingTheme.cream.opacity(0.32), location: 0.72),
            .init(color: OnboardingTheme.cream.opacity(0), location: 1),
        ], startPoint: .bottom, endPoint: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Centered stack (SketchAR-style): wordmark, balanced H1, pill, airy gap,
    /// full-width Start.
    private var content: some View {
        VStack(spacing: 0) {
            Text("Glutt")
                .font(OnboardingFonts.bricolage(22, 700)).kerning(-0.3)
                .foregroundStyle(OnboardingTheme.textHeading)
                .padding(.bottom, 14)

            Text("Cook anything\nyou actually want")
                .font(OnboardingFonts.bricolage(34, 600)).kerning(-1)
                .lineSpacing(34 * 0.08 / 2)
                .multilineTextAlignment(.center)
                .foregroundStyle(OnboardingTheme.textHeading)
                .padding(.bottom, 18)

            HStack(spacing: 8) {
                Text("1M+")
                    .font(OnboardingFonts.bricolage(14, 700))
                    .foregroundStyle(OnboardingTheme.greenDeep)
                Text("happy home cooks")
                    .font(OnboardingFonts.nunito(13.5, 700))
                    .foregroundStyle(OnboardingTheme.greenMid)
            }
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(OnboardingTheme.greenTint, in: Capsule())
            .padding(.bottom, 64)

            OnboardingPrimaryButton(title: "Start", action: onStart)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.bottom, 40)
    }
}

#Preview { WelcomeScreen(onStart: {}) }
