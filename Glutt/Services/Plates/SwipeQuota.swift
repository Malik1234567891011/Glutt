import Foundation

/// How many Discover cards a free cook may judge in a week.
///
/// The free tier's one metered feature. Everything else in Glutt is either free
/// outright (importing, reading a recipe, its macros) or Pro outright; the deck
/// is the single place where the answer is "some". It is metered rather than
/// crowned because a deck you cannot swipe at all is not a deck, and because
/// every page of cards costs real Spoonacular quota (see the proxy's
/// `plates/deck.js`, which runs on a 50-points-a-day plan for the whole app).
///
/// Kept in `UserDefaults`, matching `PlatesStreak` and `PlatesSeenStore` next
/// door. That makes it resettable by deleting the app, which is accepted: this
/// is a nudge toward subscribing, not a security boundary, and the features
/// worth actually protecting (Polly, the kitchen, week planning) are gated on
/// entitlement rather than on a counter.
///
/// The window is the **calendar week**, so the answer to "when do I get more" is
/// a weekday the cook can be told, rather than a rolling timestamp they would
/// have to guess at.
enum SwipeQuota {

    /// Swipes a free cook gets per calendar week.
    static let freeWeeklyLimit = 10

    private static let usedKey = "discover.swipes.used"
    private static let weekStartKey = "discover.swipes.weekStart"

    // MARK: - Window

    /// Start of the calendar week containing `date`. Which weekday that is comes
    /// from the user's own locale, which is also what their phone's calendar
    /// says, so "resets Monday" matches what they already believe.
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            // A calendar that can't produce a week interval is not a state worth
            // a crash: fall back to the day, so the allowance refreshes more
            // often rather than never.
            ?? calendar.startOfDay(for: date)
    }

    /// When the allowance comes back.
    static func resetDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        let start = weekStart(for: now, calendar: calendar)
        return calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start.addingTimeInterval(604_800)
    }

    // MARK: - Reading
    //
    // Reads are side-effect free on purpose. The stored week is only rewritten
    // when a swipe is actually recorded, so merely opening Discover in a new
    // week (and bouncing straight out) never touches the store.

    /// Swipes used in the week containing `now`. A stored count from an earlier
    /// week reads as zero.
    static func used(now: Date = .now, store: UserDefaults = .standard, calendar: Calendar = .current) -> Int {
        let currentWeek = weekStart(for: now, calendar: calendar)
        guard let storedWeek = storedWeekStart(in: store), storedWeek == currentWeek else { return 0 }
        return max(0, store.integer(forKey: usedKey))
    }

    static func remaining(now: Date = .now, store: UserDefaults = .standard, calendar: Calendar = .current) -> Int {
        max(0, freeWeeklyLimit - used(now: now, store: store, calendar: calendar))
    }

    /// Whether a free cook may swipe again. Pro cooks never ask.
    static func hasSwipesLeft(now: Date = .now, store: UserDefaults = .standard, calendar: Calendar = .current) -> Bool {
        remaining(now: now, store: store, calendar: calendar) > 0
    }

    // MARK: - Writing

    /// Records one swipe and returns how many are left after it.
    ///
    /// `isPro` is taken here rather than checked at the call site so the rule
    /// "a subscriber's swipes are never counted" is enforced in the one place it
    /// can be tested, instead of in whichever view remembers to ask. A lapsed
    /// subscriber therefore starts their next week from zero used, which is the
    /// generous direction and the correct one.
    @discardableResult
    static func record(
        isPro: Bool,
        now: Date = .now,
        store: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> Int {
        guard !isPro else { return freeWeeklyLimit }

        let currentWeek = weekStart(for: now, calendar: calendar)
        let priorUsed = used(now: now, store: store, calendar: calendar)
        store.set(currentWeek.timeIntervalSinceReferenceDate, forKey: weekStartKey)
        store.set(priorUsed + 1, forKey: usedKey)
        return max(0, freeWeeklyLimit - (priorUsed + 1))
    }

    /// Gives a swipe back, for an undo.
    ///
    /// Without this, undoing a swipe costs the cook the swipe anyway — they take
    /// the card back and are one closer to the wall for it, which reads as the
    /// app charging them for a mistake.
    static func refund(
        isPro: Bool,
        now: Date = .now,
        store: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        guard !isPro else { return }
        let priorUsed = used(now: now, store: store, calendar: calendar)
        guard priorUsed > 0 else { return }
        let currentWeek = weekStart(for: now, calendar: calendar)
        store.set(currentWeek.timeIntervalSinceReferenceDate, forKey: weekStartKey)
        store.set(priorUsed - 1, forKey: usedKey)
    }

    /// Clears the counter. For the dev menu and tests, not for product code.
    static func reset(store: UserDefaults = .standard) {
        store.removeObject(forKey: usedKey)
        store.removeObject(forKey: weekStartKey)
    }

    // MARK: - Private

    private static func storedWeekStart(in store: UserDefaults) -> Date? {
        guard store.object(forKey: weekStartKey) != nil else { return nil }
        return Date(timeIntervalSinceReferenceDate: store.double(forKey: weekStartKey))
    }
}
