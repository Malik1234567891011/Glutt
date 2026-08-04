import XCTest
@testable import Glutt

final class PlatesSeenStoreTests: XCTestCase {
    private func store() -> UserDefaults {
        let d = UserDefaults(suiteName: "plates.seen.test")!
        d.removePersistentDomain(forName: "plates.seen.test")
        return d
    }

    func testRecordsAndReadsBack() {
        let s = store()
        PlatesSeenStore.record("spoonacular:1", store: s)
        PlatesSeenStore.record(["spoonacular:2", "spoonacular:3"], store: s)
        XCTAssertEqual(
            PlatesSeenStore.ids(store: s),
            ["spoonacular:1", "spoonacular:2", "spoonacular:3"])
    }

    func testRecordingTwiceDoesNotGrowTheList() {
        let s = store()
        PlatesSeenStore.record("a", store: s)
        PlatesSeenStore.record("a", store: s)
        XCTAssertEqual(s.stringArray(forKey: "plates.seen.ids")?.count, 1)
    }

    func testUndoForgets() {
        let s = store()
        PlatesSeenStore.record(["a", "b"], store: s)
        PlatesSeenStore.forget("a", store: s)
        XCTAssertEqual(PlatesSeenStore.ids(store: s), ["b"])
    }

    /// Oldest first, so a cook who swipes for a year starts seeing the very
    /// earliest rejects again rather than the ones they just turned down.
    func testOldestFallOffTheEndAtCapacity() {
        let s = store()
        let ids = (0..<(PlatesSeenStore.capacity + 10)).map { "id-\($0)" }
        PlatesSeenStore.record(ids, store: s)
        let kept = PlatesSeenStore.ids(store: s)
        XCTAssertEqual(kept.count, PlatesSeenStore.capacity)
        XCTAssertFalse(kept.contains("id-0"))
        XCTAssertTrue(kept.contains("id-\(PlatesSeenStore.capacity + 9)"))
    }

    func testBlankIDIsIgnored() {
        let s = store()
        PlatesSeenStore.record("", store: s)
        XCTAssertTrue(PlatesSeenStore.ids(store: s).isEmpty)
    }
}
