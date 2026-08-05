import SwiftUI

/// Glutt design tokens: warm premium kitchen app.
/// Cream background, deep herb-green accent, tomato red secondary, soft rounded
/// cards. Exact hexes from the design handoff (`design-doc/.../*.dc.html`).
enum Theme {

    // MARK: - Colors

    enum Colors {
        /// Cream app background. (#FAF3E7)
        static let background = Color(hex: 0xFAF3E7)
        /// Primary card surface — cream-white, lifts off the background. (#FFFDF7)
        static let card = Color(hex: 0xFFFDF7)
        /// Secondary surface — icon tiles, stat pills, segment insets. (#F4EDDC)
        static let surface2 = Color(hex: 0xF4EDDC)
        /// Tertiary surface — deeper warm tile. (#F1E9D6)
        static let surface3 = Color(hex: 0xF1E9D6)
        /// Deep herb-green primary accent. (#2E5339)
        static let accent = Color(hex: 0x2E5339)
        /// Green pressed/hover. (#356145)
        static let accentPressed = Color(hex: 0x356145)
        /// Bright mint accent — waveforms, on-dark highlights. (#8FE3A3)
        static let brightAccent = Color(hex: 0x8FE3A3)
        /// Soft green tint for success / "you have it" states. (#EAF1E7)
        static let greenTint = Color(hex: 0xEAF1E7)
        /// Tomato red — destructive actions and appetite highlights. (#D9483B)
        static let tomato = Color(hex: 0xD9483B)
        /// Brighter coral variant. (#E1523D)
        static let coralBright = Color(hex: 0xE1523D)
        /// Soft tomato tint — difficulty pills, "use soon". (#F7DDD2)
        static let tomatoTint = Color(hex: 0xF7DDD2)
        /// Amber — need / low / use-soon. (#C28C21)
        static let amber = Color(hex: 0xC28C21)
        /// Amber chip background. (#FCF0D6)
        static let amberChip = Color(hex: 0xFCF0D6)
        /// Heading text — warm near-black. (#241E19)
        static let heading = Color(hex: 0x241E19)
        /// Base body text. (#2A2420) — also the neutral/warm shadow base.
        static let textPrimary = Color(hex: 0x2A2420)
        /// Warm brown-gray secondary text. (#6E6456)
        static let textSecondary = Color(hex: 0x6E6456)
        /// Muted label / lighter secondary. (#9A9082)
        static let muted = Color(hex: 0x9A9082)
        /// Subtle warm divider/border. (#E1D7CA)
        static let border = Color(hex: 0xE1D7CA)
        /// Cream text/glyph on green or dark fills (CTA text). (#FBF5E9)
        static let creamText = Color(hex: 0xFBF5E9)
        /// Slightly cooler cream for tab labels / active segment glyphs. (#F4ECDF)
        static let tabLabel = Color(hex: 0xF4ECDF)
        /// Dark rounded bottom tab bar. (#241F1A)
        static let tabBar = Color(hex: 0x241F1A)
        /// Inactive bottom-tab glyph + label on the dark bar. (#928377)
        static let tabInactive = Color(hex: 0x928377)
        /// Active bottom-tab glyph (light green) on the dark bar. (#CFE6CC)
        static let activeTabGlyph = Color(hex: 0xCFE6CC)
        /// Decorative peach panel tint behind food photos. (#F7E2D4)
        static let peachPanel = Color(hex: 0xF7E2D4)
        /// Segmented-control track. (#EBE2D4)
        static let segmentTrack = Color(hex: 0xEBE2D4)
        /// Inactive page-dot fill. (#D8CDBE)
        static let dotInactive = Color(hex: 0xD8CDBE)
        /// Middle card of the import "stack" — between `card` and `surface3`. (#F6EFE0)
        static let stackMid = Color(hex: 0xF6EFE0)
        /// Quietest text in the palette — the import status sub-line. (#B0A697)
        static let mutedSoft = Color(hex: 0xB0A697)

        // MARK: Backwards-compatible aliases (kept so existing call sites compile)
        /// Semantic alias of `greenTint`.
        static let successTint = greenTint
        /// Semantic alias of `amberChip`.
        static let warningTint = amberChip
        /// Semantic alias of `amber`.
        static let warning = amber
        /// Semantic alias of `greenTint`.
        static let sagePanel = greenTint
        /// Semantic alias of `muted`.
        static let mutedLabel = muted
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
        /// Redesigned recipe/detail/section cards — softer than `card`.
        static let cardLarge: CGFloat = 26
        /// Photo tiles nested inside cards.
        static let photo: CGFloat = 18
        /// Grouped-list container (Fresh/Pantry/inventory sections).
        static let group: CGFloat = 20
        /// 46×46 ingredient food-icon tile.
        static let iconTile: CGFloat = 13
        /// Stat pills, icon chips, active segment.
        static let pill: CGFloat = 11
        /// Segmented-control track.
        static let segment: CGFloat = 14
        static let sheet: CGFloat = 24
        static let button: CGFloat = 12
        /// Dark tab bar top corners.
        static let tabBarTop: CGFloat = 30
        /// Card tag pill (top-right of media).
        static let tag: CGFloat = 13
    }

    // MARK: - Shadows (neutral/warm only — never colored)

    static func cardShadow(_ content: some View) -> some View {
        content.shadow(color: Colors.textPrimary.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Hex color init (shared across the app + the share extension)

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
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
