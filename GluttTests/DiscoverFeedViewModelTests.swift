import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class DiscoverFeedViewModelTests: XCTestCase {
    private func video(_ id: String) -> DiscoverVideo {
        DiscoverVideo(videoId: id, title: "T-\(id)", creator: nil, thumbnailURL: nil, durationSeconds: nil)
    }

    func testSearchPopulatesQueueAndSetsLoaded() async {
        let deps = DiscoverFeedViewModel.Dependencies(
            search: { _, _ in DiscoverResponse(videos: [self.video("a"), self.video("b")], nextPageToken: nil) },
            suggested: { _ in DiscoverResponse(videos: [], nextPageToken: nil) },
            save: { v, _ in Recipe(title: v.title) }
        )
        let vm = DiscoverFeedViewModel(deps: deps)
        await vm.search("tofu")
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.videos.count, 2)
        XCTAssertEqual(vm.current?.videoId, "a")
    }

    func testEmptyResultsSetEmptyPhase() async {
        let deps = DiscoverFeedViewModel.Dependencies(
            search: { _, _ in DiscoverResponse(videos: [], nextPageToken: nil) },
            suggested: { _ in DiscoverResponse(videos: [], nextPageToken: nil) },
            save: { v, _ in Recipe(title: v.title) }
        )
        let vm = DiscoverFeedViewModel(deps: deps)
        await vm.search("asdfqwer")
        XCTAssertEqual(vm.phase, .empty)
    }

    func testShowNextFetchesNextPageNearEnd() async {
        var calls = 0
        let deps = DiscoverFeedViewModel.Dependencies(
            search: { _, token in
                calls += 1
                if token == nil {
                    return DiscoverResponse(videos: [self.video("a"), self.video("b")], nextPageToken: "P2")
                } else {
                    return DiscoverResponse(videos: [self.video("c"), self.video("d")], nextPageToken: nil)
                }
            },
            suggested: { _ in DiscoverResponse(videos: [], nextPageToken: nil) },
            save: { v, _ in Recipe(title: v.title) }
        )
        let vm = DiscoverFeedViewModel(deps: deps)
        await vm.search("pasta")            // page 1: a, b ; index 0
        await vm.showNext()                  // index 1 -> within 2 of end, token P2 -> fetch page 2
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(vm.videos.map(\.videoId), ["a", "b", "c", "d"])
        XCTAssertEqual(vm.current?.videoId, "b")
    }

    func testSaveMarksVideoSavedAndAdvances() async throws {
        let schema = Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let deps = DiscoverFeedViewModel.Dependencies(
            search: { _, _ in DiscoverResponse(videos: [self.video("a"), self.video("b")], nextPageToken: nil) },
            suggested: { _ in DiscoverResponse(videos: [], nextPageToken: nil) },
            save: { v, ctx in let r = Recipe(title: v.title); ctx.insert(r); return r }
        )
        let vm = DiscoverFeedViewModel(deps: deps)
        await vm.search("tofu")
        await vm.save(vm.current!, into: context)
        XCTAssertTrue(vm.savedVideoIDs.contains("a"))
        XCTAssertNil(vm.savingVideoID)
        XCTAssertEqual(vm.current?.videoId, "b")    // auto-advanced
    }
}
