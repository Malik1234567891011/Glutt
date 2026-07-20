import Foundation
import SwiftData

/// Evergreen technique lessons ("how to fry an egg") that live above the
/// personal recipe library. Always installed for every user — not Beta-only.
///
/// Lessons are real `Recipe`s (so Cook Mode + Polly work unchanged) tagged
/// with `CookingBasics.tag` and filtered out of the main library list.
/// User-requested how-tos (via `HowToGenerator`) share the same tag.
enum CookingBasics {

    /// Discriminator tag. Keep in sync with `Recipe.isCookingBasic`.
    static let tag = "basics"

    /// Bump when seeded lesson copy changes so existing installs refresh.
    private static let contentVersion = 2
    private static let contentVersionKey = "glutt.cookingBasics.contentVersion"

    /// Idempotent: inserts missing seeded lessons; refreshes seeded copy when
    /// `contentVersion` advances. Never overwrites user-generated how-tos
    /// (titles outside the seeded pack).
    static func install(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        // Titles aren't unique in the store (imports / versions / reseed) —
        // never use Dictionary(uniqueKeysWithValues:). Prefer a Glutt Basics
        // copy when several share a title so refresh targets the seeded lesson.
        var byTitle: [String: Recipe] = [:]
        for recipe in existing {
            if let prior = byTitle[recipe.title] {
                if prior.sourceCreator != "Glutt Basics", recipe.sourceCreator == "Glutt Basics" {
                    byTitle[recipe.title] = recipe
                }
            } else {
                byTitle[recipe.title] = recipe
            }
        }
        let needsRefresh = UserDefaults.standard.integer(forKey: contentVersionKey) < contentVersion

        for lesson in pack {
            if let recipe = byTitle[lesson.title] {
                // Refresh seeded Glutt Basics copy when lesson text advances —
                // never overwrite a user-authored recipe that reused the title.
                if needsRefresh, recipe.sourceCreator == "Glutt Basics" {
                    apply(lesson, to: recipe)
                }
            } else {
                let recipe = Recipe(
                    title: lesson.title,
                    summary: lesson.summary,
                    sourceCreator: "Glutt Basics",
                    sourcePlatform: .manual,
                    servings: lesson.servings,
                    prepMinutes: lesson.prepMinutes,
                    cookMinutes: lesson.cookMinutes,
                    difficulty: .beginner,
                    tags: [tag] + lesson.extraTags,
                    notes: lesson.notes
                )
                apply(lesson, to: recipe)
                context.insert(recipe)
            }
        }

        if needsRefresh {
            UserDefaults.standard.set(contentVersion, forKey: contentVersionKey)
        }
        try? context.save()
    }

    private static func apply(_ lesson: Lesson, to recipe: Recipe) {
        recipe.summary = lesson.summary
        recipe.sourceCreator = "Glutt Basics"
        recipe.servings = lesson.servings
        recipe.prepMinutes = lesson.prepMinutes
        recipe.cookMinutes = lesson.cookMinutes
        recipe.difficulty = .beginner
        recipe.tags = [tag] + lesson.extraTags
        recipe.notes = lesson.notes
        recipe.imageURL = lesson.imageURL
        recipe.calories = lesson.calories
        recipe.proteinGrams = lesson.proteinGrams
        recipe.carbGrams = lesson.carbGrams
        recipe.fatGrams = lesson.fatGrams
        recipe.nutritionIsEstimated = true
        recipe.ingredients = lesson.ingredients.enumerated().map { index, line in
            RecipeIngredient(
                name: line.name,
                quantity: line.quantity,
                unit: line.unit,
                note: line.note,
                isOptional: line.isOptional,
                sortIndex: index
            )
        }
        recipe.steps = lesson.steps.enumerated().map { index, step in
            RecipeStep(index: index, text: step.text, durationSeconds: step.durationSeconds)
        }
    }

    // MARK: - Pack

    private struct Lesson {
        let title: String
        let summary: String
        let servings: Int
        let prepMinutes: Int
        let cookMinutes: Int
        let extraTags: [String]
        let imageURL: String?
        let calories: Int?
        let proteinGrams: Int?
        let carbGrams: Int?
        let fatGrams: Int?
        let notes: String
        let ingredients: [(name: String, quantity: Double?, unit: String?, note: String?, isOptional: Bool)]
        let steps: [(text: String, durationSeconds: Int?)]
    }

    /// Technique content grounded in docs/research-fried-egg.md
    /// (Serious Eats, ATK, CIA, Eggs.ca / AEB science). Extra-sensory coaching.
    private static let pack: [Lesson] = [
        Lesson(
            title: "How to Fry an Egg (Sunny-Side Up)",
            summary: "Set white, runny yolk, no flip — coached by what you see and hear, not just a timer.",
            servings: 1,
            prepMinutes: 2,
            cookMinutes: 5,
            extraTags: ["eggs", "breakfast", "technique", "beginner"],
            imageURL: "https://images.unsplash.com/photo-1525351484163-7529414344d8?w=1200&q=80&auto=format&fit=crop",
            calories: 110,
            proteinGrams: 6,
            carbGrams: 0,
            fatGrams: 9,
            notes: """
            Beginner path: nonstick + butter + lid. Salt at the end so the white doesn’t weep. \
            Food safety: USDA prefers firm yolks for high-risk people — use pasteurized eggs if you want runny yolks safely. \
            Over-easy: same start; when whites are nearly set on top, flip with confidence for 5–10 seconds only. \
            Stuck egg? Add a dab of butter at the edge and wait — don’t scrape. Broken yolk? Keep going as a basted “broken sunny” or scramble — still good.
            """,
            ingredients: [
                ("Large egg", 1, nil, "fresher = thicker white that holds a tall shape", false),
                ("Unsalted butter", 1, "tsp", "~1 tsp per egg; oil works too", false),
                ("Kosher salt", nil, nil, "pinch, at the end", true),
                ("Black pepper", nil, nil, "to taste", true),
            ],
            steps: [
                (
                    """
                    Gear check first. Grab an 8–10 inch nonstick pan (not a giant skillet for one egg) and a lid that fits — \
                    glass is nice so you can peek without dumping the steam. Also grab a small bowl or cup and a thin spatula. \
                    Crack the egg into the bowl. Look: the yolk should sit whole and glossy, and a fresher egg’s white will look thick \
                    and hug the yolk instead of flooding out thin and watery. If the yolk already broke in the bowl, don’t fight it in the pan — \
                    scramble later. Fridge-cold is fine.
                    """,
                    nil
                ),
                (
                    """
                    Put the pan on medium-low to medium — patient heat, not panicked. Drop in about a teaspoon of butter. \
                    Watch the butter go through stages: solid → melting pools → it starts to foam and bubble across the pan. \
                    Tilt the pan so the melted butter fully coats the bottom — you want a thin shiny film everywhere the egg will sit, \
                    no dry spots. Wait until the big foam settles and the butter looks calm, glossy, and liquid — not still foaming hard, \
                    not smoking, not browning into nutty brown bits. If it smells toasted already or you see brown flecks, the pan is too hot: \
                    pull it off the burner for a few seconds and turn the heat down before the egg goes in.
                    """,
                    45
                ),
                (
                    """
                    Hold the bowl right down by the pan — almost kissing the butter — and tip the egg in gently, like sliding it into bed. \
                    Don’t drop from high; that breaks yolks and splashes hot fat. Listen: you want a soft, gentle sizzle — a quiet continuous \
                    “tss” — not an angry spit-and-scream. If it’s roaring and sputtering hard, heat is too high; nudge it down. Leave the egg alone. No poking.
                    """,
                    nil
                ),
                (
                    """
                    Now watch the white change. Right away the outer edges turn from glass-clear (see-through) to cloudy. \
                    Over the next ~30–60 seconds that fog rolls inward — clear → cloudy → opaque solid white — starting at the rim. \
                    Good look: edges set and white, maybe a tiny bit of soft lace, yolk still tall and bright yellow. \
                    Bad look for this gentle style: edges already deep brown, cratered, and rubbery while the middle is still jelly — that means too hot. \
                    The thin shiny film sitting on top of the yolk often still looks clear/snotty. That’s normal. That’s the part steam will fix.
                    """,
                    60
                ),
                (
                    """
                    Lid on. You’re cooking the top white with steam so you don’t have to flip. Peek by cracking the lid just a little — \
                    don’t lift it all the way and dump every bit of steam. Look for that jelly-clear ring hugging the yolk: you want it turning opaque. \
                    Optional boost: if the top is stubborn after about a minute, splash roughly a teaspoon of water into the pan — into the fat at the side, \
                    not onto the yolk — and clap the lid back. You’ll hear a quick hiss. That’s steam doing the work.
                    """,
                    90
                ),
                (
                    """
                    Doneness check — trust your eyes more than the clock (about 1–3 minutes under the lid, stove-dependent). \
                    Ready sunny-side: the entire white is opaque, including that thin film around the yolk (no jelly-clear patches); \
                    the yolk is still glossy, bright, and wobbly if you gently nudge the pan; the underside isn’t burnt. \
                    Not ready: shiny translucent white still sitting on the yolk. Overdone: white shriveled/deep brown, yolk dull and matte with no jiggle. \
                    When it’s right: salt and pepper now (salting raw white can make little watery beads). Slide onto a plate with the thin spatula — \
                    don’t flip it in the air. Eat right away; eggs wait for no one.
                    """,
                    nil
                ),
            ]
        ),
    ]
}

extension Recipe {
    /// True for Glutt Cooking Basics lessons (technique how-tos), not user recipes.
    var isCookingBasic: Bool {
        tags.contains(CookingBasics.tag)
    }
}
