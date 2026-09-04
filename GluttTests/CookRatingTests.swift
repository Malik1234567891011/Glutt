import SwiftData
import XCTest
@testable import Glutt

/// Cook Rating, which must mean "what Glutt has seen you do".
///
/// The product rule: lessons tell us what the user has learned, verified
/// cooking tells us what the user can do. These pin the second one.
final class CookRatingTests: XCTestCase {

    private func evidence(
        _ category: String,
        _ credit: RatingEvidence.Credit = .clean,
        kind: RatingEvidence.Kind = .skillCheck,
        weight: Double = 1.0,
        skill: String? = nil,
        daysAgo: Double = 0
    ) -> RatingEvidence {
        RatingEvidence(
            skillID: skill ?? "\(category).skill", categoryID: category,
            kind: kind, credit: credit, weight: weight,
            occurredAt: Date().addingTimeInterval(-daysAgo * 86_400))
    }

    // MARK: Unranked

    func testNobodyWatchedYetMeansUnranked() {
        XCTAssertNil(CookRating.rating(from: []))
        XCTAssertNil(CookRating.rating(from: [evidence("knife")]))
        XCTAssertNil(CookRating.rating(from: [evidence("knife"), evidence("heat")]))
    }

    /// Ordinary checks count toward placement. Requiring mastery trials made
    /// the rating unreachable: only five trials in the catalog can be scored
    /// and each sits behind three to five prerequisite lessons.
    func testOrdinaryChecksCanPlaceACook() {
        let placed = [evidence("knife", skill: "a"),
                      evidence("knife", skill: "b"),
                      evidence("heat", skill: "c")]
        XCTAssertNotNil(CookRating.rating(from: placed), "three verified checks is a placement")
    }

    /// And it says what earns one rather than only naming the state.
    func testUnrankedNamesTheWayOut() {
        XCTAssertEqual(CookRating.placementLine([]), "3 verified checks to place")
        XCTAssertEqual(
            CookRating.placementLine([evidence("knife"), evidence("heat")]),
            "1 verified check to place")
        XCTAssertTrue(CookRating.placementLine(
            [evidence("a"), evidence("b"), evidence("c")]).isEmpty, "placed, nothing to say")
    }

    /// A rating built on three narrow observations is not a picture of somebody
    /// and must not be presented as settled.
    func testTheFirstStretchIsProvisional() {
        let just = [evidence("knife", skill: "a"), evidence("knife", skill: "b"),
                    evidence("heat", skill: "c")]
        XCTAssertTrue(CookRating.isProvisional(just))

        let settled = (0..<9).map { evidence("knife", skill: "s\($0)") }
        XCTAssertFalse(CookRating.isProvisional(settled))
    }

    // MARK: Weighting

    /// A trial is worth several checks, because it is several criteria
    /// assessed together on technique that needs the earlier ones to work.
    func testATrialOutweighsAnOrdinaryCheck() {
        let checks = (0..<3).map { evidence("knife", kind: .skillCheck, weight: 1.0, skill: "c\($0)") }
        let withTrial = checks + [evidence("knife", kind: .masteryTrial, weight: 5.0, skill: "trial")]
        let withCheck = checks + [evidence("knife", kind: .skillCheck, weight: 1.0, skill: "extra")]
        XCTAssertGreaterThan(
            CookRating.rating(from: withTrial)!, CookRating.rating(from: withCheck)!,
            "a mastery trial has to move the needle more than another easy check")
    }

    func testHarderChecksAreWorthMore() {
        XCTAssertLessThan(
            EvidenceWeight.weight(for: skill(difficulty: .beginner)),
            EvidenceWeight.weight(for: skill(difficulty: .advanced)))
        XCTAssertLessThan(
            EvidenceWeight.weight(for: skill(difficulty: .advanced)),
            EvidenceWeight.weight(for: skill(difficulty: .beginner, challenge: true)))
    }

    private func skill(difficulty: SkillDifficulty, challenge: Bool = false) -> Skill {
        Skill(id: "x", categoryID: "knife", title: "X", shortDescription: "x",
              difficulty: difficulty, isChallenge: challenge)
    }

    /// The same easy check twenty times must not be a ladder.
    func testRepeatingOneCheckIsNotFarmable() {
        let varied = (0..<6).map { evidence("knife", skill: "s\($0)") }
        let farmed = (0..<6).map { _ in evidence("knife", skill: "same") }
        XCTAssertGreaterThan(
            CookRating.rating(from: varied)!, CookRating.rating(from: farmed)!,
            "six different techniques must beat one technique six times")

        // And the tail is worth almost nothing.
        XCTAssertLessThan(EvidenceWeight.repeatFactor(priorCount: 4), 0.1)
    }

    // MARK: Uncertainty is free

    /// The single most important rule: the model failing to see something is a
    /// fact about the photograph, never about the cook.
    func testUncertaintyProducesNoEvidenceAtAll() {
        XCTAssertNil(EvidenceWeight.credit(for: .inconclusive),
                     "could not see must write no row")
        XCTAssertNil(EvidenceWeight.credit(for: .wrongEquipment),
                     "the wrong knife says nothing about the cook")
        XCTAssertNotNil(EvidenceWeight.credit(for: .passed))
        XCTAssertNotNil(EvidenceWeight.credit(for: .corrected))
        XCTAssertNotNil(EvidenceWeight.credit(for: .stoppedForSafety))
    }

    /// Clean work climbs, corrections do not.
    func testCleanWorkClimbsAndCorrectionsDoNot() {
        let clean = (0..<4).map { evidence("knife", .clean, skill: "s\($0)") }
        let fixed = (0..<4).map { evidence("knife", .corrected, skill: "s\($0)") }
        XCTAssertGreaterThan(CookRating.rating(from: clean)!, CookRating.placementBase)
        XCTAssertLessThan(CookRating.rating(from: fixed)!, CookRating.placementBase)
    }

    // MARK: Ranks

    func testRanksClimbInOrder() {
        var last = -1
        for rank in CookRank.ladder {
            XCTAssertGreaterThan(rank.floor, last, "\(rank.title) overlaps the rank below")
            last = rank.floor
        }
        XCTAssertNil(CookRank.ladder.last?.ceiling)
    }

    func testARatingMapsToOneRank() {
        XCTAssertEqual(CookRank.rank(for: 1_284).title, "Line Cook II")
        XCTAssertEqual(CookRank.rank(for: 99_999).title, "Head Chef")
        XCTAssertEqual(CookRank.toNext(from: 1_284)?.rank.title, "Line Cook I")
        XCTAssertNil(CookRank.toNext(from: 5_000))
    }
}

/// The wall between learning and doing.
final class LessonsDoNotRateTests: XCTestCase {

    /// Finishing a lesson gives XP and must never move the rating. If reading
    /// could raise it, the rating would be a second XP bar and would mean
    /// nothing.
    func testMarkingALessonLearnedWritesNoEvidence() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Glutt/Features/Skills/SkillProgressStore.swift"),
            encoding: .utf8)
        guard let start = source.range(of: "static func markLearned") else {
            return XCTFail("markLearned moved")
        }
        let body = String(source[start.upperBound...].prefix(1600))
        XCTAssertFalse(
            body.contains("RatingEvidence("),
            "completing a lesson must not write rating evidence")
    }

    /// And evidence is only written where a check actually ran.
    func testOnlyTheCheckPathWritesEvidence() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        var writers: [String] = []
        for path in ["Glutt/Features/Skills", "Glutt/Services/Polly"] {
            let dir = root.appendingPathComponent(path)
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "swift" {
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                if text.contains("RatingEvidence(") { writers.append(file.lastPathComponent) }
            }
        }
        XCTAssertEqual(writers.sorted(), ["SkillPhotoCheck.swift"],
                       "evidence should only be written where a check was judged")
    }
}

/// Region standing, and the two regions that must never have one.
final class RegionRatingTests: XCTestCase {

    private func evidence(_ category: String, _ credit: RatingEvidence.Credit = .clean,
                          skill: String? = nil, daysAgo: Double = 0) -> RatingEvidence {
        RatingEvidence(
            skillID: skill ?? "\(category).skill", categoryID: category,
            kind: .skillCheck, credit: credit, weight: 1.0,
            occurredAt: Date().addingTimeInterval(-daysAgo * 86_400))
    }

    /// The integrity rule. You cannot photograph tasting as you go.
    func testRegionsWithNothingToMeasureAreNeverRated() {
        for id in ["flavor", "intuition"] {
            guard let category = SkillCatalog.categories.first(where: { $0.id == id }) else {
                return XCTFail("\(id) is missing from the catalog")
            }
            XCTAssertFalse(RegionRating.isRateable(category))
            let invented = (0..<6).map { _ in evidence(id) }
            XCTAssertNil(RegionRating.rating(for: category, evidence: invented))
        }
    }

    func testOneObservationIsNotARating() throws {
        let knife = try XCTUnwrap(SkillCatalog.categories.first { $0.id == "knife" })
        XCTAssertNil(RegionRating.rating(for: knife, evidence: [evidence("knife")]))
        XCTAssertNotNil(RegionRating.rating(
            for: knife, evidence: [evidence("knife", skill: "a"), evidence("knife", skill: "b")]))
    }

    /// A cook who was poor in January and good in March is good.
    func testRecentWorkCountsForMore() throws {
        let knife = try XCTUnwrap(SkillCatalog.categories.first { $0.id == "knife" })
        let improving = [evidence("knife", .clean, skill: "a", daysAgo: 0),
                         evidence("knife", .corrected, skill: "b", daysAgo: 60)]
        let declining = [evidence("knife", .corrected, skill: "a", daysAgo: 0),
                         evidence("knife", .clean, skill: "b", daysAgo: 60)]
        XCTAssertGreaterThan(
            RegionRating.rating(for: knife, evidence: improving)!,
            RegionRating.rating(for: knife, evidence: declining)!)
    }

    func testItOnlyCountsItsOwnRegion() throws {
        let knife = try XCTUnwrap(SkillCatalog.categories.first { $0.id == "knife" })
        XCTAssertNil(RegionRating.rating(
            for: knife, evidence: [evidence("heat", skill: "a"), evidence("eggs", skill: "b")]))
    }
}

/// The score, which is counted rather than guessed.
final class CountedScoreTests: XCTestCase {

    private let check = SkillVisualCheck.chefKnifeGrip

    private func assessment(_ readings: [String: String]) -> SkillVisualAssessment {
        SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.9),
            visibility: Dictionary(uniqueKeysWithValues:
                check.reportedVisibility.map { ($0.rawValue, .sufficient) }),
            overall: .ready, confidence: 0.9,
            observations: [readings, readings],
            toolPicture: 2)
    }

    /// Every authored criterion has a declared right answer, or it cannot be
    /// counted and quietly contributes nothing.
    func testTheKnifeGripDeclaresWhatCorrectMeans() {
        for observation in check.observations {
            XCTAssertNotNil(
                observation.correct,
                "\(observation.region.rawValue) has no right answer, so it can never be scored")
            XCTAssertTrue(
                observation.answers.contains(observation.correct ?? ""),
                "the right answer is not one of the offered answers")
            XCTAssertNotEqual(
                observation.correct, observation.cannotTell,
                "cannotTell can never be the right answer")
        }
    }

    /// A textbook pinch grip: thumb and index on the steel, bottom three on
    /// the handle.
    func testAPerfectGripScoresEverythingItCouldSee() throws {
        let counted = try XCTUnwrap(check.criteria(met: assessment([
            "thumb": "onBlade", "indexFinger": "onBlade", "remainingFingers": "onHandle",
        ])))
        XCTAssertEqual(counted.met, 3)
        XCTAssertEqual(counted.observable, 3)
    }

    func testOneThingWrongCostsExactlyOne() throws {
        let counted = try XCTUnwrap(check.criteria(met: assessment([
            "thumb": "onHandle", "indexFinger": "onBlade", "remainingFingers": "onHandle",
        ])))
        XCTAssertEqual(counted.met, 2)
        XCTAssertEqual(counted.observable, 3)
    }

    /// The rule the whole system rests on: a criterion nobody could place is
    /// in neither total. It cannot be met and it cannot be failed.
    func testWhatCouldNotBeSeenIsInNeitherTotal() throws {
        let counted = try XCTUnwrap(check.criteria(met: assessment([
            "thumb": "onBlade", "indexFinger": "cannotTell", "remainingFingers": "onHandle",
        ])))
        XCTAssertEqual(counted.met, 2)
        XCTAssertEqual(counted.observable, 2, "the hidden finger must not be counted against them")
    }

    /// And seeing nothing is not a zero, it is nothing to score.
    func testSeeingNothingIsNotAZero() {
        XCTAssertNil(check.criteria(met: assessment([
            "thumb": "cannotTell", "indexFinger": "cannotTell", "remainingFingers": "cannotTell",
        ])))
    }

    /// The score reaches the rating: 3 of 3 must be worth more than 2 of 3.
    func testABetterScoreIsWorthMoreToTheRating() {
        func evidence(met: Int, observable: Int) -> RatingEvidence {
            RatingEvidence(skillID: "knife.grip", categoryID: "knife", kind: .skillCheck,
                           credit: .clean, weight: 1.0,
                           criteriaMet: met, criteriaObservable: observable)
        }
        XCTAssertEqual(evidence(met: 3, observable: 3).score, 100)
        XCTAssertEqual(evidence(met: 2, observable: 3).score, 67)
        XCTAssertGreaterThan(
            evidence(met: 3, observable: 3).creditValue,
            evidence(met: 2, observable: 3).creditValue)
    }

    /// A hand on the blade is not a near miss, whatever the criteria said.
    func testASafetyFailureIsFlooredAtZero() {
        let unsafe = RatingEvidence(
            skillID: "knife.grip", categoryID: "knife", kind: .skillCheck,
            credit: .unsafe, weight: 1.0, criteriaMet: 2, criteriaObservable: 3)
        XCTAssertEqual(unsafe.creditValue, 0)
    }

    /// A check with no per-criterion questions falls back to the coarse
    /// outcome rather than inventing a count.
    func testAChecklessOfCriteriaFallsBack() {
        let coarse = RatingEvidence(
            skillID: "x", categoryID: "basics", kind: .skillCheck,
            credit: .clean, weight: 1.0)
        XCTAssertNil(coarse.score)
        XCTAssertNil(coarse.spokenScore)
        XCTAssertEqual(coarse.creditValue, 1.0)
    }
}

/// The authored criteria across the catalog.
///
/// A check whose observations are wrong is worse than one with none: it scores
/// people against something nobody meant.
final class AuthoredCriteriaTests: XCTestCase {

    private var checks: [(skill: Skill, check: SkillVisualCheck)] {
        SkillCatalog.allSkills.compactMap { skill in
            skill.visualCheck.map { (skill, $0) }
        }
    }

    /// Every question must have a right answer that is actually one of the
    /// answers offered, and it must never be the escape hatch.
    func testEveryQuestionHasAReachableRightAnswer() {
        for (skill, check) in checks {
            for observation in check.observations {
                guard let correct = observation.correct else { continue }
                XCTAssertTrue(
                    observation.answers.contains(correct),
                    "\(skill.id)/\(observation.id) is scored against \(correct), "
                    + "which is not one of \(observation.answers)")
                XCTAssertNotEqual(
                    correct, observation.cannotTell,
                    "\(skill.id)/\(observation.id) would score a cook for not being seen")
            }
        }
    }

    /// Ids have to be unique within a check, or two questions collide in the
    /// JSON and one silently overwrites the other.
    func testQuestionIdsAreUniqueWithinACheck() {
        for (skill, check) in checks {
            let ids = check.observations.map(\.id)
            XCTAssertEqual(
                Set(ids).count, ids.count,
                "\(skill.id) asks two questions under the same id: \(ids)")
        }
    }

    /// Every question must offer a way to say it could not be seen, or it is a
    /// forced choice and forced choices get guessed.
    func testEveryQuestionCanSayItCouldNotTell() {
        for (skill, check) in checks {
            for observation in check.observations {
                XCTAssertTrue(
                    observation.answers.contains(observation.cannotTell),
                    "\(skill.id)/\(observation.id) has no way to say it could not be seen")
            }
        }
    }

    /// The whole catalog is authored, not just the region I happened to start
    /// with. Every watchable check needs at least two scoreable criteria, or
    /// its score is binary and the coarse outcome would serve the cook better.
    ///
    /// One deliberate exception, named rather than skipped silently. A blanket
    /// "some checks are exempt" would let the next unauthored check hide
    /// behind it.
    func testEveryWatchableCheckIsAuthored() {
        // Judged against a target the cook names out loud before each egg, so
        // there is no fixed right answer to author. Scoring it would mean
        // inventing one and marking people wrong for hitting what they aimed
        // at.
        let judgedAgainstASpokenTarget = ["eggs.challenge"]

        for (skill, check) in checks where !judgedAgainstASpokenTarget.contains(skill.id) {
            let scoreable = check.observations.filter { $0.correct != nil }
            XCTAssertGreaterThanOrEqual(
                scoreable.count, SkillVisualCheck.minimumCountableCriteria,
                "\(skill.id) has \(scoreable.count) scoreable criteria, so it can never "
                + "produce a counted score")
        }
    }

    /// Regression: the count has to reach real skills, not just compile.
    func testTheCatalogActuallyProducesCountedScores() throws {
        let authored = checks.filter { $0.check.observations.contains { $0.correct != nil } }
        XCTAssertGreaterThan(
            authored.count, 40,
            "only \(authored.count) of \(checks.count) checks can be scored")
    }

    /// The decisive region must ask exactly one question.
    ///
    /// The standalone gate resolves it by region, so a second question in the
    /// same region would not break the build or fail loudly: it would quietly
    /// start asking about the wrong thing, and the most important gate in the
    /// check would go on returning a confident answer to a question nobody
    /// meant to ask.
    func testTheDecisiveRegionAsksOneQuestion() {
        for (skill, check) in checks {
            guard let region = check.decisiveRegion else { continue }
            let inRegion = check.observations.filter { $0.region == region }
            XCTAssertEqual(
                inRegion.count, 1,
                "\(skill.id) makes .\(region.rawValue) decisive but asks "
                + "\(inRegion.count) questions about it: \(inRegion.map(\.id))")
            XCTAssertNotNil(check.decisiveObservation, "\(skill.id) has no decisive question")
        }
    }

    /// One criterion is a pass or a fail, not a score, and reporting it as one
    /// is harsher than having authored nothing: zero out of one beats the
    /// `corrected` credit down to nothing.
    func testASingleCriterionIsNotAScore() throws {
        let check = SkillVisualCheck.chefKnifeGrip
        let readings = ["thumb": "onBlade", "indexFinger": "cannotTell",
                        "remainingFingers": "cannotTell"]
        let assessment = SkillVisualAssessment(
            equipment: .init(reading: "chef's knife", supported: true, confidence: 0.9),
            visibility: Dictionary(uniqueKeysWithValues:
                check.reportedVisibility.map { ($0.rawValue, .sufficient) }),
            overall: .ready, confidence: 0.9,
            observations: [readings, readings], toolPicture: 2)
        XCTAssertNil(
            check.criteria(met: assessment),
            "one criterion seen is not a score, it is a coin flip with a number on it")
    }
}
