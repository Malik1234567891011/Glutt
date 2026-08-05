import Foundation
import SwiftData

/// Which recipes belong to the user, and how they are identified across
/// devices. The bottom of the sync stack — everything above it assumes a recipe
/// has a `remoteID` and knows whether it is the user's to back up.
enum RecipeIdentity {

    /// True when this recipe is the user's own work and therefore worth syncing.
    ///
    /// Three kinds of recipe live in the same table. Imports, manual entries and
    /// AI-generated dishes cost real money or real effort to create, so they
    /// sync. Cooking Basics lessons and chef dishes ship inside the binary and
    /// are reinstalled from code on every launch — copying them to the server
    /// would store the same rows for every user forever, so only the *state* a
    /// user puts on them travels (see `RecipeStateSync`).
    ///
    /// `-seed` demo data needs no case of its own: the Beta scheme that passes
    /// it also skips the sign-in gate, so those launches are never signed in and
    /// nothing syncs at all.
    static func isSyncable(_ recipe: Recipe) -> Bool {
        !recipe.isCookingBasic && !recipe.isChefRecipe
    }

    /// Gives an identity to every recipe that predates this feature.
    ///
    /// Boring on purpose. One sweep on first launch after the update, a fresh
    /// UUID each, saved once. Every recipe created afterwards gets its id in
    /// `Recipe.init`, so this finds nothing on subsequent launches and costs a
    /// single fetch.
    ///
    /// Bundled content is backfilled too. It never gets pushed, but leaving a
    /// nil there would mean every code path downstream has to ask twice.
    @discardableResult
    static func backfill(in context: ModelContext) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<Recipe>()) else { return 0 }
        let missing = all.filter { $0.remoteID == nil }
        guard !missing.isEmpty else { return 0 }
        for recipe in missing {
            recipe.remoteID = UUID()
        }
        try? context.save()
        return missing.count
    }

    /// The user's own recipes, backed up and restored. Bundled content excluded.
    static func syncableRecipes(in context: ModelContext) -> [Recipe] {
        let all = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        return all.filter(isSyncable)
    }

    /// Records that a recipe was deleted, so the next sweep can tell the server.
    ///
    /// Call **before** `context.delete(recipe)` — afterwards the `remoteID` is
    /// gone with the row and there is nothing left to tombstone.
    static func recordDeletion(of recipe: Recipe, in context: ModelContext) {
        guard isSyncable(recipe), let remoteID = recipe.remoteID else { return }
        context.insert(SyncTombstone(remoteID: remoteID))
    }

    // MARK: - Matching a pulled row to a local recipe

    /// Finds the local recipe a pulled row refers to.
    ///
    /// `remoteID` is the answer almost always. The fallbacks only matter for the
    /// one-time migration of a phone that had recipes before this feature
    /// existed: those rows were pushed with ids minted on *this* device, so a
    /// second device restoring them has no id to match on and would otherwise
    /// end up with two of everything.
    ///
    /// 1. `remoteID` — the real answer.
    /// 2. `sourceURL` — the dedup `DiscoverSaver` already relies on.
    /// 3. normalized title + creator — last resort, for manual recipes that
    ///    have no URL at all.
    static func localMatch(
        forRemoteID remoteID: UUID,
        sourceURL: String?,
        title: String,
        sourceCreator: String?,
        among candidates: [Recipe]
    ) -> Recipe? {
        if let byID = candidates.first(where: { $0.remoteID == remoteID }) { return byID }

        if let sourceURL, !sourceURL.trimmingCharacters(in: .whitespaces).isEmpty,
           let byURL = candidates.first(where: { $0.sourceURL == sourceURL }) {
            return byURL
        }

        let key = matchKey(title: title, creator: sourceCreator)
        guard !key.isEmpty else { return nil }
        return candidates.first { matchKey(title: $0.title, creator: $0.sourceCreator) == key }
    }

    /// Case- and whitespace-insensitive "is this the same dish by the same
    /// person". Not clever: two genuinely different recipes sharing a title and
    /// a creator would merge, which is a better failure than a duplicate library.
    static func matchKey(title: String, creator: String?) -> String {
        let normalized = { (value: String) in
            value.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        let title = normalized(title)
        guard !title.isEmpty else { return "" }
        return "\(title)|\(normalized(creator ?? ""))"
    }
}
