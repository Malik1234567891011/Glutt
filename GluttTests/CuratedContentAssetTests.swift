import UIKit
import XCTest
@testable import Glutt

/// Guards the bundled photography for the chef and restaurant packs.
///
/// These images ship inside the app's compiled asset catalog, so the only way a
/// user ends up staring at the fork-and-knife placeholder is a name in the pack
/// that no imageset answers to — a typo, a renamed file, or an imageset that was
/// never committed. That failure is invisible in a build log and invisible in
/// the simulator if the stale asset is still in DerivedData, so it gets a test.
final class CuratedContentAssetTests: XCTestCase {

    /// Tests run hosted inside the Glutt app, so the compiled asset catalog
    /// lives in the app bundle, not the test bundle.
    private let appBundle = Bundle(identifier: "com.malik.glutt") ?? .main

    private func assertLoads(_ name: String, _ context: @autoclosure () -> String) {
        XCTAssertNotNil(
            UIImage(named: name, in: appBundle, compatibleWith: nil),
            "Missing imageset '\(name)' in Assets.xcassets — \(context()) will render a placeholder"
        )
    }

    func testEveryChefPortraitShips() {
        for chef in ChefContent.chefs {
            guard let asset = chef.portraitAsset else { continue }
            assertLoads(asset, "the \(chef.name) rail item and page header")
        }
    }

    func testEveryChefDishPhotoShips() {
        for chef in ChefContent.chefs {
            for dish in ChefContent.dishes(for: chef) {
                assertLoads(dish.imageAsset, "\(chef.name)'s \(dish.title)")
            }
        }
    }

    func testEveryRestaurantLogoShips() {
        for restaurant in RestaurantContent.restaurants {
            guard let asset = restaurant.logoAsset else { continue }
            assertLoads(asset, "the \(restaurant.name) rail item and page header")
        }
    }

    func testEveryRestaurantDishPhotoShips() {
        for restaurant in RestaurantContent.restaurants {
            for dish in RestaurantContent.dishes(for: restaurant) {
                assertLoads(dish.imageAsset, "\(restaurant.name)'s \(dish.title)")
            }
        }
    }

    /// Cotoa shipped once with four dishes borrowing stock food art, which meant
    /// a restaurant plate and a library recipe wore the same photograph. Now that
    /// the real photography is in, nothing in the pack may point back at it.
    func testCotoaDishesUseTheirOwnPhotographyNotStockArt() {
        let stockArt: Set<String> = [
            "pestoGnocchiMealPrep", "chickenRiceBowl",
            "lemonDillSalmonBowl", "greenGoddessSteakPlate",
        ]
        guard let cotoa = RestaurantContent.restaurant(id: "cotoa") else {
            return XCTFail("Cotoa missing from the pack")
        }
        for dish in RestaurantContent.dishes(for: cotoa) {
            XCTAssertFalse(
                stockArt.contains(dish.imageAsset),
                "\(dish.title) is still on the stand-in photo '\(dish.imageAsset)'")
            XCTAssertTrue(
                dish.imageAsset.hasPrefix("cotoa"),
                "\(dish.title) should use a cotoa* asset, got '\(dish.imageAsset)'")
        }
    }
}
