import Foundation
import Observation
import SwiftData

/// Holds onboarding selections and maps them onto the singleton `UserPrefs`.
/// Pure of SwiftUI so the flow's logic is unit-testable.
@Observable
final class OnboardingState {

    struct GoalOption: Identifiable {
        var id: String { label }
        let emoji: String
        let label: String
    }

    /// Glutt's own goals (not ReciMe's) — these set up the home screen.
    static let goalOptions: [GoalOption] = [
        .init(emoji: "📲", label: "Save recipes from TikTok & friends"),
        .init(emoji: "🧊", label: "Cook what I already have"),
        .init(emoji: "🗓️", label: "Plan my week"),
        .init(emoji: "♻️", label: "Waste less food"),
        .init(emoji: "💪", label: "Hit my macros"),
        .init(emoji: "🏠", label: "Eat out less"),
    ]

    var selectedGoals: Set<String> = []
    var selectedRules: Set<DietaryRule> = []
    var allergyText: String = ""
    var dislikeText: String = ""
    var nutritionMode: NutritionMode = .cookingOnly

    func toggleGoal(_ goal: String) {
        if !selectedGoals.insert(goal).inserted {
            selectedGoals.remove(goal)
        }
    }

    func toggleRule(_ rule: DietaryRule) {
        if selectedRules.contains(rule) {
            selectedRules.remove(rule)
        } else {
            selectedRules.insert(rule)
        }
    }

    func apply(to context: ModelContext) {
        let prefs = UserPrefs.current(in: context)
        prefs.goals = Array(selectedGoals)
        prefs.dietaryRules = Array(selectedRules)
        prefs.allergies = Self.splitList(allergyText)
        prefs.dislikedIngredients = Self.splitList(dislikeText)
        prefs.nutritionMode = nutritionMode
        prefs.hasCompletedOnboarding = true
    }

    static func splitList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
