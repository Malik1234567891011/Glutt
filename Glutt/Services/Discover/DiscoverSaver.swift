import Foundation
import SwiftData

/// Turns a discovered YouTube clip into a saved `Recipe`, reusing the
/// existing import pipeline. Dedups by `sourceURL` so re-saving is a no-op.
enum DiscoverSaver {
    static func existingRecipe(forSourceURL sourceURL: String, in context: ModelContext) -> Recipe? {
        var descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.sourceURL == sourceURL })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func liveImport(_ urlString: String) async throws -> ImportedRecipeDraft {
        try await ImportPipeline.run(urlString: urlString) { _ in }
    }

    @MainActor
    static func save(
        video: DiscoverVideo,
        importDraft: (String) async throws -> ImportedRecipeDraft = DiscoverSaver.liveImport,
        into context: ModelContext
    ) async throws -> Recipe {
        let sourceURL = video.watchURL.absoluteString
        if let existing = existingRecipe(forSourceURL: sourceURL, in: context) {
            return existing
        }
        var draft = try await importDraft(sourceURL)
        // Guarantee provenance even if the pipeline couldn't read the page.
        draft.sourceURL = sourceURL
        draft.platform = .youtube
        if draft.title == nil || draft.title?.isEmpty == true { draft.title = video.title }
        if draft.imageURL == nil { draft.imageURL = video.thumbnailURL }
        if draft.creator == nil { draft.creator = video.creator }

        let recipe = RecipeFactory.make(from: draft)
        context.insert(recipe)
        try context.save()
        return recipe
    }
}
