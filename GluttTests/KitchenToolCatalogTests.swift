import XCTest
@testable import Glutt

final class KitchenToolCatalogTests: XCTestCase {

    func testRequiredToolsDetectedFromRecipeText() {
        let text = "Air-fry the wings at 400°F. Purée the sauce in a blender, then finish in a dutch oven."
        let required = KitchenToolCatalog.requiredTools(inText: text)
        XCTAssertTrue(required.contains("Air fryer"))
        XCTAssertTrue(required.contains("Blender"))
        XCTAssertTrue(required.contains("Dutch oven"))
    }

    func testNoFalsePositivesForBasicRecipe() {
        // A recipe using only universal basics should flag nothing.
        let text = "Boil the pasta. Season with salt and toss with olive oil and parmesan."
        XCTAssertTrue(KitchenToolCatalog.requiredTools(inText: text).isEmpty)
    }

    func testCategoryLookup() {
        XCTAssertEqual(KitchenToolCatalog.category(for: "Air fryer"), "Appliances")
        XCTAssertEqual(KitchenToolCatalog.category(for: "Dutch oven"), "Cookware")
        XCTAssertEqual(KitchenToolCatalog.category(for: "Chef's knife"), "Tools")
        XCTAssertEqual(KitchenToolCatalog.category(for: "Fondue pot"), "Custom")
    }

    func testCanonicalPresetSetCoversEveryListedTool() {
        for tool in KitchenToolCatalog.all {
            XCTAssertTrue(KitchenToolCatalog.canonicalAll.contains(tool.lowercased()))
        }
    }
}
