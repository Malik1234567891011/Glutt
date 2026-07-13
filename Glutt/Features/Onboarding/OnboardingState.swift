import Foundation
import Observation
import SwiftData

/// Onboarding selections (design screens 3 + 4) → singleton `UserPrefs`.
/// Pure of SwiftUI so the logic is unit-testable.
@Observable
final class OnboardingState {

    /// Screen 3 goal rows, design order + copy verbatim.
    static let goalOptions: [String] = [
        "Eat healthier without the fuss",
        "Stop wasting food",
        "Spend less on takeout",
        "Cook with what I already have",
        "Build a real cooking habit",
        "Cook for people I love",
    ]

    /// Screen 4 rule tiles, design order.
    static let ruleOptions: [DietaryRule] = [
        .vegetarian, .vegan, .pescatarian, .glutenFree, .dairyFree,
        .nutFree, .halal, .kosher, .keto,
    ]

    var selectedGoals: Set<String> = []
    var selectedRules: Set<DietaryRule> = []

    /// Screen 3 gate: ≥1 goal required.
    var canContinueFromGoals: Bool { !selectedGoals.isEmpty }

    func toggleGoal(_ goal: String) {
        if !selectedGoals.insert(goal).inserted { selectedGoals.remove(goal) }
    }

    func toggleRule(_ rule: DietaryRule) {
        if !selectedRules.insert(rule).inserted { selectedRules.remove(rule) }
    }

    func apply(to context: ModelContext) {
        let prefs = UserPrefs.current(in: context)
        prefs.goals = Array(selectedGoals)
        prefs.dietaryRules = Array(selectedRules)
        prefs.hasCompletedOnboarding = true
    }
}
