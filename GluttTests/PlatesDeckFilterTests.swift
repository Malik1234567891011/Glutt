import XCTest
@testable import Glutt

final class PlatesDeckFilterTests: XCTestCase {
    private func card(_ id: String, url: String, ingredient: String) -> PlateCard {
        let json = """
        { "id": "\(id)", "title": "T", "source": "spoonacular", "sourceURL": "\(url)",
          "tags": [], "dietFlags": [],
          "ingredients": [ { "raw": "\(ingredient)", "name": "\(ingredient)" } ], "steps": ["s"] }
        """
        return try! JSONDecoder().decode(PlateCard.self, from: Data(json.utf8))
    }

    func testHardFiltersAllergyConflicts() {
        let cards = [card("1", url: "a", ingredient: "peanut butter"),
                     card("2", url: "b", ingredient: "chicken thighs")]
        let out = PlatesDeckFilter.filter(cards, rules: [], allergies: ["peanut"], savedSourceURLs: [])
        XCTAssertEqual(out.map(\.id), ["2"])
    }

    func testHardFiltersRuleConflicts() {
        let cards = [card("1", url: "a", ingredient: "pork belly"),
                     card("2", url: "b", ingredient: "chickpeas")]
        let out = PlatesDeckFilter.filter(cards, rules: [.halal], allergies: [], savedSourceURLs: [])
        XCTAssertEqual(out.map(\.id), ["2"])
    }

    func testDropsAlreadySaved() {
        let cards = [card("1", url: "https://x/a", ingredient: "rice"),
                     card("2", url: "https://x/b", ingredient: "rice")]
        let out = PlatesDeckFilter.filter(cards, rules: [], allergies: [], savedSourceURLs: ["https://x/a"])
        XCTAssertEqual(out.map(\.id), ["2"])
    }
}
