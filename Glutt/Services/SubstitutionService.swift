import Foundation

/// Static, culinary-sensible substitution table. The Phase 6 AI layer will
/// extend this with context-aware swaps; this table is the offline fallback
/// and ships first per the manually-useful-before-magical principle.
enum SubstitutionService {

    struct Substitution {
        let name: String
        let explanation: String
    }

    /// Keyed by canonical ingredient name.
    private static let table: [String: [Substitution]] = [
        "heavy cream": [
            Substitution(name: "Greek yogurt + butter", explanation: "Similar richness; add yogurt off the heat so it doesn't split."),
            Substitution(name: "sour cream", explanation: "Slightly tangier, same body."),
        ],
        "greek yogurt": [
            Substitution(name: "sour cream", explanation: "Same texture, slightly less protein."),
        ],
        "sour cream": [
            Substitution(name: "greek yogurt", explanation: "Tangier and higher protein."),
        ],
        "butter": [
            Substitution(name: "olive oil", explanation: "Works for cooking; skip for baking."),
        ],
        "green onion": [
            Substitution(name: "chives", explanation: "Milder but the same fresh-onion note."),
            Substitution(name: "red onion", explanation: "Use less — sharper flavor."),
        ],
        "coriander": [
            Substitution(name: "parsley", explanation: "Loses the citrus note but keeps freshness."),
        ],
        "parsley": [
            Substitution(name: "coriander", explanation: "Adds a citrusy edge."),
        ],
        "lemon": [
            Substitution(name: "lime", explanation: "Slightly more bitter, works in most dishes."),
            Substitution(name: "white vinegar", explanation: "Use half as much — acidity only, no aroma."),
        ],
        "lime": [
            Substitution(name: "lemon", explanation: "Slightly sweeter, works in most dishes."),
        ],
        "honey": [
            Substitution(name: "maple syrup", explanation: "Same sweetness, different aroma."),
            Substitution(name: "sugar", explanation: "Dissolve in a splash of warm water first."),
        ],
        "sriracha": [
            Substitution(name: "hot sauce + honey", explanation: "Matches the sweet-heat profile."),
            Substitution(name: "chili flakes", explanation: "Heat without the garlic-sweet note."),
        ],
        "chicken broth": [
            Substitution(name: "bouillon cube + water", explanation: "Practically identical."),
            Substitution(name: "vegetable broth", explanation: "Lighter but works."),
        ],
        "basmati rice": [
            Substitution(name: "jasmine rice", explanation: "Slightly stickier, same cook time."),
        ],
        "gnocchi": [
            Substitution(name: "pasta", explanation: "Different texture; boil instead of pan-toast."),
        ],
        "panko bread crumbs": [
            Substitution(name: "crushed crackers", explanation: "Similar crunch."),
        ],
        "brown sugar": [
            Substitution(name: "sugar + honey", explanation: "Mimics the molasses moisture."),
        ],
    ]

    /// Substitutions that should never happen — flag instead of suggesting.
    private static let doNotSubstitute: Set<String> = [
        "chicken", "beef", "salmon", "egg", "flour", "yeast", "baking powder", "baking soda",
    ]

    static func substitutions(for ingredientName: String) -> [Substitution] {
        let canonical = IngredientCanonicalizer.canonicalize(ingredientName)
        if let direct = table[canonical] { return direct }
        // Try last-word lookup: "fresh lemon juice" -> "lemon"
        if let lastWord = canonical.split(separator: " ").last.map(String.init),
           let byWord = table[lastWord] {
            return byWord
        }
        return []
    }

    static func isEssential(_ ingredientName: String) -> Bool {
        let canonical = IngredientCanonicalizer.canonicalize(ingredientName)
        return doNotSubstitute.contains { canonical.contains($0) }
    }

    /// Substitutions the user can actually make right now with their pantry —
    /// and that don't trade one problem for another (rules, allergies).
    static func availableSubstitutions(
        for ingredientName: String,
        pantry: [PantryItem],
        rules: [DietaryRule] = [],
        allergies: [String] = []
    ) -> [Substitution] {
        substitutions(for: ingredientName).filter { substitution in
            // Compound subs ("Greek yogurt + butter") need every part.
            let parts = substitution.name.split(separator: "+").map(String.init)
            return parts.allSatisfy { part in
                let canonical = IngredientCanonicalizer.canonicalize(part)
                return PantryMatcher.owns(ingredientNamed: canonical, available: pantry.filter { $0.roughQuantity != .out })
                    && DietGuard.isAllowed(ingredientName: part, rules: rules, allergies: allergies)
            }
        }
    }
}
