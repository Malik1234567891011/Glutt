import Foundation

/// Drafts a week of meals from the user's own library.
/// Heuristics only (no AI): pantry match, ratings, recency, variety.
enum WeekPlanner {

    struct DraftSlot: Identifiable {
        let id = UUID()
        let date: Date
        let mealType: MealType
        var recipe: Recipe?
        var leftover: Leftover?

        var title: String {
            recipe?.title ?? leftover.map { "Leftover: \($0.title)" } ?? "Empty"
        }
    }

    struct Input {
        var days: Int
        var mealTypes: [MealType]
        var useLeftovers: Bool
        var recipes: [Recipe]
        var pantry: [PantryItem]
        var leftovers: [Leftover]
        var recentSessions: [CookSession]
        /// Hard filters: never plan something that breaks a rule or allergy.
        var rules: [DietaryRule] = []
        var allergies: [String] = []
    }

    private static func candidates(_ input: Input) -> [Recipe] {
        input.recipes.filter {
            $0.parentRecipe == nil && !$0.steps.isEmpty
                && DietGuard.isSuggestable($0, rules: input.rules, allergies: input.allergies)
        }
    }

    static func draft(_ input: Input) -> [DraftSlot] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: .now)

        // Score every candidate recipe once.
        let ranked = candidates(input)
            .map { (recipe: $0, score: score(recipe: $0, input: input)) }
            .sorted { $0.score > $1.score }
            .map(\.recipe)

        var availableLeftovers = input.useLeftovers
            ? input.leftovers.filter { $0.servingsRemaining > 0 && !$0.isFrozen }
            : []
        var usedRecipes: [Recipe] = []
        var slots: [DraftSlot] = []

        for dayOffset in 0..<input.days {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: startDay)!
            for mealType in input.mealTypes.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                // Leftovers claim lunch slots first — that's how real kitchens work.
                if mealType == .lunch, !availableLeftovers.isEmpty {
                    let leftover = availableLeftovers.removeFirst()
                    slots.append(DraftSlot(date: date, mealType: mealType, leftover: leftover))
                    continue
                }
                let recipe = nextRecipe(from: ranked, excluding: usedRecipes)
                if let recipe {
                    usedRecipes.append(recipe)
                }
                slots.append(DraftSlot(date: date, mealType: mealType, recipe: recipe))
            }
        }
        return slots
    }

    /// Replacement candidate for a slot the user doesn't like.
    static func swap(slot: DraftSlot, in slots: [DraftSlot], input: Input) -> Recipe? {
        let used = slots.compactMap(\.recipe) + (slot.recipe.map { [$0] } ?? [])
        let ranked = candidates(input)
            .map { (recipe: $0, score: score(recipe: $0, input: input)) }
            .sorted { $0.score > $1.score }
            .map(\.recipe)
        return nextRecipe(from: ranked, excluding: used)
    }

    // MARK: - Scoring

    static func score(recipe: Recipe, input: Input) -> Double {
        var score = 0.0

        // Cookable-right-now is the biggest factor.
        let match = PantryMatcher.match(recipe: recipe, pantry: input.pantry)
        if match.totalCount > 0 {
            score += 3.0 * Double(match.ownedCount) / Double(match.totalCount)
        }

        // The user's own ratings.
        if let rating = recipe.rating {
            score += Double(rating) / 2.0
        }

        // Don't repeat what was cooked this week.
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let cookedRecently = input.recentSessions.contains {
            $0.recipe === recipe && $0.date > weekAgo
        }
        if cookedRecently { score -= 2.0 }

        // Mild jitter so the same week isn't drafted every time.
        score += Double.random(in: 0...0.4)
        return score
    }

    private static func nextRecipe(from ranked: [Recipe], excluding used: [Recipe]) -> Recipe? {
        ranked.first { candidate in !used.contains { $0 === candidate } }
            ?? ranked.first
    }
}
