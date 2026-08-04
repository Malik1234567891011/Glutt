import Foundation
import SwiftData

/// Hearts, ratings and notes on content that ships inside the app.
///
/// Cooking Basics lessons and chef dishes are reinstalled from code on every
/// launch, so copying them to the server would store the same rows for every
/// user forever. What is worth keeping is the tiny bit the user added: that they
/// hearted the omelette lesson, or gave a chef's ragu four stars. Those travel
/// keyed by content slug, and land back on whatever copy of the dish the new
/// phone reinstalled for itself.
@MainActor
enum RecipeStateSync {

    /// Volume is a handful of rows, so this fetches all of them every sweep
    /// rather than carrying a watermark for something that will never need one.
    ///
    /// Direction is decided **per key** against `lastSynced`, the signature of
    /// what this device last agreed with the server about. Without it, a pull
    /// would put a heart straight back on every time somebody removed one: the
    /// server still says true, and nothing local would say otherwise.
    static func sync(
        userID: UUID,
        in context: ModelContext,
        backend: any SyncBackend = SupabaseSyncBackend()
    ) async throws {
        let remote = try await backend.fetchUserStates(userID: userID)
        let remoteByKey = Dictionary(remote.map { ($0.contentKey, $0) },
                                     uniquingKeysWith: { first, _ in first })
        let lastSynced = signatures(userID: userID)

        // Only recipes actually installed here take part. A lesson dropped from
        // a later build has no local row to carry its heart, and its server row
        // is left alone until it comes back.
        var localByKey: [String: Recipe] = [:]
        for recipe in bundledRecipes(in: context) {
            guard let key = contentKey(for: recipe) else { continue }
            localByKey[key] = recipe
        }

        var outgoing: [RemoteUserState] = []
        var next: [String: String] = [:]

        for (key, recipe) in localByKey {
            let local = state(of: recipe, key: key)
            let localSignature = signature(local)
            // Nil means this device has never synced this key: a restore, so the
            // server wins. A value that no longer matches means the user has
            // changed it here since, so this phone wins.
            let hasLocalEdits = lastSynced[key] != nil && localSignature != lastSynced[key]

            if !hasLocalEdits, let state = remoteByKey[key] {
                recipe.isFavorite = state.isFavorite
                recipe.rating = state.rating
                recipe.notes = state.notes ?? ""
                next[key] = signature(state)
                continue
            }

            next[key] = localSignature
            // Rows the server already has are pushed even when the state has
            // gone back to its default, or un-hearting here would never reach
            // the other phone.
            let isDefault = !local.isFavorite && local.rating == nil && local.notes == nil
            guard !isDefault || remoteByKey[key] != nil else { continue }
            if let existing = remoteByKey[key], matches(existing, local) { continue }
            outgoing.append(local)
        }

        try? context.save()
        try await backend.upsertUserStates(outgoing, userID: userID)
        setSignatures(next, userID: userID)
    }

    private static func state(of recipe: Recipe, key: String) -> RemoteUserState {
        RemoteUserState(
            contentKey: key,
            isFavorite: recipe.isFavorite,
            rating: recipe.rating,
            notes: recipe.notes.isEmpty ? nil : recipe.notes
        )
    }

    private static func matches(_ remote: RemoteUserState, _ local: RemoteUserState) -> Bool {
        remote.isFavorite == local.isFavorite
            && remote.rating == local.rating
            && (remote.notes ?? "") == (local.notes ?? "")
    }

    // MARK: - Change tracking

    private static func signature(_ state: RemoteUserState) -> String {
        "\(state.isFavorite)|\(state.rating.map(String.init) ?? "")|\(state.notes ?? "")"
    }

    static func signaturesKey(userID: UUID) -> String {
        "glutt.sync.recipeState.\(userID.uuidString)"
    }

    static func signatures(userID: UUID) -> [String: String] {
        UserDefaults.standard.dictionary(forKey: signaturesKey(userID: userID)) as? [String: String]
            ?? [:]
    }

    static func setSignatures(_ value: [String: String], userID: UUID) {
        UserDefaults.standard.set(value, forKey: signaturesKey(userID: userID))
    }

    static func clearChangeTracking(userID: UUID) {
        UserDefaults.standard.removeObject(forKey: signaturesKey(userID: userID))
    }

    static func bundledRecipes(in context: ModelContext) -> [Recipe] {
        let all = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        return all.filter { !RecipeIdentity.isSyncable($0) }
    }

    /// `chef:<chef-slug>:<dish-slug>` or `basics:<lesson-slug>`.
    ///
    /// The dish slug is part of the key because a chef has several dishes and a
    /// key of `chef:ottolenghi` alone would make one heart apply to all of them.
    /// Derived from the title rather than an explicit id because the bundled
    /// content has no ids — retitle a dish and its heart is lost, which is a
    /// fair price for not adding an id to every entry in two large files.
    static func contentKey(for recipe: Recipe) -> String? {
        if let chef = recipe.chefSlug {
            return "chef:\(chef):\(slug(recipe.title))"
        }
        if recipe.isCookingBasic {
            return "basics:\(slug(recipe.title))"
        }
        return nil
    }

    static func slug(_ title: String) -> String {
        let lowered = title.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
        let cleaned = lowered.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return String(cleaned)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }
}
