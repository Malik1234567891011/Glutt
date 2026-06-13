import Foundation
import SwiftData

/// Singleton-style preferences record. Use `UserPrefs.current(in:)` to fetch or create.
@Model
final class UserPrefs {
    var displayName: String?
    var hasCompletedOnboarding: Bool

    /// What the user said they want from the app at onboarding.
    var goals: [String]

    var dietaryRules: [DietaryRule]
    var allergies: [String]
    var dislikedIngredients: [String]

    var nutritionMode: NutritionMode
    var dailyCalorieGoal: Int?
    var dailyProteinGoal: Int?

    /// Learned taste profile descriptors ("creamy", "spicy", "one-pan"). Grows over time, user-editable.
    var tasteProfile: [String]

    /// True once the user has opened the "save from the share sheet" walkthrough.
    /// Powers the getting-started checklist; inline default keeps migration lightweight.
    var hasSeenShareGuide: Bool = false
    /// User manually dismissed the getting-started checklist — never show it again.
    var didDismissGettingStarted: Bool = false

    init() {
        self.hasCompletedOnboarding = false
        self.goals = []
        self.dietaryRules = []
        self.allergies = []
        self.dislikedIngredients = []
        self.nutritionMode = .cookingOnly
        self.tasteProfile = []
    }

    static func current(in context: ModelContext) -> UserPrefs {
        let descriptor = FetchDescriptor<UserPrefs>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let prefs = UserPrefs()
        context.insert(prefs)
        return prefs
    }
}
