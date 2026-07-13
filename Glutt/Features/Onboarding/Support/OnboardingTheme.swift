import SwiftUI

/// Exact tokens from design_handoff_onboarding_flow (HTML is source of truth).
/// Scoped to onboarding — the app-wide `Theme` is deliberately untouched.
enum OnboardingTheme {
    static let cream = Color(hex: 0xFAF3E7)        // screen background
    static let surface = Color(hex: 0xFFFDF7)      // rows/cards
    static let videoFrame = Color(hex: 0xF4EDDC)   // video placeholder bg
    static let tileBase = Color(hex: 0xF1E9D6)     // welcome grid tile bg
    static let greenDeep = Color(hex: 0x2E5339)    // primary
    static let greenPressed = Color(hex: 0x356145)
    static let progressFill = Color(hex: 0x3E7A50)
    static let progressFillDark = Color(hex: 0x7BD48F)
    static let greenTint = Color(hex: 0xEAF1E7)
    static let greenMid = Color(hex: 0x4E7A5C)
    static let mintBright = Color(hex: 0x8FE3A3)
    static let sage = Color(hex: 0x6FB183)
    static let textHeading = Color(hex: 0x241E19)
    static let textBase = Color(hex: 0x2A2420)
    static let textList = Color(hex: 0x3A342C)
    static let muted = Color(hex: 0x9A9082)
    static let mutedDeep = Color(hex: 0x8A8072)
    static let mutedWarm = Color(hex: 0x6E6456)
    static let timestamp = Color(hex: 0xB3A99A)
    static let disabledBg = Color(hex: 0xDED6C4)
    static let disabledText = Color(hex: 0xA79D8B)
    static let creamText = Color(hex: 0xFBF5E9)
    static let coral = Color(hex: 0xD9483B)
    static let coralBright = Color(hex: 0xE1523D)
    /// rgba(42,36,32,x) — the design's warm-black overlay base.
    static func warmBlack(_ opacity: Double) -> Color { Color(hex: 0x2A2420).opacity(opacity) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
