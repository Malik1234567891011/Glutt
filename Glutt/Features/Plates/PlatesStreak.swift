import Foundation

/// Lightweight gamification counters in UserDefaults — no backend needed.
/// Streak = consecutive local days the user opened Plates.
enum PlatesStreak {
    private static let lastDayKey = "plates.streak.lastDay"
    private static let countKey = "plates.streak.count"
    private static let discoveredKey = "plates.discovered.total"
    private static let savedKey = "plates.saved.total"

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Records an open and returns the resulting streak length.
    @discardableResult
    static func recordOpen(today: Date = .now, store: UserDefaults = .standard) -> Int {
        let todayStr = dayString(today)
        let last = store.string(forKey: lastDayKey)
        if last == todayStr { return max(1, store.integer(forKey: countKey)) }

        let yesterday = dayString(Calendar.current.date(byAdding: .day, value: -1, to: today)!)
        let newCount = (last == yesterday) ? store.integer(forKey: countKey) + 1 : 1
        store.set(todayStr, forKey: lastDayKey)
        store.set(newCount, forKey: countKey)
        return newCount
    }

    static var current: Int { UserDefaults.standard.integer(forKey: countKey) }

    static func addDiscovered(_ n: Int, store: UserDefaults = .standard) {
        store.set(store.integer(forKey: discoveredKey) + n, forKey: discoveredKey)
    }
    static func addSaved(_ n: Int, store: UserDefaults = .standard) {
        store.set(store.integer(forKey: savedKey) + n, forKey: savedKey)
    }
    static var totalDiscovered: Int { UserDefaults.standard.integer(forKey: discoveredKey) }
    static var totalSaved: Int { UserDefaults.standard.integer(forKey: savedKey) }
}
