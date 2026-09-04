import XCTest
@testable import Glutt

/// Cook Rating, which is meant to mean something.
final class CookRatingTests: XCTestCase {

    private func result(_ category: String, _ score: Int, coachCalls: Int = 0,
                        daysAgo: Double = 0) -> TrialResult {
        TrialResult(
            skillID: "\(category).challenge", categoryID: category, score: score,
            finishedAt: Date().addingTimeInterval(-daysAgo * 86_400),
            coachCalls: coachCalls)
    }

    // MARK: Unranked is a real state

    /// No starting number. A rating invented from two attempts is worse than no
    /// rating at all.
    func testACookWithNothingToShowIsUnranked() {
        XCTAssertNil(CookRating.rating(from: []))
        XCTAssertNil(CookRating.rating(from: [result("knife", 90)]))
    }

    /// Four trials in ONE region says you are good at that region, not that you
    /// can cook. Placement needs spread.
    func testFourTrialsInOneRegionIsNotEnough() {
        let all = (0..<5).map { _ in result("knife", 90) }
        XCTAssertNil(CookRating.rating(from: all), "one region is not a cook")
    }

    func testEnoughTrialsAcrossEnoughRegionsPlacesThem() {
        let placed = [result("knife", 80), result("knife", 82),
                      result("heat", 78), result("eggs", 85)]
        XCTAssertNotNil(CookRating.rating(from: placed))
        XCTAssertTrue(CookRating.isPlaced(placed))
    }

    // MARK: Reading is not doing

    /// The whole reason this is separate from XP: scraping through repeatedly
    /// must not climb. 75 is the centre, so a bare pass is roughly neutral.
    func testScrapingThroughDoesNotClimb() {
        let scraped = (0..<8).map { i in result(i < 4 ? "knife" : "heat", 70) }
        let rating = CookRating.rating(from: scraped)!
        XCTAssertLessThan(rating, CookRating.placementBase,
                          "consistently mediocre work should not raise a rating")
    }

    func testGoodWorkClimbs() {
        let strong = [result("knife", 94), result("heat", 91),
                      result("eggs", 89), result("meat", 92)]
        XCTAssertGreaterThan(CookRating.rating(from: strong)!, CookRating.placementBase)
    }

    /// One disaster must not erase a history, and one blinder must not make a
    /// cook.
    func testASingleResultCannotDominate() {
        let one = result("knife", 0)
        XCTAssertGreaterThanOrEqual(one.ratingDelta, -25)
        XCTAssertLessThanOrEqual(result("knife", 100).ratingDelta, 34)
    }

    /// Independence is a bonus on good work, never a penalty on asking for
    /// help. Deducting points for a question would make this feel game-designed
    /// rather than cooking-designed.
    func testAskingForHelpIsNeverPunished() {
        let helped = result("knife", 90, coachCalls: 3)
        let alone = result("knife", 90, coachCalls: 0)
        XCTAssertGreaterThan(alone.ratingDelta, helped.ratingDelta, "independence is worth something")
        XCTAssertGreaterThan(helped.ratingDelta, 0, "a good result is still good with help")
        XCTAssertFalse(helped.wasIndependent)
        XCTAssertTrue(alone.wasIndependent)
    }

    // MARK: Ranks

    func testRanksClimbInOrderAndNeverGap() {
        var last = -1
        for rank in CookRank.ladder {
            XCTAssertGreaterThan(rank.floor, last, "\(rank.title) overlaps the rank below")
            last = rank.floor
        }
        XCTAssertNil(CookRank.ladder.last?.ceiling, "the top rank has no ceiling")
    }

    func testARatingMapsToOneRank() {
        XCTAssertEqual(CookRank.rank(for: 1_284).title, "Line Cook II")
        XCTAssertEqual(CookRank.rank(for: 1_000).title, "Prep Cook I")
        XCTAssertEqual(CookRank.rank(for: 99_999).title, "Head Chef")
        XCTAssertEqual(CookRank.rank(for: 0).title, "Prep Cook III")
    }

    func testItKnowsHowFarTheNextRankIs() {
        let next = CookRank.toNext(from: 1_284)
        XCTAssertEqual(next?.rank.title, "Line Cook I")
        XCTAssertEqual(next?.points, 1_400 - 1_284)
        XCTAssertNil(CookRank.toNext(from: 5_000), "nothing above the top")
    }
}

/// Region ratings, and the two regions that must never get one.
final class RegionRatingTests: XCTestCase {

    private func result(_ category: String, _ score: Int, daysAgo: Double = 0) -> TrialResult {
        TrialResult(skillID: "x", categoryID: category, score: score,
                    finishedAt: Date().addingTimeInterval(-daysAgo * 86_400))
    }

    /// The integrity rule. You cannot photograph "tasting as you go", so
    /// Flavour and Intuition have no visual checks, and giving them a number
    /// for the sake of symmetry would be inventing a measurement.
    func testRegionsWithNothingToMeasureAreNeverRated() {
        for id in ["flavor", "intuition"] {
            guard let category = SkillCatalog.categories.first(where: { $0.id == id }) else {
                return XCTFail("\(id) is missing from the catalog")
            }
            XCTAssertFalse(RegionRating.isRateable(category),
                           "\(category.name) has no visual checks and must not be scored")
            let invented = (0..<6).map { _ in result(id, 90) }
            XCTAssertNil(RegionRating.rating(for: category, results: invented),
                         "\(category.name) must stay unrated even with results against it")
            XCTAssertEqual(RegionRating.placeholder(for: category, results: invented), "")
        }
    }

    func testRegionsThatCanBeMeasuredAreRateable() {
        // Resolved with XCTUnwrap rather than `continue`: the first draft of
        // this used "knife.skills", which is not a real id, so every iteration
        // skipped and the test passed while asserting nothing.
        for id in ["knife", "heat", "eggs", "meat"] {
            guard let category = SkillCatalog.categories.first(where: { $0.id == id }) else {
                return XCTFail("\(id) is not a category id")
            }
            XCTAssertTrue(RegionRating.isRateable(category), "\(category.name) should be rateable")
        }
    }

    /// One attempt is an anecdote.
    func testOneTrialIsNotARating() throws {
        let knife = try XCTUnwrap(SkillCatalog.categories.first { RegionRating.isRateable($0) })
        XCTAssertNil(RegionRating.rating(for: knife, results: [result(knife.id, 90)]))
        XCTAssertEqual(RegionRating.placeholder(for: knife, results: []), "Unranked")
    }

    /// A cook who was poor in January and good in March is good.
    func testRecentWorkCountsForMore() throws {
        let knife = try XCTUnwrap(SkillCatalog.categories.first { RegionRating.isRateable($0) })
        let improving = [result(knife.id, 90, daysAgo: 0), result(knife.id, 50, daysAgo: 60)]
        let rating = try XCTUnwrap(RegionRating.rating(for: knife, results: improving))
        XCTAssertGreaterThan(rating, 70, "the recent 90 should outweigh the old 50")
        XCTAssertLessThan(rating, 90, "but the old result is not erased")
    }

    /// Other regions' results are not this region's business.
    func testItOnlyCountsItsOwnRegion() throws {
        let knife = try XCTUnwrap(SkillCatalog.categories.first { RegionRating.isRateable($0) })
        XCTAssertNil(RegionRating.rating(
            for: knife, results: [result("heat", 95), result("eggs", 95)]))
    }
}

/// Scoring, which must come from evidence rather than from asking a model for
/// a mark out of a hundred.
final class TrialScoreTests: XCTestCase {

    func testACleanRunScoresHigh() {
        XCTAssertGreaterThanOrEqual(
            TrialScore.score(outcomes: [.passed, .passed, .passed]), 85)
    }

    func testCorrectionsPullItDown() {
        let clean = TrialScore.score(outcomes: [.passed, .passed])
        let fixed = TrialScore.score(outcomes: [.passed, .corrected])
        XCTAssertLessThan(fixed, clean)
        XCTAssertGreaterThan(fixed, 50, "one correction is not a failure")
    }

    /// A hand on the blade is not a low score, it is a failure.
    func testASafetyStopIsNotMerelyALowScore() {
        let stopped = TrialScore.score(outcomes: [.passed, .passed, .stoppedForSafety])
        XCTAssertLessThan(stopped, 75, "this must not read as a pass")
    }

    /// Being sure of less is worth less. Saying 91 from a single glance would
    /// be inventing precision.
    func testThinEvidenceScoresLowerThanTheSameWorkSeenFully() {
        let seenAll = TrialScore.score(outcomes: [.passed, .passed, .passed, .passed])
        let seenOne = TrialScore.score(
            outcomes: [.passed, .inconclusive, .inconclusive, .inconclusive])
        XCTAssertLessThan(seenOne, seenAll)
    }

    /// Nothing seen is not a zero. A zero is a claim about the cooking; this is
    /// a claim about the pictures, and the caller has to treat it as unscored.
    func testNothingSeenIsNotJudged() {
        XCTAssertEqual(TrialScore.score(outcomes: [.inconclusive, .inconclusive]), 0)
    }

    func testItNeverLeavesTheScale() {
        for outcomes: [SkillAttemptOutcome] in [
            [.passed], [.stoppedForSafety], [.corrected, .corrected, .stoppedForSafety],
            Array(repeating: .passed, count: 20),
        ] {
            let score = TrialScore.score(outcomes: outcomes)
            XCTAssertTrue((0...100).contains(score), "\(score) is off the scale")
        }
    }
}

/// The recommendation, once a cook has shown what they are weak at.
@MainActor
final class WeaknessRecommendationTests: XCTestCase {

    private func trial(_ category: String, _ score: Int) -> TrialResult {
        TrialResult(skillID: "\(category).x", categoryID: category, score: score)
    }

    private func reader(_ trials: [TrialResult]) -> SkillsProgressReader {
        SkillsProgressReader(progress: [], trials: trials)
    }

    /// One bad afternoon is not a weakness. Without evidence this would yank a
    /// cook out of the region they are halfway through.
    func testItStaysQuietWithoutEnoughEvidence() {
        XCTAssertNil(reader([]).weakestDemonstratedRegion)
        // Rated, but only one region, so "worst" means nothing.
        XCTAssertNil(reader([trial("knife", 40), trial("knife", 42)])
            .weakestDemonstratedRegion)
    }

    /// Lowest is not the same as weak. A cook at 84, 86 and 88 has no weakness
    /// worth redirecting them over.
    func testBeingSlightlyLowestIsNotAWeakness() {
        let close = reader([
            trial("knife", 84), trial("knife", 84),
            trial("heat", 88), trial("heat", 88),
        ])
        XCTAssertNil(close.weakestDemonstratedRegion, "four points is not a weakness")
    }

    /// A real gap does pull the recommendation.
    func testAClearWeaknessPullsTheRecommendation() {
        let lopsided = reader([
            trial("knife", 92), trial("knife", 94),
            trial("heat", 58), trial("heat", 60),
        ])
        XCTAssertEqual(lopsided.weakestDemonstratedRegion, "heat")
    }

    /// And it never points at a region with nothing left to learn.
    func testItNeverPointsAtAFinishedRegion() {
        let everything = Set(SkillCatalog.allSkills.map(\.id))
        let done = SkillsProgressReader(
            progress: SkillCatalog.allSkills.map {
                SkillProgress(skillID: $0.id, learnedAt: .now)
            },
            trials: [
                trial("knife", 92), trial("knife", 94),
                trial("heat", 58), trial("heat", 60),
            ])
        XCTAssertEqual(done.learnedIDs.count, everything.count)
        XCTAssertNil(done.weakestDemonstratedRegion, "nothing left to send them to")
    }
}
