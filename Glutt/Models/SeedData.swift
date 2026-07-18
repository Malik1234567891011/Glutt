import Foundation
import SwiftData

/// Sample data for testing. Compiled into all build configs, but only ever
/// invoked when the app is launched with `-seed` (the "Glutt Beta" scheme
/// passes it), so distributed builds without that argument never seed.
/// Bump `seedVersion` to wipe and reseed after content changes.
enum SeedData {

    private static let seedVersion = 2
    private static let seedVersionKey = "glutt.seedVersion"

    static func seedIfNeeded(context: ModelContext) {
        let installedVersion = UserDefaults.standard.integer(forKey: seedVersionKey)
        let count = (try? context.fetchCount(FetchDescriptor<Recipe>())) ?? 0
        guard count == 0 || installedVersion < seedVersion else { return }

        if installedVersion < seedVersion {
            wipe(context: context)
        }
        seed(context: context)
        UserDefaults.standard.set(seedVersion, forKey: seedVersionKey)
    }

    private static func wipe(context: ModelContext) {
        // Fetch-and-delete is more reliable than batch delete for
        // models with relationships (batch deletes skip cascade rules).
        func deleteAll<T: PersistentModel>(_ type: T.Type) {
            let items = (try? context.fetch(FetchDescriptor<T>())) ?? []
            items.forEach { context.delete($0) }
        }
        deleteAll(CookSession.self)
        deleteAll(GroceryItem.self)
        deleteAll(PantryItem.self)
        deleteAll(RecipeCollection.self)
        deleteAll(Recipe.self)
        try? context.save()
    }

    // MARK: - Recipe builder

    private struct Seed {
        let title: String
        let asset: String
        let summary: String
        let creator: String?
        let platform: SourcePlatform
        let confidence: Double?
        let servings: Int
        let prep: Int
        let cook: Int
        let difficulty: Difficulty
        let tags: [String]
        let calories: Int?
        let protein: Int?
        let ingredients: [(String, Double?, String?, IngredientRole?)]
        let steps: [(String, Int?)]
    }

    private static func build(_ seed: Seed) -> Recipe {
        let recipe = Recipe(
            title: seed.title,
            summary: seed.summary,
            sourceCreator: seed.creator,
            sourceURL: seed.creator != nil ? "https://example.com/\(seed.asset)" : nil,
            sourcePlatform: seed.platform,
            importedAt: seed.platform == .manual ? nil : .now,
            importConfidence: seed.confidence,
            servings: seed.servings,
            prepMinutes: seed.prep,
            cookMinutes: seed.cook,
            difficulty: seed.difficulty,
            tags: seed.tags
        )
        recipe.imageAssetName = seed.asset
        recipe.calories = seed.calories
        recipe.proteinGrams = seed.protein
        recipe.ingredients = seed.ingredients.enumerated().map { index, item in
            RecipeIngredient(name: item.0, quantity: item.1, unit: item.2, role: item.3, sortIndex: index)
        }
        recipe.steps = seed.steps.enumerated().map { index, step in
            RecipeStep(index: index, text: step.0, durationSeconds: step.1)
        }
        return recipe
    }

    // MARK: - Seed content

    private static func seed(context: ModelContext) {
        let chickenRiceBowl = build(Seed(
            title: "Creamy Lemon Chicken Rice Bowl",
            asset: "chickenRiceBowl",
            summary: "Weeknight bowl with seared chicken and a tangy yogurt-lemon sauce.",
            creator: "@halalfoodguy", platform: .tiktok, confidence: 0.92,
            servings: 4, prep: 15, cook: 30, difficulty: .beginner,
            tags: ["High protein", "Dinner", "Chicken"],
            calories: 620, protein: 48,
            ingredients: [
                ("Chicken thighs", 600, "g", .protein),
                ("Rice", 2, "cups", .starch),
                ("Greek yogurt", 0.5, "cup", .dairy),
                ("Lemon", 1, nil, .acid),
                ("Garlic", 3, "cloves", .aromatic),
                ("Parsley", nil, nil, .garnish),
            ],
            steps: [
                ("Season chicken thighs with salt, pepper, and paprika.", nil),
                ("Sear chicken 4 minutes per side until golden.", 480),
                ("Cook rice while the chicken rests.", 900),
                ("Whisk yogurt, lemon juice, and garlic into a sauce.", nil),
                ("Slice chicken over rice, drizzle sauce, top with parsley.", nil),
            ]
        ))

        let hotHoney = build(Seed(
            title: "Hot Honey Chicken Rice",
            asset: "hotHoneyChickenRice",
            summary: "Crispy chicken glazed in hot honey over steamed rice.",
            creator: "@spicykitchen", platform: .instagram, confidence: 0.88,
            servings: 2, prep: 10, cook: 25, difficulty: .beginner,
            tags: ["Quick", "Chicken", "Spicy"],
            calories: 680, protein: 42,
            ingredients: [
                ("Chicken breast", 400, "g", .protein),
                ("Honey", 3, "tbsp", .sweetener),
                ("Sriracha", 1, "tbsp", .spice),
                ("Rice", 1.5, "cups", .starch),
                ("Butter", 1, "tbsp", .fat),
                ("Scallions", 2, nil, .garnish),
            ],
            steps: [
                ("Cube chicken and season with garlic powder and salt.", nil),
                ("Pan-fry chicken until crispy at the edges.", 600),
                ("Melt butter with honey and sriracha, toss chicken to glaze.", 120),
                ("Serve over rice and top with sliced scallions.", nil),
            ]
        ))

        let koreanBeef = build(Seed(
            title: "Korean Beef Meal Prep Bowls",
            asset: "koreanBeefMealPrep",
            summary: "Sweet-savory ground beef with rice and veg — meal prep workhorse.",
            creator: "@mealprepmania", platform: .tiktok, confidence: 0.85,
            servings: 5, prep: 15, cook: 20, difficulty: .beginner,
            tags: ["Meal prep", "High protein", "Beef"],
            calories: 540, protein: 38,
            ingredients: [
                ("Ground beef", 750, "g", .protein),
                ("Soy sauce", 0.25, "cup", .liquid),
                ("Brown sugar", 2, "tbsp", .sweetener),
                ("Garlic", 4, "cloves", .aromatic),
                ("Rice", 2.5, "cups", .starch),
                ("Broccoli", 2, "cups", .vegetable),
                ("Sesame seeds", 1, "tbsp", .garnish),
            ],
            steps: [
                ("Cook rice and steam broccoli.", 900),
                ("Brown the beef with garlic, drain excess fat.", 480),
                ("Add soy sauce and brown sugar, simmer 3 minutes.", 180),
                ("Portion into 5 containers with rice and broccoli.", nil),
            ]
        ))

        let shawarmaBowl = build(Seed(
            title: "Saffron Chicken Shawarma Jewel Bowl",
            asset: "saffronChickenShawarmaBowl",
            summary: "Marinated shawarma-spiced chicken over saffron rice with pomegranate.",
            creator: "Feast & Flavor", platform: .website, confidence: 0.95,
            servings: 4, prep: 25, cook: 35, difficulty: .intermediate,
            tags: ["Dinner", "Halal", "Chicken"],
            calories: 710, protein: 46,
            ingredients: [
                ("Chicken thighs", 700, "g", .protein),
                ("Basmati rice", 2, "cups", .starch),
                ("Saffron", 1, "pinch", .spice),
                ("Shawarma spice mix", 2, "tbsp", .spice),
                ("Greek yogurt", 0.5, "cup", .dairy),
                ("Pomegranate seeds", 0.5, "cup", .garnish),
                ("Cucumber", 1, nil, .vegetable),
            ],
            steps: [
                ("Marinate chicken in yogurt and shawarma spices, at least 20 minutes.", 1200),
                ("Steep saffron in hot water, start the rice with it.", 900),
                ("Roast chicken at 425°F until charred at the edges.", 1500),
                ("Slice chicken, build bowls, finish with pomegranate and cucumber.", nil),
            ]
        ))

        let koftaWrap = build(Seed(
            title: "Kofta Flatbread Wrap",
            asset: "koftaFlatbreadWrap",
            summary: "Grilled beef kofta wrapped in warm flatbread with garlic sauce.",
            creator: "@streetfoodathome", platform: .youtube, confidence: 0.81,
            servings: 4, prep: 20, cook: 15, difficulty: .intermediate,
            tags: ["Dinner", "Beef", "Halal"],
            calories: 650, protein: 36,
            ingredients: [
                ("Ground beef", 500, "g", .protein),
                ("Onion", 1, nil, .aromatic),
                ("Parsley", 0.5, "cup", .garnish),
                ("Flatbread", 4, nil, .starch),
                ("Garlic sauce", 0.5, "cup", .fat),
                ("Tomatoes", 2, nil, .vegetable),
            ],
            steps: [
                ("Mix beef with grated onion, parsley, and spices; shape onto skewers.", nil),
                ("Grill kofta until charred and cooked through.", 720),
                ("Warm flatbreads, spread garlic sauce, add kofta and tomatoes, wrap.", nil),
            ]
        ))

        let koftaMealPrep = build(Seed(
            title: "Kofta, Potato & Salad Meal Prep",
            asset: "koftaPotatoSaladMealPrep",
            summary: "Kofta with roasted potatoes and a crunchy salad, boxed for the week.",
            creator: nil, platform: .manual, confidence: nil,
            servings: 4, prep: 25, cook: 35, difficulty: .intermediate,
            tags: ["Meal prep", "Beef", "Halal"],
            calories: 590, protein: 34,
            ingredients: [
                ("Ground beef", 500, "g", .protein),
                ("Potatoes", 4, nil, .starch),
                ("Cucumber", 1, nil, .vegetable),
                ("Tomatoes", 2, nil, .vegetable),
                ("Olive oil", 2, "tbsp", .fat),
                ("Lemon", 1, nil, .acid),
            ],
            steps: [
                ("Roast potato wedges with olive oil at 425°F.", 1800),
                ("Shape and pan-sear kofta fingers.", 720),
                ("Chop salad, dress with lemon and olive oil.", nil),
                ("Portion into 4 containers.", nil),
            ]
        ))

        let steakPotatoBowl = build(Seed(
            title: "Garlic Butter Steak Potato Bowl",
            asset: "garlicButterSteakPotatoBowl",
            summary: "Seared steak bites and crispy potatoes in garlic butter.",
            creator: "@proteinplates", platform: .tiktok, confidence: 0.9,
            servings: 2, prep: 15, cook: 25, difficulty: .beginner,
            tags: ["High protein", "Dinner", "Beef"],
            calories: 740, protein: 52,
            ingredients: [
                ("Sirloin steak", 450, "g", .protein),
                ("Baby potatoes", 400, "g", .starch),
                ("Butter", 3, "tbsp", .fat),
                ("Garlic", 4, "cloves", .aromatic),
                ("Parsley", nil, nil, .garnish),
            ],
            steps: [
                ("Boil potatoes until just tender, then crisp in a hot pan.", 900),
                ("Sear steak bites in batches, 2 minutes per side.", 480),
                ("Add butter and garlic, toss everything to coat.", 120),
                ("Top with parsley and serve in bowls.", nil),
            ]
        ))

        let greenGoddess = build(Seed(
            title: "Green Goddess Steak & Potato Plate",
            asset: "greenGoddessSteakPlate",
            summary: "Sliced steak and potatoes under a herby green goddess sauce.",
            creator: "Feast & Flavor", platform: .website, confidence: 0.87,
            servings: 2, prep: 20, cook: 25, difficulty: .intermediate,
            tags: ["Dinner", "Beef"],
            calories: 700, protein: 48,
            ingredients: [
                ("Flank steak", 400, "g", .protein),
                ("Potatoes", 3, nil, .starch),
                ("Greek yogurt", 0.5, "cup", .dairy),
                ("Basil", 1, "cup", .aromatic),
                ("Chives", 0.25, "cup", .aromatic),
                ("Lemon", 1, nil, .acid),
            ],
            steps: [
                ("Blend yogurt, basil, chives, and lemon into green goddess sauce.", nil),
                ("Roast potatoes until golden.", 1500),
                ("Sear steak to medium-rare, rest 5 minutes, slice.", 600),
                ("Plate steak and potatoes, spoon sauce over.", nil),
            ]
        ))

        let salmonBowl = build(Seed(
            title: "Lemon Dill Salmon Cucumber Bowl",
            asset: "lemonDillSalmonBowl",
            summary: "Flaked salmon, crisp cucumber, and dill yogurt over rice.",
            creator: "@freshfishdaily", platform: .instagram, confidence: 0.83,
            servings: 2, prep: 15, cook: 15, difficulty: .beginner,
            tags: ["Quick", "Fish", "Light"],
            calories: 560, protein: 40,
            ingredients: [
                ("Salmon fillets", 350, "g", .protein),
                ("Rice", 1.5, "cups", .starch),
                ("Cucumber", 1, nil, .vegetable),
                ("Greek yogurt", 0.5, "cup", .dairy),
                ("Dill", 2, "tbsp", .aromatic),
                ("Lemon", 1, nil, .acid),
            ],
            steps: [
                ("Roast salmon at 400°F until it flakes.", 720),
                ("Stir dill and lemon into the yogurt.", nil),
                ("Build bowls with rice, cucumber, salmon, and dill sauce.", nil),
            ]
        ))

        let beefWrap = build(Seed(
            title: "Beef Wrap with Crispy Wedges",
            asset: "beefWrapWithWedges",
            summary: "Saucy shredded beef wrap with oven wedges on the side.",
            creator: "@wrapittup", platform: .tiktok, confidence: 0.74,
            servings: 3, prep: 20, cook: 40, difficulty: .intermediate,
            tags: ["Dinner", "Beef", "Comfort"],
            calories: 760, protein: 41,
            ingredients: [
                ("Beef chuck", 500, "g", .protein),
                ("Tortillas", 3, nil, .starch),
                ("Potatoes", 3, nil, .starch),
                ("Cheddar", 0.75, "cup", .dairy),
                ("BBQ sauce", 0.33, "cup", .liquid),
            ],
            steps: [
                ("Roast potato wedges at 425°F until crispy.", 1800),
                ("Shred cooked beef and warm through with BBQ sauce.", 600),
                ("Fill tortillas with beef and cheddar, toast seam-side down.", 240),
            ]
        ))

        let fajitaSalad = build(Seed(
            title: "Steak Fajita Salad Meal Prep",
            asset: "steakFajitaSalad",
            summary: "Fajita-spiced steak with peppers over crunchy salad boxes.",
            creator: "@mealprepmania", platform: .tiktok, confidence: 0.86,
            servings: 4, prep: 20, cook: 15, difficulty: .beginner,
            tags: ["Meal prep", "High protein", "Low carb"],
            calories: 480, protein: 39,
            ingredients: [
                ("Flank steak", 500, "g", .protein),
                ("Bell peppers", 3, nil, .vegetable),
                ("Red onion", 1, nil, .aromatic),
                ("Romaine lettuce", 2, "heads", .vegetable),
                ("Lime", 2, nil, .acid),
                ("Fajita seasoning", 2, "tbsp", .spice),
            ],
            steps: [
                ("Season steak with fajita spices and sear hot, 3 minutes a side.", 360),
                ("Char peppers and onion in the same pan.", 420),
                ("Slice steak, portion over chopped romaine with lime.", nil),
            ]
        ))

        let pestoGnocchi = build(Seed(
            title: "Pesto Gnocchi Meal Prep",
            asset: "pestoGnocchiMealPrep",
            summary: "Pan-toasted gnocchi in basil pesto with chicken and tomatoes.",
            creator: nil, platform: .manual, confidence: nil,
            servings: 4, prep: 10, cook: 20, difficulty: .beginner,
            tags: ["Meal prep", "Pasta", "Quick"],
            calories: 640, protein: 35,
            ingredients: [
                ("Gnocchi", 800, "g", .starch),
                ("Chicken breast", 400, "g", .protein),
                ("Basil pesto", 0.5, "cup", .fat),
                ("Cherry tomatoes", 1.5, "cups", .vegetable),
                ("Parmesan", 0.5, "cup", .dairy),
            ],
            steps: [
                ("Pan-toast gnocchi in olive oil until golden — no boiling.", 600),
                ("Cook diced chicken in the same pan.", 480),
                ("Toss with pesto and halved tomatoes off the heat.", nil),
                ("Portion and top with parmesan.", nil),
            ]
        ))

        let yogurtBowl = build(Seed(
            title: "Greek Yogurt Berry Bowl",
            asset: "greekYogurtBowl",
            summary: "Thick yogurt, berries, honey, and crunchy granola.",
            creator: nil, platform: .manual, confidence: nil,
            servings: 1, prep: 5, cook: 0, difficulty: .beginner,
            tags: ["Breakfast", "Quick", "High protein"],
            calories: 380, protein: 28,
            ingredients: [
                ("Greek yogurt", 1, "cup", .dairy),
                ("Mixed berries", 0.75, "cup", nil),
                ("Granola", 0.33, "cup", .starch),
                ("Honey", 1, "tbsp", .sweetener),
            ],
            steps: [
                ("Spoon yogurt into a bowl, top with berries, granola, and honey.", nil),
            ]
        ))

        let recipes = [
            chickenRiceBowl, hotHoney, koreanBeef, shawarmaBowl, koftaWrap, koftaMealPrep,
            steakPotatoBowl, greenGoddess, salmonBowl, beefWrap, fajitaSalad, pestoGnocchi, yogurtBowl,
        ]
        recipes.forEach(context.insert)

        // A "my version" example: hot honey, but milder for the family.
        let hotHoneyMild = build(Seed(
            title: "Hot Honey Chicken Rice (Mild)",
            asset: "hotHoneyChickenRice",
            summary: "Family-friendly version — half the sriracha, extra honey.",
            creator: "@spicykitchen", platform: .instagram, confidence: nil,
            servings: 2, prep: 10, cook: 25, difficulty: .beginner,
            tags: ["Quick", "Chicken"],
            calories: 690, protein: 42,
            ingredients: [
                ("Chicken breast", 400, "g", .protein),
                ("Honey", 4, "tbsp", .sweetener),
                ("Sriracha", 0.5, "tbsp", .spice),
                ("Rice", 1.5, "cups", .starch),
                ("Butter", 1, "tbsp", .fat),
            ],
            steps: [
                ("Cube chicken and season with garlic powder and salt.", nil),
                ("Pan-fry chicken until crispy at the edges.", 600),
                ("Melt butter with honey and a little sriracha, toss to glaze.", 120),
                ("Serve over rice.", nil),
            ]
        ))
        hotHoneyMild.parentRecipe = hotHoney
        hotHoneyMild.versionLabel = "Mild version"
        context.insert(hotHoneyMild)

        // Notes & ratings on cooked-before recipes
        koreanBeef.notes = "Double the garlic next time. Sauce is perfect at 3 min exactly."

        // Collections
        let mealPrep = RecipeCollection(name: "Meal prep")
        mealPrep.recipes = [koreanBeef, koftaMealPrep, fajitaSalad, pestoGnocchi]
        let weeknight = RecipeCollection(name: "Weeknight dinners")
        weeknight.recipes = [chickenRiceBowl, hotHoney, salmonBowl, steakPotatoBowl]
        let halal = RecipeCollection(name: "Halal favorites")
        halal.recipes = [shawarmaBowl, koftaWrap, koftaMealPrep]
        [mealPrep, weeknight, halal].forEach(context.insert)

        // Pantry
        let pantryItems: [PantryItem] = [
            PantryItem(name: "Chicken thighs", category: .meat, roughQuantity: .half, location: .fridge),
            PantryItem(name: "Ground beef", category: .meat, roughQuantity: .full, location: .freezer),
            PantryItem(name: "Rice", category: .pantry, roughQuantity: .full),
            PantryItem(name: "Eggs", category: .dairy, roughQuantity: .half, location: .fridge),
            PantryItem(name: "Greek yogurt", category: .dairy, roughQuantity: .low, location: .fridge,
                       useSoonDate: Calendar.current.date(byAdding: .day, value: 2, to: .now)),
            PantryItem(name: "Spinach", category: .produce, roughQuantity: .low, location: .fridge,
                       useSoonDate: Calendar.current.date(byAdding: .day, value: 2, to: .now)),
            PantryItem(name: "Honey", category: .pantry, roughQuantity: .full),
            PantryItem(name: "Butter", category: .dairy, roughQuantity: .half, location: .fridge),
            PantryItem(name: "Garlic", category: .produce, roughQuantity: .full),
            PantryItem(name: "Potatoes", category: .produce, roughQuantity: .half),
        ]
        pantryItems.forEach(context.insert)

        // Groceries
        let groceries: [GroceryItem] = [
            GroceryItem(name: "Greek yogurt", quantityText: "1 tub", category: .dairy,
                        substitutionHint: "Sour cream works", sourceRecipeTitles: [chickenRiceBowl.title]),
            GroceryItem(name: "Parsley", category: .produce, isOptional: true, sourceRecipeTitles: [chickenRiceBowl.title]),
            GroceryItem(name: "Lemons", quantityText: "2", category: .produce, sourceRecipeTitles: [chickenRiceBowl.title]),
            GroceryItem(name: "Sriracha", category: .pantry, sourceRecipeTitles: [hotHoney.title]),
            GroceryItem(name: "Salmon fillets", quantityText: "350 g", category: .meat, sourceRecipeTitles: [salmonBowl.title]),
        ]
        groceries.forEach(context.insert)

        // Cook history ("Cooked before" section)
        let sessions: [(Recipe, Int, Int, Double, String?)] = [
            (koreanBeef, -2, 5, 1, "Sauce is elite. Broccoli slightly overdone."),
            (hotHoney, -5, 2, 2, nil),
            (steakPotatoBowl, -9, 2, 2, "Used ribeye instead — worth it."),
            (koreanBeef, -14, 5, 1, nil),
        ]
        for (recipe, daysAgo, made, eaten, note) in sessions {
            let session = CookSession(
                date: Calendar.current.date(byAdding: .day, value: daysAgo, to: .now)!,
                servingsMade: made,
                servingsEaten: eaten,
                recipe: recipe
            )
            session.rating = 4
            session.notes = note
            session.wouldMakeAgain = true
            context.insert(session)
        }

        // Prefs
        let prefs = UserPrefs.current(in: context)
        prefs.displayName = "Malik"
        prefs.dietaryRules = [.halal]
        // Seeded dev builds skip the first-run flow (use `-onboarding` to see it).
        prefs.hasCompletedOnboarding = true

        try? context.save()
    }
}
