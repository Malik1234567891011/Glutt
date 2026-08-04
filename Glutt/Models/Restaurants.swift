import Foundation
import SwiftData

/// A restaurant whose signature plates ship with the app, as the chef packs do.
/// Bundled content, never fetched, free for everyone.
struct Restaurant: Identifiable, Hashable {
    /// Slug, and the suffix of the `restaurant:` tag on that restaurant's dishes.
    let id: String
    let name: String
    /// Credit line under the name. The dish count is appended by the view, so
    /// this stays a plain description.
    let credit: String
    /// One line on the restaurant page explaining what the kitchen is about.
    let blurb: String
    /// Asset-catalog name for the logo. Nil falls back to initials on a tinted
    /// circle, exactly as `ChefPortrait` does.
    let logoAsset: String?

    /// "Cotoa" → "CO". Used by the logo placeholder.
    var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined()
        }
        return name.prefix(2).uppercased()
    }
}

/// Restaurants and their signature dishes, sitting above the chef rail on the
/// Recipes home.
///
/// Restaurant dishes are real `Recipe` rows — so pantry match, Cook Mode and the
/// voice chef all work unchanged — tagged `restaurant:<slug>` and filtered out of
/// the personal library feed, the same trick `ChefContent` and `CookingBasics`
/// use.
enum RestaurantContent {

    /// The one switch for the whole feature: the rail, the bundled dish rows and
    /// the `-openRestaurant` hook all read it.
    ///
    /// Carries the same App Review 5.2 exposure the chef packs do, and then some.
    /// A restaurant ships by name and logo with no licence for either, and the
    /// dishes are RECONSTRUCTIONS assembled from menu descriptions, reviews and
    /// photographs — not the kitchen's own formulas. That is why the page says
    /// "Inspired by" rather than the chefs' "Official", and why every dish
    /// carries `reconstructionNote`. Getting the restaurant's written blessing
    /// is what actually settles it.
    static let isEnabled = true

    /// Discriminator tag prefix. Keep in sync with `Recipe.restaurantSlug`.
    static let tagPrefix = "restaurant:"

    /// A dish is shaped exactly like a chef's, so the two packs stay one concept
    /// and the feed card, ranking and install logic have nothing to branch on.
    typealias Dish = ChefContent.Dish

    /// Rail order on the Recipes home.
    static let restaurants: [Restaurant] = [
        Restaurant(
            id: "cotoa",
            name: "Cotoa",
            credit: "Ecuadorian, North Miami",
            blurb: "Ecuadorian born, globally inspired. Chef Alejandra Espinoza's "
                + "kitchen in North Miami, awarded a Michelin Bib Gourmand in 2026.",
            logoAsset: "restaurantCotoa"
        ),
    ]

    static func restaurant(id: String) -> Restaurant? {
        restaurants.first { $0.id == id }
    }

    // MARK: - Lookup

    /// A restaurant's dishes in rank order, paired with the stored recipe each
    /// installed as. Dishes with no row yet drop out.
    static func ranked(for restaurant: Restaurant, in recipes: [Recipe]) -> [RankedDish] {
        let mine = recipes.filter { $0.restaurantSlug == restaurant.id }
        return dishes(for: restaurant).enumerated().compactMap { index, dish in
            guard let recipe = mine.first(where: { $0.title == dish.title }) else { return nil }
            return RankedDish(rank: index + 1, dish: dish, recipe: recipe)
        }
    }

    static func dishes(for restaurant: Restaurant) -> [Dish] {
        pack[restaurant.id] ?? []
    }

    struct RankedDish: Identifiable {
        let rank: Int
        let dish: Dish
        let recipe: Recipe
        var id: String { dish.title }
    }

    // MARK: - Install

    /// Bump when dish copy or photography changes so existing installs refresh.
    /// Without a bump, a recipe row seeded by an earlier version keeps its old
    /// `imageAssetName` forever and the new photo never reaches that user.
    /// 1: Cotoa launch — five dishes, one real photo, four stand-ins.
    /// 2: Real photography for all five.
    private static let contentVersion = 2
    private static let contentVersionKey = "glutt.restaurantContent.contentVersion"

    /// Idempotent: inserts missing dishes and refreshes their copy when
    /// `contentVersion` advances. Only ever touches rows that already carry the
    /// restaurant tag, so a user recipe sharing a title is left alone.
    static func install(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        var byKey: [String: Recipe] = [:]
        for recipe in existing {
            guard let slug = recipe.restaurantSlug else { continue }
            byKey["\(slug)|\(recipe.title)"] = recipe
        }
        let needsRefresh = UserDefaults.standard.integer(forKey: contentVersionKey) < contentVersion

        for restaurant in restaurants {
            for dish in dishes(for: restaurant) {
                if let recipe = byKey["\(restaurant.id)|\(dish.title)"] {
                    if needsRefresh { apply(dish, restaurant: restaurant, to: recipe) }
                } else {
                    let recipe = Recipe(title: dish.title, sourcePlatform: .manual)
                    apply(dish, restaurant: restaurant, to: recipe)
                    context.insert(recipe)
                }
            }
        }

        if needsRefresh {
            UserDefaults.standard.set(contentVersion, forKey: contentVersionKey)
        }
        try? context.save()
    }

    private static func apply(_ dish: Dish, restaurant: Restaurant, to recipe: Recipe) {
        recipe.summary = dish.summary
        recipe.sourceCreator = restaurant.name
        recipe.servings = dish.servings
        recipe.prepMinutes = dish.prepMinutes
        recipe.cookMinutes = dish.cookMinutes
        recipe.difficulty = dish.difficulty
        // Restaurant tag last: the feed card shows `tags.first`, which should
        // stay a human tag if one of these surfaces outside a restaurant page.
        recipe.tags = dish.tags + ["\(tagPrefix)\(restaurant.id)"]
        recipe.imageAssetName = dish.imageAsset
        if let sourceURL = dish.sourceURL {
            recipe.sourceURL = sourceURL
            if let url = URL(string: sourceURL) {
                recipe.sourcePlatform = ImportedRecipeDraft.platform(for: url)
            }
        }
        recipe.ingredients = dish.ingredients.enumerated().map { index, line in
            RecipeIngredient(name: line.name, quantity: line.quantity, unit: line.unit, sortIndex: index)
        }
        recipe.steps = dish.steps.enumerated().map { index, step in
            RecipeStep(index: index, text: step.text, durationSeconds: step.durationSeconds)
        }
    }

    // MARK: - The pack

    /// Keyed by restaurant slug. Pack order is the page's rank order.
    private static let pack: [String: [Dish]] = [
        "cotoa": cotoa,
    ]

    // MARK: Cotoa

    /// Ranked as the restaurant's own signatures: the ceviche first (the clearest
    /// statement of what the kitchen does), the pasta second (its cleverest
    /// transformation), then the rest.
    ///
    /// Every one of these is a RECONSTRUCTION from confirmed menu descriptions,
    /// plating photographs, reviewers' tasting notes and Ecuadorian tradition.
    /// None is the restaurant's published formula. Keep the summaries honest
    /// about that — the page frames the whole set as "inspired by".
    private static let cotoa: [Dish] = [
        Dish(
            title: "Mahi Mahi Manicero",
            summary: "Raw mahi mahi in a peanut coconut sauce, Jipijapa style",
            servings: 4, prepMinutes: 30, cookMinutes: 15,
            difficulty: .intermediate,
            tags: ["Signature", "Ceviche", "Ecuadorian", "Raw fish"],
            imageAsset: "cotoaMahiMahiManicero",
            ingredients: [
                ("Mahi mahi, sushi grade", 450, "g"),
                ("Lime juice", 150, "ml"),
                ("Orange juice", 2, "tbsp"),
                ("Coconut milk", 120, "ml"),
                ("Roasted peanuts", 80, "g"),
                ("Ginger", 1, "tsp"),
                ("Garlic", 0.5, "clove"),
                ("Ground coriander", 1, "tsp"),
                ("Ground cumin", 0.25, "tsp"),
                ("Smoked paprika", 0.25, "tsp"),
                ("Achiote oil", 0.5, "tsp"),
                ("Panela or brown sugar", 0.5, "tsp"),
                ("Red onion", 0.5, nil),
                ("Red Fresno pepper", 1, nil),
                ("Cucumber", 0.5, nil),
                ("Avocado", 1, nil),
                ("Watermelon radish", 2, nil),
                ("Chives", 2, "tbsp"),
                ("Cilantro", 1, "handful"),
                ("Plantain chips", 1, "handful"),
            ],
            steps: [
                ("Make the quick pickle first so it has time to work. Mix 60ml lime juice, 60ml warm water, a teaspoon of sugar and half a teaspoon of salt, then drop in the thinly sliced red onion and Fresno pepper. Leave it at least 25 minutes.", 1500),
                ("Blend the sauce: coconut milk, peanuts, 2 tablespoons lime, the orange juice, ginger, garlic, coriander, cumin, paprika, achiote oil, panela and half a teaspoon of salt. Add cold water a spoon at a time until it pours like heavy cream.", 300),
                ("Taste and balance it. It should read nutty and coconut rich first, then citrus, then a gentle heat and sweetness. Lime brings it up, water pulls the peanut back. Blend the peanuts fresh — peanut butter makes it sticky and flat.", 120),
                ("Cut the mahi mahi into clean 1cm cubes and keep it in the fridge until the last moment.", 300),
                ("Marinate the fish in the remaining lime juice, the orange juice and three quarters of a teaspoon of salt for 8 to 12 minutes only. It should stay tender and translucent, not turn white and firm.", 600),
                ("Spread the cold sauce across shallow bowls. Drain the fish and pile it in the middle with the diced cucumber, avocado and some of the pickled onion and chili.", nil),
                ("Finish with shaved watermelon radish, crushed peanuts, chives and cilantro. Serve the plantain chips alongside.", nil),
            ]
        ),
        Dish(
            title: "Tortellinis con Seco de Pollo",
            summary: "Sweet plantain tortellini in Ecuadorian chicken stew",
            servings: 4, prepMinutes: 75, cookMinutes: 75,
            difficulty: .advanced,
            tags: ["Signature", "Pasta", "Chicken", "Ecuadorian"],
            imageAsset: "cotoaTortellinisSeco",
            ingredients: [
                ("Chicken thighs, boneless", 700, "g"),
                ("Ground cumin", 1.5, "tsp"),
                ("Ground coriander", 0.5, "tsp"),
                ("Achiote oil", 1, "tbsp"),
                ("Yellow onion", 1, nil),
                ("Red bell pepper", 1, nil),
                ("Garlic", 4, "clove"),
                ("Tomato paste", 2, "tbsp"),
                ("Crushed tomatoes", 240, "ml"),
                ("Beer or chicken stock", 180, "ml"),
                ("Orange juice", 120, "ml"),
                ("Cilantro", 1, "bunch"),
                ("Parsley", 0.25, "cup"),
                ("Dried oregano", 0.5, "tsp"),
                ("00 flour", 300, "g"),
                ("Eggs", 3, nil),
                ("Egg yolks", 2, nil),
                ("Ripe plantain", 1, nil),
                ("Ricotta", 120, "g"),
                ("Parmesan", 160, "g"),
                ("Lime", 1, nil),
                ("Avocado", 1, nil),
            ],
            steps: [
                ("Season the chicken with salt, cumin, coriander and pepper, then brown it hard in achiote oil and lift it out.", 480),
                ("Soften the diced onion and bell pepper in the same pot, add the garlic and tomato paste and cook until it goes brick red.", 480),
                ("Add the crushed tomato, beer or stock, orange juice and oregano. Blend the cilantro and parsley with a ladle of the liquid and stir that green purée back in — that is what makes it a seco.", 300),
                ("Return the chicken and simmer gently for about 35 minutes until it shreds easily. Lift it out, shred it finely, and reduce the sauce until glossy. Blend and strain it for the restaurant finish.", 2100),
                ("Roast the plantain in its skin at 200°C (400°F) for 25 to 35 minutes until it collapses and caramelises. Cool and mash.", 1800),
                ("Mix the mashed plantain with about 175g of the shredded chicken, the ricotta, 40g grated Parmesan, an egg yolk, cumin and lime zest. Season it assertively. It should taste like concentrated seco with plantain behind it, not like sweet plantain. Chill.", 600),
                ("Knead the flour, whole eggs, remaining yolk, a teaspoon of oil and a pinch of salt for 10 minutes until smooth. Wrap and rest 30 minutes.", 2400),
                ("Roll the dough very thin, setting 6 or 7, and cut 7cm squares. A teaspoon of filling in each, fold to a triangle, push every bit of air out, seal, then wrap the corners round to make tortellini. Short on time, use wonton wrappers instead.", 1800),
                ("Bake small mounds of the remaining Parmesan on parchment at 190°C (375°F) for 6 to 9 minutes for the cheese crisps. Cool them completely so they shatter.", 540),
                ("Boil the tortellini in well salted water for 3 to 5 minutes, then move them straight into the warm seco with a splash of pasta water and glaze them gently.", 300),
                ("Plate with lime dressed avocado, shards of crispy cheese and cilantro.", nil),
            ]
        ),
        Dish(
            title: "Cangrejada con Patacón",
            summary: "Blue crab in tomato and coconut over crisp cocolón rice",
            servings: 4, prepMinutes: 30, cookMinutes: 45,
            difficulty: .intermediate,
            tags: ["Signature", "Seafood", "Ecuadorian", "Sharing"],
            imageAsset: "cotoaCangrejadaConPatacon",
            ingredients: [
                ("Lump blue crabmeat", 450, "g"),
                ("Achiote oil", 2, "tbsp"),
                ("Red onion", 1, nil),
                ("Red bell pepper", 1, nil),
                ("Garlic", 3, "clove"),
                ("Ground cumin", 1, "tsp"),
                ("Ground coriander", 0.5, "tsp"),
                ("Smoked paprika", 0.5, "tsp"),
                ("Tomato paste", 2, "tbsp"),
                ("Crushed tomatoes", 240, "ml"),
                ("Seafood stock", 180, "ml"),
                ("Coconut milk", 120, "ml"),
                ("Panela or brown sugar", 1, "tsp"),
                ("Lime", 2, nil),
                ("Orange juice", 2, "tbsp"),
                ("Cilantro", 1, "bunch"),
                ("Long grain white rice", 200, "g"),
                ("Ripe plantain", 1, nil),
                ("Green plantain", 1, nil),
                ("Ground black lime", 0.5, "tsp"),
                ("Tomato", 1, nil),
            ],
            steps: [
                ("Cook the rice with 350ml water, a spoon of oil and salt. When it is tender, leave it untouched over low heat another 8 to 12 minutes so a golden crust forms underneath — that crust is the cocolón. For a surer version, spread the cooked rice on an oiled tray and bake at 220°C (425°F) until the edges crisp.", 1800),
                ("Slice the ripe plantain thick on the diagonal and fry until deeply caramelised on both sides.", 480),
                ("For the patacones, cut the green plantain into 2cm pieces and fry at 160°C (325°F) until pale gold and tender. Squash each piece flat, then fry again at 190°C (375°F) until crisp. Salt them the second they come out.", 900),
                ("Soften the diced onion and bell pepper in achiote oil for 6 to 8 minutes, then add the garlic, cumin, coriander and paprika.", 480),
                ("Stir in the tomato paste and cook it until brick red, then add the crushed tomato, stock, coconut milk and panela. Simmer 12 to 15 minutes until rich but still spoonable.", 900),
                ("Fold three quarters of the crab in and heat it for 2 to 3 minutes at most. Overcooked crab goes stringy and loses all its sweetness.", 180),
                ("Off the heat, add lime, orange and cilantro. Season, then add the black lime a pinch at a time — it should read as intriguing citrus, never dusty or medicinal.", 120),
                ("Dress the reserved crab with diced tomato, red onion, cilantro, lime and salt for the cold topping.", nil),
                ("Plate in layers: a round of rice with pieces of crisp cocolón, caramelised sweet plantain, the warm crab, then the cold crab salad on top. Patacones alongside. Do not stir it together in the pot — the dish is three textures or it is nothing.", nil),
            ]
        ),
        Dish(
            title: "Snapper Encocado",
            summary: "Crisp skin snapper in turmeric coconut, ginger plantain rice",
            servings: 4, prepMinutes: 20, cookMinutes: 40,
            difficulty: .intermediate,
            tags: ["Signature", "Fish", "Ecuadorian", "Coconut"],
            imageAsset: "cotoaSnapperEncocado",
            ingredients: [
                ("Snapper fillets, skin on", 4, nil),
                ("Ground cumin", 1, "tsp"),
                ("Turmeric", 1.25, "tsp"),
                ("Achiote oil", 1, "tbsp"),
                ("Yellow onion", 0.5, nil),
                ("Red bell pepper", 0.5, nil),
                ("Garlic", 3, "clove"),
                ("Ginger", 2, "tbsp"),
                ("Tomato paste", 1, "tbsp"),
                ("Coconut milk", 360, "ml"),
                ("Fish stock", 120, "ml"),
                ("Makrut lime leaves", 2, nil),
                ("Roasted peanuts", 2, "tbsp"),
                ("Lime", 1, nil),
                ("Sumac", 0.5, "tsp"),
                ("Brown sugar", 1, "tsp"),
                ("Jasmine rice", 200, "g"),
                ("Ripe plantain", 1, nil),
                ("Cilantro", 2, "tbsp"),
            ],
            steps: [
                ("Rinse the rice, then cook it with 350ml water, a tablespoon of grated ginger and salt. Rest it covered for 10 minutes.", 1200),
                ("Dice the ripe plantain and fry it until dark gold, then fold it gently through the rice with the cilantro.", 480),
                ("Soften the onion and bell pepper in achiote oil, then add the garlic, remaining ginger, a teaspoon of turmeric and half a teaspoon of cumin.", 420),
                ("Add the tomato paste, cook a minute or two, then pour in the coconut milk and stock with the crushed makrut lime leaves and sugar. Simmer gently 12 to 15 minutes — a hard boil makes coconut milk turn greasy.", 900),
                ("Blend the sauce with the peanuts until smooth and strain it back into the pan. The peanut is there for roasted depth; if it tastes like satay you have gone too far.", 300),
                ("Add lime juice, sumac and salt. It needs both acids: lime for freshness, sumac for a dry berry-like tartness. Without them all that coconut tastes flat.", 120),
                ("Pat the snapper bone dry, score the skin lightly and season with salt, cumin, the remaining turmeric and pepper.", nil),
                ("Lay it skin down in hot oil and press for 20 to 30 seconds so it cannot curl. Leave it on the skin for 4 to 6 minutes until crisp and almost cooked through, then flip for 30 to 90 seconds.", 420),
                ("Spoon the sauce into shallow bowls, add the ginger plantain rice and sit the fish on top with the skin above the liquid so it stays crisp. Finish with sumac, cilantro and a few drops of achiote oil.", nil),
            ]
        ),
        Dish(
            title: "El Pincho",
            summary: "Grilled hanger steak, smoked ají chimichurri, crisp potatoes",
            servings: 4, prepMinutes: 25, cookMinutes: 65,
            difficulty: .intermediate,
            tags: ["Beef", "Grill", "Ecuadorian", "Sharing"],
            imageAsset: "cotoaElPincho",
            ingredients: [
                ("Hanger steak", 900, "g"),
                ("Ground cumin", 1.5, "tsp"),
                ("Ground coriander", 1, "tsp"),
                ("Ground cinnamon", 0.25, "tsp"),
                ("Garlic", 3, "clove"),
                ("Worcestershire sauce", 1, "tbsp"),
                ("Lime", 2, nil),
                ("Poblano peppers", 2, nil),
                ("Jalapeño", 1, nil),
                ("Cilantro", 1, "bunch"),
                ("Flat leaf parsley", 0.5, "cup"),
                ("Scallions", 2, nil),
                ("Capers", 1, "tbsp"),
                ("Red wine vinegar", 2, "tbsp"),
                ("Extra virgin olive oil", 80, "ml"),
                ("Yukon gold potatoes", 700, "g"),
                ("Baking soda", 0.5, "tsp"),
                ("English cucumber", 1, nil),
                ("Rice vinegar", 1, "tsp"),
                ("Red onion", 1, "tbsp"),
            ],
            steps: [
                ("Rub the steak with salt, cumin, coriander, pepper, cinnamon, grated garlic, Worcestershire, lime juice and oil. Refrigerate at least an hour, ideally four to eight.", 3600),
                ("Blacken the poblanos and jalapeño over a flame, under the broiler or in a dry screaming hot pan. Cover them 10 minutes, then rub off the loose skin — leave some char, that is where the smoke comes from.", 900),
                ("Pulse the peppers with the cilantro, parsley, scallions, garlic, capers, vinegar, lime and cumin, then stir the olive oil in by hand. Keep it textured, not a smoothie.", 300),
                ("Heat the oven to 230°C (450°F). Boil the potatoes in salted water with the baking soda until completely tender, 15 to 20 minutes.", 1200),
                ("Drain them and let them steam dry, then shake the pot hard so the outsides rough up. That fluff is what turns into crust. Toss with oil and roast 35 to 50 minutes, turning now and then, until deeply crisp.", 2700),
                ("Take the steak out 30 minutes before it cooks. Grill or sear over the highest heat you can manage to 52°C (125°F) for medium rare, 57°C (135°F) for medium.", 720),
                ("Rest it 8 to 10 minutes. Hanger has two lobes either side of a centre membrane and a very pronounced grain — separate them, check which way the grain runs on each, and slice across it or it will eat tough.", 600),
                ("Dress the cucumber with lime, rice vinegar, a little sugar, salt and sliced red onion just before serving.", nil),
                ("Spoon a generous amount of chimichurri over the sliced steak and serve the potatoes and cucumber alongside.", nil),
            ]
        ),
    ]
}

extension Recipe {
    /// Slug of the restaurant this dish belongs to, from its `restaurant:` tag.
    /// Nil for the user's own recipes and for chef dishes.
    var restaurantSlug: String? {
        tags.first { $0.hasPrefix(RestaurantContent.tagPrefix) }
            .map { String($0.dropFirst(RestaurantContent.tagPrefix.count)) }
    }

    /// True for bundled restaurant content, which lives outside the personal library.
    var isRestaurantRecipe: Bool { restaurantSlug != nil }

    var restaurant: Restaurant? { restaurantSlug.flatMap(RestaurantContent.restaurant(id:)) }

    /// True for any bundled collection dish, chef's or restaurant's. These have
    /// their own pages and stay out of the personal library, the taste profile
    /// and the user's export.
    var isCuratedRecipe: Bool { isChefRecipe || isRestaurantRecipe }
}
