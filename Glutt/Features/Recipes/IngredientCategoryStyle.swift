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

    @ViewBuilder
    static func chip(for name: String) -> some View {
        switch GroceryCategorizer.categorize(name) {
        case .meat:
            IconChip(icon: Ph.hamburger.fill, foreground: Theme.Colors.tomato, background: Theme.Colors.tomatoTint)
        case .produce:
            IconChip(icon: Ph.plant.fill, foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
        case .dairy:
            IconChip(icon: Ph.drop.fill, foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
        case .pantry, .frozen, .spices, .other:
            IconChip(icon: Ph.bowlFood.fill, foreground: Theme.Colors.warning, background: Theme.Colors.warningTint)
        }
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
