import Foundation

/// Eggs, written from `docs/skills-instructor-deliverable.md`.
///
/// The instructor put this first among the unwritten categories and the reason
/// is practical: eggs are the cheapest way to practise heat control there is.
/// A cook can fail four times in ten minutes for the price of four eggs, which
/// is not true of anything else worth learning.
///
/// One rule shapes almost every lesson here, and it is the thing that stops
/// this being a list of somebody's preferences: **ask which style they want
/// before judging anything.** Soft French scrambled eggs are not better than
/// fluffy American ones. A crisp-edged fried egg is not worse than a tender
/// one. A French omelette and an American omelet are different dishes with
/// opposite rubrics, and browning is either a fault or the entire point
/// depending on an answer only the cook has.
///
/// The other correction worth naming: the common warning that salting eggs
/// early makes them tough is not supported, and it is not treated as a mistake
/// anywhere in this file.
extension SkillCatalog {

    static let eggs = SkillCategory(
        id: "eggs",
        name: "Eggs",
        blurb: "The cheapest way to practise heat control there is.",
        theme: .amber,
        skills: [
            Skill(
                id: "eggs.crack",
                categoryID: "eggs",
                title: "Crack an Egg",
                shortName: "Cracking",
                glyph: "oval.fill",
                shortDescription: "Open it cleanly, and keep the shell out of the bowl.",
                estimatedMinutes: 2,
                lesson: SkillLesson(
                    summary: "A clean crack keeps shell out of your food and gives you control "
                        + "of the yolk. It takes about a minute to learn and you will do it "
                        + "thousands of times.",
                    steps: [
                        "Tap the egg once, firmly, on a flat surface like the counter.",
                        "Put both thumbs into the crack and pull the shell apart over a bowl.",
                        "Check for shell before it goes in with anything else.",
                    ],
                    watchFors: [
                        "Squeezing the egg instead of opening it.",
                        "Driving a thumb straight down through the yolk.",
                        "Cracking into a finished mixture, where a stray shell is hard to find.",
                    ],
                    whyItMatters: "A flat surface cracks the shell in one clean line. The edge "
                        + "of a bowl pushes shards inward, which is where the little white bits "
                        + "in your scrambled eggs come from."
                ),
                visualCheck: .eggsCrack,
                column: .center
            ),
            Skill(
                id: "eggs.scrambled",
                categoryID: "eggs",
                title: "Scrambled Eggs",
                shortName: "Scrambled",
                glyph: "oval.fill",
                shortDescription: "Heat control, in its simplest possible form.",
                estimatedMinutes: 3,
                prerequisiteIDs: ["eggs.crack"],
                lesson: SkillLesson(
                    summary: "Scrambled eggs are almost entirely heat control. Decide what "
                        + "texture you want first, because creamy and fluffy are different "
                        + "dishes and they are cooked differently.",
                    steps: [
                        "Beat the eggs until the colour is even. Season them now if you like.",
                        "Melt butter in the pan over low to medium heat, gentler for creamy.",
                        "Add the eggs and keep moving the set egg back into the liquid.",
                        "Take them off while they still look slightly underdone.",
                    ],
                    watchFors: [
                        "Heat high enough that they set faster than you can move them.",
                        "Waiting until they look finished in the pan, which is too late.",
                        "Raw liquid left in the folds when you wanted them fully set.",
                    ],
                    whyItMatters: "The pan keeps cooking them for a while after it leaves the "
                        + "heat. Pulling early is not underdoing it, it is allowing for that."
                ),
                visualCheck: .eggsScrambled,
                column: .left
            ),
            Skill(
                id: "eggs.fried",
                categoryID: "eggs",
                title: "Fried Egg",
                shortName: "Fried",
                glyph: "oval.fill",
                shortDescription: "Set the white without ruining the yolk.",
                estimatedMinutes: 3,
                prerequisiteIDs: ["eggs.crack"],
                lesson: SkillLesson(
                    summary: "The white and the yolk set at different temperatures, so the "
                        + "whole skill is getting the white done without taking the yolk "
                        + "further than you wanted.",
                    steps: [
                        "Heat your fat. Hot for crisp lacy edges, gentle for a tender white.",
                        "Slide the egg in from close to the pan so the yolk stays whole.",
                        "Cook until the white is set. Cover the pan, baste with fat, or flip, "
                            + "depending on the style you are after.",
                    ],
                    watchFors: [
                        "Clear jelly-like white still sitting around the yolk.",
                        "A burnt underside while the top is still raw.",
                        "Breaking the yolk when turning it.",
                    ],
                    whyItMatters: "The white nearest the yolk is the last to set. That is why "
                        + "covering the pan or spooning hot fat over the top works, and why "
                        + "just waiting usually overcooks the bottom."
                ),
                visualCheck: .eggsFried,
                column: .right
            ),
            Skill(
                id: "eggs.soft-boiled",
                categoryID: "eggs",
                title: "Soft-Boiled Egg",
                shortName: "Soft-boiled",
                glyph: "oval.fill",
                shortDescription: "A set white and a yolk exactly as loose as you want it.",
                estimatedMinutes: 3,
                prerequisiteIDs: ["basics.simmer-vs-boil"],
                lesson: SkillLesson(
                    summary: "A repeatable method plus a timer plus cooling promptly. Once you "
                        + "find the number that works on your stove, it works every time.",
                    steps: [
                        "Bring the water to whatever state your method starts from, and keep "
                            + "it steady.",
                        "Lower the eggs in gently and start timing from that moment.",
                        "Cool them under cold water as soon as the time is up.",
                    ],
                    watchFors: [
                        "Dropping eggs in and cracking them on the bottom.",
                        "A rolling boil knocking them about.",
                        "Leaving them in the hot water after the timer, which keeps cooking them.",
                    ],
                    whyItMatters: "The centre keeps cooking after the egg leaves the water. "
                        + "Cooling is not tidying up, it is the thing that stops the clock."
                ),
                visualCheck: .eggsSoftBoiled,
                column: .left
            ),
            Skill(
                id: "eggs.hard-boiled",
                categoryID: "eggs",
                title: "Hard-Boiled Egg",
                shortName: "Hard-boiled",
                glyph: "oval.fill",
                shortDescription: "Fully set, without the rubber and the grey ring.",
                estimatedMinutes: 3,
                prerequisiteIDs: ["eggs.soft-boiled"],
                lesson: SkillLesson(
                    summary: "Getting an egg fully cooked is easy. Getting it fully cooked "
                        + "without a bouncy white and a grey-green yolk takes slightly less "
                        + "heat and slightly more attention.",
                    steps: [
                        "Cook at a gentle simmer or steam rather than a hard boil.",
                        "Give it long enough that the yolk is set right through.",
                        "Cool it promptly when it comes out.",
                    ],
                    watchFors: [
                        "A violent boil cracking the shells.",
                        "Leaving them well past done, which is where the grey ring comes from.",
                        "Skipping the cooling.",
                    ],
                    whyItMatters: "That grey-green layer around the yolk is a reaction between "
                        + "the iron in the yolk and the sulfur in the white. It is harmless and "
                        + "it is a reliable sign the egg went too far."
                ),
                visualCheck: .eggsHardBoiled,
                column: .right
            ),
            Skill(
                id: "eggs.poached",
                categoryID: "eggs",
                title: "Poached Egg",
                shortName: "Poached",
                glyph: "oval.fill",
                shortDescription: "Set the white around the yolk instead of shredding it.",
                difficulty: .intermediate,
                estimatedMinutes: 4,
                prerequisiteIDs: ["basics.simmer-vs-boil", "eggs.crack"],
                lesson: SkillLesson(
                    summary: "Poaching is gentle water and a fresh egg. Almost everything else "
                        + "you have heard about it is optional.",
                    steps: [
                        "Crack the egg into a small cup first.",
                        "Get the water to a gentle simmer, not a boil.",
                        "Bring the cup right down to the water and let the egg slide in.",
                        "Lift it out when the white is set the way you want it and drain it.",
                    ],
                    watchFors: [
                        "Water at a rolling boil, which tears the white apart.",
                        "Dropping the egg in from a height.",
                        "An older egg, whose white is thin and spreads.",
                    ],
                    whyItMatters: "A fresh egg holds together on its own. If yours spreads, "
                        + "that is the egg rather than your technique."
                ),
                visualCheck: .eggsPoached,
                column: .center
            ),
            Skill(
                id: "eggs.omelette",
                categoryID: "eggs",
                title: "Omelette",
                shortName: "Omelette",
                glyph: "oval.fill",
                shortDescription: "Two different dishes with the same name. Pick one.",
                difficulty: .intermediate,
                estimatedMinutes: 4,
                prerequisiteIDs: ["eggs.scrambled"],
                lesson: SkillLesson(
                    summary: "A French omelette is pale, smooth and soft in the middle. An "
                        + "American omelet is browned, fluffy and folded around a filling. "
                        + "Decide which one you are making before you turn the heat on.",
                    steps: [
                        "Beat the eggs until evenly mixed, and heat butter in the pan.",
                        "Add the eggs and keep pushing the set edges in so raw egg runs "
                            + "underneath.",
                        "Add any filling while the surface is still slightly soft.",
                        "Fold or roll it before it dries out.",
                    ],
                    watchFors: [
                        "Browning, which is a fault in a French omelette and expected in an "
                            + "American one.",
                        "Too much filling for the egg to close around.",
                        "Waiting so long to fold that it cracks.",
                    ],
                    whyItMatters: "Almost every omelette problem is a timing problem. The egg "
                        + "sheet has one short window where it is set enough to move and still "
                        + "soft enough to bend."
                ),
                visualCheck: .eggsOmelette,
                column: .left
            ),
            Skill(
                id: "eggs.challenge",
                categoryID: "eggs",
                title: "Egg Mastery",
                shortName: "Egg mastery",
                glyph: "oval.fill",
                shortDescription: "Three eggs, three different heat targets, in one session.",
                difficulty: .advanced,
                estimatedMinutes: 12,
                prerequisiteIDs: ["eggs.scrambled", "eggs.fried", "eggs.omelette"],
                lesson: SkillLesson(
                    summary: "Three eggs, cooked three ways, each hitting a texture you named "
                        + "before you started. This is a heat control test wearing a breakfast "
                        + "costume.",
                    steps: [
                        "Say what you are going for on each one before you cook it.",
                        "Scrambled eggs in your chosen style.",
                        "A fried egg in your chosen style.",
                        "An omelette, or a poached egg, whichever you would rather.",
                    ],
                    watchFors: [
                        "Changing your mind about the target halfway through, which makes it "
                            + "impossible to say whether you hit it.",
                        "Running all three at once, which is a different skill.",
                        "Cooking on a heat you have not adjusted since the first egg.",
                    ],
                    whyItMatters: "Naming the target first is what turns cooking into a skill. "
                        + "Anyone can produce an egg, and knowing which egg you are about to "
                        + "produce is the whole thing."
                ),
                visualCheck: .eggsChallenge,
                isChallenge: true,
                column: .center
            ),
        ]
    )
}
