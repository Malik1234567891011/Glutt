import XCTest
@testable import Glutt

/// The promotion moment, which has to happen exactly once.
///
/// A rank is derived, so it is true on every redraw. Everything here exists to
/// stop that truth being announced more than once.
final class CookRankCeremonyTests: XCTestCase {

    private var store: UserDefaults!

    override func setUpWithError() throws {
        store = UserDefaults(suiteName: "ceremony.\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { store = nil }

    private func evidence(_ count: Int, credit: RatingEvidence.Credit = .clean,
                          weight: Double = 1.0) -> [RatingEvidence] {
        (0..<count).map {
            RatingEvidence(skillID: "s\($0)", categoryID: "knife", kind: .skillCheck,
                           credit: credit, weight: weight)
        }
    }

    /// Unranked has no promotion to announce, however much reading was done.
    func testUnrankedAnnouncesNothing() {
        XCTAssertNil(CookRankCeremony.pending(for: [], store: store))
        XCTAssertNil(CookRankCeremony.pending(for: evidence(2), store: store))
    }

    /// Placement is itself a promotion, and it fires.
    func testPlacementIsAPromotion() throws {
        let rank = try XCTUnwrap(CookRankCeremony.pending(for: evidence(3), store: store))
        XCTAssertFalse(rank.title.isEmpty)
    }

    /// The whole point. Reading does not consume it; recording does.
    func testItIsAnnouncedOnceAndOnlyOnce() throws {
        let rows = evidence(3)
        let first = try XCTUnwrap(CookRankCeremony.pending(for: rows, store: store))

        // Asking twice without recording still offers it, so a view can look
        // before it commits to drawing anything.
        XCTAssertNotNil(CookRankCeremony.pending(for: rows, store: store))

        CookRankCeremony.record(first, store: store)
        XCTAssertNil(CookRankCeremony.pending(for: rows, store: store),
                     "a promotion must never be announced a second time")
    }

    /// The bottom rank has floor 0, and a missing key reads as 0. Without an
    /// explicit presence check the very first promotion would be swallowed.
    func testTheBottomRankIsNotSwallowedByAnEmptyStore() throws {
        let bottom = try XCTUnwrap(CookRank.ladder.first)
        XCTAssertEqual(bottom.floor, 0, "this test exists because the floor is 0")

        // Bad enough to sit in the bottom rank. Three corrected checks are NOT
        // enough: they land around 996, which is Prep Cook II, and the first
        // draft of this test asserted otherwise and failed honestly.
        let rough = evidence(3, credit: .unsafe, weight: 5.0)
        let rank = try XCTUnwrap(CookRankCeremony.pending(for: rough, store: store))
        XCTAssertEqual(rank.floor, bottom.floor, "should be the bottom rank")

        CookRankCeremony.record(rank, store: store)
        XCTAssertNil(CookRankCeremony.pending(for: rough, store: store),
                     "floor 0 recorded must not read as never recorded")
    }

    /// Climbing further announces again.
    func testAHigherRankAnnouncesAgain() throws {
        let modest = evidence(3, credit: .corrected)
        let low = try XCTUnwrap(CookRankCeremony.pending(for: modest, store: store))
        CookRankCeremony.record(low, store: store)

        let strong = evidence(9, credit: .clean, weight: 5.0)
        let high = try XCTUnwrap(CookRankCeremony.pending(for: strong, store: store))
        XCTAssertGreaterThan(high.floor, low.floor)
    }

    /// Nobody is told they have been demoted by an app that watched them chop
    /// an onion. The number falling is honest and visible; narrating it is not.
    func testFallingBackDownIsNeverAnnounced() throws {
        let strong = evidence(9, credit: .clean, weight: 5.0)
        let high = try XCTUnwrap(CookRankCeremony.pending(for: strong, store: store))
        CookRankCeremony.record(high, store: store)

        XCTAssertNil(CookRankCeremony.pending(for: evidence(3, credit: .corrected), store: store))
        // And the mark itself never moves down.
        CookRankCeremony.record(CookRank.ladder[0], store: store)
        XCTAssertNil(CookRankCeremony.pending(for: evidence(3, credit: .corrected), store: store))
    }

    /// A fresh install must be able to be congratulated again.
    func testResetMakesPromotionsPossibleAgain() throws {
        let rank = try XCTUnwrap(CookRankCeremony.pending(for: evidence(3), store: store))
        CookRankCeremony.record(rank, store: store)
        XCTAssertNil(CookRankCeremony.pending(for: evidence(3), store: store))

        CookRankCeremony.reset(store: store)
        XCTAssertNotNil(CookRankCeremony.pending(for: evidence(3), store: store))
    }

    /// Every rank has its own sentence. A template repeated nine times reads
    /// like a template.
    func testEveryRankHasItsOwnLine() {
        let lines = CookRank.ladder.map(CookRankCeremony.line(for:))
        XCTAssertEqual(Set(lines).count, CookRank.ladder.count, "a rank is reusing another's line")
        for line in lines {
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("A new rank, earned on"), "fell through to the fallback")
        }
    }
}

/// The badge, which has to read as a ladder rather than nine of the same hat.
final class CookRankBadgeTests: XCTestCase {

    /// Every rank resolves to its own index, so the heights differ. If two
    /// ranks shared a floor the badge would silently draw duplicates.
    func testRanksAreDistinguishable() {
        let floors = CookRank.ladder.map(\.floor)
        XCTAssertEqual(Set(floors).count, floors.count)
    }

    /// Height is the whole signal, so it has to actually differ. Two ranks
    /// rendering at the same size would draw the same badge twice.
    func testHeightClimbsWithRank() {
        let sizes = CookRank.ladder.map { CookRankBadge(rank: $0).badgeHeight(in: 38) }
        XCTAssertEqual(sizes, sizes.sorted(), "the ladder must not go down")
        XCTAssertEqual(Set(sizes).count, sizes.count, "two ranks draw at the same height")
        XCTAssertGreaterThan(sizes.last! - sizes.first!, 12,
                             "top and bottom must be tellable apart at a glance")
    }
}
