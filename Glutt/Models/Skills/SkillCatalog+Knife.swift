import Foundation

/// Knife Skills: grip first, then cuts, then the two cuts you will actually do
/// every week.
///
/// Ordered so the safety habits come before speed. Nobody gets faster by
/// trying to be fast; they get faster by holding the knife properly and
/// letting the hand stop being afraid.
extension SkillCatalog {
    static let knifeSkills = SkillCategory(
        id: "knife",
        name: "Knife Skills",
        blurb: "Hold it properly, and everything after gets faster and safer.",
        theme: .sand,
        skills: [
            Skill(
                id: "knife.grip",
                categoryID: "knife",
                title: "Hold a Chef's Knife",
                shortDescription: "Pinch the blade. Do not hold the handle like a hammer.",
                estimatedMinutes: 2,
                lesson: SkillLesson(
                    summary: "Almost everyone grips a knife too far back. Pinching the blade between thumb and forefinger gives you control over the tip, which is where the cutting actually happens.",
                    steps: [
                        "Pinch the flat of the blade just in front of the handle, thumb one side, curled forefinger the other.",
                        "Wrap the remaining three fingers around the handle.",
                        "Keep your wrist straight and let your elbow do the movement.",
                        "The tip stays near the board while the back of the blade rises and falls.",
                    ],
                    watchFors: [
                        "A fist around the handle with the forefinger along the spine. It feels safer and gives you less control.",
                        "A stiff, tense hand. A relaxed grip cuts better and tires less.",
                        "A dull knife. It needs more force, slips more, and is the more dangerous of the two.",
                    ],
                    whyItMatters: "Control comes from the front of the blade. Holding further back means steering the knife from the wrong end and pressing harder to make up for it."
                ),
                column: .center
            ),
            Skill(
                id: "knife.claw",
                categoryID: "knife",
                title: "Claw Grip",
                shortDescription: "Curl your fingertips back and let your knuckles guide the blade.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["knife.grip"],
                lesson: SkillLesson(
                    summary: "The claw is how the other hand stays safe. Fingertips curl under, knuckles come forward, and the flat of the blade rides against your knuckles as a guide.",
                    steps: [
                        "Curl your fingertips back so the first knuckle is the furthest point forward.",
                        "Rest your thumb behind your fingers, never alongside them.",
                        "Lay the side of the blade flat against your knuckles.",
                        "Walk the hand backwards as you cut, and the knife follows.",
                    ],
                    watchFors: [
                        "Flat fingers, which puts the tips exactly where the blade lands.",
                        "A thumb creeping forward past the fingers.",
                        "Lifting the blade above your knuckles, which loses the guide entirely.",
                    ],
                    whyItMatters: "Your knuckles become both the guard and the guide, so the knife physically cannot reach your fingertips and every slice comes out the same width."
                ),
                column: .left
            ),
            Skill(
                id: "knife.slice",
                categoryID: "knife",
                title: "Slice",
                shortDescription: "Draw the blade through. Do not press down on it.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["knife.claw"],
                lesson: SkillLesson(
                    summary: "A knife cuts on the slide, not on the squash. Pushing straight down crushes; drawing forward or back cuts cleanly.",
                    steps: [
                        "Start with the heel of the blade on the food and the tip on the board.",
                        "Push forward and down in one motion, letting the blade travel.",
                        "Let the knife's own weight do most of the work.",
                        "Reset and repeat, moving the claw hand back a slice at a time.",
                    ],
                    watchFors: [
                        "Sawing back and forth, which tears soft things.",
                        "Pressing straight down on a tomato, which squashes it.",
                        "Cutting fast before the motion is smooth. Smooth becomes fast on its own.",
                    ],
                    whyItMatters: "Crushed cells leak. A clean slice keeps the food's texture and stops your board turning into a puddle."
                ),
                column: .right
            ),
            Skill(
                id: "knife.rough-chop",
                categoryID: "knife",
                title: "Rough Chop",
                shortDescription: "Fast, uneven, and completely fine for stock and soup.",
                estimatedMinutes: 1,
                prerequisiteIDs: ["knife.slice"],
                lesson: SkillLesson(
                    summary: "A rough chop is deliberately imprecise. It exists for things that get blended, strained or cooked for hours, where evenness would be wasted effort.",
                    steps: [
                        "Cut the food into rough pieces of a broadly similar size.",
                        "Do not chase neatness.",
                        "Keep the pieces big enough that they do not disappear in a long cook.",
                    ],
                    watchFors: [
                        "Wildly different sizes. Rough still means roughly equal.",
                        "Using a rough chop where the pieces are visible on the plate.",
                    ],
                    whyItMatters: "Knowing when precision does not matter is as useful as being able to be precise. Stock does not care what your carrot looked like."
                ),
                column: .left
            ),
            Skill(
                id: "knife.dice",
                categoryID: "knife",
                title: "Dice",
                shortDescription: "Planks, then batons, then cubes.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["knife.slice"],
                lesson: SkillLesson(
                    summary: "Every dice is the same three moves: flat planks, then strips, then across. Once you see that, dicing anything is the same job at a different size.",
                    steps: [
                        "Square off the food so it sits flat and stops rolling.",
                        "Slice it into planks of the width you want the dice.",
                        "Stack the planks and cut into batons of the same width.",
                        "Turn ninety degrees and cut across to make cubes.",
                    ],
                    watchFors: [
                        "Skipping the flat side. Round food rolls, and rolling food is how people get cut.",
                        "Planks of different thicknesses, which no later cut can rescue.",
                        "Stacking too high, so the pile slides mid cut.",
                    ],
                    whyItMatters: "Even cubes cook at the same rate. Uneven ones give you a pan where some pieces are raw and others have gone to mush."
                ),
                column: .center
            ),
            Skill(
                id: "knife.mince",
                categoryID: "knife",
                title: "Mince",
                shortDescription: "Dice small, then rock the blade until it is finer.",
                difficulty: .intermediate,
                estimatedMinutes: 2,
                prerequisiteIDs: ["knife.dice"],
                lesson: SkillLesson(
                    summary: "Mincing is dicing taken further, finished by rocking the knife over the pile with your free hand resting on the spine.",
                    steps: [
                        "Dice as small as you comfortably can.",
                        "Gather the pile together.",
                        "Rest your free palm flat on the top of the blade near the tip.",
                        "Rock the knife through the pile, sweeping it back together as it spreads.",
                    ],
                    watchFors: [
                        "Hacking straight down, which bruises rather than cuts.",
                        "Over mincing garlic into paste unless paste is what you want.",
                        "Fingers anywhere near the edge while rocking. Palm on the spine only.",
                    ],
                    whyItMatters: "Minced aromatics melt into a dish instead of showing up as chunks. It is the difference between tasting garlic and biting garlic."
                ),
                column: .right
            ),
            Skill(
                id: "knife.julienne",
                categoryID: "knife",
                title: "Julienne",
                shortDescription: "Thin matchsticks, mostly for looks and speed.",
                difficulty: .advanced,
                estimatedMinutes: 3,
                prerequisiteIDs: ["knife.dice"],
                lesson: SkillLesson(
                    summary: "Julienne is the baton stage of a dice, stopped early and cut thinner. Matchsticks cook in moments and look deliberate on a plate.",
                    steps: [
                        "Square the food off and cut into thin planks.",
                        "Stack a few planks at a time.",
                        "Cut lengthways into matchsticks a couple of millimetres across.",
                        "Keep the stack short so it stays stable.",
                    ],
                    watchFors: [
                        "Stacks that slide. Fewer planks, more passes.",
                        "Uneven thickness, which is very visible in a raw salad.",
                    ],
                    whyItMatters: "Thin shapes cook almost instantly, which is what makes a stir fry work at all."
                ),
                column: .left
            ),
            Skill(
                id: "knife.dice-onion",
                categoryID: "knife",
                title: "Dice an Onion",
                shortDescription: "Keep the root on and the whole thing holds together.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["knife.dice", "knife.claw"],
                lesson: SkillLesson(
                    summary: "The onion is the cut you will do more than any other, and the root is the trick. Leave it attached and the layers stay held together while you work.",
                    steps: [
                        "Cut the onion in half through the root.",
                        "Peel the skin back but keep the root intact.",
                        "Lay a half flat side down and make vertical cuts toward the root, stopping before you cut through it.",
                        "Turn and cut across those slices to release an even dice.",
                        "Stop when you reach the root, and keep it for stock.",
                    ],
                    watchFors: [
                        "Cutting through the root early, after which the layers slide apart.",
                        "The flat side not actually being flat, so the onion rocks.",
                        "Chasing the last of it near the root. That part is not worth a cut finger.",
                    ],
                    whyItMatters: "Even onion is the base of a huge number of dishes, and uneven onion means some pieces burn while others stay raw and sharp."
                ),
                column: .center
            ),
            Skill(
                id: "knife.mince-garlic",
                categoryID: "knife",
                title: "Mince Garlic",
                shortDescription: "Crush, peel, slice, mince, and know when to stop.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["knife.mince"],
                lesson: SkillLesson(
                    summary: "Garlic is quick once you stop fighting the skin. Crushing the clove under the flat of the blade loosens it in a second.",
                    steps: [
                        "Lay the flat of the blade over the clove and press down firmly with your palm.",
                        "Peel away the loosened skin.",
                        "Slice thin, then turn and slice again.",
                        "Rock the knife through until it is as fine as you want.",
                    ],
                    watchFors: [
                        "Smashing so hard it becomes paste before you start.",
                        "Mincing garlic long before you cook it. It turns harsh sitting out.",
                        "Burning it. Minced garlic goes from golden to bitter in seconds.",
                    ],
                    whyItMatters: "How finely you cut garlic changes how strong it tastes. Fine mince goes sharp and everywhere; sliced is mellow and sweet."
                ),
                column: .right
            ),
            Skill(
                id: "knife.chop-herbs",
                categoryID: "knife",
                title: "Chop Herbs",
                shortDescription: "Dry them, pile them, and cut once.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["knife.mince"],
                lesson: SkillLesson(
                    summary: "Herbs bruise easily, and bruised herbs go dark and taste like the board. The goal is few cuts, cleanly.",
                    steps: [
                        "Dry the herbs properly. Wet herbs smear.",
                        "Gather the leaves into a tight pile.",
                        "Rock the knife through a few times only.",
                        "Stop as soon as they are the size you want.",
                    ],
                    watchFors: [
                        "Chopping and chopping until they go black.",
                        "Chopping soft herbs long before serving. Do it last.",
                        "A dull knife, which tears leaves rather than cutting them.",
                    ],
                    whyItMatters: "Herb flavour is in oils that escape the moment the leaf is crushed. Fewer, cleaner cuts keep them on the plate rather than the board."
                ),
                column: .left
            ),
            Skill(
                id: "knife.against-grain",
                categoryID: "knife",
                title: "Slice Against the Grain",
                shortDescription: "Find the direction of the fibres, then cut across them.",
                difficulty: .intermediate,
                estimatedMinutes: 2,
                prerequisiteIDs: ["knife.slice"],
                lesson: SkillLesson(
                    summary: "Meat is made of long fibres running in one direction. Cutting across them shortens every fibre, and short fibres are what tender means.",
                    steps: [
                        "Look at the raw meat and find the lines running along it.",
                        "Turn the meat so those lines run left to right in front of you.",
                        "Slice straight down across them.",
                        "On a cut whose grain changes direction, such as flank, adjust as you go.",
                    ],
                    watchFors: [
                        "Slicing with the grain, which leaves long chewy strands.",
                        "Trying to find the grain after cooking, when it is much harder to see. Look before.",
                        "Thick slices of a tough cut. Thinner helps more than you expect.",
                    ],
                    whyItMatters: "The same steak, cooked identically, is tender or chewy depending only on this. It is the highest reward per second of any knife habit."
                ),
                column: .right
            ),
            Skill(
                id: "knife.challenge-mirepoix",
                categoryID: "knife",
                title: "Prep a Full Mirepoix",
                shortDescription: "Onion, carrot and celery, evenly diced, in one calm run.",
                difficulty: .intermediate,
                estimatedMinutes: 6,
                prerequisiteIDs: [
                    "knife.dice-onion",
                    "knife.dice",
                    "knife.claw",
                ],
                lesson: SkillLesson(
                    summary: "The classic base of soups, stews and sauces, and a genuine test: three vegetables of different shapes and densities, diced to the same size, without rushing.",
                    steps: [
                        "Roughly two parts onion to one part carrot and one part celery.",
                        "Square each vegetable off so nothing rolls.",
                        "Dice all three to the same size, around half a centimetre.",
                        "Keep them in separate piles, since carrot takes longest and goes in first.",
                        "Check your pieces at the end and see how even they really are.",
                    ],
                    watchFors: [
                        "Carrot diced larger than onion, so it is still hard when the onion has gone.",
                        "Speeding up once it feels easy. Even beats fast.",
                        "Celery strings, which are fine here but noticeable raw.",
                    ],
                    whyItMatters: "If you can dice a mirepoix evenly and calmly, you can prep almost any recipe's base, and you will feel the difference in every braise you make afterwards."
                ),
                isChallenge: true,
                column: .center
            ),
        ]
    )
}
