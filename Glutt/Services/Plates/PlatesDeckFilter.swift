import Foundation

/// Hard-filters a deck before it's shown: drops cards with any allergy/rule
/// conflict (reusing DietGuard's ingredient check) and cards the user already
/// saved (by sourceURL). Dislikes are NOT filtered — they surface as soft
/// warnings on the card back, never silently hidden.
enum PlatesDeckFilter {
    static func filter(
        _ cards: [PlateCard],
        rules: [DietaryRule],
        allergies: [String],
        savedSourceURLs: Set<String>,
        seenIDs: Set<String> = []
    ) -> [PlateCard] {
        cards.filter { card in
            if seenIDs.contains(card.id) { return false }
            if let url = card.sourceURL, savedSourceURLs.contains(url) { return false }
            return card.ingredients.allSatisfy { ing in
                let name = ing.name ?? ing.raw
                return DietGuard.isAllowed(ingredientName: name, rules: rules, allergies: allergies)
            }
        }
    }
}
