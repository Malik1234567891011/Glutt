import SwiftUI
import PhosphorSwift

/// A 36pt section-tinted rounded-square holding a Phosphor food glyph.
/// Used in the ingredient checklist (protein/produce/pantry tints).
struct IconChip: View {
    let icon: Image
    var foreground: Color = Theme.Colors.accent
    var background: Color = Theme.Colors.successTint

    var body: some View {
        icon
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .foregroundColor(foreground)
            .frame(width: 36, height: 36)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

#Preview("IconChip tints") {
    HStack(spacing: 12) {
        IconChip(icon: Ph.hamburger.fill,
                 foreground: Theme.Colors.tomato, background: Theme.Colors.tomatoTint)
        IconChip(icon: Ph.plant.fill,
                 foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
        IconChip(icon: Ph.bowlFood.fill,
                 foreground: Theme.Colors.warning, background: Theme.Colors.warningTint)
    }
    .padding()
    .background(Theme.Colors.card)
}
