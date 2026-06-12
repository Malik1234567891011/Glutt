import SwiftUI

/// Glutt design tokens: warm premium kitchen app.
/// Cream background, deep green accent, tomato red secondary, soft rounded cards.
enum Theme {

    // MARK: - Colors

    enum Colors {
        /// Cream app background — deep enough that white cards visibly lift off it.
        static let background = Color(red: 0.965, green: 0.94, blue: 0.90)
        /// Card surfaces — slightly whiter than the background.
        static let card = Color.white
        /// Deep herb-green primary accent.
        static let accent = Color(red: 0.15, green: 0.35, blue: 0.21)
        /// Tomato red — destructive actions and appetite highlights.
        static let tomato = Color(red: 0.85, green: 0.28, blue: 0.17)
        /// Warm near-black text.
        static let textPrimary = Color(red: 0.15, green: 0.12, blue: 0.10)
        /// Warm brown-gray secondary text — dark enough to read in a kitchen.
        static let textSecondary = Color(red: 0.40, green: 0.35, blue: 0.31)
        /// Subtle warm divider/border.
        static let border = Color(red: 0.88, green: 0.84, blue: 0.79)
        /// Soft green tint for success/"you have it" states.
        static let successTint = Color(red: 0.89, green: 0.94, blue: 0.88)
        /// Soft amber tint for warnings/"use soon" states.
        static let warningTint = Color(red: 0.99, green: 0.94, blue: 0.84)
        static let warning = Color(red: 0.76, green: 0.55, blue: 0.13)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Corner radius ("rounded but not childish")

    enum Radius {
        static let chip: CGFloat = 8
        static let card: CGFloat = 16
        static let sheet: CGFloat = 24
        static let button: CGFloat = 12
    }

    // MARK: - Shadows

    static func cardShadow(_ content: some View) -> some View {
        content.shadow(color: Colors.textPrimary.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Card container modifier

struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.Spacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Theme.Colors.textPrimary.opacity(0.07), radius: 10, x: 0, y: 3)
    }
}

extension View {
    func cardStyle(padding: CGFloat = Theme.Spacing.md) -> some View {
        modifier(CardStyle(padding: padding))
    }
}
