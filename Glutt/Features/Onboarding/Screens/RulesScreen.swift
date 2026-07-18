import SwiftUI

/// Screen 4 — 3×3 gradient tiles, optional multi-select. Content only; the
/// coordinator owns the fixed "Continue" footer + chrome.
struct RulesScreen: View {
    @Bindable var state: OnboardingState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    /// Per-tile reveal delays, shuffled so the 9 tiles fade in a scattered order.
    @State private var delays = (0..<OnboardingState.ruleOptions.count)
        .map { Double($0) * 0.06 }.shuffled()

    /// Per-tile visual defs from the HTML (gradient start/end, shadow, glyph).
    private static let tileDefs: [DietaryRule: (icon: MS, start: UInt32, end: UInt32, shadow: UInt32)] = [
        .vegetarian: (.ecoFill, 0x7FB56A, 0x3F7A3A, 0x3F7A3A),
        .vegan: (.spaFill, 0x6CC99A, 0x2C8A5E, 0x2C8A5E),
        .pescatarian: (.setMealFill, 0x6BB6C4, 0x2E7385, 0x2E7385),
        .glutenFree: (.grainFill, 0xE8C06A, 0xC08A2E, 0xC08A2E),
        .dairyFree: (.icecreamFill, 0xF0B98A, 0xD9884E, 0xD9884E),
        .nutFree: (.noMealsFill, 0xE0906E, 0xB85436, 0xB85436),
        .halal: (.mosqueFill, 0x5FA377, 0x2E5339, 0x2E5339),
        .kosher: (.synagogueFill, 0x9088CC, 0x574C9E, 0x574C9E),
        .keto: (.eggFill, 0xE28AA0, 0xBC4E6E, 0xBC4E6E),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("Any food rules?", size: 27)
            OnboardingSubhead("Tap all that apply").padding(.top, 9)

            Spacer(minLength: 12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(Array(OnboardingState.ruleOptions.enumerated()), id: \.offset) { index, rule in
                    tile(rule, selected: state.selectedRules.contains(rule))
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.9)
                        .animation(reduceMotion ? nil
                            : .spring(response: 0.5, dampingFraction: 0.82).delay(0.25 + delays[index]),
                            value: appeared)
                }
            }
            .padding(.horizontal, 4).padding(.vertical, 6)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 22)
        .padding(.top, 42)   // design 96 − 54
        .onAppear { appeared = true }
    }

    private func tile(_ rule: DietaryRule, selected: Bool) -> some View {
        let def = Self.tileDefs[rule]!
        return Button {
            Haptics.selection()
            state.toggleRule(rule)
        } label: {
            // Gradient canvas is the sized base; content goes in an .overlay so
            // it is proposed the tile's bounded width (aspectRatio measures its
            // child at ideal width, which would let long labels overflow the
            // clip instead of shrink-to-fit).
            ZStack {
                LinearGradient(colors: [Color(hex: def.start), Color(hex: def.end)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // Top-left white sheen + bottom legibility shade (HTML overlays).
                RadialGradient(colors: [.white.opacity(0.38), .white.opacity(0)],
                               center: .init(x: 0.18, y: 0.12), startRadius: 0, endRadius: 130)
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.32), location: 0),
                    .init(color: .black.opacity(0), location: 0.54),
                ], startPoint: .bottom, endPoint: .top)
            }
            .aspectRatio(1 / 1.1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .fill(.white.opacity(0.22))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 19))
                        def.icon.sized(33).foregroundStyle(.white)
                    }
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(0.12), radius: 7, y: 6)

                    Text(rule.label)
                        .font(OnboardingFonts.bricolage(15, 600)).kerning(-0.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                        .padding(.horizontal, 8)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if selected {
                    ZStack {
                        Circle().fill(.white)
                        MS.checkFill.sized(15).foregroundStyle(OnboardingTheme.greenDeep)
                    }
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
                    .padding(10)
                }
            }
            // Selected: double ring (cream 3 + green 3) + lift; else soft colored shadow.
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(OnboardingTheme.greenDeep, lineWidth: selected ? 3 : 0)
                    .padding(-6)
            )
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(OnboardingTheme.cream, lineWidth: selected ? 3 : 0)
                    .padding(-3)
            )
            .shadow(color: Color(hex: def.shadow).opacity(0.45),
                    radius: selected ? 13 : 9, y: selected ? 10 : 6.5)
            .offset(y: selected ? -3 : 0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: selected)
    }
}
