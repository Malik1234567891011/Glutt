import SwiftUI
import UIKit

/// Onboarding-only brand fonts, bundled as variable TTFs (see Resources/Fonts).
/// `weight` is the CSS axis value the design uses (600/700/800). Bricolage also
/// pins `opsz` to the point size, matching the browser's automatic optical sizing.
enum OnboardingFonts {
    private static let wght: Int = 0x77676874 // 'wght'
    private static let opsz: Int = 0x6F70737A // 'opsz'

    static func bricolage(_ size: CGFloat, _ weight: CGFloat) -> Font {
        Font(uiBricolage(size, weight))
    }

    static func nunito(_ size: CGFloat, _ weight: CGFloat) -> Font {
        Font(uiNunito(size, weight))
    }

    /// Apple Color Emoji at an explicit size, for emoji-only `Text` runs that must
    /// render in color regardless of the surrounding custom-font context. (Note: the
    /// iOS Simulator's CoreText can't rasterize color-emoji glyphs, so these show as
    /// tofu boxes on the sim but render correctly on-device.)
    static func emoji(_ size: CGFloat) -> Font {
        Font(UIFont(name: "AppleColorEmoji", size: size) ?? .systemFont(ofSize: size))
    }

    static func uiBricolage(_ size: CGFloat, _ weight: CGFloat) -> UIFont {
        variable("Bricolage Grotesque", size: size, axes: [wght: weight, opsz: size])
    }

    static func uiNunito(_ size: CGFloat, _ weight: CGFloat) -> UIFont {
        variable("Nunito", size: size, axes: [wght: weight])
    }

    private static func variable(_ family: String, size: CGFloat, axes: [Int: CGFloat]) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        #if DEBUG
        if font.familyName != family { assertionFailure("Missing bundled font \(family)") }
        #endif
        return font
    }
}
