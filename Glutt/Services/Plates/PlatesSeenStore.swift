import Foundation

/// Remembers which deck cards a cook has already judged, so a recipe they
/// skipped does not walk back in tomorrow.
///
/// The deck's `skippedIDs` lived only in memory, so every launch started from a
/// clean slate with the same rejects at the front of the pile. Saved recipes
/// were already excluded by source URL; this closes the other half, and it is
/// the difference between a feed that learns and one that feels hardcoded.
enum PlatesSeenStore {
    private static let key = "plates.seen.ids"

    /// Oldest ids fall off the end. Deep enough to cover months of swiping,
    /// small enough that a synchronous read on every deck load stays free.
    static let capacity = 1500

    static func ids(store: UserDefaults = .standard) -> Set<String> {
        Set(store.stringArray(forKey: key) ?? [])
    }

    static func record(_ id: String, store: UserDefaults = .standard) {
        record([id], store: store)
    }

    static func record(_ ids: [String], store: UserDefaults = .standard) {
        var list = store.stringArray(forKey: key) ?? []
        var known = Set(list)
        for id in ids where !id.isEmpty && !known.contains(id) {
            list.append(id)
            known.insert(id)
        }
        if list.count > capacity { list.removeFirst(list.count - capacity) }
        store.set(list, forKey: key)
    }

    /// Undoing a swipe has to undo the memory of it too, or the card silently
    /// never comes back despite the cook saying they wanted it back.
    static func forget(_ id: String, store: UserDefaults = .standard) {
        let list = store.stringArray(forKey: key) ?? []
        store.set(list.filter { $0 != id }, forKey: key)
    }

    /// Backs a "show me everything again" affordance, and lets the deck dig
    /// itself out if a cook ever swipes the pool dry.
    static func reset(store: UserDefaults = .standard) {
        store.removeObject(forKey: key)
    }
}
