#if DEBUG
import Foundation
import SwiftData

/// Development-only sample data so every screen has something to render.
enum SeedData {

    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Recipe>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }
        seed(context: context)
    }

    private static func seed(context: ModelContext) {
        // Recipes
        let lemonChicken = Recipe(
            title: "Creamy Lemon Chicken Rice Bowl",
            summary: "Weeknight bowl with a tangy yogurt-lemon sauce.",
            sourceCreator: "@halalfoodguy",
            sourceURL: "https://tiktok.com/@halalfoodguy/video/1",
            sourcePlatform: .tiktok,
            importedAt: .now,
            importConfidence: 0.92,
            servings: 4,
            prepMinutes: 15,
            cookMinutes: 30,
            difficulty: .beginner,
            tags: ["High protein", "Dinner", "Chicken"]
        )
        lemonChicken.ingredients = [
            RecipeIngredient(name: "Chicken thighs", quantity: 600, unit: "g", role: .protein, sortIndex: 0),
            RecipeIngredient(name: "Rice", quantity: 2, unit: "cups", role: .starch, sortIndex: 1),
            RecipeIngredient(name: "Greek yogurt", quantity: 0.5, unit: "cup", role: .dairy, sortIndex: 2),
            RecipeIngredient(name: "Lemon", quantity: 1, role: .acid, sortIndex: 3),
            RecipeIngredient(name: "Garlic", quantity: 3, unit: "cloves", role: .aromatic, sortIndex: 4),
            RecipeIngredient(name: "Parsley", isOptional: true, role: .garnish, sortIndex: 5),
        ]
        lemonChicken.steps = [
            RecipeStep(index: 0, text: "Season chicken thighs with salt, pepper, and paprika."),
            RecipeStep(index: 1, text: "Sear chicken 4 minutes per side until golden.", durationSeconds: 480),
            RecipeStep(index: 2, text: "Cook rice while the chicken rests.", durationSeconds: 900),
            RecipeStep(index: 3, text: "Whisk yogurt, lemon juice, and garlic into a sauce."),
            RecipeStep(index: 4, text: "Slice chicken over rice, drizzle sauce, top with parsley."),
        ]
        lemonChicken.calories = 620
        lemonChicken.proteinGrams = 48

        let beefStew = Recipe(
            title: "Slow Beef Stew",
            sourceURL: "https://example.com/beef-stew",
            sourcePlatform: .website,
            importedAt: .now,
            importConfidence: 0.78,
            servings: 6,
            prepMinutes: 20,
            cookMinutes: 150,
            difficulty: .intermediate,
            tags: ["Comfort", "Meal prep"]
        )
        beefStew.ingredients = [
            RecipeIngredient(name: "Beef cubes", quantity: 800, unit: "g", role: .protein, sortIndex: 0),
            RecipeIngredient(name: "Carrots", quantity: 3, role: .vegetable, sortIndex: 1),
            RecipeIngredient(name: "Potatoes", quantity: 4, role: .starch, sortIndex: 2),
            RecipeIngredient(name: "Beef stock", quantity: 1, unit: "liter", role: .liquid, sortIndex: 3),
        ]
        beefStew.steps = [
            RecipeStep(index: 0, text: "Brown the beef in batches."),
            RecipeStep(index: 1, text: "Add vegetables and stock, simmer 2.5 hours.", durationSeconds: 9000),
        ]

        context.insert(lemonChicken)
        context.insert(beefStew)

        // Collection
        let weeknight = RecipeCollection(name: "Weeknight dinners")
        weeknight.recipes = [lemonChicken]
        context.insert(weeknight)

        // Pantry
        let pantryItems: [PantryItem] = [
            PantryItem(name: "Chicken thighs", category: .meat, roughQuantity: .half, location: .fridge),
            PantryItem(name: "Rice", category: .pantry, roughQuantity: .full),
            PantryItem(name: "Eggs", category: .dairy, roughQuantity: .half, location: .fridge),
            PantryItem(
                name: "Spinach", category: .produce, roughQuantity: .low, location: .fridge,
                useSoonDate: Calendar.current.date(byAdding: .day, value: 2, to: .now)
            ),
            PantryItem(name: "Honey", category: .pantry, roughQuantity: .full),
        ]
        pantryItems.forEach(context.insert)

        // Groceries
        let groceries: [GroceryItem] = [
            GroceryItem(
                name: "Greek yogurt", quantityText: "1 tub", category: .dairy,
                substitutionHint: "Sour cream works", sourceRecipeTitles: [lemonChicken.title]
            ),
            GroceryItem(name: "Parsley", category: .produce, isOptional: true, sourceRecipeTitles: [lemonChicken.title]),
            GroceryItem(name: "Lemons", quantityText: "2", category: .produce, sourceRecipeTitles: [lemonChicken.title]),
        ]
        groceries.forEach(context.insert)

        // Leftover
        let stewLeftover = Leftover(
            title: "Beef stew",
            servingsRemaining: 2.5,
            cookedAt: Calendar.current.date(byAdding: .day, value: -2, to: .now)!,
            sourceRecipe: beefStew
        )
        context.insert(stewLeftover)

        // Plan: dinner tonight, leftover lunch tomorrow
        let dinnerTime = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: .now)!
        context.insert(PlannedMeal(date: .now, mealType: .dinner, exactTime: dinnerTime, recipe: lemonChicken))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        context.insert(PlannedMeal(date: tomorrow, mealType: .lunch, leftover: stewLeftover))

        // A past cook session
        let session = CookSession(
            date: Calendar.current.date(byAdding: .day, value: -2, to: .now)!,
            servingsMade: 6,
            servingsEaten: 1.5,
            recipe: beefStew
        )
        session.rating = 4
        context.insert(session)

        // Prefs
        let prefs = UserPrefs.current(in: context)
        prefs.displayName = "Malik"
        prefs.dietaryRules = [.halal]

        try? context.save()
    }
}
#endif
