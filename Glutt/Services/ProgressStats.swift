import Foundation

/// Pure stat computations for the Progress tab. Kept out of the views
/// so streaks and counts are testable.
enum ProgressStats {

    /// Days in a row (ending today or yesterday) with at least one cook session.
    /// Yesterday still counts as alive — nobody loses a streak while asleep.
    static func cookingStreak(sessions: [CookSession], now: Date = .now) -> Int {
        let calendar = Calendar.current
        let cookedDays = Set(sessions.map { calendar.startOfDay(for: $0.date) })
        guard !cookedDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        var cursor = today
        if !cookedDays.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
            guard cookedDays.contains(cursor) else { return 0 }
        }

        var streak = 0
        while cookedDays.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    static func sessionsThisWeek(_ sessions: [CookSession], now: Date = .now) -> [CookSession] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        return sessions.filter { $0.date > weekAgo }
    }

    /// Distinct recipes ever cooked, and how many were first cooked in the last 30 days.
    static func recipesTried(sessions: [CookSession], now: Date = .now) -> (total: Int, newThisMonth: Int) {
        var firstCook: [ObjectIdentifier: Date] = [:]
        for session in sessions {
            guard let recipe = session.recipe else { continue }
            let id = ObjectIdentifier(recipe)
            if let existing = firstCook[id] {
                firstCook[id] = min(existing, session.date)
            } else {
                firstCook[id] = session.date
            }
        }
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let newCount = firstCook.values.filter { $0 > monthAgo }.count
        return (firstCook.count, newCount)
    }

    /// Most-loved meals: repeats weighted with ratings.
    static func favoriteRecipes(sessions: [CookSession], limit: Int = 3) -> [(recipe: Recipe, cookCount: Int)] {
        var counts: [ObjectIdentifier: (recipe: Recipe, count: Int)] = [:]
        for session in sessions {
            guard let recipe = session.recipe else { continue }
            let id = ObjectIdentifier(recipe)
            counts[id] = (recipe, (counts[id]?.count ?? 0) + 1)
        }
        return counts.values
            .sorted {
                let left = Double($0.count) + Double($0.recipe.rating ?? 0) / 2
                let right = Double($1.count) + Double($1.recipe.rating ?? 0) / 2
                return left > right
            }
            .prefix(limit)
            .map { (recipe: $0.recipe, cookCount: $0.count) }
    }

    /// Leftover logs in the window — the food-waste win.
    static func leftoversUsed(logs: [FoodLog], days: Int = 7, now: Date = .now) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        return logs.filter { $0.source == .leftover && $0.timestamp > cutoff }.count
    }

    static func eatingOutCount(logs: [FoodLog], days: Int = 7, now: Date = .now) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        return logs.filter { $0.source == .restaurant && $0.timestamp > cutoff }.count
    }

    /// Calories and protein logged per day for the last `days` days (oldest first).
    static func dailyTotals(logs: [FoodLog], days: Int = 7, now: Date = .now) -> [(day: Date, calories: Int, protein: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let dayLogs = logs.filter { calendar.startOfDay(for: $0.timestamp) == day }
            let calories = dayLogs.compactMap(\.calories).reduce(0, +)
            let protein = dayLogs.compactMap(\.proteinGrams).reduce(0, +)
            return (day, calories, protein)
        }
    }

    /// The titles this user logs most — powers "repeat frequent meal" quick-add.
    static func frequentMeals(logs: [FoodLog], limit: Int = 6) -> [String] {
        let counted = Dictionary(grouping: logs.map(\.title)) { $0 }.mapValues(\.count)
        return counted
            .filter { $0.value >= 2 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map(\.key)
    }
}
