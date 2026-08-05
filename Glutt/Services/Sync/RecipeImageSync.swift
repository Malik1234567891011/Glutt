import Foundation
import SwiftData

/// Recipe photos, to and from Supabase Storage.
///
/// `RecipeImageBackfill` already caches image bytes on the device, and its own
/// reasoning ("source-URL rot") is why they cannot simply be re-fetched on a new
/// phone. Re-fetching is free in dollars — a plain GET against the source's CDN,
/// no AI call, no API quota — but it fails in exactly the cases that matter:
///
/// - **Permanently re-fetchable:** YouTube (`i.ytimg.com/vi/{id}/…` never
///   expires), Spoonacular, most sites' `og:image`.
/// - **Rots in days:** Instagram and TikTok oEmbed thumbnails are signed CDN URLs.
/// - **Impossible:** camera-roll photos and share-sheet preview bytes. No URL
///   exists, only bytes.
///
/// So every recipe that has bytes gets them uploaded, with no clever tiering by
/// platform — that would save a couple of dollars a month and add a branch that
/// will eventually be wrong about some platform.
@MainActor
enum RecipeImageSync {

    /// Uploads per sweep. A hundred-recipe library is ~15 MB and must not all go
    /// over cellular the moment someone signs in on a new phone, so it drips out
    /// over a few foregrounds instead.
    static let uploadsPerSweep = 5
    /// Downloads per sweep. Higher than uploads because this is the restore
    /// path, where the user is looking at a library of grey rectangles.
    static let downloadsPerSweep = 10

    /// Paths that failed this app run — not retried until next launch.
    private static var failedPaths: Set<String> = []

    /// `recipes/{user_id}/{recipe_id}.jpg` in a **private** bucket with no public
    /// read. Per-user prefix so one RLS rule covers the whole feature, and so
    /// account deletion has a single prefix to remove.
    static func storagePath(userID: UUID, recipeID: UUID) -> String {
        "recipes/\(userID.uuidString)/\(recipeID.uuidString).jpg"
    }

    static func needsUpload(_ recipe: Recipe) -> Bool {
        recipe.remoteImagePath == nil && recipe.imageData != nil && recipe.imageAssetName == nil
    }

    static func needsDownload(_ recipe: Recipe) -> Bool {
        recipe.remoteImagePath != nil && recipe.imageData == nil && recipe.imageAssetName == nil
    }

    /// Uploads a few of the user's un-uploaded photos. Failures are remembered
    /// for the rest of the run and otherwise ignored — the recipe is safe on the
    /// server either way, and a missing photo is not worth a visible error.
    @discardableResult
    static func uploadSweep(
        userID: UUID,
        in context: ModelContext,
        backend: any SyncBackend = SupabaseSyncBackend()
    ) async -> Int {
        (try? await upload(userID: userID, limit: uploadsPerSweep, in: context, backend: backend)) ?? 0
    }

    /// Uploads **every** outstanding photo and lets a failure through.
    ///
    /// The sign-out path. Signing out deletes this account's recipes from the
    /// phone, so a photo that has not reached the bucket by then is gone for
    /// good — this is the one moment the drip has to become a flush, and the one
    /// moment a failed upload has to be able to stop what happens next.
    @discardableResult
    static func uploadAll(
        userID: UUID,
        in context: ModelContext,
        backend: any SyncBackend = SupabaseSyncBackend()
    ) async throws -> Int {
        // A path that failed earlier in the run gets one more try: the phone may
        // have been on a dead network then and is plainly online now.
        failedPaths.removeAll()
        return try await upload(userID: userID, limit: nil, in: context, backend: backend)
    }

    private static func upload(
        userID: UUID,
        limit: Int?,
        in context: ModelContext,
        backend: any SyncBackend
    ) async throws -> Int {
        var pending = RecipeIdentity.syncableRecipes(in: context).filter(needsUpload)
        if let limit { pending = Array(pending.prefix(limit)) }

        var uploaded = 0
        defer { if uploaded > 0 { try? context.save() } }

        for recipe in pending {
            guard let remoteID = recipe.remoteID, let bytes = recipe.imageData else { continue }
            let path = storagePath(userID: userID, recipeID: remoteID)
            guard !failedPaths.contains(path) else { continue }
            do {
                try await backend.uploadImage(path: path, data: bytes)
            } catch {
                failedPaths.insert(path)
                if limit == nil { throw error }
                continue
            }
            recipe.remoteImagePath = path
            // The path lives in a promoted column, not in the hashed body, so
            // nothing else would notice it changed. Clearing the hash is what
            // gets it to the server on the next push.
            recipe.syncedHash = nil
            uploaded += 1
        }
        return uploaded
    }

    /// Pulls down photos for recipes that arrived from the server without bytes.
    @discardableResult
    static func downloadSweep(
        in context: ModelContext,
        backend: any SyncBackend = SupabaseSyncBackend()
    ) async -> Int {
        let pending = RecipeIdentity.syncableRecipes(in: context)
            .filter(needsDownload)
            .prefix(downloadsPerSweep)

        var downloaded = 0
        for recipe in pending {
            guard let path = recipe.remoteImagePath, !failedPaths.contains(path) else { continue }
            do {
                recipe.imageData = try await backend.downloadImage(path: path)
                downloaded += 1
            } catch {
                // Missing object, revoked access, offline. `imageURL` is still
                // there and `RecipeImageBackfill.sweep` will try it for free —
                // which is exactly why that column is kept alongside the path.
                failedPaths.insert(path)
            }
        }
        if downloaded > 0 { try? context.save() }
        return downloaded
    }

    /// Test seam: clear the session failure set between tests.
    static func resetFailedPathsForTesting() { failedPaths.removeAll() }
}
