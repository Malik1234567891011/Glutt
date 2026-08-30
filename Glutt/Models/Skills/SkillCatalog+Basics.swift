import Foundation

/// Cooking Basics: the habits that make everything else easier.
///
/// Deliberately first on the map and deliberately unglamorous. Almost every
/// "my food is fine but not good" problem traces back to one of these rather
/// than to technique.
extension SkillCatalog {
    static let cookingBasics = SkillCategory(
        id: "basics",
        name: "Cooking Basics",
        blurb: "The habits that quietly decide how everything else turns out.",
        theme: .sky,
        skills: [
            Skill(
                id: "basics.read-recipe",
                categoryID: "basics",
                title: "Read a Recipe First",
                shortName: "Read it first",
                glyph: "book",
                shortDescription: "Read it all the way through before you turn anything on.",
                estimatedMinutes: 2,
                lesson: SkillLesson(
                    summary: "Reading the whole recipe before you start is the cheapest way to avoid the two things that ruin dinner: discovering a missing ingredient halfway, and discovering a step that needed to start an hour ago.",
                    steps: [
                        "Read the ingredient list and check you actually have everything.",
                        "Read every step to the end, not just the first one.",
                        "Look for anything with a wait in it: marinating, chilling, resting, bringing to room temperature.",
                        "Note which steps overlap, so you know what to start first.",
                    ],
                    watchFors: [
                        "Ingredients hidden in the steps that never made the list.",
                        "Phrases like \"meanwhile\" and \"reserved\", which mean two things happen at once.",
                        "A resting time at the end that you need to plan around.",
                    ],
                    whyItMatters: "Every recipe assumes you already know what is coming. Two minutes of reading buys back the twenty you would lose improvising."
                ),
                column: .center
            ),
            Skill(
                id: "basics.mise-en-place",
                categoryID: "basics",
                title: "Mise en Place",
                shortName: "Mise en place",
                glyph: "square.grid.2x2",
                shortDescription: "Everything prepped and within reach before the heat goes on.",
                estimatedMinutes: 3,
                prerequisiteIDs: ["basics.read-recipe"],
                lesson: SkillLesson(
                    summary: "Mise en place just means having everything measured, chopped and within arm's reach before you start cooking. It is the single habit that separates calm cooking from panic.",
                    steps: [
                        "Chop and measure everything the recipe asks for.",
                        "Put each thing in its own small bowl or pile.",
                        "Group them in the order you will use them.",
                        "Clear everything else off the counter.",
                        "Now turn on the heat.",
                    ],
                    watchFors: [
                        "Prepping while the pan is already hot. That is how garlic burns.",
                        "Leaving the bin across the kitchen. Keep a bowl for scraps beside you.",
                        "Skipping it for fast recipes. Fast recipes are exactly the ones with no time to chop.",
                    ],
                    whyItMatters: "Once the pan is hot, cooking moves faster than chopping does. Prep first and you are never choosing between stirring and slicing."
                ),
                column: .left
            ),
            Skill(
                id: "basics.season-as-you-go",
                categoryID: "basics",
                title: "Season as You Cook",
                shortName: "Seasoning",
                glyph: "drop",
                shortDescription: "Salt in layers, not all at the end.",
                estimatedMinutes: 2,
                lesson: SkillLesson(
                    summary: "Salting at each stage seasons the food itself. Salting only at the end seasons the surface, which tastes like salt sitting on top of bland food.",
                    steps: [
                        "Salt onions and vegetables as they go into the pan.",
                        "Salt meat before it hits the heat.",
                        "Salt pasta water until it tastes seasoned.",
                        "Taste near the end and adjust once more.",
                    ],
                    watchFors: [
                        "Salting hard at every stage. Each layer is a pinch, not a handful.",
                        "Forgetting that stock, soy sauce, cheese and cured meat bring their own salt.",
                        "Salting a sauce before it reduces. It concentrates as the water leaves.",
                    ],
                    whyItMatters: "Salt needs time and heat to move into food. Added late it never gets there, which is why the same amount tastes saltier and works less well."
                ),
                column: .right
            ),
            Skill(
                id: "basics.taste-as-you-go",
                categoryID: "basics",
                title: "Taste as You Cook",
                shortName: "Tasting",
                glyph: "fork.knife",
                shortDescription: "Taste at every stage, not once at the end.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["basics.season-as-you-go"],
                lesson: SkillLesson(
                    summary: "Tasting as you go is how you catch a problem while it is still fixable. At the end, your only options are to serve it or start again.",
                    steps: [
                        "Taste after each significant addition.",
                        "Ask one question: does it need salt, acid, fat or heat?",
                        "Adjust a little, then taste again.",
                        "Use a clean spoon each time.",
                    ],
                    watchFors: [
                        "Tasting only at the end, when the answer is always \"too late\".",
                        "Adjusting twice before tasting, so you cannot tell which change helped.",
                        "Tasting something that is still raw, which tells you very little.",
                    ],
                    whyItMatters: "Recipes are written for someone else's ingredients. Your onion, your salt and your pan are not theirs, so the recipe is a starting point and your tongue is the instrument."
                ),
                column: .center
            ),
            Skill(
                id: "basics.simmer-vs-boil",
                categoryID: "basics",
                title: "Simmer and Boil",
                shortName: "Simmer or boil",
                glyph: "humidity",
                shortDescription: "Tell them apart by looking at the surface.",
                difficulty: .beginner,
                estimatedMinutes: 2,
                lesson: SkillLesson(
                    summary: "A boil is big rolling bubbles across the whole surface. A simmer is small bubbles rising lazily from the bottom, with the surface barely moving. Most recipes that say simmer are ruined by a boil.",
                    steps: [
                        "Bring the pot up on high until it boils properly.",
                        "Turn the heat down until the rolling stops.",
                        "Look for small bubbles breaking the surface every second or so.",
                        "Adjust to hold it there. On most stoves that is somewhere near low.",
                    ],
                    watchFors: [
                        "A lid holding in more heat than you expect. Lids turn a simmer into a boil.",
                        "Boiling a stew, which shreds the meat and clouds the liquid.",
                        "Letting a simmer die completely, which is just warm food sitting still.",
                    ],
                    whyItMatters: "Boiling agitates and toughens. Simmering coaxes. The difference between a silky braise and a stringy one is often nothing more than this."
                ),
                visualCheck: .basicsSimmerVsBoil,
                column: .left
            ),
            Skill(
                id: "basics.doneness",
                categoryID: "basics",
                title: "Know When Food Is Done",
                shortName: "Doneness",
                glyph: "checkmark.seal",
                shortDescription: "Judge by sight, touch and smell, not by the clock.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["basics.taste-as-you-go"],
                lesson: SkillLesson(
                    summary: "Cooking times in recipes are estimates written for a stove that is not yours. Doneness is something you read off the food itself.",
                    steps: [
                        "Start checking well before the stated time.",
                        "Look: colour, bubbling, how the edges have changed.",
                        "Touch: firmness tells you more than time for meat and fish.",
                        "Smell: nuttiness and caramel mean ready, sharpness means not yet, acrid means past it.",
                        "For anything you can cut into, cut into it. A test piece costs nothing.",
                    ],
                    watchFors: [
                        "Trusting the recipe's timing over your own eyes.",
                        "Carryover cooking. Food keeps cooking off the heat, so pull it slightly early.",
                        "Opening the oven every minute, which drops the temperature and slows everything.",
                    ],
                    whyItMatters: "Two stoves set to the same number can differ by a lot. Reading the food instead of the clock is what makes you able to cook in any kitchen."
                ),
                column: .right
            ),
            Skill(
                id: "basics.thermometer",
                categoryID: "basics",
                title: "Use a Thermometer",
                shortName: "Thermometer",
                glyph: "thermometer.medium",
                shortDescription: "Where to put it, and what the numbers mean.",
                difficulty: .beginner,
                estimatedMinutes: 2,
                prerequisiteIDs: ["basics.doneness"],
                lesson: SkillLesson(
                    summary: "A thermometer turns the hardest question in cooking, is it done, into a number. For anything expensive it is the difference between guessing and knowing.",
                    steps: [
                        "Push the probe into the thickest part.",
                        "Keep it away from bone, fat and the pan, all of which read hotter.",
                        "Wait for the number to settle rather than reading the first thing it shows.",
                        "Pull food a few degrees early and let carryover finish it.",
                    ],
                    watchFors: [
                        "Probing through to the pan, which reads far too high.",
                        "Checking one spot only. Try two and trust the lower one.",
                        "Forgetting that resting meat keeps climbing.",
                    ],
                    whyItMatters: "Colour lies, especially with poultry and thick cuts. Temperature does not, and it is the only way to cook a steak the same way twice."
                ),
                visualCheck: .basicsThermometer,
                column: .center
            ),
            Skill(
                id: "basics.rest-food",
                categoryID: "basics",
                title: "Rest Food After Cooking",
                shortName: "Resting",
                glyph: "clock",
                shortDescription: "Wait before cutting, and keep the juices in the meat.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["basics.doneness"],
                lesson: SkillLesson(
                    summary: "Resting lets the juices in hot meat settle back through it. Cut too early and they run out onto the board instead of staying where you want them.",
                    steps: [
                        "Move the meat off the heat onto a board or warm plate.",
                        "Rest a steak or chop about 5 minutes, a roast or whole chicken 15 to 20.",
                        "Leave it uncovered, or tent it loosely if the room is cold.",
                        "Pour any juice from the board back over after slicing.",
                    ],
                    watchFors: [
                        "Wrapping tightly in foil, which steams the crust you just built.",
                        "Resting so long it goes cold. Warm the plates instead.",
                        "Skipping it for a thin cut. Even 2 minutes helps.",
                    ],
                    whyItMatters: "The board being covered in juice is the visible version of the meat being drier. Resting is free and it is the last chance to protect the work you already did."
                ),
                column: .left
            ),
            Skill(
                id: "basics.challenge-cook-without-timer",
                categoryID: "basics",
                title: "Cook a Meal by Feel",
                shortName: "Cook by feel",
                glyph: "star.fill",
                shortDescription: "Put it together: read it, prep it, season it, and call doneness yourself.",
                difficulty: .intermediate,
                estimatedMinutes: 5,
                prerequisiteIDs: [
                    "basics.mise-en-place",
                    "basics.taste-as-you-go",
                    "basics.doneness",
                    "basics.rest-food",
                ],
                lesson: SkillLesson(
                    summary: "A mastery run. Cook something you already know, using every basic at once, and judge the whole thing by sight, smell and taste rather than the recipe's timings.",
                    steps: [
                        "Pick a dish you have cooked before, so the recipe is not the hard part.",
                        "Read it through, then prep everything before the heat goes on.",
                        "Season at each stage and taste as you go.",
                        "Call doneness yourself, checking the recipe's time only afterwards.",
                        "Rest anything that should rest, then taste one final time and adjust.",
                    ],
                    watchFors: [
                        "Drifting back to the clock the moment you feel unsure.",
                        "Forgetting the final taste, which is where most dishes are actually won.",
                    ],
                    whyItMatters: "This is the whole point of the basics. Once you can run them together without thinking, you can cook a dish you have never seen before."
                ),
                isChallenge: true,
                column: .center
            ),
        ]
    )
}
