import XCTest
@testable import Glutt

final class PlatesSeedDeckTests: XCTestCase {
    func testDecodeParsesDeck() {
        let json = #"{ "deckTitle": "Seed", "recipes": [ { "id": "s:1", "title": "Seed Bowl", "source": "curated", "tags": [], "dietFlags": [], "ingredients": [], "steps": [] } ], "nextPageToken": null }"#
        let resp = PlatesSeedDeck.decode(Data(json.utf8))
        XCTAssertEqual(resp?.recipes.first?.id, "s:1")
    }

    func testDecodeReturnsNilOnGarbage() {
        XCTAssertNil(PlatesSeedDeck.decode(Data("not json".utf8)))
    }

    func testBundledSeedLoads() {
        // The app bundle ships PlatesSeedDeck.json with >= 1 recipe.
        let resp = PlatesSeedDeck.load()
        XCTAssertGreaterThanOrEqual(resp.recipes.count, 1)
    }
}
