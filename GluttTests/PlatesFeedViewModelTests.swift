import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PlatesFeedViewModelTests: XCTestCase {
    private func card(_ id: String) -> PlateCard {
        let json = #"{ "id": "\#(id)", "title": "T-\#(id)", "source": "spoonacular", "sourceURL": "https://x/\#(id)", "tags": [], "dietFlags": [], "ingredients": [], "steps": [] }"#
        return try! JSONDecoder().decode(PlateCard.self, from: Data(json.utf8))
    }
    private func resp(_ ids: [String]) -> PlatesResponse {
        PlatesResponse(deckTitle: "Today's Plate", recipes: ids.map(card), nextPageToken: nil)
    }
    private func resp(_ ids: [String], next: String?) -> PlatesResponse {
        PlatesResponse(deckTitle: "Today's Plate", recipes: ids.map(card), nextPageToken: next)
    }
    private func deps(
        daily: @escaping () async throws -> PlatesResponse,
        seed: @escaping () -> PlatesResponse = { PlatesResponse(deckTitle: nil, recipes: [], nextPageToken: nil) },
        cache: @escaping () -> PlatesResponse? = { nil },
        feed: @escaping (String?) async throws -> PlatesResponse = { _ in
            PlatesResponse(deckTitle: nil, recipes: [], nextPageToken: nil)
        },
        seen: @escaping () -> Set<String> = { [] },
        recordSeen: @escaping (String) -> Void = { _ in },
        forgetSeen: @escaping (String) -> Void = { _ in },
        saveCard: @escaping (PlateCard, ModelContext) async throws -> Recipe = { c, ctx in
            let r = Recipe(title: c.title); ctx.insert(r); return r
        }
    ) -> PlatesFeedViewModel.Dependencies {
        PlatesFeedViewModel.Dependencies(
            daily: daily,
            search: { _, _ in PlatesResponse(deckTitle: nil, recipes: [], nextPageToken: nil) },
            save: saveCard,
            seed: seed,
            cachedDeck: cache,
            storeDeck: { _ in },
            feed: feed,
            seenIDs: seen,
            recordSeen: recordSeen,
            forgetSeen: forgetSeen,
            // Identity, so every assertion below is about filtering rather than
            // about which way the real shuffle happened to fall.
            shuffle: { $0 }
        )
    }

    func testLoadDailyPopulatesAndFilters() async {
        let vm = PlatesFeedViewModel(deps: deps(daily: { self.resp(["a", "b"]) }))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: ["https://x/a"])
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.recipes.map(\.id), ["b"])  // "a" already saved → filtered
        XCTAssertEqual(vm.current?.id, "b")
    }

    func testLoadDailyFallsBackToSeedOnFailure() async {
        struct Boom: Error {}
        let vm = PlatesFeedViewModel(deps: deps(daily: { throw Boom() }, seed: { self.resp(["s1"]) }))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.recipes.map(\.id), ["s1"])
    }

    func testLoadDailyUsesCacheWhenPresent() async {
        var dailyCalls = 0
        let vm = PlatesFeedViewModel(deps: deps(
            daily: { dailyCalls += 1; return self.resp(["net"]) },
            cache: { self.resp(["cached"]) }
        ))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        XCTAssertEqual(vm.recipes.map(\.id), ["cached"])
        XCTAssertEqual(dailyCalls, 0, "cached deck must not hit the network")
    }

    func testSaveMarksAndAdvances() async throws {
        let container = try ModelContainer(for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self]),
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let vm = PlatesFeedViewModel(deps: deps(daily: { self.resp(["a", "b"]) }))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        await vm.save(vm.current!, into: container.mainContext)
        XCTAssertTrue(vm.savedIDs.contains("a"))
        XCTAssertEqual(vm.current?.id, "b")
    }

    func testSkipAdvancesAndRecords() async {
        let vm = PlatesFeedViewModel(deps: deps(daily: { self.resp(["a", "b"]) }))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        vm.skip(vm.current!)
        XCTAssertTrue(vm.skippedIDs.contains("a"))
        XCTAssertEqual(vm.current?.id, "b")
    }

    func testEmptyAfterFilterSetsEmpty() async {
        let vm = PlatesFeedViewModel(deps: deps(daily: { self.resp(["a"]) }))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: ["https://x/a"])
        XCTAssertEqual(vm.phase, .empty)
    }

    /// The whole point of remembering swipes: a recipe rejected last week must
    /// not be the first card of today's deck.
    func testCardsJudgedInAnEarlierSessionDoNotComeBack() async {
        let vm = PlatesFeedViewModel(deps: deps(
            daily: { self.resp(["a", "b", "c"]) },
            seen: { ["a", "c"] }
        ))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        XCTAssertEqual(vm.recipes.map(\.id), ["b"])
    }

    func testSkipAndSaveArePersistedForNextLaunch() async throws {
        let container = try ModelContainer(
            for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        var recorded: [String] = []
        let vm = PlatesFeedViewModel(deps: deps(
            daily: { self.resp(["a", "b"]) },
            recordSeen: { recorded.append($0) }
        ))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        vm.skip(vm.current!)
        await vm.save(vm.current!, into: container.mainContext)
        XCTAssertEqual(recorded, ["a", "b"])
    }

    /// A cook who swipes daily will routinely open onto a page they have already
    /// cleared. That must page forward, not dead-end on the empty state.
    func testAFullyJudgedFirstPagePagesForwardInsteadOfShowingEmpty() async {
        let vm = PlatesFeedViewModel(deps: deps(
            daily: { self.resp(["a", "b"], next: "1") },
            feed: { _ in self.resp(["c"], next: "2") },
            seen: { ["a", "b"] }
        ))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.recipes.map(\.id), ["c"])
    }

    /// Same, from the local day cache — that path returned early and never got
    /// the chance to page forward.
    func testAFullyJudgedCachedPageAlsoPagesForward() async {
        let vm = PlatesFeedViewModel(deps: deps(
            daily: { self.resp([]) },
            cache: { self.resp(["a"], next: "1") },
            feed: { _ in self.resp(["c"], next: "2") },
            seen: { ["a"] }
        ))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        XCTAssertEqual(vm.recipes.map(\.id), ["c"])
    }

    /// The deck has to move the instant the card flies off, not when SwiftData
    /// finishes. That gap is what let the incoming card render at the outgoing
    /// card's offset for a frame, which reads as the last recipe flickering back.
    func testAcceptingACardAdvancesWithoutWaitingForTheWrite() async {
        let vm = PlatesFeedViewModel(deps: deps(daily: { self.resp(["a", "b"]) }))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        vm.acceptSavedCard(vm.current!)
        XCTAssertEqual(vm.current?.id, "b")
        XCTAssertTrue(vm.savedIDs.contains("a"))
    }

    func testAFailedWriteUnmarksTheCardButDoesNotRewindTheDeck() async throws {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "no disk" } }
        let container = try ModelContainer(
            for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        var forgotten: [String] = []
        let vm = PlatesFeedViewModel(deps: deps(
            daily: { self.resp(["a", "b"]) },
            forgetSeen: { forgotten.append($0) },
            saveCard: { _, _ in throw Boom() }
        ))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        let card = vm.current!
        vm.acceptSavedCard(card)
        await vm.persistSave(card, into: container.mainContext)
        XCTAssertFalse(vm.savedIDs.contains("a"))
        XCTAssertEqual(forgotten, ["a"], "undo has to be able to find it again")
        XCTAssertEqual(vm.current?.id, "b", "the deck must not jump backwards under them")
        XCTAssertNotNil(vm.saveError)
    }

    /// `sort=random` upstream can hand the same recipe back on two pages.
    func testARecipeRepeatedAcrossPagesIsNotDealtTwice() async {
        let vm = PlatesFeedViewModel(deps: deps(
            daily: { self.resp(["a", "b"], next: "1") },
            feed: { _ in self.resp(["b", "c"], next: "2") }
        ))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        await vm.loadMoreIfNeeded(currentIndex: 0)
        XCTAssertEqual(vm.recipes.map(\.id), ["a", "b", "c"])
    }
}
