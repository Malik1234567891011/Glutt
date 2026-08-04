import Foundation
import SwiftData

/// Fire-and-forget clip pipeline after a recipe is saved (same shape as RecipeImageBackfill).
/// Import UI is never blocked; Recipe detail / Polly poll status while cooking stays available.
enum MediaClipEnqueue {

    /// Analyze is a long Gemini call against a 60s function ceiling, so timeouts
    /// are routine. Retries are driven by the detail-view poll; this throttles
    /// them to something the proxy can absorb.
    private static let analyzeRetryCooldown: TimeInterval = 120
    private static var lastAnalyzeAttempt: [String: Date] = [:]

    /// YouTube / TikTok recipes with a resolvable media id, when clip generation
    /// is switched on at all.
    static func shouldEnqueue(_ recipe: Recipe) -> Bool {
        guard MediaClipConfig.generatesClipsForImports else { return false }
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

        await runAnalyze(for: recipe, sourceURL: sourceURL, externalID: externalID, in: context)
    }

    /// Gemini index in background (YouTube). TikTok waits for media-worker.
    @MainActor
    private static func runAnalyze(
        for recipe: Recipe,
        sourceURL: String,
        externalID: String,
        in context: ModelContext
    ) async {
        lastAnalyzeAttempt[externalID] = .now
        let steps: [(id: String, title: String, instruction: String)] = recipe.sortedSteps
            .enumerated()
            .map { idx, step in ("step-\(idx)", "Step \(idx + 1)", step.text) }
        guard !steps.isEmpty else { return }
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
            recipe.mediaStatusDetail = "Queued — indexing will continue"
            try? context.save()
        }
    }

    /// Poll server and refresh Recipe fields. Safe to call from detail `.task`.
    ///
    /// Also re-drives the pipeline: an import whose enqueue or analyze failed
    /// would otherwise sit at "queued" forever, because nothing else retries.
    @MainActor
    static func refreshStatus(for recipe: Recipe, in context: ModelContext) async {
        // With generation off this would otherwise still write clip state onto a
        // user's import — the pipeline is keyed by media id, so a video another
        // user already processed reports `ready` for everyone.
        guard MediaClipConfig.clipsAllowed(for: recipe) else { return }
        let sourceURL = recipe.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let external = recipe.mediaExternalID
            ?? sourceURL.flatMap { MediaSourceID.from(sourceURL: $0) }
        guard let external else { return }

        var status: MediaIngestClient.StatusResult
        do {
            status = try await MediaIngestClient.shared.status(externalID: external)
        } catch {
            return // Soft fail — keep last known status.
        }

        // Never enqueued (or the enqueue call failed): start it now.
        if !status.found {
            await ensure(for: recipe, in: context)
            return
        }

        recipe.mediaExternalID = status.externalID
        recipe.mediaSourceAssetID = status.sourceAssetID ?? recipe.mediaSourceAssetID
        recipe.mediaJobID = status.jobID ?? recipe.mediaJobID
        recipe.mediaStatus = status.mediaStatus
        recipe.mediaProgress = status.progress
        recipe.mediaStatusDetail = status.detail
        try? context.save()

        guard status.approvedSegments == 0,
              status.mediaStatus != "ready",
              status.mediaStatus != "failed",
              let sourceURL, YouTubeEmbed.videoId(from: sourceURL) != nil else { return }
        let last = lastAnalyzeAttempt[external]
        guard last == nil || Date.now.timeIntervalSince(last!) > analyzeRetryCooldown else { return }
        await runAnalyze(for: recipe, sourceURL: sourceURL, externalID: external, in: context)
    }
}
