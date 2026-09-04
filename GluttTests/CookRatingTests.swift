import SwiftData
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

/// The wiring, which failed silently once and would have shipped.
///
/// An edit that was meant to pass trials into the reader never applied because
/// the whitespace it matched on had changed. Everything still compiled, because
/// `trials` defaults to empty and every rating call legitimately returns nil for
/// a cook with no trials. The feature was simply dead: no rating, no region
/// scores, no personal bests, whatever the database held.
@MainActor
final class ReaderWiringTests: XCTestCase {

    private func trial(_ category: String, _ score: Int) -> TrialResult {
        TrialResult(skillID: "\(category).x", categoryID: category, score: score)
    }

    /// The reader must actually use what it is handed. A reader given trials
    /// and reporting nothing is the bug that shipped.
    func testAReaderGivenTrialsUsesThem() {
        let trials = [trial("knife", 88), trial("knife", 90),
                      trial("heat", 84), trial("eggs", 86)]
        let reader = SkillsProgressReader(progress: [], trials: trials)

        XCTAssertEqual(reader.trials.count, 4)
        XCTAssertNotNil(reader.cookRating, "four trials across three regions is placed")
        XCTAssertNotNil(reader.cookRank)
    }

    func testRegionRatingsComeThroughTheReader() throws {
        let knife = try XCTUnwrap(SkillCatalog.categories.first { $0.id == "knife" })
        // Explicit timestamps, because the weighting is by recency and the
        // first draft of this gave both trials `.now`. They sorted arbitrarily
        // and the expected value flipped between 83 and 87 depending on which
        // landed first, which is a test that would have failed at random on
        // somebody else's machine.
        let reader = SkillsProgressReader(progress: [], trials: [
            TrialResult(skillID: "knife.x", categoryID: "knife", score: 90,
                        finishedAt: Date()),
            TrialResult(skillID: "knife.x", categoryID: "knife", score: 80,
                        finishedAt: Date().addingTimeInterval(-86_400)),
        ])
        // (90 × 1 + 80 × 0.5) / 1.5, the newer result carrying twice the weight.
        XCTAssertEqual(reader.rating(for: knife), 87, "recent weighted, not a plain mean")
    }

    func testPersonalBestsComeThroughTheReader() {
        let reader = SkillsProgressReader(progress: [], trials: [
            TrialResult(skillID: "knife.challenge-mirepoix", categoryID: "knife", score: 74),
            TrialResult(skillID: "knife.challenge-mirepoix", categoryID: "knife", score: 91),
            TrialResult(skillID: "eggs.challenge", categoryID: "eggs", score: 66),
        ])
        XCTAssertEqual(reader.personalBest(for: "knife.challenge-mirepoix"), 91, "the best, not the last")
        XCTAssertEqual(reader.personalBest(for: "eggs.challenge"), 66)
        XCTAssertNil(reader.personalBest(for: "meat.challenge-steak"), "never attempted")
    }

    /// And an empty reader stays honest rather than inventing a starting number.
    func testAnEmptyReaderIsUnranked() {
        let reader = SkillsProgressReader(progress: [], trials: [])
        XCTAssertNil(reader.cookRating)
        XCTAssertNil(reader.cookRank)
    }
}

/// Placement has to be reachable with the content that actually exists.
final class PlacementReachabilityTests: XCTestCase {

    /// Only some mastery trials carry a visual check, and only those can be
    /// scored. Asking for more placements than there are scoreable trials makes
    /// the whole rating unreachable, which is what happened: placement wanted
    /// four when the catalog holds five, so a cook had to complete eighty per
    /// cent of every trial in the app before seeing a number.
    func testPlacementIsReachableFromTheCatalogAsItStands() {
        let scoreable = SkillCatalog.masteryTrials.filter { $0.visualCheck != nil }
        XCTAssertGreaterThan(scoreable.count, 0, "nothing can be scored at all")

        let regions = Set(scoreable.map(\.categoryID))
        XCTAssertGreaterThanOrEqual(
            regions.count, CookRating.regionsToPlace,
            "placement spans \(CookRating.regionsToPlace) regions but only "
            + "\(regions.count) have a scoreable trial")

        // Retries count, so the bar is trials rather than distinct trials. It
        // still must not ask for most of the catalog before saying anything.
        XCTAssertLessThanOrEqual(
            CookRating.trialsToPlace, scoreable.count,
            "placement asks for \(CookRating.trialsToPlace) of \(scoreable.count) scoreable trials")
    }

    /// Unranked has to say what to do about it, in every state.
    func testUnrankedAlwaysNamesTheWayOut() {
        let states: [[TrialResult]] = [
            [],
            [TrialResult(skillID: "a", categoryID: "knife", score: 80)],
            (0..<5).map { _ in TrialResult(skillID: "a", categoryID: "knife", score: 80) },
        ]
        for trials in states {
            let line = CookRating.placementLine(trials)
            XCTAssertTrue(line.hasPrefix("Unranked"))
            XCTAssertTrue(line.contains("·"), "a bare 'Unranked' is a dead end: \(line)")
            XCTAssertTrue(line.localizedCaseInsensitiveContains("trial"),
                          "it has to name what earns a rating: \(line)")
        }
    }
}

/// Self-certifying a checkable skill, which must not be possible in a shipped
/// build.
final class SelfCertificationTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(path),
            encoding: .utf8)
    }

    /// "Mark it anyway" is a testing affordance and nothing else. Left in a
    /// release build a cook could mark every checkable skill learned without
    /// ever showing one, and "demonstrated" would mean nothing.
    ///
    /// Asserted on the compile guard rather than on a comment, because a
    /// comment saying "remove before shipping" is how things ship.
    func testTheBypassIsCompiledOutOfReleaseBuilds() throws {
        let view = try source("Glutt/Features/Skills/SkillLessonView.swift")
        guard let range = view.range(of: "Mark it anyway") else {
            // Fine: it has been removed entirely, which is the end state.
            return
        }
        let before = view[..<range.lowerBound]
        guard let guardStart = before.range(of: "#if DEBUG", options: .backwards) else {
            return XCTFail("the bypass is not behind a compile guard")
        }
        // And the guard must still be open at that point.
        let between = before[guardStart.upperBound...]
        XCTAssertFalse(
            between.contains("#endif"),
            "the DEBUG guard closes before the bypass, so it would ship")
    }

    /// A checkable skill still has to be reachable for somebody who genuinely
    /// knows it: the offer to show her is always there.
    func testTheHonestPathIsAlwaysOffered() throws {
        let view = try source("Glutt/Features/Skills/SkillLessonView.swift")
        XCTAssertTrue(view.contains("Show me instead"))
    }

    /// The reset is a testing tool too, and must not be reachable in a release
    /// build or by tapping anything.
    func testTheSkillResetCannotFireInARealBuild() throws {
        let store = try source("Glutt/Features/Skills/SkillProgressStore.swift")
        guard let range = store.range(of: "GLUTT_RESET_SKILLS") else {
            return XCTFail("the reset hook moved")
        }
        let before = store[..<range.lowerBound]
        guard let guardStart = before.range(of: "#if DEBUG", options: .backwards) else {
            return XCTFail("the reset is not behind a compile guard")
        }
        XCTAssertFalse(
            before[guardStart.upperBound...].contains("#endif"),
            "the DEBUG guard closes before the reset, so it would ship")
    }
}

/// The reset, tested where its effect can actually be observed.
///
/// The device console does not carry the app's debug log, so "it launched" is
/// not evidence that it reset. This exercises the same deletes against a real
/// in-memory store.
@MainActor
final class SkillResetTests: XCTestCase {

    private func loadedContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SkillProgress.self, SkillAttempt.self, TrialResult.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(SkillProgress(skillID: "knife.grip", learnedAt: .now, xpAwarded: 20))
        context.insert(SkillProgress(skillID: "eggs.crack", learnedAt: .now, xpAwarded: 20))
        context.insert(SkillAttempt(
            skillID: "knife.grip", checkID: "knife.grip.pinch", startedAt: .now,
            seconds: 3, outcome: .passed, note: "ok"))
        context.insert(TrialResult(skillID: "knife.challenge-mirepoix",
                                   categoryID: "knife", score: 88))
        try context.save()
        return context
    }

    /// Everything Skills owns goes, so level, XP, ratings and bests all start
    /// from nothing.
    func testItClearsEverythingSkillsOwns() throws {
        let context = try loadedContext()
        XCTAssertEqual(try context.fetch(FetchDescriptor<SkillProgress>()).count, 2)

        // The same three deletes the reset performs.
        try context.delete(model: SkillProgress.self)
        try context.delete(model: SkillAttempt.self)
        try context.delete(model: TrialResult.self)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<SkillProgress>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SkillAttempt>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TrialResult>()).isEmpty)

        // And a reader over the empty store reads as a brand new cook.
        let fresh = SkillsProgressReader(progress: [], trials: [])
        XCTAssertEqual(fresh.learnedCount, 0)
        XCTAssertEqual(fresh.levelProgress.level, 1)
        XCTAssertNil(fresh.cookRating)
        XCTAssertEqual(CookRating.placementLine([]), "Unranked · pass a trial to start")
    }
}
