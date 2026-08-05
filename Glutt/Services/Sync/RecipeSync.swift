import Foundation
import SwiftData

/// Backs the recipe library with Supabase so it survives a logout, a reinstall,
/// or a new phone. That is the whole feature — see docs/plan-recipe-sync.md.
///
/// **Offline-first.** SwiftData stays the source of truth for every screen and
/// nothing here is on the path of any of them. Supabase is the backup.
///
/// **Last-write-wins per whole recipe.** No CRDTs, no field-level merge. This is
/// a one-phone-per-person app and the worst realistic case is losing a single
/// edit — the one guard against even that is in `pull`, which refuses to
/// overwrite a local recipe that has changes it has not sent yet.
@MainActor
enum RecipeSync {

    /// How many recipes go in one upsert. Small enough that a flaky connection
    /// loses one batch rather than the sweep, large enough that a hundred-recipe
    /// first push is two round trips.
    static let pushBatchSize = 50
    /// Page size for the pull. A restore of a very large library pages until dry.
    static let pullPageSize = 500

    // MARK: - Watermark

    /// Per user id, because signing into a second account on the same phone must
    /// not inherit the first one's pull position and skip its entire library.
    static func watermarkKey(userID: UUID) -> String {
        "glutt.sync.recipes.watermark.\(userID.uuidString)"
    }

    static func watermark(userID: UUID) -> String? {
        UserDefaults.standard.string(forKey: watermarkKey(userID: userID))
    }

    static func setWatermark(_ value: String?, userID: UUID) {
        let key = watermarkKey(userID: userID)
        if let value, !value.isEmpty {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Sweep

    /// One full round trip. Pull first so a fresh install has a library before
    /// it has anything to say, then push whatever is local and unsent.
    static func sync(
        userID: UUID,
        in context: ModelContext,
        backend: any SyncBackend = SupabaseSyncBackend()
    ) async throws {
        RecipeIdentity.backfill(in: context)
        try await pull(userID: userID, in: context, backend: backend)
        try await push(userID: userID, in: context, backend: backend)
    }

    // MARK: - Push

    /// Sends every recipe whose content hash has moved, plus any tombstones.
    ///
    /// Tombstones go first. If the sweep dies halfway, a delete that has landed
    /// is better than a delete that is still pending behind a hundred upserts.
    @discardableResult
    static func push(
        userID: UUID,
        in context: ModelContext,
        backend: any SyncBackend = SupabaseSyncBackend()
    ) async throws -> Int {
        try await pushTombstones(userID: userID, in: context, backend: backend)

        let recipes = RecipeIdentity.syncableRecipes(in: context)
        var pending: [(recipe: Recipe, row: RemoteRecipeUpsert, hash: String)] = []

        for recipe in recipes {
            guard let remoteID = recipe.remoteID else { continue }
            let snapshot = RecipeSyncBody.snapshot(of: recipe)
            let hash = RecipeSyncBody.hash(snapshot)
            guard hash != recipe.syncedHash else { continue }
            pending.append((
                recipe,
                RemoteRecipeUpsert(
                    id: remoteID,
                    userID: userID,
                    title: snapshot.title,
                    imageURL: snapshot.imageURL,
                    imagePath: recipe.remoteImagePath,
                    sourceURL: snapshot.sourceURL,
                    sourcePlatform: snapshot.sourcePlatform,
                    isFavorite: snapshot.isFavorite,
                    body: snapshot.body,
                    deletedAt: nil
                ),
                hash
            ))
        }

        guard !pending.isEmpty else { return 0 }

        var pushed = 0
        for batch in pending.chunked(into: pushBatchSize) {
            try await backend.upsertRecipes(batch.map(\.row))
            // Marked synced only after the write returns. A hash stamped
            // optimistically would make a failed batch invisible to the next
            // sweep, which is how a recipe silently never gets backed up.
            let now = Date.now
            for item in batch {
                item.recipe.syncedHash = item.hash
                item.recipe.syncedAt = now
            }
            try? context.save()
            pushed += batch.count
        }
        return pushed
    }

    private static func pushTombstones(
        userID: UUID,
        in context: ModelContext,
        backend: any SyncBackend
    ) async throws {
        let tombstones = (try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? []
        guard !tombstones.isEmpty else { return }
        for batch in tombstones.chunked(into: pushBatchSize) {
            // One timestamp for the batch. The server's own `deleted_at` is what
            // other devices read; this only has to be close.
            try await backend.markRecipesDeleted(
                ids: batch.map(\.remoteID),
                userID: userID,
                at: batch.map(\.deletedAt).min() ?? .now
            )
            for tombstone in batch { context.delete(tombstone) }
            try? context.save()
        }
    }

    // MARK: - Pull

    /// Applies everything that changed on the server since the watermark.
    @discardableResult
    static func pull(
        userID: UUID,
        in context: ModelContext,
        backend: any SyncBackend = SupabaseSyncBackend()
    ) async throws -> Int {
        var applied = 0
        var cursor = watermark(userID: userID)

        while true {
            let page = try await backend.fetchRecipes(
                userID: userID,
                since: cursor,
                limit: pullPageSize
            )
            guard !page.isEmpty else { break }
            apply(page, in: context)
            applied += page.count
            // Server-ordered, so the last row of an ascending page is the
            // furthest we have read. Never recomputed from a local clock.
            cursor = page.last?.updatedAt
            setWatermark(cursor, userID: userID)
            if page.count < pullPageSize { break }
        }

        return applied
    }

    /// Merges one page into the local store.
    ///
    /// Two passes over the page because `parentRemoteID` can point at a recipe
    /// that is later in the same batch — "my version" chains would otherwise
    /// lose their parent depending on row order.
    static func apply(_ page: [RemoteRecipe], in context: ModelContext) {
        var candidates = RecipeIdentity.syncableRecipes(in: context)
        var collectionsByName = Dictionary(
            ((try? context.fetch(FetchDescriptor<RecipeCollection>())) ?? [])
                .map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var touched: [UUID: Recipe] = [:]

        for row in page {
            if row.isDeleted {
                if let local = candidates.first(where: { $0.remoteID == row.id }) {
                    context.delete(local)
                    candidates.removeAll { $0 === local }
                }
                continue
            }

            let local = RecipeIdentity.localMatch(
                forRemoteID: row.id,
                sourceURL: row.sourceURL,
                title: row.title,
                sourceCreator: row.body.sourceCreator,
                among: candidates
            )

            let recipe: Recipe
            if let local {
                // A local recipe with unsent changes is newer than anything the
                // server can be holding for it — the server copy is our own
                // earlier push coming back. Overwriting would discard the user's
                // edit to arrive at what we are about to send anyway.
                let hasUnsentEdits = local.syncedHash != nil
                    && local.syncedHash != RecipeSyncBody.hash(of: local)
                if hasUnsentEdits {
                    local.remoteID = row.id
                    touched[row.id] = local
                    continue
                }
                recipe = local
            } else {
                recipe = Recipe(title: row.title)
                context.insert(recipe)
                candidates.append(recipe)
            }

            // Adopt the server's identity either way: a row matched by URL or
            // title is the same recipe under a different id, and leaving the
            // local one would push a duplicate straight back.
            recipe.remoteID = row.id

            let snapshot = RecipeSyncBody.Snapshot(
                title: row.title,
                imageURL: row.imageURL,
                sourceURL: row.sourceURL,
                sourcePlatform: row.sourcePlatform ?? SourcePlatform.manual.rawValue,
                isFavorite: row.isFavorite,
                body: row.body
            )
            RecipeSyncBody.apply(
                snapshot,
                to: recipe,
                in: context,
                collectionsByName: &collectionsByName
            )
            recipe.remoteImagePath = row.imagePath
            // Hashed from the local object *after* applying, not from the row.
            // If the two ever disagree the next push corrects the server once
            // and it settles, rather than ping-ponging forever.
            recipe.syncedHash = RecipeSyncBody.hash(of: recipe)
            recipe.syncedAt = .now
            touched[row.id] = recipe
        }

        // Second pass: wire up the "my version" chains now that every recipe in
        // the batch exists.
        let byRemoteID = Dictionary(
            candidates.compactMap { recipe in recipe.remoteID.map { ($0, recipe) } },
            uniquingKeysWith: { first, _ in first }
        )
        for row in page where !row.isDeleted {
            guard let recipe = touched[row.id] else { continue }
            guard let parentID = row.body.parentRemoteID, let parent = byRemoteID[parentID] else {
                recipe.parentRecipe = nil
                continue
            }
            guard parent !== recipe else { continue }
            recipe.parentRecipe = parent
        }

        try? context.save()
    }

    // MARK: - Sign out

    /// Removes this account's library from the phone.
    ///
    /// Without it the next person to sign in on this device inherits the
    /// previous one's recipes. Bundled Cooking Basics and chef dishes stay —
    /// they ship in the binary and belong to nobody.
    ///
    /// Deliberately does **not** write tombstones: this is a local cleanup, not
    /// a delete. Tombstoning here would wipe the account's library on the server
    /// too, which is the exact opposite of what sign-out should do.
    ///
    /// `UserPrefs` is left alone. It carries `hasCompletedOnboarding`, and
    /// clearing that would drop a returning user back into onboarding; the next
    /// pull overwrites the parts of it that sync anyway.
    static func purgeLocalUserData(userID: UUID?, in context: ModelContext) {
        for recipe in RecipeIdentity.syncableRecipes(in: context) {
            context.delete(recipe)
        }
        for collection in (try? context.fetch(FetchDescriptor<RecipeCollection>())) ?? [] {
            context.delete(collection)
        }
        for tombstone in (try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? [] {
            context.delete(tombstone)
        }
        for item in (try? context.fetch(FetchDescriptor<PantryItem>())) ?? [] {
            context.delete(item)
        }
        for item in (try? context.fetch(FetchDescriptor<GroceryItem>())) ?? [] {
            context.delete(item)
        }
        for tool in (try? context.fetch(FetchDescriptor<KitchenTool>())) ?? [] {
            context.delete(tool)
        }
        try? context.save()

        if let userID { setWatermark(nil, userID: userID) }
    }
}

extension Array {
    /// Fixed-size batches. Sync sends in chunks so one failure costs a batch
    /// rather than the sweep.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
