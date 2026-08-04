import Foundation
import Observation
import SwiftData

/// Runs the sync sweeps and owns when they happen.
///
/// Everything underneath is a plain function you can call in a test; this is the
/// only part that knows about foregrounding, debouncing, and the fact that a
/// signed-out user syncs nothing at all.
///
/// Nothing here is on the path of any screen. A failed sweep sets `lastError`
/// and is otherwise silent — the library is on the device and works either way.
/// The one exception is sign-out, which asks before dropping unsynced work.
@MainActor
@Observable
final class SyncCoordinator {

    enum Status: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastSyncedAt: Date?

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var userID: UUID?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var backend: any SyncBackend
    /// Something changed while a sweep was already running.
    @ObservationIgnored private var needsAnotherPass = false

    /// Coalesces the burst of requests a single user action can produce — save a
    /// recipe, foreground the app, and drain the share-extension inbox all in
    /// the same second.
    @ObservationIgnored var debounce: Duration = .seconds(2)

    init(backend: any SyncBackend = SupabaseSyncBackend()) {
        self.backend = backend
    }

    /// Tells the coordinator who is signed in and where the data is. Call
    /// whenever either changes; a nil `userID` parks it.
    func configure(userID: UUID?, context: ModelContext?) {
        let changedUser = self.userID != userID
        self.userID = userID
        self.context = context
        if changedUser {
            pending?.cancel()
            pending = nil
            status = .idle
        }
    }

    /// Asks for a sweep soon. Safe to call from anywhere, as often as you like.
    func requestSync() {
        guard userID != nil, context != nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }
            await self.syncNow()
        }
    }

    /// Runs a sweep immediately. Errors land in `status`, never in the user's way.
    func syncNow() async {
        guard let userID, let context else { return }
        guard status != .syncing else {
            // A save that lands mid-sweep would otherwise wait for the next
            // foreground: the in-flight pass has already read the recipes.
            needsAnotherPass = true
            return
        }
        status = .syncing
        do {
            try await RecipeSync.sync(userID: userID, in: context, backend: backend)
            // Images and the small documents run after the recipes, so a
            // restore paints titles first and fills in photos behind them.
            await RecipeImageSync.uploadSweep(userID: userID, in: context, backend: backend)
            await RecipeImageSync.downloadSweep(in: context, backend: backend)
            try await RecipeStateSync.sync(userID: userID, in: context, backend: backend)
            try await KitchenSync.sync(userID: userID, in: context, backend: backend)
            status = .idle
            lastSyncedAt = .now
        } catch {
            status = .failed(error.localizedDescription)
        }

        if needsAnotherPass {
            needsAnotherPass = false
            await syncNow()
        }
    }

    /// Sends everything unsent, and reports whether it managed to.
    ///
    /// The sign-out path, which is the one moment sync is allowed to be in the
    /// way: signing out wipes this account's library off the phone, so anything
    /// still local and unsent would be gone for good.
    func flush() async throws {
        guard let userID, let context else { return }
        pending?.cancel()
        pending = nil
        status = .syncing
        defer { status = .idle }
        // Photos before the push, so the paths they produce ride along with it.
        // `uploadAll`, not the drip: an un-uploaded photo is about to be deleted
        // off this phone, so there is no later.
        try await RecipeImageSync.uploadAll(userID: userID, in: context, backend: backend)
        try await RecipeSync.push(userID: userID, in: context, backend: backend)
        try await RecipeStateSync.sync(userID: userID, in: context, backend: backend)
        try await KitchenSync.sync(userID: userID, in: context, backend: backend)
    }

    /// Removes this account's data from the phone. Call *after* `flush`
    /// succeeds, or after the user has chosen to sign out anyway.
    ///
    /// `userID` is passed in rather than read from `self` because by the time
    /// this runs the sign-out has already landed and the coordinator may have
    /// been reconfigured to nil — which would leave the watermark and the
    /// change-tracking keys behind for the next account to inherit. Callers
    /// capture the id *before* signing out.
    func purgeLocalUserData(for userID: UUID?) {
        guard let context else { return }
        RecipeSync.purgeLocalUserData(userID: userID, in: context)
        guard let userID else { return }
        KitchenSync.clearChangeTracking(userID: userID)
        // Bundled dishes stay on the phone, so their hearts have to be cleared
        // by hand: the next account must not inherit the last one's ratings.
        for recipe in RecipeStateSync.bundledRecipes(in: context) {
            recipe.isFavorite = false
            recipe.rating = nil
        }
        RecipeStateSync.clearChangeTracking(userID: userID)
    }
}
