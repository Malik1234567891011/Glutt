import SwiftUI

/// FRESH vs PANTRY split for the ingredient checklist, derived from the same
/// canonical→GroceryCategory mapping the grocery list uses.
enum IngredientSection: Int, CaseIterable {
    case fresh, pantry
    var title: String { self == .fresh ? "Fresh" : "Pantry" }
}

enum IngredientCategoryStyle {
    /// Section + a tinted IconChip for an ingredient name.
    static func section(for name: String) -> IngredientSection {
        switch GroceryCategorizer.categorize(name) {
        case .produce, .meat, .dairy: return .fresh
        case .pantry, .frozen, .spices, .other: return .pantry
        }
    }

    /// Single source of truth for the category → tinted IconChip mapping.
    /// Both the ingredient checklist and the Kitchen inventory use this so the
    /// glyphs and tints never drift apart. One clear glyph per category.
    static func chip(for category: GroceryCategory) -> IconChip {
        switch category {
        case .produce:
            IconChip(icon: Ph.carrot.fill, foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
        case .meat:
            IconChip(icon: Ph.forkKnife.bold, foreground: Theme.Colors.tomato, background: Theme.Colors.tomatoTint)
        case .dairy:
            IconChip(icon: Ph.cheese.fill, foreground: Theme.Colors.warning, background: Theme.Colors.warningTint)
        case .pantry:
            IconChip(icon: Ph.jar.fill, foreground: Theme.Colors.warning, background: Theme.Colors.warningTint)
        case .frozen:
            IconChip(icon: Ph.snowflake.regular, foreground: Theme.Colors.textSecondary, background: Theme.Colors.border)
        case .spices:
            IconChip(icon: Ph.pepper.fill, foreground: Theme.Colors.tomato, background: Theme.Colors.tomatoTint)
        case .other:
            IconChip(icon: Ph.bowlFood.fill, foreground: Theme.Colors.textSecondary, background: Theme.Colors.border)
        }
    }

    /// Convenience: derive the chip straight from an ingredient name.
    static func chip(for name: String) -> IconChip {
        chip(for: GroceryCategorizer.categorize(name))
    }
}

#Preview("IngredientCategoryStyle chips") {
    HStack(spacing: 12) {
        IngredientCategoryStyle.chip(for: "ground beef")
        IngredientCategoryStyle.chip(for: "cucumber")
        IngredientCategoryStyle.chip(for: "jasmine rice")
    }
    .padding().background(Theme.Colors.background)
}
