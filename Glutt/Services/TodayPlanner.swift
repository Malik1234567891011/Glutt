import Foundation

/// Decides what the Today screen leads with. Pure functions, testable.
enum TodayPlanner {

    /// The meal to feature: the first unresolved meal of today,
    /// ordered by exact time when set, meal-type order otherwise.
    static func nextUp(meals: [PlannedMeal], now: Date = .now) -> PlannedMeal? {
        let today = Calendar.current.startOfDay(for: now)
        return meals
            .filter { $0.date == today && $0.status == .planned }
            .sorted { left, right in
                switch (left.exactTime, right.exactTime) {
                case let (leftTime?, rightTime?): leftTime < rightTime
                case (.some, .none): true
                case (.none, .some): false
                case (.none, .none): left.mealType.sortOrder < right.mealType.sortOrder
                }
            }
            .first
    }

    /// Pantry items flagged use-soon that are still in stock, most urgent first.
    static func useSoonItems(pantry: [PantryItem], now: Date = .now) -> [PantryItem] {
        pantry
            .filter { $0.useSoonDate != nil && $0.roughQuantity != .out }
            .sorted { ($0.useSoonDate ?? now) < ($1.useSoonDate ?? now) }
    }

    /// "Missing: heavy cream · Swap: Greek yogurt + butter" — one honest line.
    static func missingLine(
        for recipe: Recipe,
        pantry: [PantryItem],
        rules: [DietaryRule] = [],
        allergies: [String] = []
    ) -> String? {
        let match = PantryMatcher.match(recipe: recipe, pantry: pantry)
        guard let firstMissing = match.missing.first else { return nil }

        var line: String
        if match.missing.count == 1 {
            line = "Missing: \(firstMissing.name.lowercased())"
        } else {
            line = "Missing: \(firstMissing.name.lowercased()) + \(match.missing.count - 1) more"
        }
        if let swap = SubstitutionService.availableSubstitutions(
            for: firstMissing.canonicalName,
            pantry: pantry,
            rules: rules,
            allergies: allergies
        ).first {
            line += " · Swap: \(swap.name)"
        }
        return line
    }
}
