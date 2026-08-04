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
    /// Shellfish is the seafood subset that kosher rules forbid (fin fish is fine).
    private static let shellfishWords: Set<String> = [
        "shrimp", "prawn", "crab", "lobster", "oyster", "mussel", "clam",
        "scallop", "squid", "octopus",
    ]
    private static let dairyWords: Set<String> = [
        "milk", "butter", "cheese", "cream", "yogurt", "ghee",
        "mozzarella", "parmesan", "cheddar", "feta", "ricotta", "mascarpone",
    ]
    /// Plant milks / creams / yogurts — "soy milk" must not trip `milk`.
    private static let plantDairyBases: Set<String> = [
        "soy", "soya", "oat", "almond", "coconut", "cashew", "rice", "hemp",
        "pea", "flax", "macadamia", "hazelnut", "pistachio", "walnut",
        "quinoa", "banana", "potato", "sesame", "sunflower",
    ]
    /// "Butter" that isn't dairy (nut/seed butters, cocoa butter, etc.).
    private static let nonDairyButterModifiers: Set<String> = [
        "peanut", "almond", "cashew", "sunflower", "seed", "cookie",
        "pumpkin", "walnut", "hazelnut", "cocoa", "cacao", "shea", "apple",
    ]
    private static let eggWords: Set<String> = ["egg", "eggs", "mayonnaise", "mayo"]
    private static let glutenWords: Set<String> = [
        "flour", "wheat", "bread", "pasta", "noodle", "couscous", "barley",
        "tortilla", "pita", "flatbread", "breadcrumb", "cracker", "gnocchi",
        "soy sauce", "bun", "baguette",
    ]
    /// Non-halal beyond pork: alcohol and gelatin (unless certified, which we can't know).
    private static let gelatinWords: Set<String> = ["gelatin", "gelatine"]
    private static let nutWords: Set<String> = [
        "nut", "nuts", "almond", "walnut", "peanut", "cashew", "pecan",
        "macadamia", "hazelnut", "pistachio", "brazil nut", "pine nut",
    ]
    private static let ketoWords: Set<String> = [
        "sugar", "honey", "syrup", "bread", "pasta", "noodle", "noodles",
        "potato", "potatoes", "wheat", "oats", "oatmeal", "cornstarch",
        "tortilla", "couscous", "barley",
    ]

    static func forbiddenWords(for rule: DietaryRule) -> Set<String> {
        switch rule {
        case .halal: porkWords.union(alcoholWords).union(gelatinWords)
        // Simplified, honest kosher guard: blocks pork and shellfish (the two
        // we can detect by ingredient). It can't verify certification or the
        // meat/dairy separation rule, so it's an aid, not a kosher guarantee.
        case .kosher: porkWords.union(shellfishWords)
        case .noPork: porkWords
        // Pescatarian: no land meat (pork included), but fish/shellfish are fine.
        case .pescatarian: meatWords.union(gelatinWords)
        case .vegetarian: meatWords.union(seafoodWords).union(gelatinWords)
        case .vegan: meatWords.union(seafoodWords).union(gelatinWords)
            .union(dairyWords).union(eggWords).union(["honey"])
        case .glutenFree: glutenWords
        case .dairyFree: dairyWords
        case .nutFree: nutWords
        // Keto is macro-based; keyword presence is an aid, not a guarantee —
        // favors avoiding false flags on keto-substitute ingredients
        // (almond flour, cauliflower rice, baking soda).
        case .keto: ketoWords
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
        let plantLabeled = isExplicitlyPlantBased(lowered)
        let plantDairy = isPlantDairyAlternative(lowered)

        if let allergy = allergies.first(where: { matches(lowered, word: $0.lowercased()) }) {
            // "soy milk" shouldn't count as a milk allergy hit.
            let allergyWord = allergy.lowercased()
            let allergyIsDairy = allergyWord == "dairy"
                || allergyWord == "lactose"
                || dairyWords.contains(where: { matches(allergyWord, word: $0) || allergyWord == $0 })
            if !(plantDairy && allergyIsDairy) {
                return .allergy
            }
        }
        // Plant labels only clear animal-product hits — not carbs/gluten/nuts.
        let animalWords = meatWords
            .union(seafoodWords)
            .union(gelatinWords)
            .union(dairyWords)
            .union(eggWords)
            .union(["honey"])

        if let rule = rules.first(where: { rule in
            forbiddenWords(for: rule).contains { word in
                guard matches(lowered, word: word) else { return false }
                // "vegan butter", "plant-based sausage" — labeled plant products.
                if plantLabeled && animalWords.contains(word) { return false }
                // "soy milk", "coconut cream", "peanut butter" — not animal dairy.
                if dairyWords.contains(word) && plantDairy { return false }
                return true
            }
        }) {
            return .rule(rule)
        }
        if dislikes.contains(where: { matches(lowered, word: $0.lowercased()) }) {
            return .dislike
        }
        return nil
    }

    /// "vegan …", "plant-based …", "dairy-free …", "non-dairy …".
    private static func isExplicitlyPlantBased(_ text: String) -> Bool {
        let tokens = letterTokens(text)
        if tokens.contains("vegan") || tokens.contains("plantbased") { return true }
        if tokens.contains("plant") && tokens.contains("based") { return true }
        if tokens.contains("dairyfree") || tokens.contains("nondairy") { return true }
        if tokens.contains("dairy") && tokens.contains("free") { return true }
        if tokens.contains("non") && tokens.contains("dairy") { return true }
        if tokens.contains("egg") && tokens.contains("free") { return true }
        if tokens.contains("eggfree") { return true }
        return false
    }

    /// Plant milks/creams/yogurts/cheeses and non-dairy butters.
    private static func isPlantDairyAlternative(_ text: String) -> Bool {
        if isExplicitlyPlantBased(text) { return true }
        let tokens = Set(letterTokens(text))
        let hasDairyToken = dairyWords.contains { word in
            tokens.contains(word) || tokens.contains(word + "s")
        }
        guard hasDairyToken else { return false }
        if !plantDairyBases.isDisjoint(with: tokens) { return true }
        // peanut butter, cocoa butter, apple butter, …
        if tokens.contains("butter") && !nonDairyButterModifiers.isDisjoint(with: tokens) {
            return true
        }
        return false
    }

    private static func letterTokens(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return normalized.split { !$0.isLetter }.map(String.init)
    }

    /// Word-boundary-ish match: "ham" must not match "shawarma" or "graham".
    private static func matches(_ text: String, word: String) -> Bool {
        guard !word.isEmpty else { return false }
        if word.contains(" ") { return text.contains(word) }
        let tokens = letterTokens(text)
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
