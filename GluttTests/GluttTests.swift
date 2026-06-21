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

final class IngredientLineParserTests: XCTestCase {

    func testSimpleQuantityUnitName() {
        let result = IngredientLineParser.parse("2 cups basmati rice")
        XCTAssertEqual(result.quantity, 2)
        XCTAssertEqual(result.unit, "cups")
        XCTAssertEqual(result.name, "basmati rice")
    }

    func testFractionsAndCompounds() {
        XCTAssertEqual(IngredientLineParser.parse("1/2 cup Greek yogurt").quantity, 0.5)
        XCTAssertEqual(IngredientLineParser.parse("1 1/2 lbs chicken thighs").quantity, 1.5)
        XCTAssertEqual(IngredientLineParser.parse("½ tsp salt").quantity, 0.5)
        XCTAssertEqual(IngredientLineParser.parse("1½ cups flour").quantity, 1.5)
    }

    func testNotesAndBullets() {
        let comma = IngredientLineParser.parse("2 lbs chicken thighs, boneless and skinless")
        XCTAssertEqual(comma.name, "chicken thighs")
        XCTAssertEqual(comma.note, "boneless and skinless")

        let parens = IngredientLineParser.parse("- 1 can chickpeas (drained)")
        XCTAssertEqual(parens.quantity, 1)
        XCTAssertEqual(parens.unit, "can")
        XCTAssertEqual(parens.name, "chickpeas")
        XCTAssertEqual(parens.note, "drained")
    }

    func testOfIsDropped() {
        XCTAssertEqual(IngredientLineParser.parse("2 cups of rice").name, "rice")
    }

    func testNoQuantityFallsBackToFullLine() {
        let result = IngredientLineParser.parse("Salt and pepper to taste")
        XCTAssertNil(result.quantity)
        XCTAssertEqual(result.name, "Salt and pepper to taste")
    }
}

final class RecipeHTMLParserTests: XCTestCase {

    func testCleanTitleStripsSiteSuffixes() {
        XCTAssertEqual(
            RecipeHTMLParser.cleanTitle("Glossy Fudge Brownies Recipe | BraveTart"),
            "Glossy Fudge Brownies Recipe"
        )
        XCTAssertEqual(
            RecipeHTMLParser.cleanTitle("Chicken Adobo — Serious Eats"),
            "Chicken Adobo"
        )
        XCTAssertEqual(
            RecipeHTMLParser.cleanTitle("One-Pot Pasta - Budget Bytes"),
            "One-Pot Pasta"
        )
        // Titles without a site suffix pass through untouched.
        XCTAssertEqual(
            RecipeHTMLParser.cleanTitle("Sweet-and-Sour Pork"),
            "Sweet-and-Sour Pork"
        )
    }

    private let jsonLDFixture = """
    <html><head>
    <script type="application/ld+json">
    {
      "@context": "https://schema.org",
      "@graph": [
        {"@type": "WebSite", "name": "Some Food Blog"},
        {
          "@type": "Recipe",
          "name": "Spicy Honey Chicken Bowls",
          "description": "Sweet &amp; spicy weeknight bowls.",
          "image": ["https://example.com/photo.jpg"],
          "author": {"@type": "Person", "name": "Chef Test"},
          "prepTime": "PT15M",
          "cookTime": "PT1H10M",
          "recipeYield": "4 servings",
          "keywords": "dinner, chicken, spicy",
          "recipeIngredient": ["500 g chicken thighs", "2 tbsp honey", "1 cup rice"],
          "recipeInstructions": [
            {"@type": "HowToStep", "text": "Marinate the chicken."},
            {"@type": "HowToStep", "text": "Cook rice for 15 minutes."}
          ],
          "nutrition": {"@type": "NutritionInformation", "calories": "640 calories", "proteinContent": "42 g"}
        }
      ]
    }
    </script>
    </head><body></body></html>
    """

    func testJSONLDExtraction() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/spicy-honey-chicken"))
        let draft = RecipeHTMLParser.parse(html: jsonLDFixture, sourceURL: url)

        XCTAssertEqual(draft.title, "Spicy Honey Chicken Bowls")
        XCTAssertEqual(draft.summary, "Sweet & spicy weeknight bowls.")
        XCTAssertEqual(draft.imageURL, "https://example.com/photo.jpg")
        XCTAssertEqual(draft.creator, "Chef Test")
        XCTAssertEqual(draft.prepMinutes, 15)
        XCTAssertEqual(draft.cookMinutes, 70)
        XCTAssertEqual(draft.servings, 4)
        XCTAssertEqual(draft.ingredientLines.count, 3)
        XCTAssertEqual(draft.stepTexts.count, 2)
        XCTAssertEqual(draft.tags, ["dinner", "chicken", "spicy"])
        XCTAssertEqual(draft.calories, 640)
        XCTAssertEqual(draft.proteinGrams, 42)
        XCTAssertGreaterThan(draft.confidence, 0.8)
    }

    func testMetaFallbackForSocialPages() throws {
        let html = """
        <html><head>
        <meta property="og:title" content="INSANE garlic butter steak bites 🔥" />
        <meta property="og:image" content="https://cdn.example.com/thumb.jpg" />
        <meta property="og:description" content="Recipe below!
        Ingredients:
        1 lb sirloin steak
        3 tbsp butter
        4 cloves garlic
        Instructions:
        1. Cube the steak and season.
        2. Sear in a hot pan 2 minutes per side.
        3. Add butter and garlic, baste." />
        </head><body></body></html>
        """
        let url = try XCTUnwrap(URL(string: "https://www.tiktok.com/@cook/video/123"))
        let draft = RecipeHTMLParser.parse(html: html, sourceURL: url)

        XCTAssertEqual(draft.platform, .tiktok)
        XCTAssertEqual(draft.imageURL, "https://cdn.example.com/thumb.jpg")
        XCTAssertEqual(draft.ingredientLines.count, 3)
        XCTAssertEqual(draft.stepTexts.count, 3)
    }

    func testISODurations() {
        XCTAssertEqual(RecipeHTMLParser.isoDurationMinutes("PT30M"), 30)
        XCTAssertEqual(RecipeHTMLParser.isoDurationMinutes("PT1H30M"), 90)
        XCTAssertEqual(RecipeHTMLParser.isoDurationMinutes("PT2H"), 120)
        XCTAssertNil(RecipeHTMLParser.isoDurationMinutes(nil))
    }
}

final class TextRecipeParserTests: XCTestCase {

    func testOCRStyleText() {
        let text = """
        Creamy Tuscan Chicken

        Ingredients
        2 chicken breasts
        1 cup heavy cream
        2 cups spinach
        ½ cup sun-dried tomatoes

        Instructions
        1. Season and sear the chicken.
        2. Make the cream sauce.
        3. Add spinach and tomatoes, simmer.

        Serves 4
        """
        let draft = TextRecipeParser.parse(text: text)
        XCTAssertEqual(draft.title, "Creamy Tuscan Chicken")
        XCTAssertEqual(draft.ingredientLines.count, 4)
        XCTAssertEqual(draft.stepTexts.count, 3)
        XCTAssertEqual(draft.stepTexts.first, "Season and sear the chicken.")
        XCTAssertEqual(draft.servings, 4)
    }

    func testCaptionWithoutHeaders() {
        let text = """
        you NEED to try this 😍 #fyp #cooking
        2 cups rice
        1 lb ground beef
        1 tbsp gochujang
        """
        let draft = TextRecipeParser.parse(text: text)
        XCTAssertEqual(draft.ingredientLines.count, 3)
        XCTAssertTrue(draft.issues.contains { $0.contains("guessed") })
    }
}

final class PantryMatcherTests: XCTestCase {

    private func makeRecipe() -> Recipe {
        let recipe = Recipe(title: "Test Bowl")
        recipe.ingredients = [
            RecipeIngredient(name: "Chicken thighs", quantity: 600, unit: "g", sortIndex: 0),
            RecipeIngredient(name: "Basmati rice", quantity: 2, unit: "cups", sortIndex: 1),
            RecipeIngredient(name: "Heavy cream", quantity: 1, unit: "cup", sortIndex: 2),
            RecipeIngredient(name: "Salt", sortIndex: 3),
            RecipeIngredient(name: "Parsley", isOptional: true, sortIndex: 4),
        ]
        return recipe
    }

    func testStapleMarkedOutCountsAsMissing() {
        let recipe = Recipe(title: "Seasoned Thing")
        recipe.ingredients = [RecipeIngredient(name: "Salt", sortIndex: 0)]

        // No pantry row: salt is a staple, assumed owned.
        XCTAssertEqual(PantryMatcher.match(recipe: recipe, pantry: []).ownedCount, 1)

        // Explicit "out" row overrides the staple assumption.
        let outOfSalt = PantryItem(name: "Salt", category: .spices, roughQuantity: .out)
        let result = PantryMatcher.match(recipe: recipe, pantry: [outOfSalt])
        XCTAssertEqual(result.ownedCount, 0)
        XCTAssertEqual(result.missing.map(\.name), ["Salt"])
    }

    func testMatchCountsAndCategories() {
        let pantry = [
            PantryItem(name: "Chicken thighs", category: .meat),
            PantryItem(name: "Rice", category: .pantry),
        ]
        let result = PantryMatcher.match(recipe: makeRecipe(), pantry: pantry)

        // Owned: chicken (exact), basmati rice (subset match), salt (staple)
        XCTAssertEqual(result.ownedCount, 3)
        // Missing: heavy cream. Parsley is optional -> missingOptional.
        XCTAssertEqual(result.missing.map(\.name), ["Heavy cream"])
        XCTAssertEqual(result.missingOptional.map(\.name), ["Parsley"])
        XCTAssertEqual(result.totalCount, 4)
        XCTAssertFalse(result.hasEverything)
    }

    func testOutOfStockDoesNotCount() {
        let pantry = [PantryItem(name: "Chicken thighs", roughQuantity: .out)]
        let result = PantryMatcher.match(recipe: makeRecipe(), pantry: pantry)
        XCTAssertTrue(result.missing.contains { $0.name == "Chicken thighs" })
    }
}

final class GroceryListBuilderTests: XCTestCase {

    func testCategorizer() {
        XCTAssertEqual(GroceryCategorizer.categorize("Lemons"), .produce)
        XCTAssertEqual(GroceryCategorizer.categorize("Chicken breast"), .meat)
        XCTAssertEqual(GroceryCategorizer.categorize("Greek yogurt"), .dairy)
        XCTAssertEqual(GroceryCategorizer.categorize("Basmati rice"), .pantry)
        XCTAssertEqual(GroceryCategorizer.categorize("Paprika"), .spices)
        XCTAssertEqual(GroceryCategorizer.categorize("Mystery item"), .other)
    }

    @MainActor
    func testCombinesDuplicates() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: GroceryItem.self, configurations: config)
        let context = container.mainContext

        let recipeA = Recipe(title: "Recipe A")
        let onionA = RecipeIngredient(name: "Onions", quantity: 2)
        GroceryListBuilder.add(ingredients: [onionA], from: recipeA, existing: [], context: context)

        let existing = try context.fetch(FetchDescriptor<GroceryItem>())
        XCTAssertEqual(existing.count, 1)

        let recipeB = Recipe(title: "Recipe B")
        let onionB = RecipeIngredient(name: "onion", quantity: 1)
        GroceryListBuilder.add(ingredients: [onionB], from: recipeB, existing: existing, context: context)

        let after = try context.fetch(FetchDescriptor<GroceryItem>())
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.quantity, 3)
        XCTAssertEqual(after.first?.sourceRecipeTitles.count, 2)
    }

    func testSubstitutionsRespectPantry() {
        let pantry = [
            PantryItem(name: "Greek yogurt", category: .dairy),
            PantryItem(name: "Butter", category: .dairy),
        ]
        let available = SubstitutionService.availableSubstitutions(for: "heavy cream", pantry: pantry)
        XCTAssertTrue(available.contains { $0.name == "Greek yogurt + butter" })

        let withoutButter = [PantryItem(name: "Greek yogurt", category: .dairy)]
        let unavailable = SubstitutionService.availableSubstitutions(for: "heavy cream", pantry: withoutButter)
        XCTAssertFalse(unavailable.contains { $0.name == "Greek yogurt + butter" })
    }
}

final class CookModeTests: XCTestCase {

    func testStepIngredientMatching() {
        let chicken = RecipeIngredient(name: "Chicken thighs", quantity: 600, unit: "g", sortIndex: 0)
        let rice = RecipeIngredient(name: "Rice", quantity: 2, unit: "cups", sortIndex: 1)
        let yogurt = RecipeIngredient(name: "Greek yogurt", quantity: 0.5, unit: "cup", sortIndex: 2)
        let ingredients = [chicken, rice, yogurt]

        let searStep = RecipeStep(index: 0, text: "Sear the chicken 4 minutes per side.")
        XCTAssertEqual(searStep.ingredientsUsed(from: ingredients).map(\.name), ["Chicken thighs"])

        let sauceStep = RecipeStep(index: 1, text: "Whisk the yogurt into a sauce while the rice cooks.")
        XCTAssertEqual(
            sauceStep.ingredientsUsed(from: ingredients).map(\.name),
            ["Rice", "Greek yogurt"]
        )

        let restStep = RecipeStep(index: 2, text: "Let everything rest 5 minutes.")
        XCTAssertTrue(restStep.ingredientsUsed(from: ingredients).isEmpty)
    }

    func testTimerFormatting() {
        XCTAssertEqual(TimerManager.format(seconds: 45), "0:45")
        XCTAssertEqual(TimerManager.format(seconds: 600), "10:00")
        XCTAssertEqual(TimerManager.format(seconds: 5400), "1:30:00")
    }

    func testTimerCountdown() {
        let timer = CookTimer(label: "Test", totalSeconds: 60, endDate: .now.addingTimeInterval(60))
        XCTAssertEqual(timer.remainingSeconds(), 60)
        XCTAssertFalse(timer.isFinished())
        XCTAssertTrue(timer.isFinished(at: .now.addingTimeInterval(61)))
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

final class PrepDetectorTests: XCTestCase {

    func testDetectsMarinadeAndThaw() {
        let recipe = Recipe(title: "Butter Chicken")
        recipe.steps = [
            RecipeStep(index: 0, text: "Marinate the chicken in yogurt for 4 hours."),
            RecipeStep(index: 1, text: "Thaw the frozen peas."),
            RecipeStep(index: 2, text: "Simmer the sauce."),
        ]
        let tasks = PrepDetector.tasks(for: recipe)

        XCTAssertEqual(tasks.count, 2)
        XCTAssertTrue(tasks.contains { $0.keyword == "marinate" })
        XCTAssertTrue(tasks.contains { $0.keyword == "thaw" })
        XCTAssertTrue(tasks.allSatisfy { $0.text.contains("Butter Chicken") })
    }

    func testNoFalsePositives() {
        let recipe = Recipe(title: "Quick Eggs")
        recipe.steps = [RecipeStep(index: 0, text: "Scramble the eggs over medium heat.")]
        XCTAssertTrue(PrepDetector.tasks(for: recipe).isEmpty)
    }
}

final class WeekPlannerTests: XCTestCase {

    private func makeRecipe(_ title: String, rating: Int? = nil, pantryFriendly: Bool = false) -> Recipe {
        let recipe = Recipe(title: title)
        recipe.rating = rating
        recipe.ingredients = [RecipeIngredient(name: pantryFriendly ? "Rice" : "Saffron", sortIndex: 0)]
        recipe.steps = [RecipeStep(index: 0, text: "Cook.")]
        return recipe
    }

    func testDraftFillsRequestedSlotsWithoutImmediateRepeats() {
        let recipes = (1...5).map { makeRecipe("Recipe \($0)") }
        let input = WeekPlanner.Input(
            days: 3,
            mealTypes: [.dinner],
            useLeftovers: false,
            recipes: recipes,
            pantry: [],
            leftovers: [],
            recentSessions: []
        )
        let slots = WeekPlanner.draft(input)

        XCTAssertEqual(slots.count, 3)
        XCTAssertTrue(slots.allSatisfy { $0.recipe != nil })
        // With 5 recipes and 3 slots, no recipe should repeat.
        let titles = slots.compactMap { $0.recipe?.title }
        XCTAssertEqual(Set(titles).count, 3)
    }

    func testLeftoversClaimLunchSlots() {
        let recipes = (1...4).map { makeRecipe("Recipe \($0)") }
        let leftover = Leftover(title: "Chili", servingsRemaining: 2)
        let input = WeekPlanner.Input(
            days: 2,
            mealTypes: [.lunch, .dinner],
            useLeftovers: true,
            recipes: recipes,
            pantry: [],
            leftovers: [leftover],
            recentSessions: []
        )
        let slots = WeekPlanner.draft(input)

        let firstLunch = slots.first { $0.mealType == .lunch }
        XCTAssertNotNil(firstLunch?.leftover)
        XCTAssertEqual(firstLunch?.leftover?.title, "Chili")
        // Dinners are still recipes.
        XCTAssertTrue(slots.filter { $0.mealType == .dinner }.allSatisfy { $0.recipe != nil })
    }

    func testScoringPrefersPantryMatchAndRating() {
        let pantryFriendly = makeRecipe("Fried Rice", rating: 5, pantryFriendly: true)
        let exotic = makeRecipe("Saffron Risotto")
        let pantry = [PantryItem(name: "Rice", category: .pantry)]
        let input = WeekPlanner.Input(
            days: 1,
            mealTypes: [.dinner],
            useLeftovers: false,
            recipes: [exotic, pantryFriendly],
            pantry: pantry,
            leftovers: [],
            recentSessions: []
        )

        let friendlyScore = WeekPlanner.score(recipe: pantryFriendly, input: input)
        let exoticScore = WeekPlanner.score(recipe: exotic, input: input)
        // Pantry match (3.0) + rating (2.5) dwarfs the 0.4 jitter.
        XCTAssertGreaterThan(friendlyScore, exoticScore)

        let slots = WeekPlanner.draft(input)
        XCTAssertEqual(slots.first?.recipe?.title, "Fried Rice")
    }

    func testSwapAvoidsCurrentRecipe() {
        let recipes = (1...3).map { makeRecipe("Recipe \($0)") }
        let input = WeekPlanner.Input(
            days: 1,
            mealTypes: [.dinner],
            useLeftovers: false,
            recipes: recipes,
            pantry: [],
            leftovers: [],
            recentSessions: []
        )
        var slots = WeekPlanner.draft(input)
        let original = slots[0].recipe
        let replacement = WeekPlanner.swap(slot: slots[0], in: slots, input: input)

        XCTAssertNotNil(replacement)
        XCTAssertFalse(replacement === original)
        slots[0].recipe = replacement
    }
}

final class RecipeSearchEngineTests: XCTestCase {

    private func makeLibrary() -> [Recipe] {
        let chicken = Recipe(title: "Creamy Lemon Chicken Rice Bowl", tags: ["creamy", "weeknight"])
        chicken.ingredients = [
            RecipeIngredient(name: "Chicken thighs", sortIndex: 0),
            RecipeIngredient(name: "Heavy cream", sortIndex: 1),
            RecipeIngredient(name: "Lemon", sortIndex: 2),
        ]
        chicken.steps = [RecipeStep(index: 0, text: "Cook.")]

        let brownies = Recipe(title: "Fudgy Brownies", tags: ["dessert", "chocolate"])
        brownies.ingredients = [RecipeIngredient(name: "Dark chocolate", sortIndex: 0)]
        brownies.steps = [RecipeStep(index: 0, text: "Bake.")]
        return [chicken, brownies]
    }

    func testStopWordsAreFiltered() {
        let words = RecipeSearchEngine.significantWords(in: "that creamy lemon chicken thing")
        XCTAssertEqual(words, ["creamy", "lemon", "chicken"])
    }

    func testVagueQueryFindsTheRightRecipe() {
        let results = RecipeSearchEngine.search(query: "that creamy lemon chicken thing", recipes: makeLibrary())
        XCTAssertEqual(results.first?.recipe.title, "Creamy Lemon Chicken Rice Bowl")
        XCTAssertFalse(results.first?.reasons.isEmpty ?? true)
    }

    func testSearchByIngredientNotInTitle() {
        let results = RecipeSearchEngine.search(query: "chocolate", recipes: makeLibrary())
        XCTAssertEqual(results.first?.recipe.title, "Fudgy Brownies")
    }
}

final class RecipeOptimizerTests: XCTestCase {

    @MainActor
    func testPlanSwapsAndAppliesAsVersion() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recipe.self, configurations: config)
        let context = container.mainContext

        let recipe = Recipe(title: "Creamy Pasta")
        recipe.ingredients = [
            RecipeIngredient(name: "Pasta", sortIndex: 0),
            RecipeIngredient(name: "Heavy cream", sortIndex: 1),
        ]
        recipe.steps = [RecipeStep(index: 0, text: "Cook.")]
        context.insert(recipe)

        // Greek yogurt + butter in pantry -> heavy cream is swappable.
        let pantry = [
            PantryItem(name: "Pasta"),
            PantryItem(name: "Greek yogurt", category: .dairy),
            PantryItem(name: "Butter", category: .dairy),
        ]

        let plan = RecipeOptimizer.plan(for: recipe, pantry: pantry)
        XCTAssertEqual(plan.swaps.count, 1)
        XCTAssertEqual(plan.swaps.first?.original.name, "Heavy cream")
        XCTAssertFalse(plan.swaps.first?.reason.isEmpty ?? true)

        let version = RecipeOptimizer.apply(plan, to: recipe, context: context)
        XCTAssertEqual(version.versionLabel, "Pantry version")
        XCTAssertTrue(version.parentRecipe === recipe)
        XCTAssertTrue(version.ingredients.contains { $0.name == plan.swaps.first?.substituteName })
        // Original untouched.
        XCTAssertTrue(recipe.ingredients.contains { $0.name == "Heavy cream" })
    }
}

final class NutritionEstimatorTests: XCTestCase {

    func testEstimatesKnownIngredientsPerServing() throws {
        let recipe = Recipe(title: "Chicken & Rice", servings: 2)
        recipe.ingredients = [
            RecipeIngredient(name: "Chicken breast", quantity: 400, unit: "g", sortIndex: 0),
            RecipeIngredient(name: "Rice", quantity: 200, unit: "g", sortIndex: 1),
        ]

        let estimate = try XCTUnwrap(NutritionEstimator.estimate(for: recipe))
        // 400g chicken breast (660 cal) + 200g rice (260 cal) = 920 / 2 servings = 460.
        XCTAssertEqual(estimate.calories, 460)
        // 124g protein + 5.4g = ~65/serving
        XCTAssertEqual(estimate.proteinGrams, 65)
        XCTAssertEqual(estimate.confidence, 1.0)
        XCTAssertTrue(estimate.caloriesRange.contains(estimate.calories))
    }

    func testConfidenceDropsWithUnknownIngredients() throws {
        let recipe = Recipe(title: "Mystery Bowl", servings: 1)
        recipe.ingredients = [
            RecipeIngredient(name: "Rice", quantity: 100, unit: "g", sortIndex: 0),
            RecipeIngredient(name: "Dragonfruit foam", sortIndex: 1),
        ]
        let estimate = try XCTUnwrap(NutritionEstimator.estimate(for: recipe))
        XCTAssertEqual(estimate.confidence, 0.5)
        XCTAssertEqual(estimate.matchedCount, 1)
    }

    func testNoMatchesMeansNoEstimate() {
        let recipe = Recipe(title: "Alien Cuisine", servings: 2)
        recipe.ingredients = [RecipeIngredient(name: "Quantum jelly", sortIndex: 0)]
        XCTAssertNil(NutritionEstimator.estimate(for: recipe))
    }

    func testPieceWeightsForUnitlessIngredients() {
        let egg = RecipeIngredient(name: "Eggs", quantity: 2)
        XCTAssertEqual(NutritionEstimator.estimatedGrams(for: egg), 100)
    }
}

final class ProgressStatsTests: XCTestCase {

    private func session(daysAgo: Int, recipe: Recipe? = nil) -> CookSession {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return CookSession(date: date, servingsMade: 2, recipe: recipe)
    }

    func testStreakCountsConsecutiveDays() {
        let sessions = [session(daysAgo: 0), session(daysAgo: 1), session(daysAgo: 2), session(daysAgo: 5)]
        XCTAssertEqual(ProgressStats.cookingStreak(sessions: sessions), 3)
    }

    func testStreakSurvivesIfCookedYesterdayButNotToday() {
        let sessions = [session(daysAgo: 1), session(daysAgo: 2)]
        XCTAssertEqual(ProgressStats.cookingStreak(sessions: sessions), 2)
    }

    func testStreakBreaksAfterAGap() {
        let sessions = [session(daysAgo: 3), session(daysAgo: 4)]
        XCTAssertEqual(ProgressStats.cookingStreak(sessions: sessions), 0)
    }

    func testFrequentMealsNeedAtLeastTwoLogs() {
        let logs = [
            FoodLog(title: "Protein shake", source: .quickAdd),
            FoodLog(title: "Protein shake", source: .quickAdd),
            FoodLog(title: "One-off salad", source: .manual),
        ]
        let frequents = ProgressStats.frequentMeals(logs: logs)
        XCTAssertEqual(frequents, ["Protein shake"])
    }

    func testRecipesTriedCountsDistinct() {
        let recipeA = Recipe(title: "A")
        let recipeB = Recipe(title: "B")
        let sessions = [
            session(daysAgo: 2, recipe: recipeA),
            session(daysAgo: 1, recipe: recipeA),
            session(daysAgo: 40, recipe: recipeB),
        ]
        let tried = ProgressStats.recipesTried(sessions: sessions)
        XCTAssertEqual(tried.total, 2)
        XCTAssertEqual(tried.newThisMonth, 1)
    }
}

final class TasteProfileBuilderTests: XCTestCase {

    func testLovedTagsFloatToTheTop() {
        let loved = Recipe(title: "Spicy Noodles", tags: ["spicy", "noodles"])
        loved.rating = 5
        let meh = Recipe(title: "Plain Toast", tags: ["bland"])
        meh.rating = 2

        let sessions = [
            CookSession(servingsMade: 2, recipe: loved),
            CookSession(servingsMade: 2, recipe: loved),
        ]

        let profile = TasteProfileBuilder.descriptors(recipes: [loved, meh], sessions: sessions)
        // Both loved tags carry equal weight; both must rank, "bland" must not.
        XCTAssertEqual(Set(profile.prefix(2)), Set(["spicy", "noodles"]))
        XCTAssertFalse(profile.contains("bland"))
    }
}

// MARK: - Phase 8: Today planner

final class TodayPlannerTests: XCTestCase {

    private func meal(
        _ type: MealType,
        daysFromNow: Int = 0,
        exactTime: Date? = nil,
        status: MealStatus = .planned
    ) -> PlannedMeal {
        let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: .now)!
        return PlannedMeal(date: date, mealType: type, exactTime: exactTime, status: status)
    }

    func testNextUpPicksEarliestMealTypeWhenNoExactTimes() {
        let dinner = meal(.dinner)
        let lunch = meal(.lunch)
        let next = TodayPlanner.nextUp(meals: [dinner, lunch])
        XCTAssertIdentical(next, lunch)
    }

    func testNextUpPrefersExactTimesOverMealTypeOrder() {
        let earlyDinner = meal(.dinner, exactTime: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now))
        let untimedLunch = meal(.lunch)
        let next = TodayPlanner.nextUp(meals: [untimedLunch, earlyDinner])
        XCTAssertIdentical(next, earlyDinner)
    }

    func testNextUpSkipsResolvedMealsAndOtherDays() {
        let eaten = meal(.breakfast, status: .eaten)
        let tomorrow = meal(.lunch, daysFromNow: 1)
        let dinner = meal(.dinner)
        let next = TodayPlanner.nextUp(meals: [eaten, tomorrow, dinner])
        XCTAssertIdentical(next, dinner)
    }

    func testNextUpReturnsNilWhenNothingPlannedToday() {
        let tomorrow = meal(.dinner, daysFromNow: 1)
        XCTAssertNil(TodayPlanner.nextUp(meals: [tomorrow]))
    }

    func testUseSoonExcludesOutOfStockAndSortsByUrgency() {
        let urgent = PantryItem(name: "Spinach", useSoonDate: .now)
        let later = PantryItem(name: "Yogurt", useSoonDate: Calendar.current.date(byAdding: .day, value: 2, to: .now))
        let out = PantryItem(name: "Milk", roughQuantity: .out, useSoonDate: .now)
        let normal = PantryItem(name: "Rice")

        let items = TodayPlanner.useSoonItems(pantry: [later, out, urgent, normal])
        XCTAssertEqual(items.map(\.name), ["Spinach", "Yogurt"])
    }

    func testMissingLineNamesFirstMissingAndCountsRest() {
        let recipe = Recipe(title: "Curry")
        recipe.ingredients = [
            RecipeIngredient(name: "Saffron", sortIndex: 0),
            RecipeIngredient(name: "Dragon fruit", sortIndex: 1),
        ]
        let line = TodayPlanner.missingLine(for: recipe, pantry: [])
        XCTAssertEqual(line, "Missing: saffron + 1 more")
    }

    func testMissingLineIsNilWhenPantryCoversEverything() {
        let recipe = Recipe(title: "Rice Bowl")
        recipe.ingredients = [RecipeIngredient(name: "Rice", sortIndex: 0)]
        let line = TodayPlanner.missingLine(for: recipe, pantry: [PantryItem(name: "Rice")])
        XCTAssertNil(line)
    }

    func testMissingLineSuggestsSwapWhenPantryHasSubstitute() {
        let recipe = Recipe(title: "Pasta")
        recipe.ingredients = [RecipeIngredient(name: "Heavy cream", sortIndex: 0)]
        let pantry = [PantryItem(name: "Greek yogurt"), PantryItem(name: "Butter")]
        let line = TodayPlanner.missingLine(for: recipe, pantry: pantry)
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("Swap:"), "expected a swap suggestion, got \(line!)")
    }
}

// MARK: - Phase 9: Diet guard

final class DietGuardTests: XCTestCase {

    private func recipe(_ title: String, ingredients: [String]) -> Recipe {
        let recipe = Recipe(title: title)
        recipe.ingredients = ingredients.enumerated().map { index, name in
            RecipeIngredient(name: name, sortIndex: index)
        }
        recipe.steps = [RecipeStep(index: 0, text: "Cook.")]
        return recipe
    }

    func testHalalFlagsPorkAndAlcohol() {
        let carbonara = recipe("Carbonara", ingredients: ["Bacon", "White wine", "Eggs", "Parmesan"])
        let conflicts = DietGuard.conflicts(in: carbonara, rules: [.halal], allergies: [])
        XCTAssertEqual(conflicts.count, 2)
        XCTAssertTrue(conflicts.allSatisfy(\.isBlocking))
    }

    func testAllergyOutranksRuleConflicts() {
        let dish = recipe("Satay", ingredients: ["Pork", "Peanut butter"])
        let conflicts = DietGuard.conflicts(in: dish, rules: [.noPork], allergies: ["peanut"])
        XCTAssertEqual(conflicts.first?.severity, .allergy)
    }

    func testDislikeIsFlaggedButNotBlocking() {
        let salsa = recipe("Salsa", ingredients: ["Tomato", "Cilantro"])
        let conflicts = DietGuard.conflicts(in: salsa, rules: [], allergies: [], dislikes: ["cilantro"])
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertFalse(conflicts[0].isBlocking)
        XCTAssertTrue(DietGuard.isSuggestable(salsa, rules: [], allergies: []))
    }

    func testWordBoundaryAvoidsFalsePositives() {
        // "ham" must not flag shawarma; "egg" must not flag eggplant.
        let shawarma = recipe("Shawarma", ingredients: ["Chicken shawarma spice", "Eggplant"])
        XCTAssertTrue(DietGuard.conflicts(in: shawarma, rules: [.noPork], allergies: ["egg"]).isEmpty)
    }

    func testPluralsMatchBothWays() {
        let cookies = recipe("Cookies", ingredients: ["Eggs", "Flour"])
        let conflicts = DietGuard.conflicts(in: cookies, rules: [], allergies: ["egg"])
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.severity, .allergy)
    }

    func testVeganBlocksDairyMeatAndHoney() {
        let bowl = recipe("Honey Chicken", ingredients: ["Chicken", "Honey", "Butter", "Rice"])
        let conflicts = DietGuard.conflicts(in: bowl, rules: [.vegan], allergies: [])
        XCTAssertEqual(conflicts.count, 3)
        XCTAssertFalse(DietGuard.isSuggestable(bowl, rules: [.vegan], allergies: []))
    }

    func testPescatarianAllowsFishButBlocksMeat() {
        let salmon = recipe("Salmon Rice Bowl", ingredients: ["Salmon", "Rice", "Soy sauce"])
        XCTAssertTrue(DietGuard.conflicts(in: salmon, rules: [.pescatarian], allergies: []).isEmpty)
        XCTAssertTrue(DietGuard.isSuggestable(salmon, rules: [.pescatarian], allergies: []))

        let beef = recipe("Beef Tacos", ingredients: ["Beef", "Tortilla"])
        let conflicts = DietGuard.conflicts(in: beef, rules: [.pescatarian], allergies: [])
        XCTAssertEqual(conflicts.map(\.ingredientName), ["Beef"])
        XCTAssertTrue(conflicts.allSatisfy(\.isBlocking))
    }

    func testKosherBlocksPorkAndShellfishButAllowsFinFish() {
        let shrimp = recipe("Shrimp Scampi", ingredients: ["Shrimp", "Garlic", "Butter"])
        XCTAssertTrue(DietGuard.conflicts(in: shrimp, rules: [.kosher], allergies: []).contains { $0.isBlocking })

        let porkDish = recipe("Pork Ribs", ingredients: ["Pork", "Salt"])
        XCTAssertFalse(DietGuard.isSuggestable(porkDish, rules: [.kosher], allergies: []))

        // Fin fish (salmon) is kosher-acceptable for this keyword guard.
        let salmon = recipe("Baked Salmon", ingredients: ["Salmon", "Lemon", "Dill"])
        XCTAssertTrue(DietGuard.conflicts(in: salmon, rules: [.kosher], allergies: []).isEmpty)
    }

    func testWeekPlannerNeverPlansAllergens() {
        let peanutDish = recipe("Peanut Noodles", ingredients: ["Peanuts", "Noodles"])
        let safeDish = recipe("Tomato Pasta", ingredients: ["Tomato", "Pasta"])
        let slots = WeekPlanner.draft(WeekPlanner.Input(
            days: 2,
            mealTypes: [.dinner],
            useLeftovers: false,
            recipes: [peanutDish, safeDish],
            pantry: [],
            leftovers: [],
            recentSessions: [],
            rules: [],
            allergies: ["peanut"]
        ))
        XCTAssertFalse(slots.contains { $0.recipe === peanutDish })
    }

    func testSubstitutionsRespectRules() {
        // Dairy-free user missing butter: pantry has margarine and... butter? No —
        // a substitute that is itself dairy must never be offered.
        let pantry = [PantryItem(name: "Ghee"), PantryItem(name: "Olive oil")]
        let subs = SubstitutionService.availableSubstitutions(
            for: "butter",
            pantry: pantry,
            rules: [.dairyFree],
            allergies: []
        )
        XCTAssertFalse(subs.contains { $0.name.lowercased().contains("ghee") })
    }
}

// MARK: - Recipe time estimation

final class RecipeTimeEstimateTests: XCTestCase {

    private func recipe(prep: Int, cook: Int, stepDurations: [Int?]) -> Recipe {
        let recipe = Recipe(title: "Timed", prepMinutes: prep, cookMinutes: cook)
        recipe.steps = stepDurations.enumerated().map { index, seconds in
            RecipeStep(index: index, text: "Step \(index)", durationSeconds: seconds)
        }
        return recipe
    }

    func testExplicitTimesAreTrustedAndNotEstimated() {
        let r = recipe(prep: 10, cook: 20, stepDurations: [600, nil])
        XCTAssertEqual(r.estimatedMinutes, 30)
        XCTAssertFalse(r.minutesAreEstimated)
        XCTAssertEqual(r.timeLabel, "30 min")
    }

    func testFallsBackToStepTimersPlusBuffer() {
        // No prep/cook: 10 min of timers + one untimed step (4) + 5 base = 19.
        let r = recipe(prep: 0, cook: 0, stepDurations: [600, nil])
        XCTAssertEqual(r.estimatedMinutes, 19)
        XCTAssertTrue(r.minutesAreEstimated)
        XCTAssertEqual(r.timeLabel, "~19 min")
    }

    func testAllUntimedStepsStillEstimateFromCount() {
        // Three untimed steps, no timers: 3 * 4 = 12, no base buffer added.
        let r = recipe(prep: 0, cook: 0, stepDurations: [nil, nil, nil])
        XCTAssertEqual(r.estimatedMinutes, 12)
        XCTAssertTrue(r.minutesAreEstimated)
    }

    func testNoTimesAndNoStepsShowsDash() {
        let r = recipe(prep: 0, cook: 0, stepDurations: [])
        XCTAssertEqual(r.estimatedMinutes, 0)
        XCTAssertFalse(r.minutesAreEstimated)
        XCTAssertEqual(r.timeLabel, "—")
    }
}

// MARK: - Sharing & leftovers remix

final class RecipeShareServiceTests: XCTestCase {

    func testShareTextContainsEverythingNeededToCook() {
        let recipe = Recipe(title: "Garlic Butter Pasta", servings: 2, prepMinutes: 5, cookMinutes: 15)
        recipe.ingredients = [
            RecipeIngredient(name: "Spaghetti", quantity: 200, unit: "g", sortIndex: 0),
            RecipeIngredient(name: "Garlic", quantity: 3, unit: "clove", sortIndex: 1),
            RecipeIngredient(name: "Chili flakes", isOptional: true, sortIndex: 2),
        ]
        recipe.steps = [
            RecipeStep(index: 0, text: "Boil the pasta."),
            RecipeStep(index: 1, text: "Fry garlic in butter, toss with pasta."),
        ]
        recipe.sourceURL = "https://example.com/pasta"

        let text = RecipeShareService.shareText(for: recipe)

        XCTAssertTrue(text.contains("Garlic Butter Pasta"))
        XCTAssertTrue(text.contains("serves 2 · 20 min"))
        XCTAssertTrue(text.contains("INGREDIENTS"))
        XCTAssertTrue(text.contains("Garlic"))
        XCTAssertTrue(text.contains("(optional)"))
        XCTAssertTrue(text.contains("1. Boil the pasta."))
        XCTAssertTrue(text.contains("https://example.com/pasta"))
        XCTAssertTrue(text.contains("Glutt"))
    }

    func testShareTextOmitsEmptySections() {
        let recipe = Recipe(title: "Mystery Dish")
        let text = RecipeShareService.shareText(for: recipe)
        XCTAssertFalse(text.contains("INGREDIENTS"))
        XCTAssertFalse(text.contains("STEPS"))
        XCTAssertFalse(text.contains("Original:"))
    }
}

final class LeftoverRemixTests: XCTestCase {

    func testChickenLeftoversGetChickenIdeas() {
        let ideas = LeftoverRemix.tableIdeas(for: "Hot Honey Chicken Rice")
        XCTAssertFalse(ideas.isEmpty)
        XCTAssertTrue(ideas.contains { $0.title.lowercased().contains("chicken") })
    }

    func testUnknownLeftoversStillGetGenericIdeas() {
        let ideas = LeftoverRemix.tableIdeas(for: "Grandma's casserole")
        XCTAssertFalse(ideas.isEmpty)
        XCTAssertTrue(ideas.allSatisfy { !$0.how.isEmpty })
    }

    func testRemixedMealShowsItsNewName() {
        let leftover = Leftover(title: "Korean beef bowls", servingsRemaining: 2)
        let meal = PlannedMeal(
            date: .now,
            mealType: .lunch,
            leftover: leftover,
            freeformTitle: "Beef tacos (from Korean beef bowls)"
        )
        XCTAssertEqual(meal.displayTitle, "Beef tacos (from Korean beef bowls)")
    }
}

// MARK: - Social media import

final class SocialMediaImportTests: XCTestCase {

    func testRecognizesVideoPlatformURLs() {
        XCTAssertTrue(SocialMediaImport.canHandle(URL(string: "https://www.tiktok.com/@chef/video/7299")!))
        XCTAssertTrue(SocialMediaImport.canHandle(URL(string: "https://vm.tiktok.com/ZMabc123/")!))
        XCTAssertTrue(SocialMediaImport.canHandle(URL(string: "https://www.youtube.com/watch?v=abc")!))
        XCTAssertTrue(SocialMediaImport.canHandle(URL(string: "https://youtu.be/abc")!))
        XCTAssertTrue(SocialMediaImport.canHandle(URL(string: "https://www.youtube.com/shorts/abc")!))
        // Instagram has no public oEmbed — it stays on the HTML path.
        XCTAssertFalse(SocialMediaImport.canHandle(URL(string: "https://www.instagram.com/reel/abc/")!))
        XCTAssertFalse(SocialMediaImport.canHandle(URL(string: "https://www.allrecipes.com/recipe/1234")!))
    }

    func testExtractsYouTubeDescriptionFromPlayerJSON() {
        let html = #"""
        <html><script>var ytInitialPlayerResponse = {"videoDetails":{"videoId":"x",
        "shortDescription":"The best fried rice!\n\nINGREDIENTS:\n- 2 cups day-old rice\n- 2 eggs\n\u0026 a wok","author":"Chef"}};</script></html>
        """#
        let description = SocialMediaImport.extractYouTubeDescription(html: html)
        XCTAssertNotNil(description)
        XCTAssertTrue(description!.contains("INGREDIENTS:"))
        XCTAssertTrue(description!.contains("2 cups day-old rice"))
        XCTAssertTrue(description!.contains("& a wok"), "JSON escapes should be decoded")
        XCTAssertTrue(description!.contains("\n"), "Escaped newlines should become real newlines")
    }

    func testExtractReturnsNilWhenNoDescription() {
        XCTAssertNil(SocialMediaImport.extractYouTubeDescription(html: "<html><body>nothing here</body></html>"))
    }

    func testCaptionTitleStripsHashtagsAndMentions() {
        let title = SocialMediaImport.captionTitle(
            "Creamy garlic chicken pasta 🤤 #fyp #easyrecipe @somecook\nFull recipe below!"
        )
        XCTAssertEqual(title, "Creamy garlic chicken pasta 🤤")
    }

    func testCaptionTitleTruncatesLongCaptions() {
        let caption = String(repeating: "very tasty food ", count: 20)
        let title = SocialMediaImport.captionTitle(caption)
        XCTAssertNotNil(title)
        XCTAssertLessThanOrEqual(title!.count, 75)
        XCTAssertTrue(title!.hasSuffix("…"))
    }

    func testEmptyCaptionGivesNoTitle() {
        XCTAssertNil(SocialMediaImport.captionTitle("#fyp #food"))
    }
}

// MARK: - Pantry scan

final class PantryScanTests: XCTestCase {

    func testQuantityMappingDefaultsToFull() {
        XCTAssertEqual(PantryScan.mapQuantity("half"), .half)
        XCTAssertEqual(PantryScan.mapQuantity("low"), .low)
        XCTAssertEqual(PantryScan.mapQuantity("full"), .full)
        XCTAssertEqual(PantryScan.mapQuantity("overflowing"), .full)
        XCTAssertEqual(PantryScan.mapQuantity(nil), .full)
    }

    func testCategoryMappingTrustsModelThenFallsBack() {
        XCTAssertEqual(PantryScan.mapCategory("dairy", name: "whatever"), .dairy)
        XCTAssertEqual(PantryScan.mapCategory("Produce", name: "whatever"), .produce)
        // Garbage category falls back to the keyword categorizer.
        XCTAssertEqual(PantryScan.mapCategory("beverages", name: "milk"), GroceryCategorizer.categorize("milk"))
        XCTAssertEqual(PantryScan.mapCategory(nil, name: "chicken breast"), GroceryCategorizer.categorize("chicken breast"))
    }

    func testReplacedMealStatusFlow() {
        let meal = PlannedMeal(date: .now, mealType: .dinner, freeformTitle: "Chicken rice bowl")
        XCTAssertEqual(meal.status, .planned)
        // The log-food flow marks it replaced when the user ate something else.
        meal.status = .replaced
        XCTAssertEqual(meal.status, .replaced)
    }
}
