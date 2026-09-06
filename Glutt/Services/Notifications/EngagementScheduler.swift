import Foundation
import SwiftData
import UserNotifications

/// Gathers what Glutt knows, asks `EngagementPlanner` what is worth saying, and
/// keeps exactly one engagement notification pending.
///
/// # One pending request, always
///
/// Everything is scheduled under a single identifier. That is what makes the
/// "do not stack", "cancel when stale" and "replace when state changes" rules
/// fall out for free rather than needing bookkeeping: recomputing replaces
/// whatever was pending, and if the planner now says nothing, the pending one
/// is simply removed. A cook who used the spinach and opens the app stops
/// being told to use the spinach.
///
/// # Pending is not the same as delivered
///
/// The frequency cap asks "when did iOS last *show* one of these?", and the
/// only honest answer comes from a fire time that is now in the past. Storing
/// the fire time of a request that has not fired yet and then feeding it to the
/// cap inverts the whole system: every foreground removes the pending request,
/// the cap sees a timestamp "less than 22 hours ago" (it is in the *future*),
/// declines to schedule a replacement, and the app goes quiet for a day. The
/// more somebody used Glutt, the less it would ever say. Hence two keys, and
/// `Bookkeeping.promote` as the one place a pending plan becomes delivered.
///
/// Cook timers are scheduled by `TimerManager` under their own identifiers and
/// are deliberately untouched here: they are a functional response to an
/// explicit action, not engagement, and must never be rate limited by it.
@MainActor
enum EngagementScheduler {

    /// One id, so there is only ever one of these in flight.
    // `nonisolated` because it is an immutable String: the default argument
    // `identifier: String = EngagementScheduler.identifier` is evaluated in the
    // caller context, which is an error in the Swift 6 language mode otherwise.
    nonisolated
    static let identifier = "glutt.engagement.next"

    /// The repeating 07:00 Discover reminder this system replaces.
    ///
    /// Kept as a constant because it is not enough to stop scheduling it: every
    /// existing install has a `repeats: true` request already sitting in iOS,
    /// and it would keep firing forever on those devices. It is removed on
    /// every pass rather than once behind a flag, which costs nothing and
    /// cannot be defeated by a migration that does not run.
    static let legacyPlatesIdentifier = "plates-daily"

    private static let enabledKey = "glutt.engagement.enabled"

    /// The frequency bookkeeping, kept apart from iOS on purpose.
    ///
    /// Every genuine bug in this feature has lived in the transition between
    /// "scheduled" and "shown", and none of it needs a notification centre to
    /// reason about, so none of it needs one to test either.
    enum Bookkeeping {
        /// What is scheduled right now. Freely replaced on every pass.
        static let pendingFireAtKey = "glutt.engagement.pendingFireAt"
        static let pendingKindKey = "glutt.engagement.pendingKind"
        static let pendingSubjectKey = "glutt.engagement.pendingSubject"

        /// What iOS has actually shown. Only ever written by `promote`.
        static let deliveredAtKey = "glutt.engagement.lastSentAt"
        static let deliveredKindKey = "glutt.engagement.lastKind"
        static let deliveredSubjectKey = "glutt.engagement.lastSubject"

        /// Moves a pending plan whose fire time has passed into the delivered
        /// slot. This is the only way a notification counts against the daily
        /// cap: a request that has not fired yet has not been shown to anybody.
        static func promote(store: UserDefaults, now: Date) {
            guard let fireAt = store.object(forKey: pendingFireAtKey) as? Date,
                  fireAt <= now else { return }
            store.set(fireAt, forKey: deliveredAtKey)
            store.set(store.string(forKey: pendingKindKey), forKey: deliveredKindKey)
            store.set(store.string(forKey: pendingSubjectKey), forKey: deliveredSubjectKey)
            clearPending(store: store)
        }

        static func recordPending(_ plan: EngagementPlanner.Plan, store: UserDefaults) {
            store.set(plan.fireAt, forKey: pendingFireAtKey)
            store.set(plan.kind.rawValue, forKey: pendingKindKey)
            store.set(plan.subject, forKey: pendingSubjectKey)
        }

        static func clearPending(store: UserDefaults) {
            store.removeObject(forKey: pendingFireAtKey)
            store.removeObject(forKey: pendingKindKey)
            store.removeObject(forKey: pendingSubjectKey)
        }

        /// Wipes the cap as well as the schedule, so a cook who toggles
        /// reminders off and straight back on is not silently muted for the
        /// rest of the day by a notification they just turned off.
        static func clearAll(store: UserDefaults) {
            clearPending(store: store)
            store.removeObject(forKey: deliveredAtKey)
            store.removeObject(forKey: deliveredKindKey)
            store.removeObject(forKey: deliveredSubjectKey)
        }
    }

    /// User-facing switch. Defaults on, but only ever acts once the OS
    /// permission has been granted, so "on" never means "we asked twice".
    static func isEnabled(store: UserDefaults = .standard) -> Bool {
        store.object(forKey: enabledKey) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool, store: UserDefaults = .standard) {
        store.set(enabled, forKey: enabledKey)
    }

    /// Guards against two passes interleaving across the `await` below. Both
    /// `RootView.task` and its `scenePhase` handler call `refresh`, and a
    /// second pass that snapshots after the first has written its pending keys
    /// would remove the first pass's request and schedule nothing.
    private static var isRefreshing = false

    // MARK: - Entry point

    /// Recompute from scratch. Safe to call on every launch and foreground.
    ///
    /// `isEntitled` is passed in rather than read here because Glutt is a hard
    /// paywall: with no subscription the app is inert behind an opaque cover,
    /// so a notification would be an invitation to a screen the cook cannot get
    /// past, about food they cannot cook, repeating daily. `SubscriptionGate`
    /// lives in the view layer and fails closed, so the caller owns the answer.
    static func refresh(
        context: ModelContext,
        isEntitled: Bool = true,
        center: UNUserNotificationCenter = .current(),
        store: UserDefaults = .standard,
        now: Date = .now
    ) async {
        // Always, regardless of permission or settings.
        center.removePendingNotificationRequests(withIdentifiers: [legacyPlatesIdentifier])

        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Before anything else: has the request we scheduled last time now
        // fired? That is the only event that moves the frequency cap.
        Bookkeeping.promote(store: store, now: now)

        // Turning the system off pulls the pending request *and* the record of
        // it. Leaving the record behind would let a notification nobody ever
        // saw get promoted to "delivered" later and spend a day of the cap.
        guard isEnabled(store: store), isEntitled else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            Bookkeeping.clearPending(store: store)
            return
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            Bookkeeping.clearPending(store: store)
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let state = snapshot(context: context, store: store, now: now)
        guard let plan = EngagementPlanner.plan(for: state, now: now) else {
            Bookkeeping.clearPending(store: store)
            return
        }

        do {
            try await center.add(request(for: plan, now: now))
        } catch {
            // A failed add must not leave bookkeeping claiming something is
            // scheduled: that would mute the next 22 hours for a notification
            // nobody will ever see.
            Bookkeeping.clearPending(store: store)
            return
        }

        Bookkeeping.recordPending(plan, store: store)
    }

    /// The one place a plan becomes something iOS will show.
    ///
    /// Shared with the debug preview hook on purpose: a preview built from a
    /// second, parallel content builder would be a preview of code that does
    /// not ship, which is worse than not previewing at all.
    ///
    /// The trigger is a **calendar** trigger, not an interval one. "17:30" is a
    /// wall-clock intention about when people decide what is for dinner, and
    /// freezing it into a number of seconds means someone who flies London to
    /// New York gets the dinner notification at half past twelve.
    static func request(
        for plan: EngagementPlanner.Plan,
        now: Date = .now,
        calendar: Calendar = .current,
        identifier: String = EngagementScheduler.identifier
    ) -> UNNotificationRequest {
        let components = calendar.dateComponents([.hour, .minute], from: plan.fireAt)
        return UNNotificationRequest(
            identifier: identifier,
            content: content(for: plan),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    /// Interval-triggered variant, for the debug preview only: a real preview
    /// cannot wait until 17:30.
    static func request(
        for plan: EngagementPlanner.Plan,
        in seconds: TimeInterval,
        identifier: String
    ) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: identifier,
            content: content(for: plan),
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, seconds), repeats: false))
    }

    private static func content(for plan: EngagementPlanner.Plan) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.userInfo = ["url": plan.destination.absoluteString,
                            "kind": plan.kind.rawValue]
        // Deliberately NOT `.timeSensitive`. These are worth reading; none of
        // them is worth breaking through somebody's Focus for.
        content.interruptionLevel = .active
        // Groups engagement notifications together in Notification Centre and
        // keeps them visually separate from `TimerManager`'s cook timers, which
        // are functional and must never look like the same kind of message.
        content.threadIdentifier = "glutt.engagement"
        content.categoryIdentifier = "GLUTT_ENGAGEMENT"
        return content
    }

    /// Clear everything this system owns, for a settings toggle going off.
    ///
    /// The frequency bookkeeping goes too. Leaving it behind means a cook who
    /// toggles off and straight back on is silently muted for the rest of the
    /// day by a cap counting a notification they turned off.
    static func cancelAll(center: UNUserNotificationCenter = .current(),
                          store: UserDefaults = .standard) {
        center.removePendingNotificationRequests(
            withIdentifiers: [identifier, legacyPlatesIdentifier])
        Bookkeeping.clearAll(store: store)
    }

    // MARK: - Reading the world

    static func snapshot(
        context: ModelContext,
        store: UserDefaults = .standard,
        now: Date = .now
    ) -> EngagementPlanner.State {
        var state = EngagementPlanner.State()

        let pantry = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        // `PantryItem.isUseSoon` has no floor: once the date passes it stays
        // true forever, so a bag of spinach bought in March is still "use soon"
        // in June. Unbounded, that one row would be the subject of every
        // notification this system ever sends, because the tier is rank one.
        let oldestWorthMentioning = now.addingTimeInterval(-Double(useSoonGraceDays) * 86_400)
        state.useSoonItems = pantry
            .filter {
                $0.isUseSoon && $0.roughQuantity != .out
                    && ($0.useSoonDate ?? .distantPast) >= oldestWorthMentioning
            }
            .sorted { ($0.useSoonDate ?? .distantFuture) < ($1.useSoonDate ?? .distantFuture) }
            .map(\.name)

        // The user's own library, using the same predicate as `RecipesView`.
        // The raw `Recipe` table also holds the technique lessons and ~26
        // bundled chef and restaurant dishes that `GluttApp` installs for
        // everybody on launch. Counting those made the empty-library tier
        // unreachable in production, and sorting by `importedAt` (which bundled
        // rows leave nil) floated them to the front of every other tier, so the
        // first notification a new cook received would call a technique lesson
        // "dinner they saved".
        let recipes = ((try? context.fetch(FetchDescriptor<Recipe>())) ?? []).filter {
            $0.parentRecipe == nil && !$0.isCookingBasic && (!$0.isCuratedRecipe || $0.isFavorite)
        }
        state.savedRecipeCount = recipes.count

        let sessions = (try? context.fetch(FetchDescriptor<CookSession>())) ?? []
        let cookedIDs = Set(sessions.compactMap { $0.recipe?.persistentModelID })

        // Oldest save first: the one most likely to have been forgotten.
        let uncooked = recipes
            .filter { !cookedIDs.contains($0.persistentModelID) }
            .sorted { ($0.importedAt ?? .distantPast) < ($1.importedAt ?? .distantPast) }

        state.savedNotCooked = uncooked.compactMap(saved)
        state.cookableNow = uncooked
            .filter { PantryMatcher.match(recipe: $0, pantry: pantry).hasEverything }
            .compactMap(saved)

        state.skillStreak = SkillStreak.current(today: now, store: store)
        state.streakNeedsToday = SkillStreak.needsTodayToContinue(today: now, store: store)

        let progress = (try? context.fetch(FetchDescriptor<SkillProgress>())) ?? []
        state.hasStartedSkills = !progress.isEmpty
        state.lastSkillLearnedAt = progress.compactMap(\.learnedAt).max()

        let learnedIDs = Set(progress.filter(\.isLearned).map(\.skillID))
        if let next = SkillProgression.recommended(learnedIDs: learnedIDs) {
            state.nextSkill = .init(id: next.id, title: next.title)
        }

        state.lastSentAt = store.object(forKey: Bookkeeping.deliveredAtKey) as? Date
        state.lastSentKind = (store.string(forKey: Bookkeeping.deliveredKindKey))
            .flatMap(EngagementPlanner.Kind.init(rawValue:))
        state.lastSentSubject = store.string(forKey: Bookkeeping.deliveredSubjectKey)

        return state
    }

    /// How far past its date a use-soon item stays worth a notification. Long
    /// enough to cover a weekend of not opening the app, short enough that an
    /// abandoned pantry row ages out instead of becoming a daily fixture.
    static let useSoonGraceDays = 2

    /// A recipe the planner can talk about. Needs a stable id to deep link to,
    /// which `RecipeIdentity.backfill` guarantees at launch.
    private static func saved(_ recipe: Recipe) -> EngagementPlanner.SavedRecipe? {
        guard let id = recipe.remoteID else { return nil }
        let minutes = recipe.prepMinutes + recipe.cookMinutes
        return EngagementPlanner.SavedRecipe(
            id: id,
            title: recipe.title,
            savedAt: recipe.importedAt,
            totalMinutes: minutes > 0 ? minutes : nil,
            // `MatchResult.hasEverything` is `missing.isEmpty`, which is
            // vacuously true for a recipe that parsed no ingredients at all. A
            // botched screenshot import would otherwise be permanently and
            // confidently "already in your kitchen".
            ingredientCount: recipe.ingredients.count)
    }
}
