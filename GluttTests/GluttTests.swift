import SwiftData
import XCTest
@testable import Glutt

final class IngredientCanonicalizerTests: XCTestCase {

    func testStripsPreparationNoise() {
        XCTAssertEqual(IngredientCanonicalizer.canonicalize("Chicken thighs, boneless skinless"), "chicken thigh")
        XCTAssertEqual(IngredientCanonicalizer.canonicalize("freshly chopped Parsley"), "parsley")
    }

    func testSynonymMapping() {
        XCTAssertEqual(IngredientCanonicalizer.canonicalize("Scallions"), "green onion")
        XCTAssertEqual(IngredientCanonicalizer.canonicalize("spring onions"), "green onion")
        XCTAssertEqual(IngredientCanonicalizer.canonicalize("Double cream"), "heavy cream")
    }

    func testMatchesAcrossVariants() {
        XCTAssertTrue(IngredientCanonicalizer.matches("Scallions", "green onion"))
        XCTAssertTrue(IngredientCanonicalizer.matches("Tomatoes", "tomato"))
        XCTAssertFalse(IngredientCanonicalizer.matches("Chicken breast", "chicken thigh"))
    }
}

final class UnitConverterTests: XCTestCase {

    func testFractionsFormatting() {
        XCTAssertEqual(UnitConverter.format(quantity: 0.5, unit: "cup"), "½ cup")
        XCTAssertEqual(UnitConverter.format(quantity: 1.5), "1½")
        XCTAssertEqual(UnitConverter.format(quantity: 2.0, unit: "tbsp"), "2 tbsp")
        XCTAssertEqual(UnitConverter.format(quantity: 0.25), "¼")
    }

    func testMetricConversion() {
        let cups = UnitConverter.convert(quantity: 2, unit: "cups", to: .metric)
        XCTAssertEqual(cups.quantity, 480)
        XCTAssertEqual(cups.unit, "ml")

        let pounds = UnitConverter.convert(quantity: 1, unit: "lb", to: .metric)
        XCTAssertEqual(pounds.quantity, 454)
        XCTAssertEqual(pounds.unit, "g")

        // Promotes to liters at >= 1000 ml
        let quarts = UnitConverter.convert(quantity: 2, unit: "quarts", to: .metric)
        XCTAssertEqual(quarts.unit, "l")
    }

    func testOriginalSystemIsUntouched() {
        let result = UnitConverter.convert(quantity: 2, unit: "cups", to: .original)
        XCTAssertEqual(result.quantity, 2)
        XCTAssertEqual(result.unit, "cups")
    }

    func testScaledDisplay() {
        // 0.5 cup scaled from 4 -> 6 servings = 0.75 cup
        let display = UnitConverter.display(quantity: 0.5, unit: "cup", scale: 1.5)
        XCTAssertEqual(display, "¾ cup")
    }

    func testFahrenheitToCelsius() {
        XCTAssertEqual(UnitConverter.fahrenheitToCelsius(425), 218)
    }
}

final class ModelTests: XCTestCase {

    @MainActor
    func testModelContainerCreatesAndSavesAllModels() throws {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
            PantryItem.self, GroceryItem.self, Leftover.self,
            PlannedMeal.self, FoodLog.self, CookSession.self, UserPrefs.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let recipe = Recipe(title: "Test Dish", servings: 2, prepMinutes: 10, cookMinutes: 20)
        recipe.ingredients = [RecipeIngredient(name: "Scallions", quantity: 2)]
        recipe.steps = [RecipeStep(index: 0, text: "Cook it.", durationSeconds: 300)]
        context.insert(recipe)

        let meal = PlannedMeal(
            date: .now,
            mealType: .dinner,
            exactTime: Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now),
            recipe: recipe
        )
        context.insert(meal)
        try context.save()

        XCTAssertEqual(recipe.totalMinutes, 30)
        XCTAssertEqual(recipe.ingredients.first?.canonicalName, "green onion")

        // Start time = meal time - (total + 10 min buffer)
        let start = try XCTUnwrap(meal.suggestedStartTime)
        let expected = Calendar.current.date(byAdding: .minute, value: -40, to: meal.exactTime!)
        XCTAssertEqual(start, expected)
    }

    @MainActor
    func testUserPrefsSingleton() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UserPrefs.self, configurations: config)
        let context = container.mainContext

        let first = UserPrefs.current(in: context)
        first.displayName = "Malik"
        try context.save()

        let second = UserPrefs.current(in: context)
        XCTAssertEqual(second.displayName, "Malik")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserPrefs>()), 1)
    }
}
