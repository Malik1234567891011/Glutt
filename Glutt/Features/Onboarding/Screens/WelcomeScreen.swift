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
                .padding(.top, 0) // design 54 − 54: grid starts at safe-area top
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()

            scrim
            content
        }
        .background(OnboardingTheme.cream)
        .ignoresSafeArea(edges: .bottom)
    }

    /// 3-column masonry, 76pt row unit, 9pt gaps — hand-placed to match the CSS
    /// grid's auto-placement (`grid-auto-flow: row`, sparse), verified against
    /// the prototype HTML: columns are {0,5,7,10}, {1,3,6,9}, {2,4,8}.
    private var masonry: some View {
        let unit: CGFloat = 76, gap: CGFloat = 9
        func h(_ span: Int) -> CGFloat { CGFloat(span) * unit + CGFloat(span - 1) * gap }
        func tile(_ i: Int) -> some View {
            // `scaledToFill` reports the image's oversized aspect-filled size
            // (not the frame it's given) to its parent, and a plain
            // `.frame(maxWidth: .infinity)` has no upper clamp — so that
            // oversized width leaks all the way up through the HStack/ZStack
            // (nearly doubling the whole screen's reported width and shoving
            // the leading-aligned wordmark/H1/pill off-screen). GeometryReader
            // always reports exactly its proposed size regardless of content,
            // so reading the column width from it and applying it as an
            // explicit (non-flexible) frame on the image contains the overflow
            // right here; `.clipped()` then only has to do the visual crop.
            GeometryReader { geo in
                Image(Self.tiles[i].asset)
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .frame(height: h(Self.tiles[i].span))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 20).fill(OnboardingTheme.tileBase))
            .shadow(color: OnboardingTheme.warmBlack(0.06), radius: 8, y: 6)
        }
        // Three independent columns approximate the CSS auto-placed grid.
        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) { tile(0); tile(5); tile(7); tile(10) }
            VStack(spacing: gap) { tile(1); tile(3); tile(6); tile(9) }
            VStack(spacing: gap) { tile(2); tile(4); tile(8) }
        }
    }

    private var scrim: some View {
        GeometryReader { geo in
            LinearGradient(stops: [
                .init(color: OnboardingTheme.cream, location: 0),
                .init(color: OnboardingTheme.cream, location: 0.46),
                .init(color: OnboardingTheme.cream.opacity(0.86), location: 0.60),
                .init(color: OnboardingTheme.cream.opacity(0), location: 1),
            ], startPoint: .bottom, endPoint: .top)
            .frame(height: geo.size.height * 0.62)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text("Glutt")
                    .font(OnboardingFonts.bricolage(22, 700)).kerning(-0.3)
                    .foregroundStyle(OnboardingTheme.textHeading)
                RoundedRectangle(cornerRadius: 3)
                    .fill(OnboardingTheme.coral)
                    .frame(width: 10, height: 10)
            }
            .padding(.bottom, 14)

            Text("Cook anything you actually want")
                .font(OnboardingFonts.bricolage(34, 600)).kerning(-1)
                .lineSpacing(34 * 0.08 / 2)
                .foregroundStyle(OnboardingTheme.textHeading)
                .frame(maxWidth: 320, alignment: .leading)
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
            .padding(.bottom, 26)

            OnboardingPrimaryButton(title: "Start", action: onStart)
        }
        .padding(.leading, 28).padding(.trailing, 28)
        .padding(.bottom, 40)
    }
}

#Preview { WelcomeScreen(onStart: {}) }
