import Foundation

/// Hands shared URLs from the share extension to the main app via the app group.
enum PendingImportStore {
    static let appGroupID = "group.com.omarlahmimi.glutt"
    private static let key = "pendingImportURL"

    static func save(urlString: String) {
        UserDefaults(suiteName: appGroupID)?.set(urlString, forKey: key)
    }

    /// Returns and clears the pending URL, if any.
    static func consume() -> URL? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let urlString = defaults.string(forKey: key),
              let url = URL(string: urlString)
        else { return nil }
        defaults.removeObject(forKey: key)
        return url
    }
}
