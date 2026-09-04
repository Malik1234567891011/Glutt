import Foundation

/// What a cook has actually demonstrated, as opposed to how much they have read.
///
/// Deliberately separate from XP and levels, and the separation is the whole
/// point. XP measures how far you have travelled: open a lesson, read it, press
/// "I've got it", collect the XP. Cook Rating measures what you have shown,
/// and it only moves when a practical trial is judged.
///
/// Somebody should not become a highly rated cook by reading every lesson.
/// That distinction is what makes the number worth anything.
///
/// # Unranked is a real state
///
/// A rating invented from two attempts is worse than no rating, so there is no
/// starting number. A cook is `unranked` until they have completed enough
/// trials across enough different regions, and then it is revealed once.
enum CookRating {

    /// Trials needed before a cook is placed, and how many regions they must
    /// span.
    ///
    /// Both, not either. Five trials in one region says you are good at that
    /// region; it says nothing about cooking. Spanning regions is what makes
    /// the first number defensible.
    ///
    /// Three rather than four, and the reason is a count nobody had done: of
    /// the seven mastery trials in the catalog only FIVE carry a visual check,
    /// so only five can be scored at all. Asking for four meant asking a cook
    /// to complete eighty per cent of every scoreable trial in the app before
    /// the rating would say anything, which is why a cook with fourteen skills
    /// learned still saw nothing. Three across two regions is still real work
    /// and still cannot be reached from one region alone.
    static let trialsToPlace = 3
    static let regionsToPlace = 2

    /// Where a placed cook starts, before their results move them.
    static let placementBase = 1_000

    /// What a cook is worth right now, or nil while they are unranked.
    static func rating(from results: [TrialResult]) -> Int? {
        guard isPlaced(results) else { return nil }
        return placementBase + results.reduce(0) { $0 + $1.ratingDelta }
    }

    static func isPlaced(_ results: [TrialResult]) -> Bool {
        guard results.count >= trialsToPlace else { return false }
        return Set(results.map(\.categoryID)).count >= regionsToPlace
    }

    /// How close an unplaced cook is to being placed, for the reveal.
    static func placementProgress(_ results: [TrialResult]) -> (done: Int, needed: Int) {
        (min(results.count, trialsToPlace), trialsToPlace)
    }

    /// One line telling an unplaced cook what the rating is and how to get one.
    ///
    /// "Unranked" on its own is a dead end. It names a state without naming the
    /// way out of it, so a cook reads it once, learns nothing, and never looks
    /// again. This is the only thing on the screen that explains the whole
    /// mechanic, so it has to earn its line.
    static func placementLine(_ results: [TrialResult]) -> String {
        guard !results.isEmpty else {
            return "Unranked · pass a trial to start"
        }
        let regions = Set(results.map(\.categoryID)).count
        if results.count >= trialsToPlace, regions < regionsToPlace {
            // The commoner near miss, and the one worth naming precisely: they
            // have done the work, just all in one place.
            return "Unranked · try a trial in another region"
        }
        let remaining = max(0, trialsToPlace - results.count)
        return "Unranked · \(remaining) more \(remaining == 1 ? "trial" : "trials")"
    }
}

/// The title that comes with a rating.
///
/// Kitchen brigade names rather than invented tiers, because they are real
/// words with real meaning and they carry the sense of a trade rather than a
/// video game ladder. Numbered downward within a rank the way the kitchen does
/// it: Line Cook III is junior to Line Cook I.
struct CookRank: Equatable, Sendable {
    let title: String
    /// The floor of this rank, so progress toward the next one can be shown.
    let floor: Int
    let ceiling: Int?

    var spoken: String { title }

    /// Every rank, lowest first.
    static let ladder: [CookRank] = [
        CookRank(title: "Prep Cook III", floor: 0, ceiling: 900),
        CookRank(title: "Prep Cook II", floor: 900, ceiling: 1_000),
        CookRank(title: "Prep Cook I", floor: 1_000, ceiling: 1_100),
        CookRank(title: "Line Cook III", floor: 1_100, ceiling: 1_250),
        CookRank(title: "Line Cook II", floor: 1_250, ceiling: 1_400),
        CookRank(title: "Line Cook I", floor: 1_400, ceiling: 1_550),
        CookRank(title: "Chef de Partie", floor: 1_550, ceiling: 1_750),
        CookRank(title: "Sous Chef", floor: 1_750, ceiling: 2_000),
        CookRank(title: "Head Chef", floor: 2_000, ceiling: nil),
    ]

    static func rank(for rating: Int) -> CookRank {
        ladder.last { rating >= $0.floor } ?? ladder[0]
    }

    /// How much more is needed for the next title, or nil at the top.
    static func toNext(from rating: Int) -> (rank: CookRank, points: Int)? {
        guard let next = ladder.first(where: { $0.floor > rating }) else { return nil }
        return (next, next.floor - rating)
    }
}

/// A region's demonstrated standard, 0 to 100.
///
/// Only ever computed where there is something real to compute it from. Two of
/// the nine regions, Flavour & Seasoning and Cooking Intuition, have no visual
/// checks at all because you cannot photograph tasting as you go, and they must
/// never be given a number. Inventing symmetry there would be the exact kind of
/// unconsidered system that makes software feel generated: real systems have
/// exceptions because reality has them.
enum RegionRating {

    /// Trials in a region before its rating is worth showing.
    static let trialsToRate = 2

    /// Whether this region is the sort of thing that can be scored at all.
    static func isRateable(_ category: SkillCategory) -> Bool {
        category.skills.contains { $0.visualCheck != nil }
    }

    /// The region's standard, or nil when it cannot or should not be shown.
    ///
    /// Weighted toward recent work, because a cook who was poor at pans in
    /// January and good in March is good at pans.
    static func rating(for category: SkillCategory, results: [TrialResult]) -> Int? {
        guard isRateable(category) else { return nil }
        let mine = results
            .filter { $0.categoryID == category.id }
            .sorted { $0.finishedAt > $1.finishedAt }
        guard mine.count >= trialsToRate else { return nil }

        // Most recent counts most, halving back through the history.
        var total = 0.0
        var weightSum = 0.0
        for (index, result) in mine.enumerated() {
            let weight = pow(0.5, Double(index))
            total += Double(result.score) * weight
            weightSum += weight
        }
        return Int((total / weightSum).rounded())
    }

    /// What to show when there is no number: the reason, not a zero.
    static func placeholder(for category: SkillCategory, results: [TrialResult]) -> String {
        guard isRateable(category) else { return "" }
        return "Unranked"
    }
}
