import SwiftUI

/// Warm-dark cooking-session palette from `docs/newDesign.md` (§8).
/// Video supplies color; UI frames it. Prefer these over cream Theme tokens
/// inside the Polly Adaptive Video Canvas.
enum CookCanvasTheme {
    static let mainBlack = Color(hex: 0x0C0B09)
    static let elevated = Color(hex: 0x181612)
    static let stepSheet = Color(hex: 0x201D18)
    static let primaryText = Color(hex: 0xF6F2EA)
    static let secondaryText = Color(hex: 0xAAA39A)
    static let mutedText = Color(hex: 0x777169)
    static let green = Color(hex: 0x80E3A0)
    static let greenPressed = Color(hex: 0x62C982)
    static let warning = Color(hex: 0xF0B85A)
    static let destructive = Color(hex: 0xFF5B50)

    static let sheetRadius: CGFloat = 30
    static let dockHeight: CGFloat = 60
    static let dockRadius: CGFloat = 30
    static let margin: CGFloat = 16
}
