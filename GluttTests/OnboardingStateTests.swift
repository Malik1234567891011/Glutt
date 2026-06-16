import SwiftData
import XCTest
@testable import Glutt

final class OnboardingStateTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserPrefs.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testToggleGoalInsertsThenRemoves() {
        let state = OnboardingState()
        state.toggleGoal("Plan my week")
        XCTAssertTrue(state.selectedGoals.contains("Plan my week"))
        state.toggleGoal("Plan my week")
        XCTAssertFalse(state.selectedGoals.contains("Plan my week"))
    }

    func testSplitListTrimsAndDropsEmpties() {
        XCTAssertEqual(OnboardingState.splitList(" peanuts ,  shellfish ,,"),
                       ["peanuts", "shellfish"])
        XCTAssertEqual(OnboardingState.splitList(""), [])
    }

    @MainActor
    func testApplyWritesPrefsAndCompletesOnboarding() throws {
        let context = try makeContext()
        let state = OnboardingState()
        state.toggleGoal("Cook what I already have")
        state.allergyText = "peanuts, shellfish"
        state.dislikeText = "cilantro"
        state.nutritionMode = .gymMode

        state.apply(to: context)

        let prefs = UserPrefs.current(in: context)
        XCTAssertEqual(Set(prefs.goals), Set(["Cook what I already have"]))
        XCTAssertEqual(prefs.allergies, ["peanuts", "shellfish"])
        XCTAssertEqual(prefs.dislikedIngredients, ["cilantro"])
        XCTAssertEqual(prefs.nutritionMode, .gymMode)
        XCTAssertTrue(prefs.hasCompletedOnboarding)
    }
}
