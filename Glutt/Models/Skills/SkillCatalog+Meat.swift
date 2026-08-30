import Foundation

/// Meat, written from `docs/skills-instructor-deliverable.md`.
///
/// Two things the instructor was emphatic about, and both are corrections to
/// what this category would otherwise have taught:
///
/// **Searing does not seal in juices.** It is a browning reaction that builds
/// flavour and colour, and nothing else. The myth is everywhere and it appears
/// nowhere here.
///
/// **Colour is not a safety test.** Chef never certifies that meat is cooked
/// from how it looks, on any lesson in this category. Where doneness matters
/// the answer is a thermometer, and the consumer safety floors are stated
/// rather than implied: 145F with a three minute rest for whole cuts of beef,
/// pork, lamb and veal, 160F for anything minced, 165F for poultry.
///
/// A quality target and a safety minimum are different things and the lessons
/// keep them apart. A cook who wants a steak at 130F is not being corrected;
/// they are being told which of those two numbers they are choosing.
extension SkillCatalog {

    static let meat = SkillCategory(
        id: "meat",
        name: "Meat",
        blurb: "The expensive ingredient, and the one worth being deliberate with.",
        theme: .peach,
        skills: [
            Skill(
                id: "meat.season",
                categoryID: "meat",
                title: "Season Meat",
                shortName: "Seasoning meat",
                glyph: "flame",
                shortDescription: "Evenly, and at a time that suits what you are cooking.",
                estimatedMinutes: 2,
                lesson: SkillLesson(
                    summary: "Salt on meat does two jobs: it seasons it, and it pulls moisture "
                        + "to the surface. When you salt decides which of those you get.",
                    steps: [
                        "Pat the surface dry.",
                        "Salt from a height so it lands evenly, including the sides.",
                        "Either cook it soon, or leave it long enough to dry brine properly.",
                    ],
                    watchFors: [
                        "Patchy coverage, with clumps in some places and bare patches in others.",
                        "Salting fifteen minutes before searing, which is the worst window.",
                        "Sugary rubs on anything going into a hard sear.",
                    ],
                    whyItMatters: "Salt pulls moisture out at first and then lets it back in. "
                        + "Cook straight away or give it hours. In between is when the surface "
                        + "is wettest and will not brown."
                ),
                visualCheck: .meatSeason,
                column: .center
            ),
            Skill(
                id: "meat.dry",
                categoryID: "meat",
                title: "Dry Meat Before Searing",
                shortName: "Drying",
                glyph: "flame",
                shortDescription: "The least glamorous step, and the one that decides the crust.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["meat.season"],
                lesson: SkillLesson(
                    summary: "Water on the surface has to boil off before anything can brown. "
                        + "Removing it first is the cheapest improvement you can make to "
                        + "a sear.",
                    steps: [
                        "Blot every exposed surface with paper towel.",
                        "Check the folds, the creases and the skin side.",
                        "Get it into the pan while it is still dry.",
                    ],
                    watchFors: [
                        "A glossy wet sheen still on the surface.",
                        "Marinade dripping off as it goes into the pan.",
                        "Paper towel shredding onto delicate fish.",
                    ],
                    whyItMatters: "A wet surface cannot get above the boiling point of water, "
                        + "and browning happens well above that. Until the water is gone, the "
                        + "pan is just making steam."
                ),
                visualCheck: .meatDry,
                column: .left
            ),
            Skill(
                id: "meat.temperature",
                categoryID: "meat",
                title: "Understand Internal Temperature",
                shortName: "Temperature",
                glyph: "flame",
                shortDescription: "The only honest answer to whether it is done.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["basics.thermometer"],
                lesson: SkillLesson(
                    summary: "Doneness is a temperature question. Time is a forecast and colour "
                        + "is a guess, and the thermometer is the only one of the three that "
                        + "measures anything.",
                    steps: [
                        "Know two numbers before you start: the safety floor, and the quality "
                            + "target you personally want.",
                        "Probe the thickest part, clear of bone and pan.",
                        "Pull it below your target, because it keeps climbing after it "
                            + "comes off.",
                    ],
                    watchFors: [
                        "Judging pork or chicken by how pink it looks.",
                        "Pulling a large roast exactly at the number you want to eat it at.",
                        "Checking one spot on something an awkward shape.",
                    ],
                    whyItMatters: "Consumer safety floors are 145F with a three minute rest for "
                        + "whole beef, pork, lamb and veal, 160F for anything minced, and 165F "
                        + "for poultry. What you want past that is your business."
                ),
                visualCheck: .meatTemperature,
                column: .right
            ),
            Skill(
                id: "meat.sear",
                categoryID: "meat",
                title: "Sear Meat",
                shortName: "Searing",
                glyph: "flame",
                shortDescription: "Build a crust without cooking the middle past where you want it.",
                difficulty: .intermediate,
                estimatedMinutes: 4,
                prerequisiteIDs: ["meat.dry", "heat.sear"],
                lesson: SkillLesson(
                    summary: "A sear is browning, and browning is flavour. It does not seal "
                        + "anything in. Your job is to build a crust while keeping an eye on a "
                        + "centre that is cooking at the same time.",
                    steps: [
                        "Start dry, seasoned, and in a pan that is properly hot.",
                        "Let it build real colour before you move it, or flip often if "
                            + "you prefer.",
                        "Track the centre separately with a thermometer.",
                    ],
                    watchFors: [
                        "Black scorched patches while the rest is still pale.",
                        "A grey wet surface, which means the pan or the meat was too cool.",
                        "Chasing more crust after the centre has already arrived.",
                    ],
                    whyItMatters: "Searing does not seal in juices. That idea has been tested "
                        + "and it is not true. What it does is build the browned flavour that "
                        + "makes cooked meat taste of anything at all."
                ),
                visualCheck: .meatSear,
                column: .center
            ),
            Skill(
                id: "meat.baste",
                categoryID: "meat",
                title: "Baste a Steak",
                shortName: "Basting",
                glyph: "flame",
                shortDescription: "Foaming butter, spooned over, without burning it or the steak.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["meat.sear", "heat.butter"],
                lesson: SkillLesson(
                    summary: "Basting cooks the top of the steak with hot fat while adding the "
                        + "flavour of browned butter and whatever aromatics are in the pan.",
                    steps: [
                        "Get your sear established first.",
                        "Lower the heat and add butter, and aromatics if you want them.",
                        "Tilt the pan so the butter pools, handle away from you, and spoon it "
                            + "over the steak.",
                        "Keep checking the centre while you do it.",
                    ],
                    watchFors: [
                        "Butter solids going black rather than brown.",
                        "Tilting the pan toward yourself.",
                        "Basting so long that the steak goes past where you wanted it.",
                    ],
                    whyItMatters: "Basting is a trade. Every extra spoonful adds flavour and "
                        + "also adds heat to a steak that is already cooking."
                ),
                visualCheck: .meatBaste,
                column: .left
            ),
            Skill(
                id: "meat.rest",
                categoryID: "meat",
                title: "Rest Meat",
                shortName: "Resting",
                glyph: "flame",
                shortDescription: "Long enough for a roast, and not so long the crust goes soft.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["meat.temperature"],
                lesson: SkillLesson(
                    summary: "Meat keeps cooking after it comes off the heat, and a large piece "
                        + "keeps cooking for a long time. Resting is how you let that finish "
                        + "before you cut into it.",
                    steps: [
                        "Take it off below your target temperature.",
                        "Give a large roast real time. A small cut may need only the walk to "
                            + "the table.",
                        "Leave a crisp surface uncovered, or tent it loosely.",
                    ],
                    watchFors: [
                        "Slicing a big roast the moment it comes out.",
                        "Wrapping something crisp tightly in foil.",
                        "Applying a fixed rule like ten minutes to everything regardless "
                            + "of size.",
                    ],
                    whyItMatters: "Carryover is a few degrees on a steak and a lot more on a "
                        + "roast. The old line about juices being reabsorbed is a simplification "
                        + "worth ignoring. What is really happening is temperature and pressure "
                        + "evening out."
                ),
                column: .right
            ),
            Skill(
                id: "meat.butterfly",
                categoryID: "meat",
                title: "Butterfly a Chicken Breast",
                shortName: "Butterflying",
                glyph: "flame",
                shortDescription: "Open it into an even sheet, with your hand out of the way.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["knife.grip", "knife.claw"],
                lesson: SkillLesson(
                    summary: "A chicken breast is thick at one end and thin at the other, which "
                        + "means it is always overcooked somewhere. Butterflying makes it "
                        + "one thickness.",
                    steps: [
                        "Lay it flat and hold the top with your palm, high and well clear of "
                            + "the blade.",
                        "Slice horizontally into the thick side, keeping the knife level.",
                        "Stop about a centimetre before the far edge so it stays hinged.",
                        "Open it out like a book and even up any thick spots.",
                    ],
                    watchFors: [
                        "The knife travelling toward the hand holding the meat.",
                        "Sawing blindly instead of watching the blade.",
                        "Going straight through and ending up with two pieces.",
                    ],
                    whyItMatters: "This is the one knife skill where the blade moves sideways "
                        + "toward your other hand. Keep that hand high and flat on top, never in "
                        + "front, and the cut is easy."
                ),
                visualCheck: .meatButterfly,
                column: .left
            ),
            Skill(
                id: "meat.challenge-steak",
                categoryID: "meat",
                title: "Cook a Great Steak",
                shortName: "Great steak",
                glyph: "flame",
                shortDescription: "Crust, centre and rest, all landing together.",
                difficulty: .advanced,
                estimatedMinutes: 15,
                prerequisiteIDs: ["meat.sear", "meat.baste", "meat.rest"],
                lesson: SkillLesson(
                    summary: "Everything in this category at once. Season it deliberately, "
                        + "build a crust, land the centre where you said you wanted it, and "
                        + "rest it properly.",
                    steps: [
                        "Say what centre temperature you are aiming for before you start.",
                        "Dry it, season it, and choose a searing approach that suits "
                            + "its thickness.",
                        "Build a deep brown crust without bitter black patches.",
                        "Pull it early enough that carryover brings it to your number, then "
                            + "rest it and slice across the grain.",
                    ],
                    watchFors: [
                        "Guessing the centre instead of measuring it.",
                        "Chasing more crust once the middle is already there.",
                        "Cutting into it straight off the pan.",
                    ],
                    whyItMatters: "A great steak is four decisions that each have to land. Get "
                        + "them individually right and the steak takes care of itself."
                ),
                visualCheck: .meatSteakChallenge,
                isChallenge: true,
                column: .center
            ),
        ]
    )
}
