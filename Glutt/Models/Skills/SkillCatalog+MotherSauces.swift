import Foundation

/// The Mother Sauces, written from `docs/skills-instructor-deliverable.md`.
///
/// **Mechanisms first, then the classical five, then the two modern ones.**
/// That order was the instructor's strongest structural recommendation and it
/// is the whole shape of this category: hollandaise is the hardest emulsion in
/// classical cooking and putting it fourth in a beginner's list, because
/// Escoffier listed it fourth, is how people conclude they cannot cook.
///
/// Roux opens the category because it is the one mechanism nothing earlier
/// teaches. Reduction, fond and deglazing, and emulsion are prerequisites
/// reaching back into Heat and Sauces rather than being taught twice: a cook
/// arriving here has already reduced a pan sauce and already broken and rebuilt
/// a vinaigrette, and those are the same skills wearing different names.
///
/// On the canon itself: the classical five are kept, because ICE, Escoffier and
/// Rouxbe all still teach them and they genuinely do expose distinct
/// structures. Espagnole is taught alongside demi-glace rather than as a museum
/// piece. Mayonnaise and beurre blanc are added as modern foundations and are
/// deliberately NOT presented as replacement mothers.
extension SkillCatalog {

    static let motherSauces = SkillCategory(
        id: "mother-sauces",
        name: "Mother Sauces",
        blurb: "The classical five, and the mechanisms underneath all of them.",
        theme: .peach,
        skills: [
            Skill(
                id: "mother.roux",
                categoryID: "mother-sauces",
                title: "Make a Roux",
                shortName: "Roux",
                glyph: "circle.hexagongrid.fill",
                shortDescription: "Equal parts fat and flour, and a colour you choose.",
                estimatedMinutes: 4,
                prerequisiteIDs: ["sauces.thicken"],
                lesson: SkillLesson(
                    summary: "Cooked flour and fat, which thickens a liquid and flavours it at "
                        + "the same time. How long you cook it decides both, and they pull in "
                        + "opposite directions.",
                    steps: [
                        "Melt the fat, then stir in an equal weight of flour.",
                        "Cook it, stirring, until every bit of flour is coated and the raw "
                            + "smell has gone.",
                        "Keep going to the colour you want: white, blond, or brown.",
                        "Take it off before it goes past that, because it moves quickly at "
                            + "the end.",
                    ],
                    watchFors: [
                        "Dry pockets of flour that never met the fat.",
                        "Black specks, which are burnt and mean starting again.",
                        "Expecting a dark roux to thicken as strongly as a pale one.",
                    ],
                    whyItMatters: "Equal parts by WEIGHT, not by volume, because flour is much "
                        + "lighter than butter. And the longer you cook it the more it tastes "
                        + "of itself and the less it thickens, which is the trade at the heart "
                        + "of every brown sauce."
                ),
                visualCheck: .motherRoux,
                column: .center
            ),
            Skill(
                id: "mother.bechamel",
                categoryID: "mother-sauces",
                title: "Béchamel",
                shortName: "Béchamel",
                glyph: "circle.hexagongrid.fill",
                shortDescription: "Pale roux and milk. The cleanest way to learn the mechanism.",
                difficulty: .intermediate,
                estimatedMinutes: 5,
                prerequisiteIDs: ["mother.roux"],
                lesson: SkillLesson(
                    summary: "A white sauce built on a pale roux and milk. It is the simplest "
                        + "of the five and the one that teaches you what smooth feels like.",
                    steps: [
                        "Make a pale roux and keep it from taking colour.",
                        "Add the milk gradually, whisking each addition smooth before the "
                            + "next one.",
                        "Bring it to a gentle simmer so the starch fully thickens.",
                        "Season it, and strain it if you want it perfectly smooth.",
                    ],
                    watchFors: [
                        "Lumps, which come from adding milk faster than you can whisk.",
                        "A scorched layer on the bottom of the pan.",
                        "Stopping before the starch has properly cooked, so it stays thin.",
                    ],
                    whyItMatters: "Ratios vary a lot depending on whether you want a pouring "
                        + "sauce or something stiff enough to bind a croquette. Judge the "
                        + "finished consistency rather than the arithmetic."
                ),
                visualCheck: .motherBechamel,
                column: .left
            ),
            Skill(
                id: "mother.veloute",
                categoryID: "mother-sauces",
                title: "Velouté",
                shortName: "Velouté",
                glyph: "circle.hexagongrid.fill",
                shortDescription: "The same mechanism, with stock instead of milk.",
                difficulty: .intermediate,
                estimatedMinutes: 5,
                prerequisiteIDs: ["mother.bechamel"],
                lesson: SkillLesson(
                    summary: "Blond roux and a light stock. Mechanically it is béchamel, but "
                        + "the stock is exposed rather than hidden, so the quality of it shows.",
                    steps: [
                        "Cook the roux to a light blond rather than keeping it white.",
                        "Add the stock gradually, whisking smooth as you go.",
                        "Simmer until it is velvety and lightly coating.",
                        "Season it if it is going to the table as it is.",
                    ],
                    watchFors: [
                        "A roux taken too dark for a sauce meant to stay pale.",
                        "Stopping while it is still watery.",
                        "A stock that is not good enough to be tasted on its own.",
                    ],
                    whyItMatters: "Milk hides a lot. Stock hides nothing, which is why velouté "
                        + "is the sauce that teaches you whether your stock is any good."
                ),
                visualCheck: .motherVeloute,
                column: .right
            ),
            Skill(
                id: "mother.espagnole",
                categoryID: "mother-sauces",
                title: "Espagnole and Demi-Glace",
                shortName: "Espagnole",
                glyph: "circle.hexagongrid.fill",
                shortDescription: "The brown sauce family, and the thing it becomes.",
                difficulty: .advanced,
                estimatedMinutes: 8,
                prerequisiteIDs: ["mother.veloute", "heat.reduce"],
                lesson: SkillLesson(
                    summary: "Brown stock, browned aromatics, a brown roux and tomato, reduced "
                        + "and strained. Reduce it further with more stock and it becomes "
                        + "demi-glace, which is what most kitchens actually keep.",
                    steps: [
                        "Brown your aromatics properly, without letting them burn.",
                        "Build a brown roux, or work from the browned base directly.",
                        "Add the tomato element and the brown stock.",
                        "Simmer, skimming as you go, then strain it.",
                        "Reduce it with more stock for demi-glace.",
                    ],
                    watchFors: [
                        "A burnt base, which no amount of reduction will rescue.",
                        "A greasy sauce, from not skimming.",
                        "Tomato taking over, which makes it taste red rather than brown.",
                    ],
                    whyItMatters: "This is the long one, and it teaches something the quick "
                        + "sauces cannot: that a great brown sauce is mostly a great stock, "
                        + "concentrated patiently."
                ),
                visualCheck: .motherEspagnole,
                column: .left
            ),
            Skill(
                id: "mother.tomate",
                categoryID: "mother-sauces",
                title: "Sauce Tomate",
                shortName: "Tomate",
                glyph: "circle.hexagongrid.fill",
                shortDescription: "The classical French one, which is not the Italian one.",
                difficulty: .intermediate,
                estimatedMinutes: 6,
                prerequisiteIDs: ["mother.roux"],
                lesson: SkillLesson(
                    summary: "The classical version is built on aromatics and often stock, and "
                        + "sometimes a roux. It is a different sauce from a clean Italian tomato "
                        + "sauce, and neither is a wrong version of the other.",
                    steps: [
                        "Sweat or brown your aromatics as the recipe intends.",
                        "Add the tomato and your liquid.",
                        "Simmer and reduce until the flavour is concentrated.",
                        "Pass it or finish it according to the style you are making.",
                    ],
                    watchFors: [
                        "A scorched layer on the bottom, which flavours everything.",
                        "Stopping while it still tastes raw and sharp.",
                        "Reducing it to a paste.",
                    ],
                    whyItMatters: "Classical sauce tomate and modern Italian tomato sauce are "
                        + "cousins rather than the same thing. Knowing which one you are making "
                        + "stops you chasing the wrong result."
                ),
                visualCheck: .motherTomate,
                column: .right
            ),
            Skill(
                id: "mother.mayonnaise",
                categoryID: "mother-sauces",
                title: "Mayonnaise",
                shortName: "Mayonnaise",
                glyph: "circle.hexagongrid.fill",
                shortDescription: "A cold emulsion, with no heat to complicate it.",
                difficulty: .intermediate,
                estimatedMinutes: 5,
                prerequisiteIDs: ["sauces.emulsion"],
                lesson: SkillLesson(
                    summary: "Oil broken into an egg yolk base until it holds. Because there is "
                        + "no heat involved, it is the clearest possible demonstration of how "
                        + "an emulsion works.",
                    steps: [
                        "Start with yolk, a little acid, mustard if you want it, and salt.",
                        "Add the oil drop by drop at first, whisking constantly.",
                        "Once it thickens and holds, the oil can go in faster.",
                        "Loosen it with water or acid if it gets too stiff.",
                    ],
                    watchFors: [
                        "Oil going in too fast at the start, which is how it breaks.",
                        "A greasy separated mess, which means starting again around a "
                            + "fresh base.",
                        "Something so stiff it will not spread.",
                    ],
                    whyItMatters: "It is not a classical mother sauce and it is more useful "
                        + "than most of them. It also makes emulsion mechanics obvious in a way "
                        + "hollandaise cannot, because nothing can curdle."
                ),
                visualCheck: .motherMayonnaise,
                column: .center
            ),
            Skill(
                id: "mother.hollandaise",
                categoryID: "mother-sauces",
                title: "Hollandaise",
                shortName: "Hollandaise",
                glyph: "circle.hexagongrid.fill",
                shortDescription: "A warm emulsion, where heat is the thing that can ruin it.",
                difficulty: .advanced,
                estimatedMinutes: 8,
                prerequisiteIDs: ["mother.mayonnaise"],
                lesson: SkillLesson(
                    summary: "Egg yolk and butter, held together with gentle heat. Everything "
                        + "that can go wrong goes wrong because of temperature, which is why "
                        + "this comes after the cold emulsions rather than before them.",
                    steps: [
                        "Whisk yolks with a little acid over gentle heat until thickened "
                            + "and aerated.",
                        "Take it off the direct heat and add warm butter in a thin stream, "
                            + "whisking.",
                        "Adjust the consistency with a little water or lemon.",
                        "Hold it briefly and warm, or better, make it close to serving.",
                    ],
                    watchFors: [
                        "Grainy bits, which are scrambled yolk and mean starting the base again.",
                        "A thin greasy split, from butter added too fast or too much heat.",
                        "A sauce so thick it is about to break.",
                    ],
                    whyItMatters: "Yolks begin to set around 65C, and hollandaise gets steadily "
                        + "more likely to curdle as it approaches that. Gentle heat is not "
                        + "caution, it is the technique."
                ),
                visualCheck: .motherHollandaise,
                column: .left
            ),
            Skill(
                id: "mother.beurre-blanc",
                categoryID: "mother-sauces",
                title: "Beurre Blanc",
                shortName: "Beurre blanc",
                glyph: "circle.hexagongrid.fill",
                shortDescription: "A butter emulsion, with no egg to hide behind.",
                difficulty: .advanced,
                estimatedMinutes: 6,
                prerequisiteIDs: ["mother.hollandaise", "heat.reduce"],
                lesson: SkillLesson(
                    summary: "Cold butter whisked into a reduced acidic base. There is no egg "
                        + "yolk holding this one together, so temperature control is the "
                        + "only thing keeping it alive.",
                    steps: [
                        "Reduce wine or vinegar with shallot until there is very little left.",
                        "Lower the heat right down.",
                        "Whisk in cold butter a piece at a time, letting each one go before "
                            + "the next.",
                        "Season it, strain it if you like, and keep it warm rather than hot.",
                    ],
                    watchFors: [
                        "Reducing the base completely dry, so there is no water left to "
                            + "emulsify into.",
                        "Letting it boil once the butter is going in.",
                        "Pools of clear butter fat on the surface, which means it has split.",
                    ],
                    whyItMatters: "This is the emulsion with the smallest margin, which makes "
                        + "it the best test of whether you actually understand them."
                ),
                visualCheck: .motherBeurreBlanc,
                isChallenge: true,
                column: .center
            ),
        ]
    )
}
