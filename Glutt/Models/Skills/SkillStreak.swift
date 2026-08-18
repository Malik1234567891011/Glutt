import Foundation

/// Consecutive local days on which the cook learned at least one skill.
///
/// Same shape as `PlatesStreak` next door, deliberately: two streaks in one app
/// that roll over on different rules would be a bug nobody could explain. Kept
/// in `UserDefaults` for the same reason, since it is a counter rather than
/// something worth a model and a migration.
enum SkillStreak {
    private static let lastDayKey = "glutt.skills.streak.lastDay"
    private static let countKey = "glutt.skills.streak.count"

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Records a skill learned today and returns the resulting streak.
    /// Learning five skills in one day is one day, not five.
    @discardableResult
    static func recordLearned(today: Date = .now, store: UserDefaults = .standard) -> Int {
        let todayString = dayString(today)
        let last = store.string(forKey: lastDayKey)
        if last == todayString { return max(1, store.integer(forKey: countKey)) }

        let yesterday = dayString(Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today)
        let count = (last == yesterday) ? store.integer(forKey: countKey) + 1 : 1
        store.set(todayString, forKey: lastDayKey)
        store.set(count, forKey: countKey)
        return count
    }

    /// The streak as it stands, which is zero once a day has been missed.
    ///
    /// Computed rather than stored so a streak expires by itself. Reading the
    /// stored count directly would show "7 day streak" to someone who last
    /// cooked in March.
    static func current(today: Date = .now, store: UserDefaults = .standard) -> Int {
        guard let last = store.string(forKey: lastDayKey) else { return 0 }
        let todayString = dayString(today)
        let yesterday = dayString(Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today)
        guard last == todayString || last == yesterday else { return 0 }
        return max(0, store.integer(forKey: countKey))
    }

    /// True when today has not been counted yet, so the UI can say "keep it going".
    static func needsTodayToContinue(today: Date = .now, store: UserDefaults = .standard) -> Bool {
        store.string(forKey: lastDayKey) != dayString(today)
    }

    static func reset(store: UserDefaults = .standard) {
        store.removeObject(forKey: lastDayKey)
        store.removeObject(forKey: countKey)
    }
}
