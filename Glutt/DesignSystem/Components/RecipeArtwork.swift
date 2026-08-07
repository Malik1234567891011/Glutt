import SwiftUI

extension Recipe {
    /// Whether an image slot will actually show a picture.
    ///
    /// Worth asking before laying a card out rather than after. A recipe with no
    /// artwork used to get the same 180pt slot as one with a photo, filled with
    /// a grey rectangle and a fork-and-knife glyph, and a screen of those reads
    /// as broken rather than as sparse. Planned dinners are invented on the spot
    /// and will never have a photo, so the answer here is permanent for them and
    /// the layout can commit to it.
    var hasArtwork: Bool {
        if let name = imageAssetName, UIImage(named: name) != nil { return true }
        if imageData != nil { return true }
        if let imageURL, !imageURL.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return false
    }
}

/// How a recipe's first tag is drawn: an icon and a colour.
///
/// Shared so the small glyph tile and the big card's tag pill cannot drift
/// apart, and so the same dish is the same colour wherever it appears.
enum RecipeTagStyle {
    static func style(for tag: String) -> (icon: MS, color: Color) {
        let t = tag.lowercased()
        if t.contains("spic") || t.contains("hot") { return (.fireFill, Theme.Colors.tomato) }
        if t.contains("protein") { return (.boltFill, Theme.Colors.accent) }
        if t.contains("prep") || t.contains("batch") { return (.lunchDiningFill, Theme.Colors.accent) }
        if t.contains("veg") || t.contains("plant") || t.contains("green") { return (.ecoFill, Theme.Colors.accent) }
        if t.contains("omega") || t.contains("fish") || t.contains("seafood") { return (.restaurantFill, Theme.Colors.accent) }
        if t.contains("soup") || t.contains("stew") || t.contains("curry") { return (.lunchDiningFill, Theme.Colors.amber) }
        if t.contains("noodle") || t.contains("pasta") || t.contains("rice") { return (.restaurantFill, Theme.Colors.amber) }
        return (.restaurantFill, Theme.Colors.accent)
    }
}

/// Stands in for a photo on a recipe that has none.
///
/// Not a placeholder. A placeholder says "a picture belongs here and is
/// missing"; this says "this dish is identified by its tag". Small, tinted from
/// the dish's own tag so a list of them has colour and rhythm rather than eight
/// identical grey squares, and sized to sit beside a title rather than above it.
struct RecipeGlyphTile: View {
    let recipe: Recipe
    var size: CGFloat = 46

    private var style: (icon: MS, color: Color) {
        RecipeTagStyle.style(for: recipe.tags.first ?? "")
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(style.color.opacity(0.13))
            .frame(width: size, height: size)
            .overlay(
                style.icon
                    .sized(size * 0.46)
                    .foregroundStyle(style.color)
            )
    }
}
