import SwiftUI

/// Maps an ingredient name to one of the vendored flat food-icon PNGs
/// (`ing-*`, from the 0xGF/food-icons set). Only a starter set of ~10 icons is
/// bundled; unmatched ingredients fall back to a neutral glyph. Extend `catalog`
/// as more `ing-*` imagesets are added.
enum IngredientIcon {
    /// (asset name, matching keywords) — first keyword hit wins, so order matters
    /// (specific before generic).
    private static let catalog: [(asset: String, keywords: [String])] = [
        ("ing-avocado", ["avocado", "guac"]),
        ("ing-chicken", ["chicken", "poultry", "thigh", "breast", "turkey", "wing", "drumstick"]),
        ("ing-beef", ["beef", "steak", "ground beef", "mince", "lamb", "pork", "bacon", "sausage", "meat"]),
        ("ing-scallion", ["scallion", "green onion", "spring onion", "onion", "shallot", "leek", "chive"]),
        ("ing-spinach", ["spinach", "kale", "lettuce", "arugula", "greens", "chard", "cabbage", "herb", "basil", "cilantro", "parsley"]),
        ("ing-rice", ["rice", "quinoa", "grain", "couscous", "barley", "risotto"]),
        ("ing-flour", ["flour", "bread", "pasta", "noodle", "dough", "sugar", "baking", "cornstarch", "oat"]),
        ("ing-milk", ["milk", "buttermilk", "cream", "yogurt", "yoghurt", "cheese", "butter", "dairy"]),
        ("ing-honey", ["honey", "syrup", "molasses", "agave"]),
        ("ing-olive-oil", ["olive oil", "oil", "vinegar", "sauce", "dressing"]),
    ]

    /// The matched food-icon image, or nil if nothing in the starter set fits.
    static func image(for name: String) -> Image? {
        let n = name.lowercased()
        for entry in catalog where entry.keywords.contains(where: n.contains) {
            return Image(entry.asset)
        }
        return nil
    }
}

/// The design's ingredient row tile: a 46×46 rounded-13 square holding a flat
/// food-icon PNG (or a neutral fallback glyph). `isMissing` swaps the warm base
/// tile for the amber "need it" tint.
struct IngredientTile: View {
    let name: String
    var isMissing: Bool = false
    var size: CGFloat = 46

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.iconTile, style: .continuous)
            .fill(isMissing ? Theme.Colors.amberChip : Theme.Colors.surface2)
            .frame(width: size, height: size)
            .overlay {
                if let icon = IngredientIcon.image(for: name) {
                    icon.resizable().scaledToFit()
                        .frame(width: size * 0.65, height: size * 0.65)
                } else {
                    MS.restaurant.sized(size * 0.42)
                        .foregroundStyle(isMissing ? Theme.Colors.amber : Theme.Colors.textSecondary)
                }
            }
    }
}

#Preview("IngredientTiles") {
    HStack(spacing: 12) {
        IngredientTile(name: "Chicken breast")
        IngredientTile(name: "Buttermilk", isMissing: true)
        IngredientTile(name: "Jasmine rice")
        IngredientTile(name: "Mystery item")
    }
    .padding()
    .background(Theme.Colors.background)
}
