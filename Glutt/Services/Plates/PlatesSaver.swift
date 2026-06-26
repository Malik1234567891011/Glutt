import Foundation
import SwiftData

/// Saves a `PlateCard` into the library. Dedups by `sourceURL`, builds a Recipe
/// through the shared `RecipeFactory` chokepoint, and — unlike DiscoverSaver —
/// eagerly backfills the hero image so My Recipes shows it instantly/offline.
enum PlatesSaver {
    @MainActor
    static func save(
        card: PlateCard,
        into context: ModelContext,
        fetch: RecipeImageBackfill.Fetch = RecipeImageBackfill.defaultFetch
    ) async throws -> Recipe {
        if let sourceURL = card.sourceURL,
           let existing = DiscoverSaver.existingRecipe(forSourceURL: sourceURL, in: context) {
            return existing
        }
        let draft = PlateCardMapper.draft(from: card)
        let recipe = RecipeFactory.make(from: draft)
        context.insert(recipe)
        try context.save()
        await RecipeImageBackfill.ensure(for: recipe, in: context, fetch: fetch)
        return recipe
    }
}
