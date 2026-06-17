import SwiftData
import XCTest
@testable import Glutt

@MainActor
final class RouterImportNavigationTests: XCTestCase {

    /// A real PersistentIdentifier requires an inserted model.
    private func makeIdentifier() throws -> PersistentIdentifier {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recipe.self, configurations: config)
        let recipe = Recipe(title: "Test")
        container.mainContext.insert(recipe)
        return recipe.persistentModelID
    }

    func testResolvesWhenImportNotedBeforeOpenRequested() throws {
        let id = try makeIdentifier()
        let uuid = UUID()
        let router = Router()

        router.noteImported([uuid: id])
        XCTAssertNil(router.recipeToOpenID)          // nothing requested yet

        router.requestOpenRecipe(importID: uuid)
        XCTAssertEqual(router.recipeToOpenID, id)
        XCTAssertEqual(router.selectedTab, .recipes)
    }

    func testResolvesWhenOpenRequestedBeforeImportNoted() throws {
        let id = try makeIdentifier()
        let uuid = UUID()
        let router = Router()

        router.requestOpenRecipe(importID: uuid)
        XCTAssertNil(router.recipeToOpenID)          // not drained yet

        router.noteImported([uuid: id])
        XCTAssertEqual(router.recipeToOpenID, id)
    }

    func testUnmatchedImportLeavesTargetNil() throws {
        let id = try makeIdentifier()
        let router = Router()
        router.noteImported([UUID(): id])
        router.requestOpenRecipe(importID: UUID())    // different id
        XCTAssertNil(router.recipeToOpenID)
    }

    func testRecipeDeepLinkRequestsOpen() {
        let router = Router()
        let uuid = UUID()
        router.handle(url: URL(string: "glutt://recipe?import=\(uuid.uuidString)")!)
        XCTAssertEqual(router.selectedTab, .recipes)
        // No drain happened, so the concrete id is still pending — but the tab switched.
    }
}
