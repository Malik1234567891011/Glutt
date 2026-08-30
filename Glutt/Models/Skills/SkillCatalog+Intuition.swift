import Foundation

/// Cooking Intuition, written from `docs/skills-instructor-deliverable.md`.
///
/// Like Flavor, **none of these has a visual rubric and none should**. They are
/// reasoning skills: working backwards from when you want to eat, deciding what
/// an ingredient is actually doing before replacing it, knowing that the first
/// move when something is overcooking is to stop cooking it. A camera can watch
/// somebody execute a plan and it cannot watch them make one.
///
/// The instructor's honest note on this category is worth keeping in view: much
/// of it cannot be taught through a camera at all, and pretending otherwise
/// would be the clearest possible case of the app being a pose classifier with
/// opinions. These are written to be read, and to be talked through with Chef
/// once she can do that.
///
/// One structural recommendation is NOT applied here: merging "Know Why Food
/// Tastes Bland" into "Fix Bland Food". They do overlap, the instructor is
/// right about it, and removing a node from a published map is a product
/// decision rather than a content one. The overlap is noted in the lesson so
/// a cook who has done both is not surprised.
extension SkillCatalog {

    static let intuition = SkillCategory(
        id: "intuition",
        name: "Cooking Intuition",
        blurb: "The part that stops being a recipe and starts being cooking.",
        theme: .sky,
        skills: [
            Skill(
                id: "intuition.why-bland",
                categoryID: "intuition",
                title: "Know Why Food Tastes Bland",
                shortName: "Why bland",
                glyph: "lightbulb",
                shortDescription: "Four questions that find the problem in about ten seconds.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["flavor.fix-bland"],
                lesson: SkillLesson(
                    summary: "The diagnosis behind Fix Bland Food, on its own. If you already "
                        + "worked through that one, this is the same four questions with more "
                        + "time spent on why each answer points where it does.",
                    steps: [
                        "Is it actually short of salt, or does it just taste of nothing?",
                        "Is it heavy and rich, which usually means it wants acid?",
                        "Is it watery, which means concentration rather than seasoning?",
                        "Is it thin and shallow, which means it needs browning or stock?",
                    ],
                    watchFors: [
                        "Answering salt to all four, which is the default and wrong most "
                            + "of the time.",
                        "Diagnosing a spoonful instead of the dish with its component parts.",
                        "Changing more than one thing before tasting again.",
                    ],
                    whyItMatters: "Cooks who never get past salt hit a ceiling quickly. The "
                        + "moment you can tell heavy from bland from watery, most of your food "
                        + "gets better at once."
                ),
                column: .center
            ),
            Skill(
                id: "intuition.substitutions",
                categoryID: "intuition",
                title: "Make Substitutions",
                shortName: "Substituting",
                glyph: "lightbulb",
                shortDescription: "Swap by what it does, not by what it is.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["flavor.fat"],
                lesson: SkillLesson(
                    summary: "Every ingredient is doing a job. Once you can name the job, you "
                        + "can work out what else does it, and you stop being stuck because "
                        + "you are out of one thing.",
                    steps: [
                        "Name what it does here: fat, acid, structure, water, leavening, "
                            + "thickening, or aroma.",
                        "Find something that does the same job.",
                        "Adjust the amount, because equivalents are rarely one for one.",
                        "Expect it to taste different, and decide whether that is fine.",
                    ],
                    watchFors: [
                        "Swapping something structural in baking, where it is doing "
                            + "chemistry rather than flavour.",
                        "Swapping one acid for another without adjusting for strength.",
                        "Any substitution that changes how the food needs to be handled "
                            + "for safety.",
                    ],
                    whyItMatters: "Buttermilk in a cake is acid and liquid, not dairy. Once you "
                        + "see that, milk with lemon in it is an obvious answer instead of "
                        + "a trick."
                ),
                column: .left
            ),
            Skill(
                id: "intuition.recover",
                categoryID: "intuition",
                title: "Recover From Overcooking",
                shortName: "Recovering",
                glyph: "lightbulb",
                shortDescription: "First stop the heat. Then decide what is still possible.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["basics.doneness"],
                lesson: SkillLesson(
                    summary: "The first move is always the same, and almost nobody makes it: "
                        + "get the food off the heat before you start working out what to do.",
                    steps: [
                        "Take it out of the hot pan. Deciding takes time and it is still "
                            + "cooking while you decide.",
                        "Work out what the damage is: dry, burnt, or collapsed.",
                        "Choose a rescue. Add moisture or fat, slice it thinner, shred it into "
                            + "something else, or trim the burnt part away.",
                        "Accept when it is not recoverable and repurpose it.",
                    ],
                    watchFors: [
                        "Leaving it in the pan while you think.",
                        "Trying to make dry meat juicy by cooking it more.",
                        "Scraping a burnt layer into the rest of the dish.",
                    ],
                    whyItMatters: "Not every overcook is recoverable, and knowing which ones "
                        + "are is what stops you making it worse trying."
                ),
                column: .right
            ),
            Skill(
                id: "intuition.timing",
                categoryID: "intuition",
                title: "Time Multiple Components",
                shortName: "Timing",
                glyph: "lightbulb",
                shortDescription: "Work backwards from when you want to eat.",
                difficulty: .advanced,
                estimatedMinutes: 4,
                prerequisiteIDs: ["basics.mise-en-place"],
                lesson: SkillLesson(
                    summary: "Getting three things to the table at once is a planning problem "
                        + "rather than a cooking one. You solve it before you turn anything on.",
                    steps: [
                        "Decide when you want to eat.",
                        "For each component, note how long it takes and how long it will "
                            + "hold once done.",
                        "Work backwards and start the longest, least flexible one first.",
                        "Use the resting and holding windows as slack, and re-check as you go.",
                    ],
                    watchFors: [
                        "Starting everything at once because it feels efficient.",
                        "Finishing the delicate thing first and letting it die.",
                        "Forgetting that meat needs resting time inside the plan.",
                    ],
                    whyItMatters: "Some things wait happily and some do not. A braise will sit "
                        + "for twenty minutes; a fried egg will not sit for two."
                ),
                column: .center
            ),
            Skill(
                id: "intuition.scale",
                categoryID: "intuition",
                title: "Scale a Recipe",
                shortName: "Scaling",
                glyph: "lightbulb",
                shortDescription: "Multiply the ingredients. Then notice what does not scale.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["basics.read-recipe"],
                lesson: SkillLesson(
                    summary: "Doubling a recipe is arithmetic for about eighty per cent of it. "
                        + "The rest is knowing which things do not behave that way.",
                    steps: [
                        "Multiply the core ingredients.",
                        "Then check the things that do not scale: pan size, surface area, "
                            + "cooking time, salt, spice and leavening.",
                        "Use a bigger pan or cook in batches rather than overloading one.",
                        "Season toward the end rather than doubling it up front.",
                    ],
                    watchFors: [
                        "Doubling the food and keeping the same pan, which turns a sauté "
                            + "into a steam.",
                        "Doubling the cooking time, which almost never applies.",
                        "Doubling salt blindly in something that reduces.",
                    ],
                    whyItMatters: "Twice the food in the same pan is not twice the cooking, it "
                        + "is a different and worse method."
                ),
                column: .left
            ),
            Skill(
                id: "intuition.challenge-no-recipe",
                categoryID: "intuition",
                title: "Cook Without a Recipe",
                shortName: "No recipe",
                glyph: "lightbulb",
                shortDescription: "A method, some ingredients, and a doneness cue you chose.",
                difficulty: .advanced,
                estimatedMinutes: 20,
                prerequisiteIDs: [
                    "intuition.timing",
                    "intuition.substitutions",
                    "flavor.finish-acid",
                ],
                lesson: SkillLesson(
                    summary: "Build a meal from a cooking method and what you actually have, "
                        + "rather than from a page. This is everything else in the map used "
                        + "at once.",
                    steps: [
                        "Pick your main ingredient and a method that suits it.",
                        "Decide your fat, your aromatics and your seasoning structure.",
                        "Decide, before you start, how you will know it is done.",
                        "Cook, adjust as you go, and finish with balance.",
                    ],
                    watchFors: [
                        "Turning the heat on before you have a plan.",
                        "Changing five things at once when something is not working.",
                        "Never deciding on a doneness cue, so you are guessing at the end.",
                    ],
                    whyItMatters: "Recipes are somebody else's decisions written down. Once you "
                        + "can make those decisions yourself, a recipe becomes a suggestion "
                        + "rather than an instruction."
                ),
                isChallenge: true,
                column: .center
            ),
        ]
    )
}
