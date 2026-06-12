import Foundation
import SwiftData

/// Small pack of easy, crowd-pleasing recipes for users who arrive with
/// nothing to import. Offered in onboarding; safe to call twice.
enum StarterRecipes {

    static func install(context: ModelContext) {
        let existingTitles = Set(
            (try? context.fetch(FetchDescriptor<Recipe>()))?.map(\.title) ?? []
        )

        for starter in pack where !existingTitles.contains(starter.title) {
            let recipe = Recipe(
                title: starter.title,
                summary: starter.summary,
                servings: starter.servings,
                prepMinutes: starter.prepMinutes,
                cookMinutes: starter.cookMinutes,
                difficulty: .beginner,
                tags: starter.tags
            )
            recipe.imageAssetName = starter.asset
            recipe.ingredients = starter.ingredients.enumerated().map { index, line in
                RecipeIngredient(name: line.name, quantity: line.quantity, unit: line.unit, sortIndex: index)
            }
            recipe.steps = starter.steps.enumerated().map { index, text in
                RecipeStep(index: index, text: text)
            }
            context.insert(recipe)
        }
        try? context.save()
    }

    // MARK: - The pack

    private struct Starter {
        let title: String
        let summary: String
        let servings: Int
        let prepMinutes: Int
        let cookMinutes: Int
        let tags: [String]
        let asset: String
        let ingredients: [(name: String, quantity: Double?, unit: String?)]
        let steps: [String]
    }

    private static let pack: [Starter] = [
        Starter(
            title: "One-Pan Chicken Rice Bowl",
            summary: "The weeknight default: juicy chicken over rice with whatever vegetables you have.",
            servings: 2, prepMinutes: 10, cookMinutes: 20,
            tags: ["easy", "one-pan", "high-protein"],
            asset: "chickenRiceBowl",
            ingredients: [
                ("Chicken thighs", 4, nil),
                ("Rice", 1.5, "cup"),
                ("Broccoli", 1, "head"),
                ("Soy sauce", 3, "tbsp"),
                ("Garlic", 3, "clove"),
                ("Olive oil", 1, "tbsp"),
            ],
            steps: [
                "Cook rice according to the package.",
                "Season chicken with salt and pepper. Sear in olive oil over medium-high heat, 5–6 minutes per side, until cooked through. Rest, then slice.",
                "Steam or pan-fry the broccoli with the garlic for 4–5 minutes.",
                "Build bowls: rice, chicken, broccoli. Drizzle soy sauce over everything.",
            ]
        ),
        Starter(
            title: "Lemon Dill Salmon Bowl",
            summary: "Fancy-looking, ten minutes of actual work.",
            servings: 2, prepMinutes: 10, cookMinutes: 15,
            tags: ["fresh", "fish", "bowl"],
            asset: "lemonDillSalmonBowl",
            ingredients: [
                ("Salmon fillets", 2, nil),
                ("Rice", 1, "cup"),
                ("Cucumber", 1, nil),
                ("Greek yogurt", 0.5, "cup"),
                ("Lemon", 1, nil),
                ("Fresh dill", 2, "tbsp"),
            ],
            steps: [
                "Cook rice. Mix yogurt with chopped dill, half the lemon juice, salt.",
                "Season salmon, roast at 200°C (400°F) for 10–12 minutes.",
                "Slice cucumber thin, toss with a pinch of salt.",
                "Assemble: rice, salmon, cucumber, a big spoon of the dill yogurt, lemon wedge.",
            ]
        ),
        Starter(
            title: "Greek Yogurt Berry Bowl",
            summary: "Breakfast or dessert. Five minutes, no cooking.",
            servings: 1, prepMinutes: 5, cookMinutes: 0,
            tags: ["breakfast", "no-cook", "sweet"],
            asset: "greekYogurtBowl",
            ingredients: [
                ("Greek yogurt", 1, "cup"),
                ("Mixed berries", 0.5, "cup"),
                ("Honey", 1, "tbsp"),
                ("Granola", 0.25, "cup"),
            ],
            steps: [
                "Spoon yogurt into a bowl.",
                "Top with berries, granola, and a drizzle of honey.",
            ]
        ),
        Starter(
            title: "Pesto Gnocchi Skillet",
            summary: "Shelf-stable comfort food that tastes like effort.",
            servings: 2, prepMinutes: 5, cookMinutes: 15,
            tags: ["comfort", "vegetarian", "one-pan"],
            asset: "pestoGnocchiMealPrep",
            ingredients: [
                ("Gnocchi", 500, "g"),
                ("Pesto", 4, "tbsp"),
                ("Cherry tomatoes", 1, "cup"),
                ("Parmesan", 0.25, "cup"),
                ("Olive oil", 1, "tbsp"),
            ],
            steps: [
                "Pan-fry gnocchi in olive oil over medium heat until golden and crisp, 8–10 minutes. No need to boil first.",
                "Add halved cherry tomatoes for the last 3 minutes.",
                "Off the heat, stir in pesto. Top with parmesan.",
            ]
        ),
        Starter(
            title: "Korean-Style Beef Bowls",
            summary: "Sweet-savory ground beef over rice. Meal-prep gold.",
            servings: 4, prepMinutes: 10, cookMinutes: 15,
            tags: ["meal-prep", "savory", "high-protein"],
            asset: "koreanBeefMealPrep",
            ingredients: [
                ("Ground beef", 500, "g"),
                ("Rice", 2, "cup"),
                ("Soy sauce", 4, "tbsp"),
                ("Brown sugar", 2, "tbsp"),
                ("Garlic", 4, "clove"),
                ("Green onions", 3, nil),
                ("Sesame oil", 1, "tsp"),
            ],
            steps: [
                "Cook rice.",
                "Brown the beef over high heat, breaking it up. Drain excess fat.",
                "Add garlic, soy sauce, brown sugar, sesame oil. Simmer 2–3 minutes.",
                "Serve over rice, topped with sliced green onions.",
            ]
        ),
        Starter(
            title: "Steak Fajita Salad",
            summary: "A loud, colorful salad that eats like a meal.",
            servings: 2, prepMinutes: 15, cookMinutes: 10,
            tags: ["fresh", "salad", "high-protein"],
            asset: "steakFajitaSalad",
            ingredients: [
                ("Steak", 300, "g"),
                ("Bell peppers", 2, nil),
                ("Red onion", 1, nil),
                ("Romaine lettuce", 1, "head"),
                ("Lime", 1, nil),
                ("Olive oil", 2, "tbsp"),
                ("Cumin", 1, "tsp"),
            ],
            steps: [
                "Season steak with salt, pepper, and cumin. Sear 3–4 minutes per side for medium-rare. Rest, then slice against the grain.",
                "Sear sliced peppers and onion in the same pan until charred at the edges.",
                "Toss chopped romaine with lime juice and olive oil.",
                "Top the salad with the steak and vegetables.",
            ]
        ),
    ]
}
