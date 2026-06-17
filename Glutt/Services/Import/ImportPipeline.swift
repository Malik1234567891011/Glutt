import Foundation

/// One orchestration of the link-import flow, shared by the in-app importer and
/// the share extension: fetch the page, then run the AI passes that improve it.
/// `progress` reports the user-facing status line for each phase.
enum ImportPipeline {

    /// Seams so the orchestration can be unit-tested without network/LLM calls.
    struct Dependencies {
        var fetch: (String) async throws -> ImportedRecipeDraft
        var wouldImprove: (ImportedRecipeDraft) -> Bool
        var cleanUp: (ImportedRecipeDraft) async -> ImportedRecipeDraft
        var reconstruct: (ImportedRecipeDraft) async -> ImportedRecipeDraft
        var inferSteps: (ImportedRecipeDraft) async -> ImportedRecipeDraft

        static let live = Dependencies(
            fetch: { try await RecipeImportService.importFrom(urlString: $0) },
            wouldImprove: DraftCleanup.wouldImprove,
            cleanUp: DraftCleanup.cleanUp,
            reconstruct: DraftCleanup.reconstruct,
            inferSteps: DraftCleanup.inferSteps
        )
    }

    static func run(
        urlString: String,
        deps: Dependencies = .live,
        progress: @MainActor @escaping (String) -> Void
    ) async throws -> ImportedRecipeDraft {
        await progress("Reading the recipe…")
        var draft = try await deps.fetch(urlString)

        if deps.wouldImprove(draft) {
            await progress("Cleaning it up with AI…")
            draft = await deps.cleanUp(draft)
        }
        if draft.ingredientLines.isEmpty, draft.isSocialVideo {
            await progress("No recipe in the caption — drafting the dish…")
            draft = await deps.reconstruct(draft)
        }
        if draft.stepTexts.isEmpty, !draft.ingredientLines.isEmpty {
            await progress("No method listed — drafting the steps…")
            draft = await deps.inferSteps(draft)
        }
        return draft
    }
}
