import Foundation
import SwiftData

/// A record of a recipe being cooked: servings made, rating, and quick feedback.
/// This is the app's cook history — powers RecipeDetailView's "Cooked before"
/// section and taste profiling. (Intake/leftover tracking was removed.)
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
