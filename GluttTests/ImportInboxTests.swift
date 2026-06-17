import XCTest
@testable import Glutt

final class ImportedRecipeDraftCodableTests: XCTestCase {

    func testCodableRoundTripPreservesEverything() throws {
        var draft = ImportedRecipeDraft()
        draft.title = "Spicy Peanut Noodles"
        draft.summary = "Fast and fiery."
        draft.creator = "@cookfast"
        draft.sourceURL = "https://www.tiktok.com/@cookfast/video/1"
        draft.platform = .tiktok
        draft.caption = "recipe below"
        draft.servings = 3
        draft.prepMinutes = 5
        draft.cookMinutes = 15
        draft.ingredientLines = ["200g rice noodles", "2 tbsp peanut butter"]
        draft.stepTexts = ["Boil noodles.", "Toss with sauce."]
        draft.tags = ["quick", "spicy"]
        draft.calories = 520
        draft.proteinGrams = 18
        draft.issues = ["Cleaned up with AI — give it a once-over"]
        draft.stepsAreAISuggested = true

        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(ImportedRecipeDraft.self, from: data)

        XCTAssertEqual(decoded.id, draft.id)
        XCTAssertEqual(decoded.title, "Spicy Peanut Noodles")
        XCTAssertEqual(decoded.platform, .tiktok)
        XCTAssertEqual(decoded.ingredientLines, draft.ingredientLines)
        XCTAssertEqual(decoded.stepTexts, draft.stepTexts)
        XCTAssertEqual(decoded.servings, 3)
        XCTAssertEqual(decoded.calories, 520)
        XCTAssertEqual(decoded.issues, draft.issues)
        XCTAssertTrue(decoded.stepsAreAISuggested)
    }
}

final class ImportInboxTests: XCTestCase {

    private let suiteName = "test.glutt.importinbox"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func draft(_ title: String) -> ImportedRecipeDraft {
        var d = ImportedRecipeDraft()
        d.title = title
        d.ingredientLines = ["1 thing"]
        return d
    }

    func testAppendThenDrainReturnsItemsInOrderThenEmpties() {
        let inbox = ImportInbox(defaults: defaults)
        inbox.append(draft("First"))
        inbox.append(draft("Second"))

        let drained = inbox.drain()
        XCTAssertEqual(drained.map(\.title), ["First", "Second"])

        // Draining a second time yields nothing.
        XCTAssertTrue(inbox.drain().isEmpty)
    }

    func testDrainOnEmptyInboxReturnsEmpty() {
        XCTAssertTrue(ImportInbox(defaults: defaults).drain().isEmpty)
    }

    func testCorruptDataDrainsToEmptyAndClears() {
        defaults.set(Data("not json".utf8), forKey: "importInboxItems")
        let inbox = ImportInbox(defaults: defaults)
        XCTAssertTrue(inbox.drain().isEmpty)
        XCTAssertNil(defaults.data(forKey: "importInboxItems"))
    }
}
