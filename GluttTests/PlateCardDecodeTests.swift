import XCTest
@testable import Glutt

final class PlateCardDecodeTests: XCTestCase {
    private let json = """
    {
      "deckTitle": "Today's Plate",
      "recipes": [
        {
          "id": "spoonacular:715538",
          "title": "Creamy Lemon Chicken Rice Bowl",
          "imageURL": "https://img.test/715538.jpg",
          "source": "spoonacular",
          "sourceURL": "https://feast.test/recipe",
          "creator": "Feast & Flavor",
          "license": "spoonacular",
          "summary": "Weeknight bowl",
          "servings": 4,
          "prepMinutes": 0,
          "cookMinutes": 30,
          "difficulty": "beginner",
          "tags": ["high-protein","dinner"],
          "dietFlags": ["gluten free"],
          "macros": { "calories": 620, "protein": 48, "carbs": 55, "fat": 18, "estimated": false },
          "ingredients": [
            { "raw": "600 g chicken thighs", "name": "chicken thighs", "quantity": 600, "unit": "g" }
          ],
          "steps": ["Season the chicken", "Sear 4 min per side"],
          "nutritionNote": null
        }
      ],
      "nextPageToken": null
    }
    """

    func testDecodesContract() throws {
        let resp = try JSONDecoder().decode(PlatesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.deckTitle, "Today's Plate")
        XCTAssertNil(resp.nextPageToken)
        let card = try XCTUnwrap(resp.recipes.first)
        XCTAssertEqual(card.id, "spoonacular:715538")
        XCTAssertEqual(card.servings, 4)
        XCTAssertEqual(card.macros?.caloriesInt, 620)
        XCTAssertEqual(card.macros?.carbsInt, 55)
        XCTAssertEqual(card.macros?.estimated, false)
        XCTAssertEqual(card.ingredients.first?.raw, "600 g chicken thighs")
        XCTAssertEqual(card.steps.count, 2)
    }

    func testToleratesDecimalMacrosAndMissingOptionals() throws {
        let minimal = """
        { "recipes": [ {
          "id": "x:1", "title": "T", "source": "spoonacular",
          "tags": [], "dietFlags": [],
          "macros": { "calories": 612.6, "protein": 47.4, "carbs": null, "fat": null, "estimated": true },
          "ingredients": [], "steps": []
        } ] }
        """
        let resp = try JSONDecoder().decode(PlatesResponse.self, from: Data(minimal.utf8))
        let card = try XCTUnwrap(resp.recipes.first)
        XCTAssertNil(card.imageURL)
        XCTAssertEqual(card.macros?.caloriesInt, 613)
        XCTAssertNil(card.macros?.carbsInt)
        XCTAssertEqual(card.macros?.estimated, true)
    }
}
