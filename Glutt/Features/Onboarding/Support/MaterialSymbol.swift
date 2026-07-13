import SwiftUI

/// Vendored Material Symbols Rounded glyphs (template SVG imagesets under
/// Assets.xcassets/MaterialSymbols) — same pattern as the vendored Phosphor set.
/// `-fill` cases are the design's `FILL 1` variants. Tint via .foregroundStyle.
enum MS: String, CaseIterable {
    case checkFill = "ms-check-fill"
    case ecoFill = "ms-eco-fill"
    case spaFill = "ms-spa-fill"
    case setMealFill = "ms-set-meal-fill"
    case grainFill = "ms-grain-fill"
    case icecreamFill = "ms-icecream-fill"
    case noMealsFill = "ms-no-meals-fill"
    case mosqueFill = "ms-mosque-fill"
    case synagogueFill = "ms-synagogue-fill"
    case eggFill = "ms-egg-fill"
    case fireFill = "ms-local-fire-department-fill"
    case kitchenFill = "ms-kitchen-fill"
    case graphicEqFill = "ms-graphic-eq-fill"
    case micFill = "ms-mic-fill"
    case skilletFill = "ms-skillet-fill"
    case favoriteFill = "ms-favorite-fill"
    case chatFill = "ms-chat-fill"
    case chatBubbleFill = "ms-chat-bubble-fill"
    case mailFill = "ms-mail-fill"
    case checkCircleFill = "ms-check-circle-fill"
    case arrowUpwardFill = "ms-arrow-upward-fill"
    case chevronLeft = "ms-chevron-left"
    case send = "ms-send"
    case modeComment = "ms-mode-comment"
    case bookmark = "ms-bookmark"
    case search = "ms-search"
    case addCircle = "ms-add-circle"
    case iosShare = "ms-ios-share"
    case link = "ms-link"
    case wifiTethering = "ms-wifi-tethering"
    case contentCopy = "ms-content-copy"
    case chromeReaderMode = "ms-chrome-reader-mode"
    case schedule = "ms-schedule"
    case restaurant = "ms-restaurant"
    case fire = "ms-local-fire-department"

    var image: Image { Image(rawValue).renderingMode(.template).resizable() }

    /// Sized like the design's icon-font glyphs (font-size ≈ square box).
    func sized(_ pt: CGFloat) -> some View {
        image.scaledToFit().frame(width: pt, height: pt)
    }
}
