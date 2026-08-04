import Foundation

/// The canonical names of everything currently in the kitchen, mirrored into the
/// app group so the share extension can say "8 of the 12 ingredients already in
/// your kitchen" the moment an import lands.
///
/// The extension can't reach SwiftData, and the alternative — dropping the claim
/// — makes the confirmation screen vaguer than the design. The app rewrites this
/// whenever it changes hands (launch and every foreground/background), which is
/// exactly when the extension might next run.
///
/// `read()` returns `nil` when no snapshot has ever been written, which is
/// different from an empty kitchen: the first tells you not to make the claim,
/// the second tells you the honest answer is zero.
enum PantrySnapshot {
    static let appGroupID = "group.com.malik.glutt"
    private static let key = "pantrySnapshotCanonicalNames"

    /// Called by the app with the canonical names of every pantry row that isn't
    /// marked out of stock, **plus the assumed staples**. Folding staples in on
    /// the writing side keeps `PantryMatcher` (and the SwiftData models it needs)
    /// out of the extension entirely.
    static func write(canonicalNames: [String]) {
        UserDefaults(suiteName: appGroupID)?.set(Array(Set(canonicalNames)), forKey: key)
    }

    /// `nil` when the app has never written one (fresh install, or the user has
    /// only ever used the share extension).
    static func read() -> Set<String>? {
        guard let names = UserDefaults(suiteName: appGroupID)?.array(forKey: key) as? [String]
        else { return nil }
        return Set(names)
    }

    /// How many of these ingredient lines the kitchen already covers, and how
    /// many were countable at all. `nil` when there is no snapshot to match
    /// against — say nothing rather than imply an empty kitchen.
    static func coverage(forIngredientLines lines: [String]) -> (owned: Int, total: Int)? {
        guard let pantry = read() else { return nil }
        let names = lines
            .map { IngredientCanonicalizer.canonicalize(IngredientLineParser.parse($0).name) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }

        return (names.filter(pantry.contains).count, names.count)
    }
}
