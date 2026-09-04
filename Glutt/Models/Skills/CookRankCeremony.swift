import Foundation

/// Whether a promotion still owes the cook a moment.
///
/// # Why this needs storing at all
///
/// A rank is derived from evidence, so it is true every time the view is
/// built. Without a record of what has already been said out loud, the
/// promotion would re-announce itself on every redraw, which turns the one
/// moment worth having into wallpaper. This holds the highest rank floor the
/// cook has actually been congratulated for.
///
/// `UserDefaults` rather than SwiftData, matching `SkillStreak`: it is a
/// high-water mark rather than a record of anything, nothing else joins
/// against it, and losing it costs one duplicate congratulation.
///
/// # Promotions only
///
/// The mark never moves down. A rating can fall, because it is evidence
/// weighted by recency and a bad run genuinely lowers it, but nobody should be
/// told they have been demoted by an app that watched them chop an onion. The
/// number falling is honest and visible in the rating itself. Narrating it
/// would be something else.
enum CookRankCeremony {

    private static let key = "cookRank.celebratedFloor"

    /// The rank to announce right now, or nil when there is nothing new.
    ///
    /// Reading it does NOT consume it, so a view can ask without committing to
    /// showing anything. `record(_:)` is what spends it.
    static func pending(for evidence: [RatingEvidence], store: UserDefaults = .standard) -> CookRank? {
        guard let rating = CookRating.rating(from: evidence) else { return nil }
        let rank = CookRank.rank(for: rating)
        // `object(forKey:)` rather than `integer(forKey:)`, because a missing
        // key reads as 0, and 0 is a real floor: it is Prep Cook III. Without
        // this the first promotion into the bottom rank would be swallowed as
        // already celebrated.
        guard let celebrated = store.object(forKey: key) as? Int else { return rank }
        return rank.floor > celebrated ? rank : nil
    }

    /// Remember that this promotion has been said out loud.
    static func record(_ rank: CookRank, store: UserDefaults = .standard) {
        let celebrated = (store.object(forKey: key) as? Int) ?? Int.min
        guard rank.floor > celebrated else { return }
        store.set(rank.floor, forKey: key)
    }

    /// Wipe it, for the fresh-install path.
    static func reset(store: UserDefaults = .standard) {
        store.removeObject(forKey: key)
    }

    /// What Chef says on a promotion.
    ///
    /// One line each, written per rank rather than templated, because
    /// "You reached Sous Chef!" nine times is a template and reads like one.
    /// Each says what the rank actually means about the cook's hands.
    static func line(for rank: CookRank) -> String {
        switch rank.title {
        case "Prep Cook III":
            return "You are on the board. Everything from here is built on what I have seen you do."
        case "Prep Cook II":
            return "Your basics are holding up under watching, which is harder than doing them alone."
        case "Prep Cook I":
            return "Clean, repeatable work. This is the level most home cooks never get past."
        case "Line Cook III":
            return "You are cooking rather than following. That is a real line to have crossed."
        case "Line Cook II":
            return "Consistency across techniques now, not just one good day on one skill."
        case "Line Cook I":
            return "You could hold a station. I mean that literally."
        case "Chef de Partie":
            return "You own a section of this properly. Depth, not just coverage."
        case "Sous Chef":
            return "You are running things. Very few people who cook at home reach this."
        case "Head Chef":
            return "The top of the ladder. There is nothing left for me to verify."
        default:
            return "A new rank, earned on verified cooking."
        }
    }
}
