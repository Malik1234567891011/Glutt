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
    private func deps(
        daily: @escaping () async throws -> PlatesResponse,
        seed: @escaping () -> PlatesResponse = { PlatesResponse(deckTitle: nil, recipes: [], nextPageToken: nil) },
        cache: @escaping () -> PlatesResponse? = { nil }
    ) -> PlatesFeedViewModel.Dependencies {
        PlatesFeedViewModel.Dependencies(
            daily: daily,
            search: { _, _ in PlatesResponse(deckTitle: nil, recipes: [], nextPageToken: nil) },
            save: { c, ctx in let r = Recipe(title: c.title); ctx.insert(r); return r },
            seed: seed,
            cachedDeck: cache,
            storeDeck: { _ in }
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
}
