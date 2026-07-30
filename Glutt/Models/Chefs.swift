import Foundation
import SwiftData

/// A guest chef whose greatest hits ship with the app. Bundled content, never
/// fetched, and free for everyone.
struct Chef: Identifiable, Hashable {
    /// Slug, and the suffix of the `chef:` tag on that chef's recipes.
    let id: String
    let name: String
    /// Credit line under the name on the chef page. The recipe count is appended
    /// by the view, so this stays a plain description.
    let credit: String
    /// Asset-catalog name for the portrait. Nil until licensed headshots land —
    /// the rail and the chef header fall back to initials on a tinted circle.
    let portraitAsset: String?

    /// "Gordon Ramsay" → "GR". Used by the portrait placeholder.
    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

/// The three chefs and their five most popular recipes each.
///
/// Chef dishes are real `Recipe` rows (so pantry match, Cook Mode and Polly all
/// work unchanged) tagged `chef:<slug>` and filtered out of the personal
/// library feed — the same trick `CookingBasics` uses for technique lessons.
enum ChefContent {

    /// Discriminator tag prefix. Keep in sync with `Recipe.chefSlug`.
    static let tagPrefix = "chef:"

    /// Rail order on the Recipes home.
    static let chefs: [Chef] = [
        Chef(
            id: "gordon-ramsay",
            name: "Gordon Ramsay",
            credit: "Michelin chef, London",
            portraitAsset: nil
        ),
        Chef(
            id: "nick-digiovanni",
            name: "Nick DiGiovanni",
            credit: "MasterChef finalist, cookbook author",
            portraitAsset: nil
        ),
        Chef(
            id: "joshua-weissman",
            name: "Joshua Weissman",
            credit: "Cookbook author, Austin",
            portraitAsset: nil
        ),
    ]

    static func chef(id: String) -> Chef? {
        chefs.first { $0.id == id }
    }

    // MARK: - Lookup

    /// A chef's dishes in rank order, paired with the stored recipe each one
    /// installed as. Dishes with no row yet (a store wiped mid-launch) drop out.
    static func ranked(for chef: Chef, in recipes: [Recipe]) -> [RankedDish] {
        let mine = recipes.filter { $0.chefSlug == chef.id }
        return dishes(for: chef).enumerated().compactMap { index, dish in
            guard let recipe = mine.first(where: { $0.title == dish.title }) else { return nil }
            return RankedDish(rank: index + 1, dish: dish, recipe: recipe)
        }
    }

    static func dishes(for chef: Chef) -> [Dish] {
        pack[chef.id] ?? []
    }

    struct RankedDish: Identifiable {
        let rank: Int
        let dish: Dish
        let recipe: Recipe
        var id: String { dish.title }
    }

    // MARK: - Install

    /// Bump when dish copy changes so existing installs refresh.
    private static let contentVersion = 1
    private static let contentVersionKey = "glutt.chefContent.contentVersion"

    /// Idempotent: inserts missing chef dishes and refreshes their copy when
    /// `contentVersion` advances. Only ever touches rows that already carry the
    /// chef tag, so a user recipe that happens to share a title is left alone.
    static func install(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        var byKey: [String: Recipe] = [:]
        for recipe in existing {
            guard let slug = recipe.chefSlug else { continue }
            byKey["\(slug)|\(recipe.title)"] = recipe
        }
        let needsRefresh = UserDefaults.standard.integer(forKey: contentVersionKey) < contentVersion

        for chef in chefs {
            for dish in dishes(for: chef) {
                if let recipe = byKey["\(chef.id)|\(dish.title)"] {
                    if needsRefresh { apply(dish, chef: chef, to: recipe) }
                } else {
                    let recipe = Recipe(title: dish.title, sourcePlatform: .manual)
                    apply(dish, chef: chef, to: recipe)
                    context.insert(recipe)
                }
            }
        }

        if needsRefresh {
            UserDefaults.standard.set(contentVersion, forKey: contentVersionKey)
        }
        try? context.save()
    }

    private static func apply(_ dish: Dish, chef: Chef, to recipe: Recipe) {
        recipe.summary = dish.summary
        recipe.sourceCreator = chef.name
        recipe.servings = dish.servings
        recipe.prepMinutes = dish.prepMinutes
        recipe.cookMinutes = dish.cookMinutes
        recipe.difficulty = dish.difficulty
        // Chef tag last: the feed card shows `tags.first`, which should stay a
        // human tag if one of these ever surfaces outside a chef page.
        recipe.tags = dish.tags + ["\(tagPrefix)\(chef.id)"]
        recipe.imageAssetName = dish.imageAsset
        recipe.ingredients = dish.ingredients.enumerated().map { index, line in
            RecipeIngredient(name: line.name, quantity: line.quantity, unit: line.unit, sortIndex: index)
        }
        recipe.steps = dish.steps.enumerated().map { index, step in
            RecipeStep(index: index, text: step.text, durationSeconds: step.durationSeconds)
        }
    }

    // MARK: - The pack

    struct Dish {
        let title: String
        let summary: String
        /// Popularity rating shown on the card. Not the user's private 1 to 5 rating.
        let rating: Double
        let servings: Int
        let prepMinutes: Int
        let cookMinutes: Int
        let difficulty: Difficulty
        let tags: [String]
        /// Stand-in dish photography until chef recipe photos are shot.
        let imageAsset: String
        let ingredients: [(name: String, quantity: Double?, unit: String?)]
        let steps: [(text: String, durationSeconds: Int?)]
    }

    /// Keyed by chef slug. Each array is that chef's five, most popular first.
    private static let pack: [String: [Dish]] = [
        "gordon-ramsay": gordonRamsay,
        "nick-digiovanni": nickDiGiovanni,
        "joshua-weissman": joshuaWeissman,
    ]

    // MARK: Gordon Ramsay

    private static let gordonRamsay: [Dish] = [
        Dish(
            title: "Beef Wellington",
            summary: "Fillet in mushroom duxelles, wrapped in puff pastry",
            rating: 4.9,
            servings: 4, prepMinutes: 45, cookMinutes: 105,
            difficulty: .advanced,
            tags: ["signature", "beef", "dinner party"],
            imageAsset: "garlicButterSteakPotatoBowl",
            ingredients: [
                ("Beef fillet", 1, "kg"),
                ("Chestnut mushrooms", 500, "g"),
                ("Prosciutto", 12, "slice"),
                ("Puff pastry", 500, "g"),
                ("English mustard", 2, "tbsp"),
                ("Egg yolks", 2, nil),
                ("Thyme", 4, "sprig"),
                ("Olive oil", 2, "tbsp"),
            ],
            steps: [
                ("Season the fillet hard all over. Sear it in a ripping hot pan with olive oil, about a minute a side, until every face is deep brown. Lift it out, let it cool, then brush the whole thing with mustard.", nil),
                ("Blitz the mushrooms to a coarse paste. Dry fry over high heat until all the water has gone and the pan squeaks, 10 to 15 minutes. Add the thyme leaves, season, spread on a tray and cool completely. Wet duxelles is what makes a soggy Wellington.", 900),
                ("Lay the prosciutto in overlapping rows on cling film. Spread the cool duxelles over it, sit the fillet on top and roll it into a tight cylinder, twisting the ends like a cracker. Chill 20 minutes so it firms up.", 1200),
                ("Roll the pastry to about 4mm. Unwrap the beef onto it, wrap and seal the seam, trim the ends. Brush all over with egg yolk, score the top lightly and chill another 15 minutes.", 900),
                ("Bake at 200°C (400°F) for 20 minutes, then drop to 180°C (350°F) for 15 more. That is blushing pink in the middle. Rest it 10 to 15 minutes before you carve, or the juices run out onto the board.", 1200),
            ]
        ),
        Dish(
            title: "Pan Seared Salmon",
            summary: "Crisp skin salmon, lemon butter, soft herbs",
            rating: 4.8,
            servings: 2, prepMinutes: 5, cookMinutes: 13,
            difficulty: .intermediate,
            tags: ["fish", "quick", "high protein"],
            imageAsset: "lemonDillSalmonBowl",
            ingredients: [
                ("Salmon fillets", 2, nil),
                ("Olive oil", 1, "tbsp"),
                ("Butter", 30, "g"),
                ("Lemon", 1, nil),
                ("Garlic", 1, "clove"),
                ("Thyme", 2, "sprig"),
            ],
            steps: [
                ("Pat the skin bone dry, score it three or four times, and salt it heavily right before it goes in the pan. Wet skin steams, it never crisps.", nil),
                ("Lay the fillets skin down in hot oil, away from you, and press them flat for ten seconds so the skin stays in full contact. Now leave them alone for 5 to 6 minutes, until the flesh has gone opaque two thirds of the way up.", 360),
                ("Flip, drop in the butter, garlic and thyme, tilt the pan and spoon the foaming butter over the fish for a minute or two.", 120),
                ("Rest for 2 minutes. Squeeze lemon over the top, finish with flaky salt, and serve it skin side up so it stays crisp.", 120),
            ]
        ),
        Dish(
            title: "Shepherd's Pie",
            summary: "Slow cooked lamb under a browned mash crust",
            rating: 4.7,
            servings: 4, prepMinutes: 20, cookMinutes: 50,
            difficulty: .intermediate,
            tags: ["comfort", "lamb", "sunday"],
            imageAsset: "koreanBeefMealPrep",
            ingredients: [
                ("Lamb mince", 700, "g"),
                ("Potatoes", 1, "kg"),
                ("Onion", 1, nil),
                ("Carrots", 2, nil),
                ("Garlic", 2, "clove"),
                ("Tomato puree", 2, "tbsp"),
                ("Worcestershire sauce", 1, "tbsp"),
                ("Chicken stock", 300, "ml"),
                ("Butter", 60, "g"),
                ("Egg yolks", 2, nil),
                ("Parmesan", 30, "g"),
                ("Rosemary", 2, "sprig"),
            ],
            steps: [
                ("Brown the lamb in a wide pan in batches, hard, until it is properly coloured and not grey. Drain off most of the fat.", nil),
                ("Add the diced onion, carrot and garlic and cook until soft. Stir in the tomato puree and cook it out for two minutes, then the Worcestershire sauce, rosemary and stock.", nil),
                ("Simmer uncovered for 25 minutes until the sauce coats the meat and there is no loose liquid in the pan. Season, then spread it into a baking dish and let it cool a little.", 1500),
                ("Boil the potatoes until a knife slides through, drain and steam dry for a minute. Mash with the butter, beat in the egg yolks and season well.", nil),
                ("Pipe or fork the mash over the lamb, right to the edges so nothing bubbles up the sides. Scatter parmesan on top.", nil),
                ("Bake at 200°C (400°F) for 20 to 25 minutes until the top is properly browned and the edges are bubbling. Rest 5 minutes before serving.", 1500),
            ]
        ),
        Dish(
            title: "Spiced Lamb Flatbread",
            summary: "Kofta spiced lamb, yogurt, quick pickled onion",
            rating: 4.6,
            servings: 4, prepMinutes: 20, cookMinutes: 20,
            difficulty: .beginner,
            tags: ["lamb", "sharing", "weeknight"],
            imageAsset: "koftaFlatbreadWrap",
            ingredients: [
                ("Lamb mince", 400, "g"),
                ("Flatbreads", 4, nil),
                ("Red onion", 1, nil),
                ("Garlic", 2, "clove"),
                ("Cumin", 1, "tsp"),
                ("Ground coriander", 1, "tsp"),
                ("Smoked paprika", 1, "tsp"),
                ("Greek yogurt", 150, "g"),
                ("Lemon", 1, nil),
                ("Mint", 1, "handful"),
                ("Pine nuts", 2, "tbsp"),
            ],
            steps: [
                ("Slice half the red onion paper thin, toss with the juice of half the lemon and a big pinch of salt, and leave it to pickle while you cook.", nil),
                ("Fry the rest of the onion with the garlic until soft, add the lamb and break it up. Cook hard until the water has gone and the mince is catching and browning.", nil),
                ("Stir in the cumin, coriander and paprika, cook one more minute, and season. It should taste slightly over seasoned on its own, the yogurt will pull it back.", nil),
                ("Spread the lamb over the flatbreads and bake at 220°C (425°F) for 6 to 8 minutes until the edges are crisp.", 480),
                ("Loosen the yogurt with a squeeze of lemon. Spoon it over, then the pickled onion, torn mint and toasted pine nuts. Cut into wedges.", nil),
            ]
        ),
        Dish(
            title: "Scrambled Eggs",
            summary: "Low and slow, folded off the heat with creme fraiche",
            rating: 4.9,
            servings: 2, prepMinutes: 2, cookMinutes: 6,
            difficulty: .beginner,
            tags: ["breakfast", "eggs", "quick"],
            imageAsset: "greekYogurtBowl",
            ingredients: [
                ("Eggs", 6, nil),
                ("Butter", 30, "g"),
                ("Creme fraiche", 1, "tbsp"),
                ("Chives", 1, "tbsp"),
                ("Sourdough", 2, "slice"),
            ],
            steps: [
                ("Crack the eggs into a cold pan with the butter. No whisking in a bowl, no salt yet. Salt now and they turn watery.", nil),
                ("Put the pan on medium heat and stir constantly with a spatula, scraping the base. After about 30 seconds, lift the pan off the heat for 10 seconds, keep stirring, then put it back. Repeat.", nil),
                ("Keep going for about 5 minutes. You are looking for soft folds and a glossy, loose custard, not dry curds. Take it off the heat while it still looks slightly underdone.", 300),
                ("Stir in the creme fraiche to stop the cooking dead, season now, add chives, and pile it onto hot toast. Eat immediately.", nil),
            ]
        ),
    ]

    // MARK: Nick DiGiovanni

    private static let nickDiGiovanni: [Dish] = [
        Dish(
            title: "Garlic Butter Steak Bites",
            summary: "Hard seared sirloin, basted in garlic rosemary butter",
            rating: 4.9,
            servings: 2, prepMinutes: 10, cookMinutes: 15,
            difficulty: .beginner,
            tags: ["beef", "high protein", "quick"],
            imageAsset: "greenGoddessSteakPlate",
            ingredients: [
                ("Sirloin steak", 500, "g"),
                ("Baby potatoes", 400, "g"),
                ("Butter", 50, "g"),
                ("Garlic", 4, "clove"),
                ("Rosemary", 2, "sprig"),
                ("Olive oil", 1, "tbsp"),
                ("Parsley", 1, "handful"),
            ],
            steps: [
                ("Halve the potatoes and roast at 220°C (425°F) for 25 minutes, or boil them until tender and smash them flat in the pan later.", 1500),
                ("Cut the steak into 3cm cubes and dry them properly on paper towel. Season with salt just before cooking.", nil),
                ("Get a heavy pan rippling hot with the oil. Add the cubes in one layer with space between them and do not touch them for 2 minutes. Toss and give them another minute.", 180),
                ("Drop the heat to medium, add the butter, crushed garlic cloves and rosemary. Baste for a minute, spooning the foam over everything.", 60),
                ("Tip the bites and all the pan butter over the potatoes, rest 3 minutes, and finish with chopped parsley and flaky salt.", 180),
            ]
        ),
        Dish(
            title: "Chicken Katsu Sandwich",
            summary: "Panko chicken, milk bread, tonkatsu sauce, crunchy cabbage",
            rating: 4.8,
            servings: 2, prepMinutes: 15, cookMinutes: 20,
            difficulty: .intermediate,
            tags: ["chicken", "sandwich", "fried"],
            imageAsset: "beefWrapWithWedges",
            ingredients: [
                ("Chicken breasts", 2, nil),
                ("Panko breadcrumbs", 100, "g"),
                ("Flour", 60, "g"),
                ("Eggs", 2, nil),
                ("Milk bread", 4, "slice"),
                ("White cabbage", 0.25, "head"),
                ("Tonkatsu sauce", 3, "tbsp"),
                ("Mayonnaise", 3, "tbsp"),
                ("Neutral oil", 500, "ml"),
            ],
            steps: [
                ("Butterfly each breast and pound it between two sheets of parchment until it is an even 1cm thick. Even thickness is the whole game here. Season both sides.", nil),
                ("Set up flour, beaten egg and panko. Coat each cutlet in that order, pressing the panko on firmly so it stays craggy.", nil),
                ("Heat the oil to 170°C (340°F). Fry one cutlet at a time for 3 to 4 minutes a side until deep gold, then drain on a rack, never on paper.", 420),
                ("Shred the cabbage as fine as you can and dress it with a spoon of the mayo and a pinch of salt.", nil),
                ("Butter and lightly toast the bread. Mayo on both slices, cutlet, a heavy brush of tonkatsu sauce, then the cabbage. Press the sandwich for a minute, cut off the crusts, slice in half.", nil),
            ]
        ),
        Dish(
            title: "Truffle Mac and Cheese",
            summary: "Gruyere and cheddar sauce under a parmesan panko lid",
            rating: 4.8,
            servings: 4, prepMinutes: 10, cookMinutes: 30,
            difficulty: .beginner,
            tags: ["comfort", "pasta", "vegetarian"],
            imageAsset: "pestoGnocchiMealPrep",
            ingredients: [
                ("Macaroni", 400, "g"),
                ("Butter", 50, "g"),
                ("Flour", 50, "g"),
                ("Whole milk", 600, "ml"),
                ("Gruyere", 150, "g"),
                ("Cheddar", 200, "g"),
                ("Truffle oil", 1, "tsp"),
                ("Panko breadcrumbs", 50, "g"),
                ("Parmesan", 40, "g"),
            ],
            steps: [
                ("Boil the macaroni two minutes short of the packet time. It finishes in the oven and mushy pasta is unfixable.", nil),
                ("Melt the butter, whisk in the flour and cook the raw taste out for two minutes. Add the milk a splash at a time, whisking, until you have a smooth sauce that coats a spoon.", nil),
                ("Off the heat, stir in the grated gruyere and cheddar a handful at a time. Direct heat splits cheese sauce, patience keeps it glossy. Season with salt, pepper and a little nutmeg.", nil),
                ("Fold in the pasta, tip into a baking dish, and top with the panko tossed with parmesan.", nil),
                ("Bake at 200°C (400°F) for 15 minutes until the top is gold and the edges bubble. Off the heat, drizzle the truffle oil over the top. Cooked truffle oil tastes like nothing.", 900),
            ]
        ),
        Dish(
            title: "Crispy Chicken Fried Rice",
            summary: "Day old rice pressed flat until it crackles",
            rating: 4.7,
            servings: 2, prepMinutes: 10, cookMinutes: 15,
            difficulty: .beginner,
            tags: ["chicken", "rice", "quick"],
            imageAsset: "chickenRiceBowl",
            ingredients: [
                ("Cooked rice", 3, "cup"),
                ("Chicken thighs", 300, "g"),
                ("Eggs", 2, nil),
                ("Soy sauce", 2, "tbsp"),
                ("Oyster sauce", 1, "tbsp"),
                ("Sesame oil", 1, "tsp"),
                ("Green onions", 3, nil),
                ("Garlic", 2, "clove"),
                ("Frozen peas", 0.5, "cup"),
                ("Neutral oil", 2, "tbsp"),
            ],
            steps: [
                ("Use rice from the fridge. Fresh rice steams and clumps. Break the grains apart with wet hands before you start.", nil),
                ("Get the wok or widest pan you own smoking hot. Sear the diced chicken until browned at the edges, then push it to one side.", nil),
                ("Pour the beaten egg into the empty side, scramble it hard for 20 seconds, then chop it through the chicken.", nil),
                ("Add the garlic, then the rice. Press it flat against the pan and leave it for a full minute at a time so the bottom crackles, then toss. Do that three times.", 180),
                ("Add the peas, soy, oyster sauce and sesame oil around the edge of the pan, not the middle, toss to coat, and finish with the sliced green onions.", nil),
            ]
        ),
        Dish(
            title: "Hot Honey Chicken",
            summary: "Craggy buttermilk chicken tossed in chili honey butter",
            rating: 4.7,
            servings: 2, prepMinutes: 15, cookMinutes: 30,
            difficulty: .intermediate,
            tags: ["chicken", "spicy", "fried"],
            imageAsset: "hotHoneyChickenRice",
            ingredients: [
                ("Chicken thighs", 500, "g"),
                ("Buttermilk", 250, "ml"),
                ("Hot sauce", 2, "tbsp"),
                ("Flour", 200, "g"),
                ("Cornstarch", 50, "g"),
                ("Smoked paprika", 1, "tsp"),
                ("Honey", 100, "g"),
                ("Chili flakes", 1, "tsp"),
                ("Butter", 30, "g"),
                ("Rice", 1.5, "cup"),
                ("Neutral oil", 700, "ml"),
            ],
            steps: [
                ("Cut the thighs into big chunks and soak them in the buttermilk and hot sauce for at least 15 minutes. Overnight is better.", 900),
                ("Mix the flour, cornstarch, paprika and a heavy pinch of salt. Spoon two tablespoons of the buttermilk into the flour and rub it through with your fingers, those clumps become the crunchy bits.", nil),
                ("Dredge each piece, pressing the flour on hard. Let the coated chicken sit for 5 minutes so it hydrates and stops falling off in the oil.", 300),
                ("Fry at 170°C (340°F) in batches for 6 to 7 minutes until deep gold and 74°C (165°F) inside. Rest on a rack.", 420),
                ("Warm the honey, chili flakes and butter until glossy. Toss the chicken through it right before serving so it stays crisp, and pile it over rice.", nil),
            ]
        ),
    ]

    // MARK: Joshua Weissman

    private static let joshuaWeissman: [Dish] = [
        Dish(
            title: "Birria Tacos",
            summary: "Chile braised beef, cheese crisped tortillas, consomme",
            rating: 4.9,
            servings: 6, prepMinutes: 20, cookMinutes: 180,
            difficulty: .advanced,
            tags: ["beef", "slow cooked", "sharing"],
            imageAsset: "steakFajitaSalad",
            ingredients: [
                ("Beef chuck", 1.5, "kg"),
                ("Guajillo chiles", 6, nil),
                ("Ancho chiles", 3, nil),
                ("Chipotle in adobo", 2, "tbsp"),
                ("Tomatoes", 3, nil),
                ("Onion", 1, nil),
                ("Garlic", 6, "clove"),
                ("Cinnamon stick", 1, nil),
                ("Cumin", 1, "tsp"),
                ("Dried oregano", 1, "tsp"),
                ("White vinegar", 2, "tbsp"),
                ("Beef stock", 1, "l"),
                ("Corn tortillas", 18, nil),
                ("Oaxaca cheese", 300, "g"),
                ("Cilantro", 1, "bunch"),
                ("Lime", 2, nil),
            ],
            steps: [
                ("Stem and seed the dried chiles, toast them in a dry pan for 30 seconds a side until they smell nutty, then cover with hot water for 15 minutes. Burnt chiles turn the whole braise bitter, so watch them.", 900),
                ("Season the chuck in big chunks and sear it hard on every face in a heavy pot. Take it out and set it aside.", nil),
                ("Blend the soaked chiles with the tomatoes, onion, garlic, chipotle, cumin, oregano and vinegar until completely smooth, then pass it through a sieve into the pot.", nil),
                ("Return the beef, add the stock and cinnamon, bring to a bare simmer, cover and cook at 160°C (325°F) for about 3 hours until the meat shreds under no pressure at all.", 10800),
                ("Shred the beef. Skim the red fat off the top of the braise and keep it, that is what you dip the tortillas in. Season the remaining liquid, that is your consomme.", nil),
                ("Dip a tortilla in the red fat, lay it on a hot griddle, cheese on one half, beef on top, fold. Crisp both sides until the edges shatter. Serve with cilantro, onion, lime and a cup of consomme.", nil),
            ]
        ),
        Dish(
            title: "Smash Burgers",
            summary: "Lacy edged patties, american cheese, toasted potato bun",
            rating: 4.9,
            servings: 4, prepMinutes: 15, cookMinutes: 15,
            difficulty: .intermediate,
            tags: ["beef", "burger", "weekend"],
            imageAsset: "beefWrapWithWedges",
            ingredients: [
                ("Ground beef", 600, "g"),
                ("Potato buns", 4, nil),
                ("American cheese", 8, "slice"),
                ("Onion", 1, nil),
                ("Pickles", 8, "slice"),
                ("Mayonnaise", 3, "tbsp"),
                ("Ketchup", 2, "tbsp"),
                ("Mustard", 1, "tbsp"),
                ("Butter", 20, "g"),
            ],
            steps: [
                ("Use 80/20 beef and roll it into loose 75g balls. Do not compact them. A tight ball steams instead of crisping.", nil),
                ("Mix the mayo, ketchup and mustard for the sauce. Slice the onion as thin as you can bear.", nil),
                ("Butter the cut side of the buns and toast them face down until golden. Set aside.", nil),
                ("Get cast iron or a steel plate as hot as it goes. Sit a ball down, cover it with a scrap of parchment and smash it flat and thin with a stiff spatula. Hold for 10 seconds. Season now.", nil),
                ("Cook 90 seconds without moving it, until the edges are brown and lacy. Scrape underneath with the sharpest spatula you own so the crust comes with the patty. Flip, cheese on, 30 seconds more.", 120),
                ("Stack two patties per bun with sauce, onion and pickles. Eat standing up, they do not wait.", nil),
            ]
        ),
        Dish(
            title: "Crispy Orange Chicken",
            summary: "Double fried chicken in a sharp citrus glaze",
            rating: 4.8,
            servings: 4, prepMinutes: 20, cookMinutes: 15,
            difficulty: .intermediate,
            tags: ["chicken", "fried", "takeout"],
            imageAsset: "hotHoneyChickenRice",
            ingredients: [
                ("Chicken thighs", 700, "g"),
                ("Cornstarch", 100, "g"),
                ("Egg whites", 2, nil),
                ("Oranges", 2, nil),
                ("Soy sauce", 2, "tbsp"),
                ("Rice vinegar", 2, "tbsp"),
                ("Sugar", 60, "g"),
                ("Ginger", 1, "tbsp"),
                ("Garlic", 3, "clove"),
                ("Chili flakes", 0.5, "tsp"),
                ("Rice", 2, "cup"),
                ("Neutral oil", 700, "ml"),
            ],
            steps: [
                ("Cut the thighs into bite sized pieces and toss them with the egg whites, a pinch of salt and half the cornstarch. Rest 10 minutes, then dredge in the rest of the cornstarch.", 600),
                ("Fry at 160°C (320°F) for 4 minutes to cook them through. Lift out and rest on a rack for 5 minutes.", 240),
                ("Bring the oil up to 190°C (375°F) and fry again for 90 seconds. The second fry drives out the surface moisture, which is why it stays crisp under sauce.", 90),
                ("In a wide pan, cook the ginger, garlic and chili for 30 seconds, then add the zest and juice of both oranges, soy, vinegar and sugar. Reduce until it coats a spoon.", nil),
                ("Kill the heat, tip in the chicken and toss fast. Serve straight away over rice, it softens by the minute.", nil),
            ]
        ),
        Dish(
            title: "Chicken Shawarma",
            summary: "Yogurt spiced thighs, garlic sauce, warm flatbread",
            rating: 4.7,
            servings: 4, prepMinutes: 20, cookMinutes: 30,
            difficulty: .intermediate,
            tags: ["chicken", "grill", "wrap"],
            imageAsset: "saffronChickenShawarmaBowl",
            ingredients: [
                ("Chicken thighs", 1, "kg"),
                ("Greek yogurt", 150, "g"),
                ("Garlic", 5, "clove"),
                ("Lemon", 2, nil),
                ("Cumin", 2, "tsp"),
                ("Ground coriander", 1, "tsp"),
                ("Smoked paprika", 2, "tsp"),
                ("Turmeric", 1, "tsp"),
                ("Cinnamon", 0.5, "tsp"),
                ("Olive oil", 3, "tbsp"),
                ("Flatbreads", 4, nil),
                ("Tomatoes", 2, nil),
                ("Pickles", 1, "handful"),
                ("Parsley", 1, "handful"),
            ],
            steps: [
                ("Whisk the yogurt with the crushed garlic, lemon juice, all the spices, olive oil and plenty of salt. Coat the thighs and marinate at least 2 hours, ideally overnight.", nil),
                ("Take the chicken out of the fridge 20 minutes before cooking and scrape off the excess marinade, or it burns before the meat colours.", 1200),
                ("Cook in a hot heavy pan in batches, 6 to 7 minutes a side, pressing them flat, until the edges are almost black in places. Do not crowd the pan.", 780),
                ("Rest 5 minutes, then slice thin across the grain and toss the slices back through the pan juices.", 300),
                ("Warm the flatbreads. Build with garlic sauce, chicken, tomato, pickles and parsley, then roll tight and give the seam 30 seconds in the pan.", nil),
            ]
        ),
        Dish(
            title: "Burrito Bowl",
            summary: "Adobo chicken, cilantro lime rice, quick pico",
            rating: 4.6,
            servings: 4, prepMinutes: 25, cookMinutes: 20,
            difficulty: .beginner,
            tags: ["chicken", "meal prep", "high protein"],
            imageAsset: "koftaPotatoSaladMealPrep",
            ingredients: [
                ("Chicken thighs", 600, "g"),
                ("Chipotle in adobo", 2, "tbsp"),
                ("Rice", 2, "cup"),
                ("Lime", 2, nil),
                ("Cilantro", 1, "bunch"),
                ("Black beans", 1, "tin"),
                ("Corn", 1, "cup"),
                ("Red onion", 0.5, nil),
                ("Tomatoes", 3, nil),
                ("Jalapeno", 1, nil),
                ("Sour cream", 4, "tbsp"),
                ("Cheddar", 100, "g"),
            ],
            steps: [
                ("Blend the chipotle with a splash of water, the juice of one lime, salt and cumin. Coat the thighs and leave them while you do everything else.", nil),
                ("Cook the rice, then fork through the juice of the second lime, a big handful of chopped cilantro and a pinch of salt while it is still hot.", nil),
                ("Dice the tomatoes, red onion and jalapeno for the pico, squeeze in lime and salt it properly. Let it sit, it gets better.", nil),
                ("Sear the chicken in a hot pan for 6 minutes a side until charred at the edges, rest for 5, then chop it roughly on the board so it catches the juices.", 720),
                ("Warm the beans and corn. Build the bowls: rice, chicken, beans, corn, pico, sour cream and cheese.", nil),
            ]
        ),
    ]
}

extension Recipe {
    /// Slug of the chef this recipe belongs to, from its `chef:` tag. Nil for
    /// the user's own recipes.
    var chefSlug: String? {
        tags.first { $0.hasPrefix(ChefContent.tagPrefix) }
            .map { String($0.dropFirst(ChefContent.tagPrefix.count)) }
    }

    /// True for bundled chef content, which lives outside the personal library.
    var isChefRecipe: Bool { chefSlug != nil }

    var chef: Chef? { chefSlug.flatMap(ChefContent.chef(id:)) }
}
