import Foundation

/// The safety layer for food rules. Checks recipes, suggestions, and
/// substitutions against dietary rules, allergies, and dislikes.
/// Allergies are hard blocks; rules are hard blocks; dislikes are soft
/// (surfaced, never silently hidden — the user may be cooking for others).
enum DietGuard {

    struct Conflict: Identifiable, Equatable {
        enum Severity: Equatable {
            case allergy
            case rule(DietaryRule)
            case dislike
        }

        let ingredientName: String
        let severity: Severity

        var id: String { ingredientName + message }

        var message: String {
            switch severity {
            case .allergy:
                "\(ingredientName) — allergy"
            case .rule(let rule):
                "\(ingredientName) — conflicts with \(rule.label.lowercased())"
            case .dislike:
                "\(ingredientName) — you dislike this"
            }
        }

        var isBlocking: Bool {
            if case .dislike = severity { return false }
            return true
        }
    }

    // MARK: - Rule keyword tables

    private static let porkWords: Set<String> = [
        "pork", "bacon", "ham", "prosciutto", "pepperoni", "salami",
        "chorizo", "pancetta", "lard", "sausage",
    ]
    private static let alcoholWords: Set<String> = [
        "wine", "beer", "rum", "brandy", "whiskey", "vodka", "bourbon",
        "sherry", "sake", "mirin", "liqueur",
    ]
    private static let meatWords: Set<String> = porkWords.union([
        "chicken", "beef", "steak", "lamb", "turkey", "duck", "veal",
        "kofta", "meatball", "mince", "brisket", "ribs",
    ])
    private static let seafoodWords: Set<String> = [
        "fish", "salmon", "tuna", "shrimp", "prawn", "crab", "lobster",
        "anchovy", "cod", "tilapia", "sardine", "oyster", "mussel", "clam",
        "scallop", "squid", "octopus",
    ]
    private static let dairyWords: Set<String> = [
        "milk", "butter", "cheese", "cream", "yogurt", "ghee",
        "mozzarella", "parmesan", "cheddar", "feta", "ricotta", "mascarpone",
    ]
    private static let eggWords: Set<String> = ["egg", "eggs", "mayonnaise", "mayo"]
    private static let glutenWords: Set<String> = [
        "flour", "wheat", "bread", "pasta", "noodle", "couscous", "barley",
        "tortilla", "pita", "flatbread", "breadcrumb", "cracker", "gnocchi",
        "soy sauce", "bun", "baguette",
    ]
    /// Non-halal beyond pork: alcohol and gelatin (unless certified, which we can't know).
    private static let gelatinWords: Set<String> = ["gelatin", "gelatine"]

    static func forbiddenWords(for rule: DietaryRule) -> Set<String> {
        switch rule {
        case .halal: porkWords.union(alcoholWords).union(gelatinWords)
        case .noPork: porkWords
        case .vegetarian: meatWords.union(seafoodWords).union(gelatinWords)
        case .vegan: meatWords.union(seafoodWords).union(gelatinWords)
            .union(dairyWords).union(eggWords).union(["honey"])
        case .glutenFree: glutenWords
        case .dairyFree: dairyWords
        }
    }

    // MARK: - Checks

    /// All conflicts in a recipe, worst first (allergies > rules > dislikes).
    static func conflicts(
        in recipe: Recipe,
        rules: [DietaryRule],
        allergies: [String],
        dislikes: [String] = []
    ) -> [Conflict] {
        var conflicts: [Conflict] = []
        var flagged: Set<String> = []

        for ingredient in recipe.ingredients.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            guard let severity = severity(
                ofIngredient: ingredient.name,
                rules: rules,
                allergies: allergies,
                dislikes: dislikes
            ) else { continue }
            // One conflict per ingredient name, no matter how many rules it trips.
            guard flagged.insert(ingredient.canonicalName).inserted else { continue }
            conflicts.append(Conflict(ingredientName: ingredient.name, severity: severity))
        }

        return conflicts.sorted { rank($0.severity) < rank($1.severity) }
    }

    /// Whether a recipe is safe to *suggest* (allergies and rules block; dislikes don't).
    static func isSuggestable(
        _ recipe: Recipe,
        rules: [DietaryRule],
        allergies: [String]
    ) -> Bool {
        conflicts(in: recipe, rules: rules, allergies: allergies)
            .allSatisfy { !$0.isBlocking }
    }

    /// Whether an ingredient (e.g. a proposed substitute) is acceptable.
    static func isAllowed(
        ingredientName: String,
        rules: [DietaryRule],
        allergies: [String]
    ) -> Bool {
        severity(ofIngredient: ingredientName, rules: rules, allergies: allergies, dislikes: []) == nil
    }

    // MARK: - Internals

    private static func severity(
        ofIngredient name: String,
        rules: [DietaryRule],
        allergies: [String],
        dislikes: [String]
    ) -> Conflict.Severity? {
        let lowered = name.lowercased()

        if let _ = allergies.first(where: { matches(lowered, word: $0.lowercased()) }) {
            return .allergy
        }
        if let rule = rules.first(where: { rule in
            forbiddenWords(for: rule).contains { matches(lowered, word: $0) }
        }) {
            return .rule(rule)
        }
        if dislikes.contains(where: { matches(lowered, word: $0.lowercased()) }) {
            return .dislike
        }
        return nil
    }

    /// Word-boundary-ish match: "ham" must not match "shawarma" or "graham".
    private static func matches(_ text: String, word: String) -> Bool {
        guard !word.isEmpty else { return false }
        if word.contains(" ") { return text.contains(word) }
        let tokens = text.split { !$0.isLetter }.map(String.init)
        // Cover simple plurals both ways ("egg" rule vs "eggs" ingredient).
        return tokens.contains { token in
            token == word || token == word + "s" || token + "s" == word
        }
    }

    private static func rank(_ severity: Conflict.Severity) -> Int {
        switch severity {
        case .allergy: 0
        case .rule: 1
        case .dislike: 2
        }
    }
}
