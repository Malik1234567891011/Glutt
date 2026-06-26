import Foundation

/// Builds an `ImportedRecipeDraft` directly from a structured `PlateCard`,
/// skipping scraping and the macro-lossy AI cleanup path. Macros + the trusted
/// flag are written straight onto the draft so they survive to the saved Recipe.
enum PlateCardMapper {
    static func draft(from card: PlateCard) -> ImportedRecipeDraft {
        var draft = ImportedRecipeDraft()
        draft.title = card.title
        draft.summary = card.summary
        draft.imageURL = card.imageURL
        draft.creator = card.creator
        draft.sourceURL = card.sourceURL
        draft.platform = .website
        draft.servings = card.servings
        draft.prepMinutes = card.prepMinutes
        draft.cookMinutes = card.cookMinutes
        draft.ingredientLines = card.ingredients.map(\.raw).filter { !$0.isEmpty }
        draft.stepTexts = card.steps
        draft.tags = card.tags
        draft.calories = card.macros?.caloriesInt
        draft.proteinGrams = card.macros?.proteinInt
        draft.carbGrams = card.macros?.carbsInt
        draft.fatGrams = card.macros?.fatInt
        draft.nutritionIsEstimated = card.macros?.estimated ?? true
        return draft
    }
}
