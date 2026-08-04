import Foundation
import SwiftData

/// Drains finished imports from the inbox into the model context and returns
/// a draft-id → recipe-id map for "View recipe" deep-link navigation.
/// Saves before capturing identifiers so each recipe has its PERMANENT
/// `persistentModelID` (a newly-inserted, unsaved model has a temporary id
/// that SwiftData remaps on autosave — capturing it pre-save makes the later
/// `@Query` match fail intermittently).
enum ImportInboxDrainer {
    @MainActor
    static func drain(_ inbox: ImportInbox = ImportInbox(), into context: ModelContext) -> [UUID: PersistentIdentifier] {
        let drafts = inbox.drain()
        guard !drafts.isEmpty else { return [:] }
        var inserted: [(UUID, Recipe)] = []
        for draft in drafts {
            let recipe = RecipeFactory.make(from: draft)
            context.insert(recipe)
            inserted.append((draft.id, recipe))
        }
        try? context.save()   // make persistentModelIDs permanent before correlating
        // Imports that came from the share sheet. The extension cannot report
        // them itself — no PostHog SDK there, and it is dead before the recipe
        // exists — so the app reports them when it drains the inbox.
        for _ in inserted {
            Analytics.capture(.recipeCreated, ["source": "import_share"])
        }
        for (_, recipe) in inserted {
            Task {
                // Eagerly, not on the next foreground sweep. Social platforms
                // hand out signed image URLs that expire — Instagram's carry an
                // `oe=` stamp days out — so a shared import that waits for a
                // sweep can find its own cover image already dead. In-app import
                // has always done this; the share sheet was the gap.
                await RecipeImageBackfill.ensure(for: recipe, in: context)
                await MediaClipEnqueue.ensure(for: recipe, in: context)
            }
        }
        var map: [UUID: PersistentIdentifier] = [:]
        for (id, recipe) in inserted {
            map[id] = recipe.persistentModelID
        }
        return map
    }
}
