import SwiftData
import XCTest
@testable import Glutt

@MainActor
final class ImportInboxDrainerTests: XCTestCase {

    private let suiteName = "test.glutt.drainer"
    private var defaults: UserDefaults!
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Recipe.self, configurations: config)
        context = container.mainContext
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func makeDraft(title: String) -> ImportedRecipeDraft {
        var draft = ImportedRecipeDraft()
        draft.title = title
        draft.ingredientLines = ["1 cup flour", "2 eggs"]
        draft.stepTexts = ["Mix ingredients.", "Bake for 30 minutes."]
        return draft
    }

    // MARK: - Empty inbox

    func testDrainEmptyInboxReturnsEmptyMap() {
        let inbox = ImportInbox(defaults: defaults)
        let map = ImportInboxDrainer.drain(inbox, into: context)
        XCTAssertTrue(map.isEmpty)
    }

    // MARK: - Two recipes: map has correct count and permanent ids

    func testDrainTwoDraftsReturnsTwoEntriesWithResolvablePermanentIDs() throws {
        let inbox = ImportInbox(defaults: defaults)
        let draft1 = makeDraft(title: "Pasta Primavera")
        let draft2 = makeDraft(title: "Lemon Tart")
        inbox.append(draft1)
        inbox.append(draft2)

        let map = ImportInboxDrainer.drain(inbox, into: context)

        XCTAssertEqual(map.count, 2, "Should return one entry per drained draft")

        // Verify each persistentModelID resolves to a recipe with the expected title.
        let expectedTitles: [UUID: String] = [
            draft1.id: "Pasta Primavera",
            draft2.id: "Lemon Tart"
        ]

        for (draftID, persistentID) in map {
            let recipe = context.model(for: persistentID) as? Recipe
            XCTAssertNotNil(recipe, "persistentModelID \(persistentID) must resolve after save")
            let expectedTitle = expectedTitles[draftID]
            XCTAssertEqual(recipe?.title, expectedTitle,
                           "Recipe for draft \(draftID) should have title '\(expectedTitle ?? "?")'")
        }
    }

    // MARK: - Inbox is empty after drain

    func testInboxIsEmptyAfterDrain() {
        let inbox = ImportInbox(defaults: defaults)
        inbox.append(makeDraft(title: "Crêpes"))
        _ = ImportInboxDrainer.drain(inbox, into: context)
        // A second drain on the same inbox must yield an empty map.
        let secondMap = ImportInboxDrainer.drain(inbox, into: context)
        XCTAssertTrue(secondMap.isEmpty, "Inbox should be cleared after the first drain")
    }

    // MARK: - Draft IDs match recipe content

    func testDraftIDsArePreservedInMap() throws {
        let inbox = ImportInbox(defaults: defaults)
        let draft = makeDraft(title: "Avocado Toast")
        inbox.append(draft)

        let map = ImportInboxDrainer.drain(inbox, into: context)

        XCTAssertEqual(map.count, 1)
        let persistentID = try XCTUnwrap(map[draft.id], "Map must contain an entry for draft.id")
        let recipe = context.model(for: persistentID) as? Recipe
        XCTAssertEqual(recipe?.title, "Avocado Toast")
    }
}
