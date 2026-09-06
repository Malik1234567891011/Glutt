import SwiftUI
import UIKit

/// App-wide brand fonts: **Bricolage Grotesque** (display / headings) and
/// **Nunito** (body / UI), bundled as variable TTFs (`Resources/Fonts`, registered
/// in Info.plist `UIAppFonts`). Weights are instantiated through the Core Text
/// variable axis (`wght`), because SwiftUI's `Font.custom(_:size:).weight(_:)` does
/// not reliably pick a variable font's weight. `weight` is the CSS axis value the
/// design uses (400–800); Bricolage also pins `opsz` to the point size to match the
/// browser's automatic optical sizing. Sizes are fixed (the design is pixel-spec'd,
/// light-mode + portrait only), mirroring the onboarding font approach.
enum BrandFont {
    private static let wght: Int = 0x77676874 // 'wght'
    private static let opsz: Int = 0x6F70737A // 'opsz'

    static func bricolage(_ size: CGFloat, _ weight: CGFloat = 600) -> Font {
        Font(uiBricolage(size, weight))
    }

    static func nunito(_ size: CGFloat, _ weight: CGFloat = 600) -> Font {
        Font(uiNunito(size, weight))
    }

    /// The same faces, but following the reader's text size.
    ///
    /// Everything above returns a fixed point size, which is what the pixel
    /// spec asked for and is why the app rendered identically at every setting
    /// including the accessibility ones: somebody who has told iOS they need
    /// larger text got no larger text anywhere in Glutt.
    ///
    /// `UIFontMetrics` scales a custom face the way the system scales its own,
    /// so the design is unchanged at the default setting and grows from there.
    /// Opt in per role rather than everywhere: a caption and a cooking
    /// instruction should not grow at the same rate, and a display face that
    /// doubles will wreck a layout that a body face survives.
    ///
    /// `maxSize` is the ceiling. Without one a 27pt instruction reaches the
    /// fifties at the largest accessibility setting and pushes everything
    /// under it off the screen, which helps nobody.
    static func bricolage(
        _ size: CGFloat,
        _ weight: CGFloat = 600,
        relativeTo textStyle: UIFont.TextStyle,
        maxSize: CGFloat? = nil
    ) -> Font {
        Font(scaled(uiBricolage(size, weight), textStyle: textStyle, maxSize: maxSize))
    }

    static func nunito(
        _ size: CGFloat,
        _ weight: CGFloat = 600,
        relativeTo textStyle: UIFont.TextStyle,
        maxSize: CGFloat? = nil
    ) -> Font {
        Font(scaled(uiNunito(size, weight), textStyle: textStyle, maxSize: maxSize))
    }

    private static func scaled(
        _ font: UIFont,
        textStyle: UIFont.TextStyle,
        maxSize: CGFloat?
    ) -> UIFont {
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        if let maxSize {
            return metrics.scaledFont(for: font, maximumPointSize: maxSize)
        }
        return metrics.scaledFont(for: font)
    }

    static func uiBricolage(_ size: CGFloat, _ weight: CGFloat = 600) -> UIFont {
        variable("Bricolage Grotesque", size: size, axes: [wght: weight, opsz: size])
    }

    static func uiNunito(_ size: CGFloat, _ weight: CGFloat = 600) -> UIFont {
        variable("Nunito", size: size, axes: [wght: weight])
    }

    private static func variable(_ family: String, size: CGFloat, axes: [Int: CGFloat]) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        // The main app registers both families (Info.plist UIAppFonts). If a target
        // that doesn't bundle them uses these (e.g. the share extension), CoreText
        // hands back a system fallback — render with it rather than crashing.
        #if DEBUG
        if font.familyName != family { print("BrandFont: '\(family)' unavailable in this target, using fallback") }
        #endif
        return font
    }
}
