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

/// Guest chefs and their signature dishes (Gordon ships six; Nick and Joshua
/// five; Preppy Kitchen ships the Crème Brûlée clip pilot).
///
/// Chef dishes are real `Recipe` rows (so pantry match, Cook Mode and Polly all
/// work unchanged) tagged `chef:<slug>` and filtered out of the personal
/// library feed — the same trick `CookingBasics` uses for technique lessons.
enum ChefContent {

    /// The one switch for the whole feature: the rail, the bundled dish rows and
    /// the `-openChef` hook all read it.
    ///
    /// Held back from 1.2 on 2026-07-30, switched back on the same day. The
    /// reason it was ever off still stands: the three chefs ship by name and
    /// likeness, with portraits and dish photos cut from YouTube thumbnails and
    /// no licence for either, which is App Review 5.2 exposure. Dropping the
    /// real names and portraits, or licensing the content, is what settles it.
    /// See `docs/appstore-metadata-1.2.md` section 1.1.
    static let isEnabled = true

    /// Discriminator tag prefix. Keep in sync with `Recipe.chefSlug`.
    static let tagPrefix = "chef:"

    /// Rail order on the Recipes home.
    static let chefs: [Chef] = [
        Chef(
            id: "gordon-ramsay",
            name: "Gordon Ramsay",
            credit: "Michelin chef, London",
            portraitAsset: "chefGordonRamsay"
        ),
        Chef(
            id: "nick-digiovanni",
            name: "Nick DiGiovanni",
            credit: "MasterChef finalist",
            portraitAsset: "chefNickDiGiovanni"
        ),
        Chef(
            id: "joshua-weissman",
            name: "Joshua Weissman",
            credit: "Cookbook author, Austin",
            portraitAsset: "chefJoshuaWeissman"
        ),
        Chef(
            id: "kitchen-sanctuary",
            name: "Nicky's Kitchen Sanctuary",
            credit: "Nicky Corbishley",
            // No licensed headshot yet — rail falls back to initials.
            portraitAsset: nil
        ),
        Chef(
            id: "preppy-kitchen",
            name: "Preppy Kitchen",
            credit: "John Kanell",
            // No licensed headshot yet — rail falls back to initials.
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

    /// Bump when dish copy or photography changes so existing installs refresh.
    /// 2: real dish photos replaced the stand-in stock food art.
    /// 3: Eggs Benedict + YouTube source URLs on Gordon clip pilots.
    /// 4: Scrambled Eggs TikTok technique source (vt → canonical /video/id).
    /// 5: Re-stamp pilot sourceURLs (Beef Wellington / Eggs Benedict / scramble)
    ///    — some library rows lost them across bundle-id / version churn and
    ///    Polly's canvas then had nothing to fetch clips for.
    /// 6: Preppy Kitchen + Crème Brûlée YouTube clip pilot.
    /// 7: Kitchen Sanctuary + Gnocchi with Brown Butter and Sage, the live demo
    ///    dish. Its step text carries the doneness cues verbatim so they survive
    ///    even if the cook plan is ever recompiled from the recipe.
    private static let contentVersion = 7
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

    struct Dish {
        let title: String
        let summary: String
        let servings: Int
        let prepMinutes: Int
        let cookMinutes: Int
        let difficulty: Difficulty
        let tags: [String]
        /// Asset-catalog name. `chef*` assets are the real dish photos; the
        /// three that aren't yet fall back to the app's stock food art.
        let imageAsset: String
        let ingredients: [(name: String, quantity: Double?, unit: String?)]
        let steps: [(text: String, durationSeconds: Int?)]
        /// Optional technique video URL (YouTube / TikTok) — powers Polly native clips.
        let sourceURL: String?

        init(
            title: String,
            summary: String,
            servings: Int,
            prepMinutes: Int,
            cookMinutes: Int,
            difficulty: Difficulty,
            tags: [String],
            imageAsset: String,
            ingredients: [(name: String, quantity: Double?, unit: String?)],
            steps: [(text: String, durationSeconds: Int?)],
            sourceURL: String? = nil
        ) {
            self.title = title
            self.summary = summary
            self.servings = servings
            self.prepMinutes = prepMinutes
            self.cookMinutes = cookMinutes
            self.difficulty = difficulty
            self.tags = tags
            self.imageAsset = imageAsset
            self.ingredients = ingredients
            self.steps = steps
            self.sourceURL = sourceURL
        }
    }

    /// Keyed by chef slug. Pack order is the chef-page rank order.
    private static let pack: [String: [Dish]] = [
        "gordon-ramsay": gordonRamsay,
        "nick-digiovanni": nickDiGiovanni,
        "joshua-weissman": joshuaWeissman,
        "preppy-kitchen": preppyKitchen,
        "kitchen-sanctuary": kitchenSanctuary,
    ]

    // MARK: Gordon Ramsay

    private static let gordonRamsay: [Dish] = [
        Dish(
            title: "Beef Wellington",
            summary: "Fillet in mushroom duxelles, wrapped in puff pastry",
            servings: 4, prepMinutes: 45, cookMinutes: 105,
            difficulty: .advanced,
            tags: ["Signature", "Beef", "Dinner party"],
            imageAsset: "chefBeefWellington",
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
                ("Season the fillet hard all over. Sear it in a ripping hot pan with olive oil, about a minute a side, until every face is deep brown. Lift it out and let it cool.", 300),
                ("Brush the warm seared fillet all over with English mustard.", 120),
                ("Blitz the mushrooms to a coarse paste. Dry fry over high heat until all the water has gone and the pan squeaks, 10 to 15 minutes. Add the thyme leaves, season, spread on a tray and cool completely. Wet duxelles is what makes a soggy Wellington.", 900),
                ("Lay the prosciutto in overlapping rows on cling film. Spread the cool duxelles over it, sit the fillet on top and roll it into a tight cylinder, twisting the ends like a cracker. Chill 20 minutes so it firms up.", 1200),
                ("Roll the pastry to about 4mm. Unwrap the beef onto it, wrap and seal the seam, trim the ends. Brush all over with egg yolk, score the top lightly and chill another 15 minutes.", 900),
                ("Bake at 200°C (400°F) for 20 minutes, then drop to 180°C (350°F) for 15 more. That is blushing pink in the middle. Rest it 10 to 15 minutes before you carve, or the juices run out onto the board.", 1200),
            ],
            sourceURL: "https://www.youtube.com/watch?v=Cyskqnp1j64"
        ),
        Dish(
            title: "Eggs Benedict",
            summary: "Poached eggs on toasted English muffins with hollandaise",
            servings: 2, prepMinutes: 15, cookMinutes: 20,
            difficulty: .intermediate,
            tags: ["Signature", "Breakfast", "Brunch", "Eggs"],
            imageAsset: "eggsBenedict",
            ingredients: [
                ("Eggs", 4, nil),
                ("English muffins", 2, nil),
                ("Butter", 150, "g"),
                ("Egg yolks", 2, nil),
                ("Lemon juice", 1, "tbsp"),
                ("White wine vinegar", 1, "tbsp"),
                ("Canadian bacon or ham", 4, "slices"),
                ("Salt", nil, nil),
                ("Cayenne or white pepper", nil, nil),
                ("Chives", nil, nil),
            ],
            steps: [
                ("Toast the English muffins cut-side down in a hot pan (with ham fat if you have it) until golden; keep warm.", 180),
                ("Warm the ham or Canadian bacon in a pan; set aside.", 180),
                ("Make hollandaise: whisk egg yolks with a splash of water over gentle heat until thickened, then slowly whisk in melted butter and finish with lemon juice, salt, and cayenne.", 480),
                ("Bring a pot of water to a gentle simmer and add a splash of vinegar.", 300),
                ("Crack each egg into a cup, swirl the water, and poach 3–4 minutes until whites are set and yolks are soft.", 240),
                ("Plate: muffin, ham, poached egg, hollandaise; garnish with chives.", nil),
            ],
            sourceURL: "https://www.youtube.com/watch?v=gBJjRYk0yC0"
        ),
        Dish(
            title: "Pan Seared Salmon",
            summary: "Crisp skin salmon, lemon butter, soft herbs",
            servings: 2, prepMinutes: 5, cookMinutes: 13,
            difficulty: .intermediate,
            tags: ["Fish", "Quick", "High protein"],
            imageAsset: "chefPanSearedSalmon",
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
            servings: 4, prepMinutes: 20, cookMinutes: 50,
            difficulty: .intermediate,
            tags: ["Comfort", "Lamb", "Sunday"],
            imageAsset: "chefShepherdsPie",
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
            servings: 4, prepMinutes: 20, cookMinutes: 20,
            difficulty: .beginner,
            tags: ["Lamb", "Sharing", "Weeknight"],
            imageAsset: "chefSpicedLambFlatbread",
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
            servings: 2, prepMinutes: 2, cookMinutes: 6,
            difficulty: .beginner,
            tags: ["Breakfast", "Eggs", "Quick"],
            imageAsset: "chefScrambledEggs",
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
            ],
            // Canonical TikTok id (short vt.tiktok.com links are not parseable as numeric ids).
            sourceURL: "https://www.tiktok.com/@f00dt0k1/video/7333706662634704161"
        ),
    ]

    // MARK: Nick DiGiovanni

    private static let nickDiGiovanni: [Dish] = [
        Dish(
            title: "Garlic Butter Steak Bites",
            summary: "Hard seared sirloin, basted in garlic rosemary butter",
            servings: 2, prepMinutes: 10, cookMinutes: 15,
            difficulty: .beginner,
            tags: ["Beef", "High protein", "Quick"],
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
            servings: 2, prepMinutes: 15, cookMinutes: 20,
            difficulty: .intermediate,
            tags: ["Chicken", "Sandwich", "Fried"],
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
            servings: 4, prepMinutes: 10, cookMinutes: 30,
            difficulty: .beginner,
            tags: ["Comfort", "Pasta", "Vegetarian"],
            imageAsset: "chefTruffleMac",
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
            servings: 2, prepMinutes: 10, cookMinutes: 15,
            difficulty: .beginner,
            tags: ["Chicken", "Rice", "Quick"],
            imageAsset: "chefFriedRice",
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
            servings: 2, prepMinutes: 15, cookMinutes: 30,
            difficulty: .intermediate,
            tags: ["Chicken", "Spicy", "Fried"],
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
            servings: 6, prepMinutes: 20, cookMinutes: 180,
            difficulty: .advanced,
            tags: ["Beef", "Slow cooked", "Sharing"],
            imageAsset: "chefBirriaTacos",
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
            servings: 4, prepMinutes: 15, cookMinutes: 15,
            difficulty: .intermediate,
            tags: ["Beef", "Burger", "Weekend"],
            imageAsset: "chefSmashBurgers",
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
            servings: 4, prepMinutes: 20, cookMinutes: 15,
            difficulty: .intermediate,
            tags: ["Chicken", "Fried", "Takeout"],
            imageAsset: "chefOrangeChicken",
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
            servings: 4, prepMinutes: 20, cookMinutes: 30,
            difficulty: .intermediate,
            tags: ["Chicken", "Grill", "Wrap"],
            imageAsset: "chefChickenShawarma",
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
            servings: 4, prepMinutes: 25, cookMinutes: 20,
            difficulty: .beginner,
            tags: ["Chicken", "Meal prep", "High protein"],
            imageAsset: "chefBurritoBowl",
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

    // MARK: Preppy Kitchen

    private static let preppyKitchen: [Dish] = [
        Dish(
            title: "Crème Brûlée",
            summary: "Silky vanilla custard under a crackly caramelized sugar top",
            servings: 6, prepMinutes: 20, cookMinutes: 40,
            difficulty: .intermediate,
            tags: ["Signature", "Dessert", "French"],
            imageAsset: "chefCremeBrulee",
            ingredients: [
                ("Heavy cream", 3, "cup"),
                ("Vanilla bean", 1, nil),
                ("Egg yolks", 5, nil),
                ("Granulated sugar", 0.5, "cup"),
                ("Salt", 0.125, "tsp"),
                ("Sugar for topping", nil, nil),
            ],
            steps: [
                ("Split the vanilla bean lengthwise and scrape out every seed. Keep the pod — it goes in the cream too.", 120),
                ("In a saucepan, bring the cream with the vanilla seeds and pod just to a simmer over medium heat. Kill the heat and let it steep for 15 minutes so the cream cools and the flavor goes in.", 900),
                ("Separate five egg yolks into a large bowl. Whisk in the sugar and a pinch of salt until combined — you are not whipping air in, just dissolving the sugar.", 180),
                ("Strain the warm cream through a fine mesh sieve into the yolks, stirring as you go. Strain the custard a second time so no pod pieces or foam make it into the ramekins.", 300),
                ("Set six 6-ounce ramekins in a deep roasting pan. Divide the custard among them, then carefully pour boiling water into the pan until it comes halfway up the sides. Bake at 325°F (160°C) for 30 to 40 minutes, until the edges are set and the centers still wobble. Cool in the bath, then chill several hours.", 2400),
                ("When you are ready to serve, blot any moisture off the tops, sprinkle a thin even layer of sugar to the edges, and torch with sweeping motions until amber. Serve immediately so the crust stays crisp.", 180),
            ],
            sourceURL: "https://www.youtube.com/watch?v=6tSdlo0r0Io"
        ),
    ]

    // MARK: Kitchen Sanctuary

    /// The live demo dish. Quantities are Nicky's exactly, from
    /// kitchensanctuary.com/gnocchi-brown-butter-sage.
    ///
    /// The step text is longer than the source's, on purpose and only where the
    /// source leaves a judgement unspoken. Every risky moment in this dish is a
    /// *look* rather than a time: gnocchi are done when they float, the pan is
    /// ready when a water droplet skitters, butter is browned about fifteen
    /// seconds before it is burnt. Those cues live here as well as in the
    /// bundled cook plan, so a recompile cannot quietly lose them.
    private static let kitchenSanctuary: [Dish] = [
        Dish(
            title: "Gnocchi with Brown Butter and Sage",
            summary: "Pillowy gnocchi in nutty brown butter with crisp sage and lemon",
            servings: 4, prepMinutes: 5, cookMinutes: 10,
            difficulty: .beginner,
            tags: ["Signature", "Dinner", "Italian"],
            imageAsset: "chefGnocchiBrownButter",
            ingredients: [
                ("Fresh gnocchi", 500, "g"),
                ("Olive oil", 2, "tbsp"),
                ("Unsalted butter", 75, "g"),
                ("Fresh sage leaves", 20, nil),
                ("Garlic", 2, "clove"),
                ("Salt", 0.25, "tsp"),
                ("Black pepper", 0.25, "tsp"),
                ("Lemon", 1, nil),
                ("Parmesan", nil, nil),
            ],
            steps: [
                ("Get a pan of well salted water on to boil, and while it comes up, finely slice 2 cloves of garlic and pick 20 sage leaves off their stems. Zest the lemon and halve it.", 300),
                ("Drop the gnocchi into the boiling water. They are ready the moment they float and bob on the surface, which takes about 2 minutes. Floating is the whole signal, and leaving them in after that turns them gluey.", 120),
                ("Lift the gnocchi out with a slotted spoon into a bowl. Keep them, not the water.", nil),
                ("Heat 2 tbsp olive oil in a frying pan over medium-high. Test it before the gnocchi go in: flick in a few drops of water, and they should skitter and bead across the surface. If they vanish with a crack the pan is too hot, so take it off the heat for thirty seconds.", 120),
                ("Fry the gnocchi with a pinch of salt and pepper for 5 to 6 minutes, turning them, until golden and crisp on two sides. Give them room or they steam instead of colouring.", 360),
                ("Tip the gnocchi back into the bowl and wipe the pan out if anything caught.", nil),
                ("Turn the heat down to medium and melt 75g of butter. It will foam, and then the foam will subside. Watch the milk solids at the bottom: the moment they turn the colour of a hazelnut and it smells nutty, it is done, about 2 to 3 minutes. Black flecks and a sharp smell mean it has gone past, and burnt butter cannot be brought back.", 180),
                ("Drop in the sage leaves. They will crackle and go still and crisp in about 2 minutes, and the flavour mellows as they fry.", 120),
                ("Add the sliced garlic and stir it for 1 minute, no longer. It only wants to smell sweet, and garlic in hot butter turns bitter fast.", 60),
                ("Return the gnocchi to the pan with a quarter teaspoon each of salt and pepper, and stir for 1 minute to coat everything in the butter.", 60),
                ("Take the pan off the heat, then add the lemon zest and the juice of half the lemon and stir it through. Off the heat so the lemon stays bright.", nil),
                ("Divide between bowls and finish with grated parmesan and a good grind of black pepper. Serve straight away while the sage is still crisp.", nil),
            ],
            sourceURL: "https://www.youtube.com/watch?v=3sUJwjvmzk8"
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
