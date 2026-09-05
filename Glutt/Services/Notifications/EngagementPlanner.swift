import Foundation

/// Decides the single most useful reason to open Glutt right now, or nothing.
///
/// # Why this is a pure function
///
/// The whole product question lives here: *given everything Glutt knows about
/// this person, is there one thing worth interrupting them for?* That question
/// has nothing to do with SwiftData or `UNUserNotificationCenter`, and mixing
/// it with either would make it untestable in exactly the cases that matter,
/// which are the ones where the answer should be **no**.
///
/// So: `EngagementScheduler` gathers a snapshot, this decides, and only the
/// scheduler talks to iOS.
///
/// # The rule this replaces
///
/// The app used to schedule one repeating 07:00 request that said "Today's
/// Plate is ready, 12 fresh recipes to swipe through", every day, forever,
/// identically, to everyone. It advertised the shallowest surface in the
/// product, at an hour nobody decides what to cook, with a recipe count that
/// was hardcoded. This exists to say something true instead, or say nothing.
enum EngagementPlanner {

    // MARK: - What the planner is told

    struct SavedRecipe: Equatable {
        let id: UUID
        let title: String
        let savedAt: Date?
        /// Only set when the recipe genuinely carries a time. Never invented.
        let totalMinutes: Int?
        /// How many required ingredients the recipe actually parsed. A recipe
        /// with none of them cannot honestly be called cookable.
        let ingredientCount: Int

        init(id: UUID, title: String, savedAt: Date?, totalMinutes: Int?, ingredientCount: Int = 1) {
            self.id = id
            self.title = title
            self.savedAt = savedAt
            self.totalMinutes = totalMinutes
            self.ingredientCount = ingredientCount
        }
    }

    struct NextSkill: Equatable {
        let id: String
        let title: String
    }

    /// A snapshot of everything the decision is allowed to look at.
    struct State {
        /// Names of pantry items worth cooking now, most urgent first. The
        /// scheduler is responsible for excluding items whose date has gone so
        /// far past that the food is no longer plausibly in the fridge.
        var useSoonItems: [String] = []
        /// Saved, never cooked, oldest save first. The user's own library only:
        /// bundled chef dishes and technique lessons are not theirs to be
        /// reminded about.
        var savedNotCooked: [SavedRecipe] = []
        /// Saved recipes the pantry covers completely.
        var cookableNow: [SavedRecipe] = []
        var savedRecipeCount: Int = 0

        var skillStreak: Int = 0
        /// True when today has not counted toward the streak yet.
        var streakNeedsToday: Bool = false
        var hasStartedSkills: Bool = false
        var lastSkillLearnedAt: Date?
        var nextSkill: NextSkill?

        /// The last engagement notification iOS actually **delivered**. Not the
        /// one currently scheduled: see `EngagementScheduler` for why confusing
        /// the two silences the entire system.
        var lastSentAt: Date?
        var lastSentKind: Kind?
        /// What that notification was about, so the same pantry item or recipe
        /// is not the subject two days running.
        var lastSentSubject: String?
    }

    // MARK: - What comes out

    enum Kind: String, Equatable, Codable, CaseIterable {
        case useSoon
        case savedRecipe
        case cookableNow
        case streakAtRisk
        case skillInactive
        case emptyLibrary
    }

    struct Plan: Equatable {
        let kind: Kind
        let title: String
        let body: String
        /// Where a tap lands. Every plan has one; none of them opens "the app".
        let destination: URL
        let fireAt: Date
        /// The thing this is about, for the repeat guard. Nil when the tier is
        /// about the account rather than an item.
        let subject: String?
    }

    // MARK: - Thresholds
    //
    // Named rather than inline so the product decisions are arguable without
    // reading control flow.

    /// One engagement notification per day, whatever else is true.
    static let minimumGapHours = 22
    /// A recipe saved this recently is still on the cook's mind. Resurfacing it
    /// the next morning would be nagging somebody about a decision they have
    /// not had a chance to act on yet.
    static let savedRecipeQuietDays = 2
    /// Past this, a saved recipe has been forgotten rather than postponed.
    static let savedRecipeStaleDays = 21
    /// A streak worth protecting. Two days is a coincidence, not a habit, and
    /// telling somebody on day one that they have a streak to lose is the kind
    /// of manufactured urgency this ladder exists to avoid.
    static let streakWorthProtecting = 3
    /// Long enough that the map has genuinely gone quiet.
    static let skillInactiveDays = 5
    /// Below this the library is empty enough that building it IS the next step.
    static let smallLibraryCount = 3
    /// The lowest tier is a fallback, not a drip. Once a week at most.
    static let emptyLibraryGapDays = 7
    /// No single pantry item or recipe may be the subject two days running,
    /// however urgent it is. This is what stops one forgotten bag of spinach
    /// from becoming a daily message that never changes.
    static let sameSubjectGapDays = 2
    /// A recipe needs to be more than a title before Glutt claims the kitchen
    /// covers it. Imports that parsed nothing match everything, vacuously.
    static let minimumIngredientsToClaimCookable = 3

    // MARK: - The decision

    /// The one notification worth scheduling, or nil for silence.
    static func plan(for state: State, now: Date = .now, calendar: Calendar = .current) -> Plan? {
        // Frequency first, so no amount of good signal can produce two in a day.
        if let last = state.lastSentAt,
           now.timeIntervalSince(last) < Double(minimumGapHours) * 3600 {
            return nil
        }

        for kind in Kind.allCases {
            guard !isOnCooldown(kind, state: state, now: now) else { continue }
            if let plan = build(kind, state: state, now: now, calendar: calendar) {
                return plan
            }
        }
        return nil
    }

    /// The two weakest tiers must not run on consecutive days at all. The higher
    /// tiers may repeat, because they are about a real and changing kitchen, but
    /// never about the *same thing* two days running: that guard is per subject
    /// and lives in `blockedSubject`.
    private static func isOnCooldown(_ kind: Kind, state: State, now: Date) -> Bool {
        guard state.lastSentKind == kind, let last = state.lastSentAt else { return false }
        switch kind {
        case .emptyLibrary:
            return now.timeIntervalSince(last) < Double(emptyLibraryGapDays) * 86_400
        case .skillInactive, .streakAtRisk:
            return now.timeIntervalSince(last) < 2 * 86_400
        case .useSoon, .savedRecipe, .cookableNow:
            return false
        }
    }

    /// The subject that may not be repeated right now, if any.
    private static func blockedSubject(_ kind: Kind, state: State, now: Date) -> String? {
        guard state.lastSentKind == kind,
              let last = state.lastSentAt,
              now.timeIntervalSince(last) < Double(sameSubjectGapDays) * 86_400
        else { return nil }
        return state.lastSentSubject
    }

    private static func build(
        _ kind: Kind,
        state: State,
        now: Date,
        calendar: Calendar
    ) -> Plan? {
        switch kind {

        // 1. Something in the kitchen is on a clock. The only tier about food
        //    that will be wasted if nobody acts, so it outranks everything.
        case .useSoon:
            let blocked = blockedSubject(.useSoon, state: state, now: now)
            guard let item = state.useSoonItems.first(where: { $0 != blocked }) else { return nil }
            let name = Copy.clean(item, limit: Copy.maxNameLength)
            guard !name.isEmpty else { return nil }
            return Plan(
                kind: .useSoon,
                // The name leads, so its own capitalisation is always correct.
                // Bending "Greek yogurt" into mid-sentence case is how the
                // previous version turned proper nouns into typos.
                title: "\(name) won't keep much longer",
                // No count of recipes: the app has not run a search at send
                // time and would be inventing the number. The Kitchen tab opens
                // on the invent-a-dish prompt, so this is one tap from true.
                body: "Glutt can build tonight's dinner around it.",
                destination: Destination.kitchen,
                fireAt: nextFoodHour(after: now, calendar: calendar),
                subject: item)

        // 2. They already decided they wanted this. That is stronger intent
        //    than anything Glutt could suggest on its own.
        case .savedRecipe:
            let blocked = blockedSubject(.savedRecipe, state: state, now: now)
            guard let recipe = eligibleSavedRecipe(state, now: now, blocked: blocked),
                  case let title = Copy.clean(recipe.title), !title.isEmpty else { return nil }
            return Plan(
                kind: .savedRecipe,
                title: "Dinner is already saved",
                body: subtitle(title: title, minutes: recipe.totalMinutes),
                destination: Destination.recipe(recipe.id),
                fireAt: nextFoodHour(after: now, calendar: calendar),
                subject: recipe.id.uuidString)

        // 3. Nothing to buy, nothing to decide.
        case .cookableNow:
            let blocked = blockedSubject(.cookableNow, state: state, now: now)
            guard let recipe = state.cookableNow.first(where: {
                $0.id.uuidString != blocked
                    && $0.ingredientCount >= minimumIngredientsToClaimCookable
            }), case let title = Copy.clean(recipe.title), !title.isEmpty else { return nil }
            return Plan(
                kind: .cookableNow,
                title: "No shopping needed tonight",
                // "Covers" rather than "you have everything": the pantry match
                // is deliberately fuzzy about quantity, and the in-app version
                // of this claim sits next to a count the cook can check.
                body: "Your kitchen already covers \(title).",
                destination: Destination.recipe(recipe.id),
                fireAt: nextFoodHour(after: now, calendar: calendar),
                subject: recipe.id.uuidString)

        // 4. Only for a streak that actually exists, and only today. A streak
        //    number is true for a matter of hours: scheduling one for tomorrow
        //    evening means announcing a streak that midnight already ended.
        case .streakAtRisk:
            guard state.skillStreak >= streakWorthProtecting,
                  state.streakNeedsToday,
                  let next = state.nextSkill else { return nil }
            let fireAt = nextSkillHour(after: now, calendar: calendar)
            guard calendar.isDate(fireAt, inSameDayAs: now) else { return nil }
            return Plan(
                kind: .streakAtRisk,
                title: "Keep your \(state.skillStreak)-day streak",
                body: "\(next.title) takes a couple of minutes.",
                destination: Destination.skill(next.id),
                fireAt: fireAt,
                subject: next.id)

        // 5. They started the course and stopped. Say how long only because
        //    the date is stored, and never in a way that reads as surveillance.
        case .skillInactive:
            guard state.hasStartedSkills,
                  let last = state.lastSkillLearnedAt,
                  let next = state.nextSkill else { return nil }
            let days = calendar.dayCount(from: last, to: now)
            guard days >= skillInactiveDays else { return nil }
            return Plan(
                kind: .skillInactive,
                title: "Ready for the next one?",
                body: "\(next.title) is next on your Skills map.",
                destination: Destination.skill(next.id),
                fireAt: nextSkillHour(after: now, calendar: calendar),
                subject: next.id)

        // 6. The weakest tier, and the only one with no fact about the cook in
        //    it. So it describes the mechanism rather than selling the product:
        //    somebody with an empty library usually does not yet know that a
        //    share sheet is the way in.
        case .emptyLibrary:
            guard state.savedRecipeCount < smallLibraryCount else { return nil }
            return Plan(
                kind: .emptyLibrary,
                title: "Save a recipe from anywhere",
                body: "Share a link or a screenshot to Glutt and it becomes something you can cook.",
                destination: Destination.saveHelp,
                fireAt: nextFoodHour(after: now, calendar: calendar),
                subject: nil)
        }
    }

    /// Saved long enough ago to have been forgotten, recently enough to still
    /// be wanted.
    private static func eligibleSavedRecipe(
        _ state: State, now: Date, blocked: String?
    ) -> SavedRecipe? {
        state.savedNotCooked.first { recipe in
            guard recipe.id.uuidString != blocked, let savedAt = recipe.savedAt else { return false }
            let days = now.timeIntervalSince(savedAt) / 86_400
            return days >= Double(savedRecipeQuietDays) && days <= Double(savedRecipeStaleDays)
        }
    }

    /// The recipe's own time when it has a believable one, and nothing invented
    /// when it does not. "about 30 min" on a recipe that never recorded a
    /// duration is the kind of small lie that costs more than the click is
    /// worth, and "about 730 min" off an overnight marinade is worse.
    private static func subtitle(title: String, minutes: Int?) -> String {
        guard let minutes = Copy.minutes(minutes) else {
            return "\(title) is still waiting for you."
        }
        return "\(title) · about \(minutes) min"
    }

    // MARK: - Copy hygiene
    //
    // Recipe and pantry names are user typed or scraped off the open web. They
    // arrive with emoji, marketing parentheticals, subtitle dashes and full
    // sentences of SEO. The planner's own strings are reviewed; these are not,
    // and they land on the lock screen with equal weight.

    enum Copy {
        /// Long enough for a real dish name, short enough that iOS does not cut
        /// the sentence off mid claim.
        static let maxLength = 34
        /// A pantry name leads its title and carries 23 more characters of
        /// sentence after it, so it gets a tighter budget than a recipe title
        /// that sits in the body. Real ones ("Chicken thighs") are well inside.
        static let maxNameLength = 16
        /// Below five minutes is almost always a parse failure; above three
        /// hours is a marinade or a proving time, not "dinner is 730 min away".
        static let plausibleMinutes = 5...180

        static func minutes(_ raw: Int?) -> Int? {
            guard let raw, plausibleMinutes.contains(raw) else { return nil }
            return raw
        }

        static func clean(_ raw: String, limit: Int = maxLength) -> String {
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            // "(Easy 30 Minute Weeknight Dinner!)", "[Vegan]" — the pitch, not
            // the dish.
            if let cut = text.firstIndex(where: { $0 == "(" || $0 == "[" }) {
                text = String(text[..<cut])
            }
            // A dash used as punctuation introduces a subtitle. Keeping the
            // dish and dropping the rest also keeps the repo's no-dashes rule,
            // which a scraped title would otherwise launder onto the lock
            // screen. Hyphenated compounds like "sun-dried" survive.
            for separator in [" — ", " – ", " - ", ", plus ", ": "] {
                if let range = text.range(of: separator) {
                    text = String(text[..<range.lowerBound])
                }
            }
            // Emoji, exclamation marks and stray symbols.
            let allowed: Set<Character> = ["'", "\u{2019}", ",", ".", "&", "-", "/", "+", "%"]
            text = String(text.filter {
                $0.isLetter || $0.isNumber || $0.isWhitespace || allowed.contains($0)
            })
            text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.-/&+"))

            // "MILK" is a real thing people type into a pantry list. Shouting it
            // back at them is not.
            if text.count > 3, text.contains(where: \.isLetter), text == text.uppercased() {
                text = String(text.prefix(1)) + text.dropFirst().lowercased()
            }

            guard text.count > limit else { return text }
            var clipped = ""
            for word in text.split(separator: " ") {
                if clipped.count + word.count + 1 > limit { break }
                clipped += clipped.isEmpty ? String(word) : " " + word
            }
            if clipped.isEmpty { clipped = String(text.prefix(limit)) }
            return clipped + "\u{2026}"
        }
    }

    // MARK: - When

    /// Late afternoon, when people decide what is for dinner.
    ///
    /// Fixed rather than learned. `CookSession` does store real timestamps, so
    /// a median cooking hour is computable, but before launch almost every user
    /// has zero sessions and the personalised path would be dead code carrying
    /// the risk of sending at 03:00 off one late-night session.
    static func nextFoodHour(after now: Date, calendar: Calendar = .current) -> Date {
        next(hour: 17, minute: 30, after: now, calendar: calendar)
    }

    /// Early evening: after dinner, when a two minute lesson is plausible.
    static func nextSkillHour(after now: Date, calendar: Calendar = .current) -> Date {
        next(hour: 19, minute: 0, after: now, calendar: calendar)
    }

    private static func next(hour: Int, minute: Int, after now: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        // On a DST transition `date(from:)` can fail for a wall-clock time that
        // does not exist that day. Falling back to `now` would then schedule at
        // whatever arbitrary hour it happens to be, which is exactly the 03:00
        // notification this function exists to prevent, so fall back to the
        // same clock time tomorrow instead.
        guard let today = calendar.date(from: components) else {
            return calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        }
        // At least a few minutes out, so a plan made at 17:29 does not fire
        // while the person is still holding the phone.
        if today.timeIntervalSince(now) > 300 { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
    }

    // MARK: - Where a tap lands

    enum Destination {
        /// The Kitchen tab, which opens on the inventory list with the
        /// invent-a-dish prompt pinned above it.
        static let kitchen = URL(string: "glutt://kitchen")!
        /// The share-sheet lesson, which is the thing an empty library needs.
        static let saveHelp = URL(string: "glutt://save-help")!
        static func recipe(_ id: UUID) -> URL {
            URL(string: "glutt://recipe?rid=\(id.uuidString)")!
        }
        static func skill(_ id: String) -> URL {
            let encoded = id.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? id
            return URL(string: "glutt://skill?id=\(encoded)")!
        }
    }
}

private extension Calendar {
    /// Whole days between two instants, counted by calendar day so "5 days"
    /// means five sleeps rather than 120 hours.
    func dayCount(from start: Date, to end: Date) -> Int {
        let a = startOfDay(for: start)
        let b = startOfDay(for: end)
        return dateComponents([.day], from: a, to: b).day ?? 0
    }
}
