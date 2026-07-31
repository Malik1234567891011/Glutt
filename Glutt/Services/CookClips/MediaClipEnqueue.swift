import Foundation
import SwiftData

/// Fire-and-forget clip pipeline after a recipe is saved (same shape as RecipeImageBackfill).
/// Import UI is never blocked; Recipe detail / Polly poll status while cooking stays available.
enum MediaClipEnqueue {

    /// YouTube / TikTok recipes with a resolvable media id.
    static func shouldEnqueue(_ recipe: Recipe) -> Bool {
        switch recipe.sourcePlatform {
        case .youtube, .tiktok: break
        default: return false
        }
        guard let url = recipe.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty,
              MediaSourceID.from(sourceURL: url) != nil else { return false }
        if recipe.mediaStatus == "ready" { return false }
        return true
    }

    @MainActor
    static func ensure(for recipe: Recipe, in context: ModelContext) async {
        guard shouldEnqueue(recipe),
              let sourceURL = recipe.sourceURL,
              let externalID = MediaSourceID.from(sourceURL: sourceURL) else { return }

        recipe.mediaExternalID = externalID
        if recipe.mediaStatus == nil || recipe.mediaStatus == "failed" {
            recipe.mediaStatus = "queued"
            recipe.mediaProgress = 0.05
            recipe.mediaStatusDetail = "Preparing technique clips…"
            try? context.save()
        }

        do {
            let enq = try await MediaIngestClient.shared.enqueue(
                sourceURL: sourceURL,
                title: recipe.title,
                creator: recipe.sourceCreator
            )
            recipe.mediaExternalID = enq.externalID
            recipe.mediaSourceAssetID = enq.sourceAssetID
            recipe.mediaJobID = enq.jobID
            recipe.mediaStatus = enq.mediaStatus == "ready" ? "ready" : "queued"
            recipe.mediaProgress = enq.progress
            recipe.mediaStatusDetail = enq.detail
            try? context.save()
        } catch {
            recipe.mediaStatusDetail = "Clip queue unavailable — cooking still works"
            try? context.save()
            return
        }

        // Gemini index in background (YouTube). TikTok waits for media-worker.
        let steps: [(id: String, title: String, instruction: String)] = recipe.sortedSteps.enumerated().map { idx, step in
            ("step-\(idx)", "Step \(idx + 1)", step.text)
        }
        do {
            let analyzed = try await MediaIngestClient.shared.analyze(
                sourceURL: sourceURL,
                externalID: externalID,
                recipeTitle: recipe.title,
                steps: steps
            )
            recipe.mediaStatus = analyzed.mediaStatus
            recipe.mediaProgress = analyzed.progress
            recipe.mediaStatusDetail = analyzed.detail
            if let id = analyzed.sourceAssetID { recipe.mediaSourceAssetID = id }
            try? context.save()
        } catch {
            // Enqueue succeeded; analyze can retry on next detail open.
            recipe.mediaStatusDetail = "Queued — indexing will continue"
            try? context.save()
        }
    }

    /// Poll server and refresh Recipe fields. Safe to call from detail `.task`.
    @MainActor
    static func refreshStatus(for recipe: Recipe, in context: ModelContext) async {
        let external = recipe.mediaExternalID
            ?? recipe.sourceURL.flatMap { MediaSourceID.from(sourceURL: $0) }
        guard let external else { return }
        do {
            let status = try await MediaIngestClient.shared.status(externalID: external)
            guard status.found else { return }
            recipe.mediaExternalID = status.externalID
            recipe.mediaSourceAssetID = status.sourceAssetID ?? recipe.mediaSourceAssetID
            recipe.mediaJobID = status.jobID ?? recipe.mediaJobID
            recipe.mediaStatus = status.mediaStatus
            recipe.mediaProgress = status.progress
            recipe.mediaStatusDetail = status.detail
            try? context.save()
        } catch {
            // Soft fail — keep last known status.
        }
    }
}
