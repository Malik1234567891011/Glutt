import Foundation

/// Heat & Pan Control: the category that fixes the most food.
///
/// Grey chicken, soggy vegetables, burnt garlic and food welded to the pan are
/// nearly always one problem wearing four costumes: the pan was not hot enough,
/// or it was too full.
extension SkillCatalog {
    static let heatControl = SkillCategory(
        id: "heat",
        name: "Heat & Pan Control",
        blurb: "Most cooking problems are a pan that was too cool or too crowded.",
        theme: .ember,
        skills: [
            Skill(
                id: "heat.stove-levels",
                categoryID: "heat",
                title: "Understand Stove Heat",
                shortName: "Stove heat",
                glyph: "dial.medium",
                shortDescription: "What low, medium and high are actually for.",
                estimatedMinutes: 2,
                lesson: SkillLesson(
                    summary: "Stove numbers mean nothing on their own. What matters is matching the level to the job, and most home cooking happens at medium rather than the extremes.",
                    steps: [
                        "High: boiling water, searing, getting a pan up to temperature.",
                        "Medium high: most searing and sautéing once the pan is hot.",
                        "Medium: onions, garlic, anything you want soft rather than coloured.",
                        "Low: simmering, melting, reducing, holding food warm.",
                    ],
                    watchFors: [
                        "Cooking everything on high because it feels faster. It mostly burns the outside.",
                        "Never changing the dial once the food is in. Heat is something you steer.",
                        "Assuming your stove matches someone else's. Learn yours.",
                    ],
                    whyItMatters: "Heat decides whether food browns, steams or burns. It is the single control with the biggest effect on the result."
                ),
                column: .center
            ),
            Skill(
                id: "heat.preheat",
                categoryID: "heat",
                title: "Preheat a Pan",
                shortName: "Preheat",
                glyph: "flame",
                shortDescription: "Heat the pan before anything goes in it.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["heat.stove-levels"],
                lesson: SkillLesson(
                    summary: "Food added to a cold pan sits in slowly warming metal and leaks moisture before it can brown. Preheating is what makes the difference between searing and stewing.",
                    steps: [
                        "Put the empty dry pan on the heat first.",
                        "Give it two or three minutes on medium high.",
                        "Add oil, and let the oil come up to heat too.",
                        "Then add the food.",
                    ],
                    watchFors: [
                        "Adding oil to a cold pan and heating both together, which is how nonstick coatings suffer.",
                        "Preheating an empty nonstick pan on high, which damages it.",
                        "Rushing it. Two minutes feels long and is not.",
                    ],
                    whyItMatters: "Browning needs the surface hot enough to drive water off instantly. A cool pan lets the water sit, and food in its own water steams."
                ),
                column: .left
            ),
            Skill(
                id: "heat.pan-ready",
                categoryID: "heat",
                title: "Know When Your Pan Is Hot",
                shortName: "Pan ready",
                glyph: "flame.fill",
                shortDescription: "Read the oil, or flick in a drop of water.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["heat.preheat"],
                lesson: SkillLesson(
                    summary: "A hot pan tells you it is ready. Oil goes thin and shimmers and moves like water when you tilt it; a drop of water skitters instead of sitting.",
                    steps: [
                        "Tilt the pan. Hot oil runs thin and fast, cool oil is thick and slow.",
                        "Look for a shimmer across the surface.",
                        "For a dry pan, flick in a drop of water. It should dance, not sit and boil.",
                        "Wisps of smoke mean you have gone slightly far. Pull it off the heat for a moment.",
                    ],
                    watchFors: [
                        "Waiting for smoke as the signal. That is past ready for most oils.",
                        "Testing with food. If it was not ready, you have already wasted the first piece.",
                    ],
                    whyItMatters: "Every searing and sautéing instruction assumes a properly hot pan. Being able to see it is what makes the rest repeatable."
                ),
                column: .right
            ),
            Skill(
                id: "heat.oil",
                categoryID: "heat",
                title: "Add Oil Correctly",
                shortName: "Oil",
                glyph: "drop.fill",
                shortDescription: "Enough to coat, added to a hot pan.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["heat.preheat"],
                lesson: SkillLesson(
                    summary: "Oil is not just non-stick insurance. It is the contact between food and pan, and thin patches are where sticking starts.",
                    steps: [
                        "Add oil once the pan is hot.",
                        "Use enough to coat the base in a thin, unbroken film.",
                        "Swirl to spread it.",
                        "Let it heat for a few seconds before the food goes in.",
                    ],
                    watchFors: [
                        "Too little, leaving dry patches that grab.",
                        "Too much for a sauté, which fries instead.",
                        "Using a delicate oil at high heat. Save the good olive oil for finishing.",
                    ],
                    whyItMatters: "Oil carries heat into the food's surface far better than air does, which is why a lightly oiled pan browns evenly and a dry one browns in patches."
                ),
                column: .left
            ),
            Skill(
                id: "heat.crowding",
                categoryID: "heat",
                title: "Avoid Crowding the Pan",
                shortName: "Crowding",
                glyph: "square.grid.2x2.fill",
                shortDescription: "Cook in batches. A full pan steams.",
                difficulty: .intermediate,
                estimatedMinutes: 2,
                prerequisiteIDs: ["heat.pan-ready"],
                lesson: SkillLesson(
                    summary: "Every piece of food releases water. Too many pieces at once release more water than the pan can drive off, the temperature drops, and everything sits and steams in a grey pool.",
                    steps: [
                        "Leave visible space between pieces.",
                        "Cook in two or three batches rather than one crowded one.",
                        "Let the pan come back up to heat between batches.",
                        "Keep finished batches somewhere warm.",
                    ],
                    watchFors: [
                        "Liquid pooling in the pan. That is the moment browning stopped.",
                        "Mushrooms and onions, which hold far more water than they look like they do.",
                        "Believing batches take longer. Two fast batches usually beat one slow crowd.",
                    ],
                    whyItMatters: "This is the single most common reason home cooking looks grey instead of golden, and it costs nothing to fix."
                ),
                column: .center
            ),
            Skill(
                id: "heat.saute",
                categoryID: "heat",
                title: "Sauté",
                shortName: "Saute",
                glyph: "arrow.triangle.2.circlepath",
                shortDescription: "Keep it moving over fairly high heat.",
                difficulty: .intermediate,
                estimatedMinutes: 2,
                prerequisiteIDs: ["heat.crowding"],
                lesson: SkillLesson(
                    summary: "Sautéing is cooking small pieces quickly in a little fat, keeping them moving so they colour without catching.",
                    steps: [
                        "Get the pan and oil properly hot.",
                        "Add food in a single uncrowded layer.",
                        "Keep it moving with a shake or a spoon.",
                        "Cook until just done, which is usually faster than expected.",
                    ],
                    watchFors: [
                        "Stirring constantly at too low a heat, which softens without colouring.",
                        "Adding garlic at the start. It burns long before onions soften.",
                    ],
                    whyItMatters: "Sauté is the default move for vegetables and small pieces of meat, and the technique behind a large share of weeknight dinners."
                ),
                column: .right
            ),
            Skill(
                id: "heat.sear",
                categoryID: "heat",
                title: "Sear",
                shortName: "Sear",
                glyph: "flame.circle.fill",
                shortDescription: "Put it down, and leave it alone.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["heat.crowding"],
                lesson: SkillLesson(
                    summary: "A sear is a hard, fast browning of a surface. The whole skill is patience: the crust forms while the food sits still, and moving it early interrupts it.",
                    steps: [
                        "Dry the surface of the food thoroughly.",
                        "Get the pan hot and the oil shimmering.",
                        "Lay the food down away from you and do not touch it.",
                        "Wait until it releases from the pan by itself, then turn once.",
                    ],
                    watchFors: [
                        "Poking and lifting to check. Every lift restarts the crust.",
                        "Wet food, which steams and never browns.",
                        "Food that sticks. If it will not release, it is not ready to turn.",
                    ],
                    whyItMatters: "The brown crust is where most of the flavour of roasted and pan cooked food lives, and it also leaves the fond that a pan sauce is built from."
                ),
                column: .left
            ),
            Skill(
                id: "heat.butter",
                categoryID: "heat",
                title: "Cook With Butter",
                shortName: "Butter",
                glyph: "square.fill",
                shortDescription: "Great flavour, low burning point. Manage both.",
                difficulty: .intermediate,
                estimatedMinutes: 2,
                prerequisiteIDs: ["heat.oil"],
                lesson: SkillLesson(
                    summary: "Butter is mostly fat with some milk solids and water. The solids are the flavour and also the thing that burns, which is why butter needs lower heat than oil.",
                    steps: [
                        "Melt butter over medium rather than high.",
                        "Watch it foam, then quieten as the water cooks off.",
                        "Cook while it is golden and smells nutty.",
                        "For higher heat, use butter with a little oil, or add butter at the end.",
                    ],
                    watchFors: [
                        "Butter in a screaming hot pan, which is black in seconds.",
                        "Black flecks and an acrid smell. Start again; it will not come back.",
                        "Salted butter in something already well seasoned.",
                    ],
                    whyItMatters: "Butter added at the right moment makes food taste finished. Added at the wrong one it makes the whole pan bitter."
                ),
                column: .right
            ),
            Skill(
                id: "heat.deglaze",
                categoryID: "heat",
                title: "Deglaze",
                shortName: "Deglaze",
                glyph: "wineglass",
                shortDescription: "Lift the brown stuff off the pan with liquid.",
                difficulty: .intermediate,
                estimatedMinutes: 2,
                prerequisiteIDs: ["heat.sear"],
                lesson: SkillLesson(
                    summary: "The brown bits stuck to the pan after searing are called fond, and they are concentrated flavour. Deglazing dissolves them into liquid instead of leaving them to be scrubbed off.",
                    steps: [
                        "Pour off excess fat, keeping the brown bits.",
                        "Put the pan back on heat and add a splash of liquid: stock, wine, even water.",
                        "Scrape the base with a wooden spoon as it bubbles.",
                        "Let it reduce slightly.",
                    ],
                    watchFors: [
                        "Deglazing a pan whose bits are black rather than brown. That is bitter, not flavour.",
                        "Too much liquid at once, which cools the pan and dilutes everything.",
                        "Forgetting the alcohol needs a moment to cook off.",
                    ],
                    whyItMatters: "It turns the mess in the pan into the best part of the dish, and it is the first half of every pan sauce ever made."
                ),
                column: .center
            ),
            Skill(
                id: "heat.reduce",
                categoryID: "heat",
                title: "Reduce",
                shortName: "Reduce",
                glyph: "arrow.down.right.and.arrow.up.left",
                shortDescription: "Boil liquid away to concentrate what is left.",
                difficulty: .intermediate,
                estimatedMinutes: 2,
                prerequisiteIDs: ["heat.deglaze"],
                lesson: SkillLesson(
                    summary: "Reducing is simply simmering liquid until enough water has left that the flavour is stronger and the texture thicker.",
                    steps: [
                        "Simmer uncovered, since a lid traps the water you are trying to lose.",
                        "Use a wider pan for a faster reduction.",
                        "Watch it thicken and coat the back of a spoon.",
                        "Season at the end, not the start.",
                    ],
                    watchFors: [
                        "Salting early, then finding it too salty once reduced.",
                        "Reducing too far, which goes sticky and over concentrated.",
                        "A lid, which stops it entirely.",
                    ],
                    whyItMatters: "Reduction is how thin liquid becomes sauce without adding anything, and why restaurant sauces taste deeper than a splash of stock."
                ),
                column: .left
            ),
            Skill(
                id: "heat.challenge-pan-sauce",
                categoryID: "heat",
                title: "Sear, Deglaze and Sauce",
                shortName: "Pan sauce",
                glyph: "star.fill",
                shortDescription: "One pan, start to finish: crust, fond, sauce.",
                difficulty: .advanced,
                estimatedMinutes: 8,
                prerequisiteIDs: [
                    "heat.sear",
                    "heat.deglaze",
                    "heat.reduce",
                    "heat.butter",
                ],
                lesson: SkillLesson(
                    summary: "The move that makes a weeknight chicken thigh taste like it came from a kitchen. Everything in this region, run in one continuous sequence.",
                    steps: [
                        "Dry and season the meat, then sear it hard and leave it alone.",
                        "Take the meat out to rest.",
                        "Pour off excess fat, keeping the fond.",
                        "Deglaze with stock or wine and scrape the base clean.",
                        "Reduce until it lightly coats a spoon.",
                        "Take it off the heat and swirl in a knob of cold butter.",
                        "Taste, adjust, and pour over the rested meat.",
                    ],
                    watchFors: [
                        "Adding butter over direct heat, which splits the sauce. Off the heat, swirling.",
                        "Reducing so far there is nothing left to serve.",
                        "Skipping the resting juices. Pour them in.",
                    ],
                    whyItMatters: "This is the moment most people realise cooking is a chain of causes rather than a list of steps. The crust makes the fond, the fond makes the sauce."
                ),
                isChallenge: true,
                column: .center
            ),
        ]
    )
}
