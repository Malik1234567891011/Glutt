import Foundation

/// What a cook has been seen to do, as opposed to what they have read.
///
/// The product rule this exists to express: **lessons tell us what the user has
/// learned, verified cooking tells us what the user can do.** Cook Rating is
/// the second one. Finishing a lesson moves XP and level and never touches
/// this; being watched moves this and never touches XP.
///
/// # Not another XP bar
///
/// XP counts events. This weighs them. A beginner check that establishes one
/// narrow thing is worth a fraction of a mastery trial, the same check passed
/// for the fifth time is worth almost nothing, and anything the checker could
/// not see is worth exactly nothing rather than a penalty.
///
/// # Unranked is a real state
///
/// No invented starting number. A cook is unranked until there is enough
/// verified evidence to say anything, and the first stretch after that is
/// marked provisional, because three narrow checks is not a full picture of
/// somebody's cooking and it would be dishonest to present it as one.
enum CookRating {

    /// Verified events before a rating is shown at all.
    ///
    /// Three, and any mix of ordinary checks and trials counts. It used to be
    /// three *trials*, which was unreachable: only five mastery trials in the
    /// catalog carry a visual check, so a cook had to complete most of the
    /// hardest content in the app before the rating would say a word.
    static let evidenceToPlace = 3

    /// Below this the rating is shown but marked provisional, because it rests
    /// on a handful of narrow observations.
    static let evidenceToSettle = 8

    /// Where a placed cook starts, before their evidence moves them.
    static let placementBase = 1_000

    /// The credit an average competent attempt is worth. Evidence above this
    /// raises a rating, below it lowers one.
    ///
    /// 0.6 sits between a clean pass and a correction, deliberately nearer the
    /// correction: a cook who needs a fix on most things is not standing still,
    /// they are below where they will be.
    static let neutralCredit = 0.6

    /// How many rating points one unit of weighted evidence is worth.
    static let pointsPerWeight = 12.0

    /// Evidence that actually counts, with repeats damped.
    ///
    /// Oldest first per skill, so the FIRST time somebody demonstrates a
    /// technique carries full weight and later repeats decay. Doing it once
    /// well is the evidence; doing it nine more times is practice.
    static func effective(_ evidence: [RatingEvidence]) -> [(RatingEvidence, weight: Double)] {
        var seen: [String: Int] = [:]
        return evidence
            .sorted { $0.occurredAt < $1.occurredAt }
            .map { item in
                let prior = seen[item.skillID, default: 0]
                seen[item.skillID] = prior + 1
                return (item, item.weight * EvidenceWeight.repeatFactor(priorCount: prior))
            }
    }

    static func isPlaced(_ evidence: [RatingEvidence]) -> Bool {
        evidence.count >= evidenceToPlace
    }

    /// True while the rating rests on too little to be presented as settled.
    static func isProvisional(_ evidence: [RatingEvidence]) -> Bool {
        isPlaced(evidence) && evidence.count < evidenceToSettle
    }

    /// What a cook is worth right now, or nil while unranked.
    static func rating(from evidence: [RatingEvidence]) -> Int? {
        guard isPlaced(evidence) else { return nil }
        let movement = effective(evidence).reduce(0.0) { total, item in
            total + (item.0.credit.rawValue - neutralCredit) * item.weight * pointsPerWeight
        }
        return placementBase + Int(movement.rounded())
    }

    /// How much more is needed before a rating appears.
    static func placementRemaining(_ evidence: [RatingEvidence]) -> Int {
        max(0, evidenceToPlace - evidence.count)
    }

    /// The line under the Cook Rating row while unranked.
    ///
    /// Says what earns a rating, because "Unranked" on its own names a state
    /// without naming the way out of it.
    static func placementLine(_ evidence: [RatingEvidence]) -> String {
        let remaining = placementRemaining(evidence)
        guard remaining > 0 else { return "" }
        return "\(remaining) verified \(remaining == 1 ? "check" : "checks") to place"
    }

    /// Progress toward placement, for the sheet.
    static func placementProgress(_ evidence: [RatingEvidence]) -> (done: Int, needed: Int) {
        (min(evidence.count, evidenceToPlace), evidenceToPlace)
    }
}

/// The title that comes with a rating.
///
/// Kitchen brigade names rather than invented tiers: real words for a real
/// trade, and they carry a sense of progression that "Tier 4" does not.
/// Numbered downward within a rank the way a kitchen does it, so Line Cook III
/// is junior to Line Cook I.
struct CookRank: Equatable, Sendable {
    let title: String
    let floor: Int
    let ceiling: Int?

    var spoken: String { title }

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

    static func toNext(from rating: Int) -> (rank: CookRank, points: Int)? {
        guard let next = ladder.first(where: { $0.floor > rating }) else { return nil }
        return (next, next.floor - rating)
    }
}

/// A region's demonstrated standard, 0 to 100.
///
/// Only ever computed where there is something real to compute it from. Flavour
/// & Seasoning and Cooking Intuition have no visual checks, because you cannot
/// photograph tasting as you go, and they must never be given a number.
/// Inventing symmetry there would be exactly the kind of unconsidered system
/// that makes software feel generated: real systems have exceptions because
/// reality has them.
enum RegionRating {

    /// Verified events in a region before its standard is worth showing.
    ///
    /// Two, and either kind counts. One observation is an anecdote.
    static let evidenceToRate = 2

    static func isRateable(_ category: SkillCategory) -> Bool {
        category.skills.contains { $0.visualCheck != nil }
    }

    /// The region's standard, or nil when it cannot or should not be shown.
    static func rating(for category: SkillCategory, evidence: [RatingEvidence]) -> Int? {
        guard isRateable(category) else { return nil }
        let mine = evidence.filter { $0.categoryID == category.id }
        guard mine.count >= evidenceToRate else { return nil }

        // Weighted by what each piece is worth AND by how recent it is, so a
        // cook who was poor in January and good in March reads as good.
        let weighted = Array(CookRating.effective(mine).reversed())
        var total = 0.0
        var weightSum = 0.0
        for (index, item) in weighted.enumerated() {
            let recency = pow(0.7, Double(index))
            let weight = item.weight * recency
            total += item.0.credit.rawValue * weight
            weightSum += weight
        }
        guard weightSum > 0 else { return nil }
        return Int((total / weightSum * 100).rounded())
    }
}
