import Foundation
import SwiftData

@Model
final class PlannedMeal {
    /// The day this meal belongs to (start of day).
    var date: Date
    var mealType: MealType
    /// Optional exact time ("dinner at 7:30"). Drives cooking-start reminders.
    var exactTime: Date?
    var status: MealStatus

    var recipe: Recipe?
    var leftover: Leftover?
    /// For non-recipe meals: "eating out", "leftover pizza", etc.
    var freeformTitle: String?

    var createdAt: Date

    var displayTitle: String {
        recipe?.title ?? leftover?.title ?? freeformTitle ?? "Meal"
    }

    /// When the user should start cooking, based on the recipe's total time plus a buffer.
    var suggestedStartTime: Date? {
        guard let exactTime, let recipe else { return nil }
        let bufferMinutes = 10
        return Calendar.current.date(
            byAdding: .minute,
            value: -(recipe.totalMinutes + bufferMinutes),
            to: exactTime
        )
    }

    init(
        date: Date,
        mealType: MealType,
        exactTime: Date? = nil,
        status: MealStatus = .planned,
        recipe: Recipe? = nil,
        leftover: Leftover? = nil,
        freeformTitle: String? = nil
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.mealType = mealType
        self.exactTime = exactTime
        self.status = status
        self.recipe = recipe
        self.leftover = leftover
        self.freeformTitle = freeformTitle
        self.createdAt = .now
    }
}

@Model
final class FoodLog {
    var timestamp: Date
    var title: String
    var source: FoodLogSource

    // Estimates use a range — no fake precision.
    var calories: Int?
    var caloriesLow: Int?
    var caloriesHigh: Int?
    var proteinGrams: Int?
    var carbGrams: Int?
    var fatGrams: Int?
    /// 0.0–1.0 confidence of the estimate (nil when user entered values manually).
    var estimateConfidence: Double?

    @Attribute(.externalStorage) var photoData: Data?
    var notes: String?

    var plannedMeal: PlannedMeal?
    var leftover: Leftover?

    init(
        timestamp: Date = .now,
        title: String,
        source: FoodLogSource,
        calories: Int? = nil,
        proteinGrams: Int? = nil,
        plannedMeal: PlannedMeal? = nil,
        leftover: Leftover? = nil
    ) {
        self.timestamp = timestamp
        self.title = title
        self.source = source
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.plannedMeal = plannedMeal
        self.leftover = leftover
    }
}

@Model
final class CookSession {
    var date: Date
    var servingsMade: Int
    var servingsEaten: Double
    var rating: Int?
    var notes: String?
    var worthTheEffort: Bool?
    var wouldMakeAgain: Bool?

    var recipe: Recipe?

    init(
        date: Date = .now,
        servingsMade: Int,
        servingsEaten: Double = 0,
        recipe: Recipe? = nil
    ) {
        self.date = date
        self.servingsMade = servingsMade
        self.servingsEaten = servingsEaten
        self.recipe = recipe
    }
}
