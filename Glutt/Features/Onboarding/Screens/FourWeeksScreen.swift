import SwiftUI

/// Screen 5 — 3 aspirational benefit cards with glossy gradient icons. Content
/// only; the coordinator owns the fixed "Continue" footer + chrome.
struct FourWeeksScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private static let cards: [(title: String, body: String, icon: MS, start: UInt32, end: UInt32, glow: UInt32)] = [
        ("Cook with confidence", "Hands-free guided recipes that actually work",
         .fireFill, 0xF4906F, 0xD9483B, 0xE1523D),
        ("A kitchen that runs itself", "Your pantry, tools, and grocery list in one place",
         .kitchenFill, 0x6FB183, 0x2E5339, 0x2E5339),
        ("Less waste, less takeout", "Use what you have before it goes off",
         .ecoFill, 0xF3C877, 0xD99A3C, 0xD99A3C),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("Here's where you'll be\nin 4 weeks", size: 27, maxWidth: 290)
            VStack(spacing: 14) {
                ForEach(Array(Self.cards.enumerated()), id: \.element.title) { index, card in
                    row(card)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(reduceMotion ? nil
                            : .easeOut(duration: 0.7).delay(0.25 + Double(index) * 0.38),
                            value: appeared)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .onAppear { appeared = true }
    }

    private func row(_ card: (title: String, body: String, icon: MS, start: UInt32, end: UInt32, glow: UInt32)) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(OnboardingFonts.bricolage(18, 600))
                    .foregroundStyle(OnboardingTheme.textHeading)
                Text(card.body)
                    .font(OnboardingFonts.nunito(13.5, 600))
                    .foregroundStyle(OnboardingTheme.muted)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                // Radial glow halo behind the icon square.
                RadialGradient(colors: [Color(hex: card.glow).opacity(0.55), Color(hex: card.glow).opacity(0)],
                               center: .center, startRadius: 0, endRadius: 52)
                    .frame(width: 104, height: 104)
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: card.start), Color(hex: card.end)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay( // inset top highlight + bottom shade (HTML inset shadows)
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .fill(LinearGradient(stops: [
                                .init(color: .white.opacity(0.35), location: 0),
                                .init(color: .white.opacity(0), location: 0.18),
                                .init(color: .black.opacity(0), location: 0.75),
                                .init(color: .black.opacity(0.16), location: 1),
                            ], startPoint: .top, endPoint: .bottom))
                    )
                    .frame(width: 62, height: 62)
                    .shadow(color: Color(hex: card.glow).opacity(0.45), radius: 10, y: 10)
                card.icon.sized(30).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .frame(width: 62, height: 62)
        }
        .padding(.vertical, 18).padding(.horizontal, 20)
        .background(OnboardingTheme.surface.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(OnboardingTheme.warmBlack(0.05), lineWidth: 1))
        .shadow(color: OnboardingTheme.warmBlack(0.05), radius: 11, y: 8)
    }
}
