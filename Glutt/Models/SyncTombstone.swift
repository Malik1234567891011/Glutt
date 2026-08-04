import Foundation
import SwiftData

/// A recipe the user deleted, remembered just long enough to tell the server.
///
/// The push sweep works by hashing every local recipe, and a hash sweep cannot
/// see a row that no longer exists — so without this, deleting a recipe on one
/// phone would leave it alive on the server and it would come straight back on
/// the next restore.
///
/// Deliberately tiny and short-lived: written at the one delete site, pushed as
/// `deleted_at` on the next sweep, and dropped the moment that push confirms.
/// The server keeps its tombstone for 90 days (long enough for a phone that has
/// been off to learn about the delete) and a cron purges it after that.
@Model
final class SyncTombstone {
    /// The deleted recipe's `remoteID`. Unique in practice; not enforced,
    /// because a duplicate would only cost one redundant upsert.
    var remoteID: UUID
    var deletedAt: Date

    init(remoteID: UUID, deletedAt: Date = .now) {
        self.remoteID = remoteID
        self.deletedAt = deletedAt
    }
}
