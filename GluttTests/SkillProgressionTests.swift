import XCTest
@testable import Glutt

/// Levels, recommendation and the streak. All pure, so these run against the
/// real catalog without a store.
final class SkillProgressionTests: XCTestCase {

    // MARK: - Levels

    func testEverybodyStartsAtLevelOne() {
        XCTAssertEqual(SkillProgression.level(forXP: 0), 1)
        XCTAssertEqual(SkillProgression.level(forXP: 1), 1)
    }

    func testLevelTwoArrivesAtTheFirstLevelCost() {
        let cost = SkillProgression.xpToClear(level: 1)
        XCTAssertEqual(SkillProgression.level(forXP: cost - 1), 1)
        XCTAssertEqual(SkillProgression.level(forXP: cost), 2)
    }

    func testEachLevelCostsMoreThanTheLast() {
        for level in 1..<10 {
            XCTAssertGreaterThan(
                SkillProgression.xpToClear(level: level + 1),
                SkillProgression.xpToClear(level: level)
            )
        }
    }

    func testLevelProgressAgreesWithLevel() {
        for xp in stride(from: 0, through: 2000, by: 37) {
            let progress = SkillProgression.levelProgress(forXP: xp)
            XCTAssertEqual(progress.level, SkillProgression.level(forXP: xp), "at \(xp) xp")
            XCTAssertGreaterThanOrEqual(progress.into, 0)
            XCTAssertLessThan(progress.into, progress.needed, "at \(xp) xp the bar would be full or overflowing")
        }
    }

    /// A corrupt or absurd value must not spin the level loop.
    func testAbsurdXPTerminatesAtTheCeiling() {
        XCTAssertLessThanOrEqual(SkillProgression.level(forXP: .max / 2), SkillProgression.maxLevel)
        XCTAssertEqual(SkillProgression.level(forXP: -500), 1)
    }

    // MARK: - Prerequisites are advice, not gates

    func testUnmetPrerequisitesAreReportedButNeverBlock() {
        // "Dice an Onion" needs the dice and the claw grip.
        guard let onion = SkillCatalog.skill("knife.dice-onion") else { return XCTFail("missing skill") }
        let unmet = SkillProgression.unmetPrerequisites(for: onion, learnedIDs: [])
        XCTAssertFalse(unmet.isEmpty)
        XCTAssertFalse(SkillProgression.prerequisitesMet(for: onion, learnedIDs: []))

        // Nothing in this type refuses access. The lesson screen shows the list
        // and lets the cook carry on, per section 7 of the brief.
        let met = SkillProgression.prerequisitesMet(
            for: onion,
            learnedIDs: Set(onion.prerequisiteIDs)
        )
        XCTAssertTrue(met)
    }

    // MARK: - Recommendation

    func testAFreshCookIsPointedAtSomethingWithNoPrerequisites() {
        guard let first = SkillProgression.recommended(learnedIDs: []) else {
            return XCTFail("a new cook must be given somewhere to start")
        }
        XCTAssertTrue(first.prerequisiteIDs.isEmpty)
        XCTAssertTrue(first.isAuthored, "never recommend a skill with nothing to read")
    }

    func testRecommendationNeverPointsAtSomethingAlreadyLearned() {
        var learned: Set<String> = []
        for _ in 0..<25 {
            guard let next = SkillProgression.recommended(learnedIDs: learned) else { break }
            XCTAssertFalse(learned.contains(next.id), "recommended \(next.id) twice")
            learned.insert(next.id)
        }
    }

    func testRecommendationOnlyOffersSkillsWhosePrerequisitesAreMet() {
        var learned: Set<String> = []
        for _ in 0..<25 {
            guard let next = SkillProgression.recommended(learnedIDs: learned) else { break }
            XCTAssertTrue(
                SkillProgression.prerequisitesMet(for: next, learnedIDs: learned),
                "\(next.id) was recommended before its prerequisites"
            )
            learned.insert(next.id)
        }
    }

    func testRecommendationNeverOffersAnUnwrittenSkill() {
        var learned: Set<String> = []
        for _ in 0..<40 {
            guard let next = SkillProgression.recommended(learnedIDs: learned) else { break }
            XCTAssertTrue(next.isAuthored, "\(next.id) has no lesson and should not be recommended")
            learned.insert(next.id)
        }
    }

    func testFinishingASkillKeepsYouInTheSameRegionWhenItCan() {
        guard let grip = SkillCatalog.skill("knife.grip") else { return XCTFail("missing skill") }
        let next = SkillProgression.next(after: grip, learnedIDs: ["knife.grip"])
        XCTAssertEqual(next?.categoryID, "knife",
                       "after a knife skill the map should keep going in knives")
    }

    func testEveryWrittenSkillIsReachableByFollowingRecommendations() {
        // The strongest guarantee the map can offer: a cook who only ever taps
        // what Glutt suggests eventually sees all of it.
        var learned: Set<String> = []
        var guard_ = 0
        while let next = SkillProgression.recommended(learnedIDs: learned), guard_ < 500 {
            learned.insert(next.id)
            guard_ += 1
        }
        let authored = Set(SkillCatalog.authoredSkills.map(\.id))
        XCTAssertTrue(authored.isSubset(of: learned),
                      "unreachable: \(authored.subtracting(learned).sorted())")
    }

    // MARK: - Counting

    func testCategoryCountsOnlyCountThatCategory() {
        guard let knife = SkillCatalog.category("knife") else { return XCTFail("missing category") }
        let learned: Set<String> = ["knife.grip", "knife.claw", "basics.mise-en-place"]
        XCTAssertEqual(SkillProgression.learnedCount(in: knife, learnedIDs: learned), 2)
    }

    func testTotalXPIgnoresSkillsThatWereOpenedButNotFinished() {
        let finished = SkillProgress(skillID: "a", learnedAt: .now, xpAwarded: 20)
        let opened = SkillProgress(skillID: "b", learnedAt: nil, xpAwarded: 20)
        XCTAssertEqual(SkillProgression.totalXP(learned: [finished, opened]), 20)
    }

    // MARK: - State

    func testAnUnwrittenSkillReadsAsComingSoonEvenIfRecommended() {
        guard let unwritten = SkillCatalog.skill("eggs.poached") else { return XCTFail("missing skill") }
        let state = SkillProgression.state(
            for: unwritten,
            learnedIDs: [],
            inProgressIDs: [],
            recommendedID: unwritten.id
        )
        XCTAssertEqual(state, .comingSoon)
    }

    func testLearnedBeatsEveryOtherState() {
        guard let skill = SkillCatalog.skill("knife.grip") else { return XCTFail("missing skill") }
        let state = SkillProgression.state(
            for: skill,
            learnedIDs: [skill.id],
            inProgressIDs: [skill.id],
            recommendedID: skill.id
        )
        XCTAssertEqual(state, .learned)
    }

    // MARK: - Streak

    func testStreakStartsAtZeroAndBecomesOneOnTheFirstSkill() {
        let store = freshStore()
        XCTAssertEqual(SkillStreak.current(today: day(0), store: store), 0)
        XCTAssertEqual(SkillStreak.recordLearned(today: day(0), store: store), 1)
        XCTAssertEqual(SkillStreak.current(today: day(0), store: store), 1)
    }

    func testSeveralSkillsInOneDayCountOnce() {
        let store = freshStore()
        SkillStreak.recordLearned(today: day(0), store: store)
        SkillStreak.recordLearned(today: day(0), store: store)
        XCTAssertEqual(SkillStreak.recordLearned(today: day(0), store: store), 1)
    }

    func testConsecutiveDaysBuildTheStreak() {
        let store = freshStore()
        SkillStreak.recordLearned(today: day(0), store: store)
        SkillStreak.recordLearned(today: day(1), store: store)
        XCTAssertEqual(SkillStreak.recordLearned(today: day(2), store: store), 3)
    }

    func testMissingADayBreaksIt() {
        let store = freshStore()
        SkillStreak.recordLearned(today: day(0), store: store)
        SkillStreak.recordLearned(today: day(1), store: store)
        XCTAssertEqual(SkillStreak.recordLearned(today: day(3), store: store), 1)
    }

    /// The one that matters most: a stale streak must read as zero rather than
    /// showing someone a 7 they lost weeks ago.
    func testAStaleStreakReadsAsZeroWithoutBeingRecorded() {
        let store = freshStore()
        SkillStreak.recordLearned(today: day(0), store: store)
        XCTAssertEqual(SkillStreak.current(today: day(1), store: store), 1, "yesterday still counts")
        XCTAssertEqual(SkillStreak.current(today: day(2), store: store), 0, "two days on, it is gone")
    }

    func testNeedsTodayFlipsOnceTodayIsCounted() {
        let store = freshStore()
        XCTAssertTrue(SkillStreak.needsTodayToContinue(today: day(0), store: store))
        SkillStreak.recordLearned(today: day(0), store: store)
        XCTAssertFalse(SkillStreak.needsTodayToContinue(today: day(0), store: store))
    }

    // MARK: - Helpers

    private var suiteName = ""

    private func freshStore() -> UserDefaults {
        suiteName = "SkillProgressionTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        if !suiteName.isEmpty {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    /// Fixed dates so the tests never depend on when they run.
    private func day(_ offset: Int) -> Date {
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return Calendar.current.date(byAdding: .day, value: offset, to: base) ?? base
    }
}
