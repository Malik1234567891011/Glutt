import XCTest
@testable import Glutt

/// The notification ladder.
///
/// Every test here is a product decision written down. The most important one
/// is `testSilenceWhenThereIsNothingToSay`: this system is allowed to say
/// nothing, and a change that makes it chatty should fail a test rather than
/// ship.
final class EngagementPlannerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func recipe(
        _ title: String = "Creamy Lemon Chicken Rice Bowl",
        savedDaysAgo: Double = 5,
        minutes: Int? = 45,
        ingredients: Int = 8
    ) -> EngagementPlanner.SavedRecipe {
        EngagementPlanner.SavedRecipe(
            id: UUID(),
            title: title,
            savedAt: now.addingTimeInterval(-savedDaysAgo * 86_400),
            totalMinutes: minutes,
            ingredientCount: ingredients)
    }

    private var skill: EngagementPlanner.NextSkill {
        .init(id: "knife.claw", title: "Claw Grip")
    }

    // MARK: Priority order

    /// 1 beats everything. Food that will be thrown away is the only tier where
    /// doing nothing has a cost.
    func testUseSoonOutranksEverythingElse() throws {
        var state = EngagementPlanner.State()
        state.useSoonItems = ["Spinach"]
        state.savedNotCooked = [recipe()]
        state.cookableNow = [recipe()]
        state.savedRecipeCount = 12
        state.skillStreak = 9
        state.streakNeedsToday = true
        state.nextSkill = skill

        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertEqual(plan.kind, .useSoon)
        XCTAssertTrue(plan.title.contains("Spinach"), "should name the actual item: \(plan.title)")
        XCTAssertEqual(plan.destination, EngagementPlanner.Destination.kitchen)
    }

    /// 2 beats the Skills tiers: they already chose this recipe.
    func testASavedRecipeOutranksSkillSignals() throws {
        var state = EngagementPlanner.State()
        state.savedNotCooked = [recipe("Butter Chicken")]
        state.savedRecipeCount = 4
        state.hasStartedSkills = true
        state.lastSkillLearnedAt = now.addingTimeInterval(-20 * 86_400)
        state.skillStreak = 6
        state.streakNeedsToday = true
        state.nextSkill = skill

        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertEqual(plan.kind, .savedRecipe)
        XCTAssertTrue(plan.body.contains("Butter Chicken"))
    }

    func testCookableNowWinsWhenNothingAboveApplies() throws {
        var state = EngagementPlanner.State()
        state.cookableNow = [recipe("Creamy Lemon Chicken Rice Bowl")]
        state.savedRecipeCount = 6

        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertEqual(plan.kind, .cookableNow)
        XCTAssertTrue(plan.body.contains("Creamy Lemon Chicken Rice Bowl"))
    }

    func testAGenuineStreakAtRisk() throws {
        var state = EngagementPlanner.State()
        state.savedRecipeCount = 8
        state.skillStreak = 6
        state.streakNeedsToday = true
        state.nextSkill = skill

        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertEqual(plan.kind, .streakAtRisk)
        XCTAssertTrue(plan.title.contains("6"))
        XCTAssertEqual(plan.destination.absoluteString, "glutt://skill?id=knife.claw")
    }

    func testSkillInactivityAfterTheThreshold() throws {
        var state = EngagementPlanner.State()
        state.savedRecipeCount = 8
        state.hasStartedSkills = true
        state.lastSkillLearnedAt = now.addingTimeInterval(-6 * 86_400)
        state.nextSkill = skill

        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertEqual(plan.kind, .skillInactive)
    }

    func testEmptyLibraryIsTheFallback() throws {
        var state = EngagementPlanner.State()
        state.savedRecipeCount = 1

        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertEqual(plan.kind, .emptyLibrary)
        XCTAssertEqual(plan.destination, EngagementPlanner.Destination.saveHelp)
    }

    /// The one that matters most.
    func testSilenceWhenThereIsNothingToSay() {
        var state = EngagementPlanner.State()
        state.savedRecipeCount = 20      // library is healthy
        state.hasStartedSkills = false   // never touched Skills
        XCTAssertNil(EngagementPlanner.plan(for: state, now: now))
    }

    // MARK: Not manufacturing urgency

    /// Two days is a coincidence. Telling somebody on day one that they have a
    /// streak to protect is exactly the manipulation this ladder avoids.
    func testAShortStreakIsNotAStreak() {
        var state = EngagementPlanner.State()
        state.savedRecipeCount = 20
        state.skillStreak = 2
        state.streakNeedsToday = true
        state.nextSkill = skill
        XCTAssertNil(EngagementPlanner.plan(for: state, now: now))
    }

    /// Somebody who saved a recipe last night has not ignored it yet.
    func testARecipeSavedYesterdayIsLeftAlone() {
        var state = EngagementPlanner.State()
        state.savedRecipeCount = 20
        state.savedNotCooked = [recipe(savedDaysAgo: 1)]
        XCTAssertNil(EngagementPlanner.plan(for: state, now: now))
    }

    /// And one saved months ago is not "still thinking about it".
    func testAVeryOldSaveIsNotResurfaced() {
        var state = EngagementPlanner.State()
        state.savedRecipeCount = 20
        state.savedNotCooked = [recipe(savedDaysAgo: 60)]
        XCTAssertNil(EngagementPlanner.plan(for: state, now: now))
    }

    /// Never invent a duration.
    func testNoCookingTimeIsClaimedWhenTheRecipeHasNone() throws {
        var state = EngagementPlanner.State()
        state.savedNotCooked = [recipe("Shakshuka", minutes: nil)]
        state.savedRecipeCount = 5

        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertTrue(plan.body.contains("Shakshuka"))
        XCTAssertFalse(plan.body.contains("min"), "invented a cooking time: \(plan.body)")
    }

    // MARK: Frequency

    func testOnlyOneEngagementNotificationPerDay() {
        var state = EngagementPlanner.State()
        state.useSoonItems = ["Spinach"]
        state.lastSentAt = now.addingTimeInterval(-3 * 3600)
        XCTAssertNil(EngagementPlanner.plan(for: state, now: now),
                     "a second notification inside the window must not be scheduled")
    }

    func testTheWindowReopensAfterADay() throws {
        var state = EngagementPlanner.State()
        state.useSoonItems = ["Spinach"]
        state.lastSentAt = now.addingTimeInterval(-25 * 3600)
        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertEqual(plan.kind, .useSoon)
    }

    /// The weakest tier is a fallback, not a drip.
    func testTheEmptyLibraryNudgeIsNotADailyHabit() {
        var state = EngagementPlanner.State()
        state.savedRecipeCount = 0
        state.lastSentAt = now.addingTimeInterval(-2 * 86_400)
        state.lastSentKind = .emptyLibrary
        XCTAssertNil(EngagementPlanner.plan(for: state, now: now))

        state.lastSentAt = now.addingTimeInterval(-8 * 86_400)
        XCTAssertNotNil(EngagementPlanner.plan(for: state, now: now))
    }

    /// A real kitchen fact may repeat, but never about the same thing two days
    /// running. One forgotten bag of spinach outranking everything else, every
    /// day, forever, is the single most likely reason somebody turns Glutt's
    /// notifications off, and the tier above it has no cooldown to stop it.
    func testTheSameItemIsNotTheSubjectTwoDaysRunning() {
        var state = EngagementPlanner.State()
        state.useSoonItems = ["Spinach"]
        state.savedRecipeCount = 9
        state.lastSentAt = now.addingTimeInterval(-25 * 3600)
        state.lastSentKind = .useSoon
        state.lastSentSubject = "Spinach"
        XCTAssertNil(EngagementPlanner.plan(for: state, now: now))
    }

    /// A *different* item is a different fact, and may follow immediately.
    func testADifferentUseSoonItemMayFollowTheNextDay() throws {
        var state = EngagementPlanner.State()
        state.useSoonItems = ["Spinach", "Chicken thighs"]
        state.lastSentAt = now.addingTimeInterval(-25 * 3600)
        state.lastSentKind = .useSoon
        state.lastSentSubject = "Spinach"
        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertEqual(plan.subject, "Chicken thighs")
    }

    // MARK: Claims the app has to be able to keep

    /// `PantryMatcher.hasEverything` is `missing.isEmpty`, which is vacuously
    /// true for an import that parsed no ingredients. Announcing that the
    /// kitchen covers a recipe made of nothing is a confident lie.
    func testARecipeThatParsedNoIngredientsIsNeverCallable() {
        var state = EngagementPlanner.State()
        state.cookableNow = [recipe(ingredients: 0)]
        state.savedRecipeCount = 9
        XCTAssertNil(EngagementPlanner.plan(for: state, now: now))
    }

    /// A streak number is true for a matter of hours. Planning one for tomorrow
    /// evening means announcing a streak that tonight's midnight already ended.
    func testAStreakIsNeverPromisedForTomorrow() {
        var state = EngagementPlanner.State()
        state.savedRecipeCount = 9
        state.skillStreak = 6
        state.streakNeedsToday = true
        state.nextSkill = skill
        // 20:00, so the 19:00 slot has gone.
        let calendar = Calendar.current
        let tonight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        let plan = EngagementPlanner.plan(for: state, now: tonight)
        XCTAssertNotEqual(plan?.kind, .streakAtRisk)
    }

    /// The repo forbids dashes as punctuation in UI copy, and "6-day streak" is
    /// a hyphenated compound, which is the permitted case.
    func testTheStreakCountReadsAsACompound() throws {
        var state = EngagementPlanner.State()
        state.savedRecipeCount = 9
        state.skillStreak = 6
        state.streakNeedsToday = true
        state.nextSkill = skill
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: morning))
        XCTAssertEqual(plan.title, "Keep your 6-day streak")
    }

    // MARK: Copy hygiene on data Glutt did not write

    /// Recipe titles are scraped off the open web and pantry names are typed by
    /// hand. Both land on the lock screen with the same weight as copy that was
    /// reviewed, so both get cleaned.
    func testScrapedTitlesAreNotPastedOntoTheLockScreen() {
        let clean = EngagementPlanner.Copy.clean
        XCTAssertEqual(
            clean("Creamy Garlic Tuscan Chicken (Easy 30 Minute Weeknight Dinner!)", 34),
            "Creamy Garlic Tuscan Chicken")
        // A dash used as punctuation starts the pitch, and the repo bans it.
        XCTAssertEqual(clean("Miso Salmon - the best you'll ever eat", 34), "Miso Salmon")
        XCTAssertEqual(clean("🔥 Spicy Rigatoni 🔥", 34), "Spicy Rigatoni")
        // Hyphenated compounds are explicitly allowed and must survive.
        XCTAssertEqual(clean("Sun-Dried Tomato Pasta", 34), "Sun-Dried Tomato Pasta")
    }

    /// The previous version lowercased the first letter of any name with no
    /// other capital in it, which is exactly the shape of a two word proper
    /// noun. "Greek yogurt" became "greek yogurt". Names now lead the sentence
    /// instead, so their own capitalisation is always right.
    func testAProperNounKeepsItsCapital() throws {
        var state = EngagementPlanner.State()
        state.useSoonItems = ["Greek yogurt"]
        state.savedRecipeCount = 9
        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertTrue(plan.title.hasPrefix("Greek yogurt"), plan.title)
    }

    /// Somebody typing "MILK" into their pantry should not be shouted at.
    func testAnAllCapsPantryNameIsCalmedDown() throws {
        var state = EngagementPlanner.State()
        state.useSoonItems = ["MILK"]
        state.savedRecipeCount = 9
        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertTrue(plan.title.hasPrefix("Milk"), plan.title)
    }

    /// The code takes care not to invent a duration. It should take equal care
    /// not to print an absurd one it was given.
    func testAnImplausibleDurationIsDroppedRatherThanPrinted() throws {
        var state = EngagementPlanner.State()
        state.savedNotCooked = [recipe(minutes: 730)]
        state.savedRecipeCount = 9
        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertFalse(plan.body.contains("730"), plan.body)
        XCTAssertFalse(plan.body.contains("min"), plan.body)
    }

    /// Every string that reaches the lock screen, including the interpolated
    /// halves the copy audit above never inspected.
    func testInterpolatedTitlesCannotOverflowTheLockScreen() throws {
        let monster = "Creamy Garlic Tuscan Chicken with Sun-Dried Tomatoes and Spinach in a Rich Parmesan Cream Sauce"
        var state = EngagementPlanner.State()
        state.useSoonItems = [monster]
        state.savedNotCooked = [recipe(monster)]
        state.cookableNow = [recipe(monster)]
        state.savedRecipeCount = 9

        for _ in 0..<3 {
            let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
            XCTAssertLessThan(plan.title.count, 42, plan.title)
            XCTAssertLessThan(plan.body.count, 90, plan.body)
            switch plan.kind {
            case .useSoon: state.useSoonItems = []
            case .savedRecipe: state.savedNotCooked = []
            default: state.cookableNow = []
            }
        }
    }

    // MARK: Timing and links

    func testFoodRemindersLandLateAfternoonNotAtSeven() throws {
        var state = EngagementPlanner.State()
        state.useSoonItems = ["Spinach"]
        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))

        let parts = Calendar.current.dateComponents([.hour, .minute], from: plan.fireAt)
        XCTAssertEqual(parts.hour, 17)
        XCTAssertEqual(parts.minute, 30)
    }

    func testSkillRemindersLandInTheEvening() throws {
        var state = EngagementPlanner.State()
        state.savedRecipeCount = 20
        state.skillStreak = 5
        state.streakNeedsToday = true
        state.nextSkill = skill

        let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
        XCTAssertEqual(Calendar.current.component(.hour, from: plan.fireAt), 19)
    }

    func testTheFireTimeIsAlwaysInTheFuture() {
        for hour in 0...23 {
            let at = Calendar.current.date(bySettingHour: hour, minute: 31, second: 0, of: now)!
            XCTAssertGreaterThan(EngagementPlanner.nextFoodHour(after: at), at,
                                 "scheduled in the past when planned at \(hour):31")
        }
    }

    /// Every plan goes somewhere specific. None of them opens "the app".
    func testEveryPlanDeepLinksSomewhereSpecific() throws {
        var states: [EngagementPlanner.State] = []
        var useSoon = EngagementPlanner.State(); useSoon.useSoonItems = ["Spinach"]
        var saved = EngagementPlanner.State(); saved.savedNotCooked = [recipe()]; saved.savedRecipeCount = 9
        var cookable = EngagementPlanner.State(); cookable.cookableNow = [recipe()]; cookable.savedRecipeCount = 9
        var streak = EngagementPlanner.State()
        streak.savedRecipeCount = 9; streak.skillStreak = 5
        streak.streakNeedsToday = true; streak.nextSkill = skill
        var empty = EngagementPlanner.State(); empty.savedRecipeCount = 0
        states = [useSoon, saved, cookable, streak, empty]

        for state in states {
            let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now))
            XCTAssertEqual(plan.destination.scheme, "glutt")
            XCTAssertFalse(plan.destination.host?.isEmpty ?? true)
        }
    }

    /// Copy audit, applied to every tier the ladder can produce.
    func testCopyNeverBegsAndNeverShouts() throws {
        let banned = ["miss you", "come back", "don't lose", "!!", "🔥", "👀", "Unlock"]
        var everyState = EngagementPlanner.State()
        everyState.useSoonItems = ["Spinach"]
        everyState.savedNotCooked = [recipe()]
        everyState.cookableNow = [recipe()]
        everyState.skillStreak = 5
        everyState.streakNeedsToday = true
        everyState.nextSkill = skill

        for kind in EngagementPlanner.Kind.allCases {
            var state = everyState
            // Walk down the ladder by removing what is above each tier.
            switch kind {
            case .useSoon: break
            case .savedRecipe: state.useSoonItems = []
            case .cookableNow: state.useSoonItems = []; state.savedNotCooked = []
            case .streakAtRisk:
                state.useSoonItems = []; state.savedNotCooked = []; state.cookableNow = []
            case .skillInactive:
                state.useSoonItems = []; state.savedNotCooked = []; state.cookableNow = []
                state.skillStreak = 0; state.streakNeedsToday = false
                state.hasStartedSkills = true
                state.lastSkillLearnedAt = now.addingTimeInterval(-7 * 86_400)
            case .emptyLibrary:
                state = EngagementPlanner.State()
                state.savedRecipeCount = 0
            }
            if kind != .emptyLibrary { state.savedRecipeCount = 9 }

            let plan = try XCTUnwrap(EngagementPlanner.plan(for: state, now: now),
                                     "\(kind) produced nothing")
            XCTAssertEqual(plan.kind, kind)
            for phrase in banned {
                XCTAssertFalse(plan.title.contains(phrase), "\(kind) title: \(plan.title)")
                XCTAssertFalse(plan.body.contains(phrase), "\(kind) body: \(plan.body)")
            }
            XCTAssertLessThan(plan.title.count, 42, "title will truncate: \(plan.title)")
            XCTAssertFalse(plan.title.isEmpty)
            XCTAssertFalse(plan.body.isEmpty)
        }
    }
}
