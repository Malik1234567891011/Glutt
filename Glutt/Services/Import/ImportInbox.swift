import Foundation

/// Append-only queue of finished imported recipes, shared between the share
/// extension (which appends) and the app (which drains on next foreground).
/// Upgrades the old single-URL `PendingImportStore` handoff to whole recipes.
struct ImportInbox {
    static let appGroupID = "group.com.omarlahmimi.glutt"
    private static let key = "importInboxItems"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: ImportInbox.appGroupID)) {
        self.defaults = defaults ?? .standard
    }

    func append(_ draft: ImportedRecipeDraft) {
        var items = load()
        items.append(draft)
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Returns queued recipes in append order and clears the queue. Corrupt
    /// data is treated as empty and cleared, so it can never block future imports.
    func drain() -> [ImportedRecipeDraft] {
        let items = load()
        defaults.removeObject(forKey: Self.key)
        return items
    }

    private func load() -> [ImportedRecipeDraft] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([ImportedRecipeDraft].self, from: data)) ?? []
    }
}
