import SwiftUI

/// A small tinted stat capsule (icon + text). Powers the recipe-card stat row:
/// rating · time · difficulty. Radius 11, padding 7×12, 13pt heavy text.
struct StatPill: View {
    let icon: Image
    let text: String
    var foreground: Color = Theme.Colors.accent
    var background: Color = Theme.Colors.successTint

    var body: some View {
        HStack(spacing: 4) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundColor(foreground)
            Text(text)
                .font(BrandFont.nunito(13, 800))
                .foregroundColor(foreground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
    }

    /// ★ rating — herb-green on sage.
    static func rating(_ value: String) -> StatPill {
        StatPill(icon: Ph.star.fill, text: value,
                 foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
    }

    /// Clock time — amber on warm.
    static func time(_ text: String) -> StatPill {
        StatPill(icon: Ph.clock.regular, text: text,
                 foreground: Theme.Colors.warning, background: Theme.Colors.warningTint)
    }

    /// Signal difficulty — tomato on soft tomato.
    static func difficulty(_ text: String) -> StatPill {
        StatPill(icon: Ph.cellSignalMedium.fill, text: text,
                 foreground: Theme.Colors.tomato, background: Theme.Colors.tomatoTint)
    }
}

#Preview("StatPill row") {
    HStack(spacing: 8) {
        StatPill.rating("4.9")
        StatPill.time("30 min")
        StatPill.difficulty("Medium")
    }
    .padding()
    .background(Theme.Colors.card)
}
