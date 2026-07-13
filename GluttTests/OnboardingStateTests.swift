import SwiftData
import XCTest
@testable import Glutt

final class DietaryRuleTests: XCTestCase {
    func testNewCasesExistWithLabels() {
        XCTAssertEqual(DietaryRule.nutFree.label, "Nut-free")
        XCTAssertEqual(DietaryRule.keto.label, "Keto")
        XCTAssertEqual(DietaryRule.nutFree.rawValue, "nutFree")
        XCTAssertEqual(DietaryRule.keto.rawValue, "keto")
    }
}

final class OnboardingStateTests: XCTestCase {
    func testGoalOptionsAreTheSixDesignLabels() {
        XCTAssertEqual(OnboardingState.goalOptions, [
            "Eat healthier without the fuss",
            "Stop wasting food",
            "Spend less on takeout",
            "Cook with what I already have",
            "Build a real cooking habit",
            "Cook for people I love",
        ])
    }

    func testRuleOptionsAreTheNineTilesInDesignOrder() {
        XCTAssertEqual(OnboardingState.ruleOptions, [
            .vegetarian, .vegan, .pescatarian, .glutenFree, .dairyFree,
            .nutFree, .halal, .kosher, .keto,
        ])
    }

    func testGoalsGate() {
        let state = OnboardingState()
        XCTAssertFalse(state.canContinueFromGoals)
        state.toggleGoal("Stop wasting food")
        XCTAssertTrue(state.canContinueFromGoals)
        state.toggleGoal("Stop wasting food")
        XCTAssertFalse(state.canContinueFromGoals, "toggle off empties the gate")
    }

    func testApplyWritesGoalsRulesAndFlagOnly() throws {
        let container = try ModelContainer(
            for: UserPrefs.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let state = OnboardingState()
        state.toggleGoal("Cook for people I love")
        state.toggleRule(.keto)
        state.toggleRule(.nutFree)
        state.apply(to: context)

        let prefs = UserPrefs.current(in: context)
        XCTAssertEqual(Set(prefs.goals), ["Cook for people I love"])
        XCTAssertEqual(Set(prefs.dietaryRules), [.keto, .nutFree])
        XCTAssertTrue(prefs.hasCompletedOnboarding)
        XCTAssertEqual(prefs.nutritionMode, .cookingOnly, "untouched default")
        XCTAssertTrue(prefs.allergies.isEmpty, "no longer captured at onboarding")
    }
}
