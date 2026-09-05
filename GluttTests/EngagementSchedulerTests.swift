import UserNotifications
import SwiftData
import XCTest
@testable import Glutt

/// The half of the notification system that touches the world.
///
/// `EngagementPlannerTests` covers what Glutt decides to say. This covers the
/// two things that decide whether it ever gets said: the frequency bookkeeping,
/// and which recipes the planner is even shown.
@MainActor
final class EngagementSchedulerTests: XCTestCase {

    private var store: UserDefaults!
    private var suiteName: String!
    private var container: ModelContainer!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUpWithError() throws {
        suiteName = "glutt.engagement.tests.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suiteName)
        container = try ModelContainer(
            for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self,
                         PantryItem.self, CookSession.self, SkillProgress.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        store = nil
        container = nil
    }

    private var context: ModelContext { container.mainContext }

    private func plan(
        kind: EngagementPlanner.Kind = .useSoon,
        fireAt: Date,
        subject: String? = "Spinach"
    ) -> EngagementPlanner.Plan {
        .init(kind: kind, title: "t", body: "b",
              destination: EngagementPlanner.Destination.kitchen,
              fireAt: fireAt, subject: subject)
    }

    // MARK: Pending is not delivered

    /// The bug this whole split exists for.
    ///
    /// The first version stored the *fire* time under the delivered key. Every
    /// foreground then removed the pending request, asked "has it been 22 hours
    /// since the last one?", got a timestamp in the **future**, decided it had
    /// been minus eight hours, and scheduled nothing. Opening the app twice in
    /// an afternoon silently destroyed that day's notification, so the more
    /// somebody used Glutt the less it ever spoke. It looked perfect in a
    /// simulator, where you launch once.
    func testASecondForegroundDoesNotMuteTheDay() {
        let fireAt = now.addingTimeInterval(8 * 3600)
        EngagementScheduler.Bookkeeping.recordPending(plan(fireAt: fireAt), store: store)

        // Foreground again, twenty minutes later. Nothing has fired yet.
        EngagementScheduler.Bookkeeping.promote(store: store, now: now.addingTimeInterval(1_200))

        let state = EngagementScheduler.snapshot(
            context: context, store: store, now: now.addingTimeInterval(1_200))
        XCTAssertNil(state.lastSentAt, "a request that has not fired is not a send")

        var probe = state
        probe.useSoonItems = ["Spinach"]
        XCTAssertNotNil(EngagementPlanner.plan(for: probe, now: now.addingTimeInterval(1_200)),
                        "the daily cap must not be spent by an unfired request")
    }

    /// And once it has fired, it does count.
    func testAFiredNotificationSpendsTheDay() {
        let fireAt = now.addingTimeInterval(-3_600)
        EngagementScheduler.Bookkeeping.recordPending(plan(fireAt: fireAt), store: store)
        EngagementScheduler.Bookkeeping.promote(store: store, now: now)

        var state = EngagementScheduler.snapshot(context: context, store: store, now: now)
        XCTAssertEqual(state.lastSentAt, fireAt)
        XCTAssertEqual(state.lastSentKind, .useSoon)
        XCTAssertEqual(state.lastSentSubject, "Spinach")

        state.useSoonItems = ["Spinach"]
        XCTAssertNil(EngagementPlanner.plan(for: state, now: now),
                     "one per day, and this one has already been shown")
    }

    /// Promotion is a one-way move: the pending slot is emptied, so the same
    /// fire time cannot be counted twice.
    func testPromotionEmptiesThePendingSlot() {
        EngagementScheduler.Bookkeeping.recordPending(
            plan(fireAt: now.addingTimeInterval(-60)), store: store)
        EngagementScheduler.Bookkeeping.promote(store: store, now: now)
        XCTAssertNil(store.object(forKey: EngagementScheduler.Bookkeeping.pendingFireAtKey))
    }

    /// Toggling reminders off and back on must not leave the cap armed.
    func testCancellingClearsTheFrequencyCapToo() {
        EngagementScheduler.Bookkeeping.recordPending(
            plan(fireAt: now.addingTimeInterval(-60)), store: store)
        EngagementScheduler.Bookkeeping.promote(store: store, now: now)
        EngagementScheduler.Bookkeeping.clearAll(store: store)

        let state = EngagementScheduler.snapshot(context: context, store: store, now: now)
        XCTAssertNil(state.lastSentAt)
        XCTAssertNil(state.lastSentSubject)
    }

    // MARK: What the planner is allowed to see

    /// `GluttApp` installs technique lessons and ~26 bundled chef and
    /// restaurant dishes into the `Recipe` table for every user on every
    /// launch. Counting those made the empty-library tier unreachable in
    /// production while its test passed on a hand-set number, and floated
    /// bundled content to the front of the saved-recipe tiers, because bundled
    /// rows leave `importedAt` nil and so sort oldest.
    func testBundledContentIsNotTheCooksLibrary() throws {
        let lesson = Recipe(title: "How to Fry an Egg")
        lesson.tags = [CookingBasics.tag]
        let chefDish = Recipe(title: "Chef's Signature Ragu")
        chefDish.tags = [ChefContent.tagPrefix + "someone"]
        let mine = Recipe(title: "Weeknight Miso Salmon")
        mine.importedAt = now.addingTimeInterval(-5 * 86_400)
        for recipe in [lesson, chefDish, mine] { context.insert(recipe) }

        let state = EngagementScheduler.snapshot(context: context, store: store, now: now)
        XCTAssertEqual(state.savedRecipeCount, 1, "only the recipe the cook saved")
        XCTAssertEqual(state.savedNotCooked.map(\.title), ["Weeknight Miso Salmon"])
    }

    /// A curated dish the cook explicitly hearted *is* theirs, matching the
    /// predicate the Recipes tab already uses.
    func testAFavouritedCuratedDishCountsAsSaved() {
        let hearted = Recipe(title: "Chef's Signature Ragu")
        hearted.tags = [ChefContent.tagPrefix + "someone"]
        hearted.isFavorite = true
        context.insert(hearted)

        let state = EngagementScheduler.snapshot(context: context, store: store, now: now)
        XCTAssertEqual(state.savedRecipeCount, 1)
    }

    /// An AI variant is a child of a recipe the cook already has. Reminding
    /// them about it as a separate save would be reminding them twice.
    func testAIVariantsAreNotSeparateSaves() {
        let parent = Recipe(title: "Weeknight Miso Salmon")
        let variant = Recipe(title: "Weeknight Miso Salmon, lighter")
        variant.parentRecipe = parent
        context.insert(parent)
        context.insert(variant)

        let state = EngagementScheduler.snapshot(context: context, store: store, now: now)
        XCTAssertEqual(state.savedRecipeCount, 1)
    }

    // MARK: Use-soon has to age out

    /// `PantryItem.isUseSoon` is `useSoonDate <= now + 3 days` and has no
    /// floor, so it stays true forever once the date passes. Since use-soon is
    /// rank one and repeats, one forgotten row would otherwise be the subject
    /// of every notification the app ever sent, blocking the five tiers below.
    func testAForgottenPantryItemStopsBeingNews() {
        let fresh = PantryItem(name: "Spinach")
        fresh.useSoonDate = now.addingTimeInterval(86_400)
        let ancient = PantryItem(name: "Mushrooms")
        ancient.useSoonDate = now.addingTimeInterval(-40 * 86_400)
        context.insert(fresh)
        context.insert(ancient)

        let state = EngagementScheduler.snapshot(context: context, store: store, now: now)
        XCTAssertEqual(state.useSoonItems, ["Spinach"])
    }

    /// A weekend of not opening the app should not lose the reminder either.
    func testYesterdaysUseSoonItemIsStillWorthSaying() {
        let item = PantryItem(name: "Chicken thighs")
        item.useSoonDate = now.addingTimeInterval(-86_400)
        context.insert(item)

        let state = EngagementScheduler.snapshot(context: context, store: store, now: now)
        XCTAssertEqual(state.useSoonItems, ["Chicken thighs"])
    }

    /// Something already used up is not a reason to open the app.
    func testAnItemMarkedOutIsNotMentioned() {
        let item = PantryItem(name: "Spinach", roughQuantity: .out)
        item.useSoonDate = now.addingTimeInterval(86_400)
        context.insert(item)

        let state = EngagementScheduler.snapshot(context: context, store: store, now: now)
        XCTAssertTrue(state.useSoonItems.isEmpty)
    }

    // MARK: The shape of what iOS gets

    /// "17:30" is a wall-clock intention about when people decide what is for
    /// dinner. An interval trigger freezes it into a number of seconds, so
    /// flying London to New York delivers the dinner reminder at half twelve.
    func testTheTriggerIsAWallClockTimeNotAnOffset() throws {
        let fireAt = Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: now)!
        let request = EngagementScheduler.request(for: plan(fireAt: fireAt), now: now)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 17)
        XCTAssertEqual(trigger.dateComponents.minute, 30)
        XCTAssertFalse(trigger.repeats)
    }

    /// Engagement and cook timers must not look like the same kind of message,
    /// because the only off switch iOS offers on the lock screen is app-wide.
    func testEngagementNotificationsAreTheirOwnThread() {
        let request = EngagementScheduler.request(
            for: plan(fireAt: now.addingTimeInterval(3_600)), now: now)
        XCTAssertEqual(request.content.threadIdentifier, "glutt.engagement")
        XCTAssertNotEqual(request.content.interruptionLevel, .timeSensitive)
    }

    /// Every plan deep links, and the tap target rides on the request itself.
    func testTheDestinationSurvivesOntoTheRequest() throws {
        let request = EngagementScheduler.request(
            for: plan(fireAt: now.addingTimeInterval(3_600)), now: now)
        let url = try XCTUnwrap(request.content.userInfo["url"] as? String)
        XCTAssertEqual(url, "glutt://kitchen")
        XCTAssertEqual(request.content.userInfo["kind"] as? String, "useSoon")
    }
}
