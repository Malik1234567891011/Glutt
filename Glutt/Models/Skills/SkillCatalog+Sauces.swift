import Foundation

/// Sauces, written from `docs/skills-instructor-deliverable.md`.
///
/// The everyday sauces: what fond is, the pan sauce it becomes, a vinaigrette,
/// the emulsion underneath both of those, thickening, and balancing. The
/// classical curriculum sits in its own category after this one and builds on
/// exactly these mechanisms.
///
/// **Balance a Sauce is deliberately not watchable.** It is the one skill here
/// that is entirely a matter of taste, and the instructor was direct that
/// giving it a visual rubric would produce an app with confident opinions about
/// flavour. Chef can watch the discipline, tasting before adjusting and
/// changing one thing at a time, but she cannot tell you whether it worked. It
/// stays a reading lesson until she can coach it through conversation.
extension SkillCatalog {

    static let sauces = SkillCategory(
        id: "sauces",
        name: "Sauces",
        blurb: "Where the brown bits in the pan turn into the best part of dinner.",
        theme: .plum,
        skills: [
            Skill(
                id: "sauces.fond",
                categoryID: "sauces",
                title: "What Is Fond?",
                shortName: "Fond",
                glyph: "drop.fill",
                shortDescription: "Learn to tell the good brown bits from the burnt ones.",
                estimatedMinutes: 2,
                prerequisiteIDs: ["heat.sear"],
                lesson: SkillLesson(
                    summary: "Fond is the browned material stuck to the pan after you cook "
                        + "something in it. It is concentrated flavour, and it is the starting "
                        + "point for most quick sauces.",
                    steps: [
                        "After browning, look at what is stuck to the base.",
                        "Golden through to deep brown is fond and it is what you want.",
                        "Black and carbonised is burnt, and it will make anything you build "
                            + "on it bitter.",
                    ],
                    watchFors: [
                        "Washing a good pan out before you have used what is in it.",
                        "Treating black residue as fond.",
                        "Expecting much fond from non-stick, which does not develop it.",
                    ],
                    whyItMatters: "Everything that made your kitchen smell good while you were "
                        + "searing is stuck to that pan. Fond is how you get it into the food "
                        + "instead of into the washing up."
                ),
                visualCheck: .saucesFond,
                column: .center
            ),
            Skill(
                id: "sauces.pan-sauce",
                categoryID: "sauces",
                title: "Make a Pan Sauce",
                shortName: "Pan sauce",
                glyph: "drop.fill",
                shortDescription: "Fond, liquid, reduction, and something to finish it.",
                difficulty: .intermediate,
                estimatedMinutes: 5,
                prerequisiteIDs: ["sauces.fond", "heat.deglaze", "heat.reduce"],
                lesson: SkillLesson(
                    summary: "The fastest good sauce there is. Four moves, all in the pan you "
                        + "already used, in about five minutes.",
                    steps: [
                        "Pour off excess fat and keep the browned bits.",
                        "Add your liquid and scrape everything loose while it bubbles.",
                        "Reduce it until it has real body.",
                        "Take it off the heat and finish it, with butter or cream if you want.",
                    ],
                    watchFors: [
                        "Building on burnt fond.",
                        "Stopping while it is still watery.",
                        "Boiling it hard after the butter goes in, which splits it.",
                    ],
                    whyItMatters: "A pan sauce teaches fond, deglazing, reduction and "
                        + "emulsification in one go, using something you were going to wash up "
                        + "anyway."
                ),
                visualCheck: .saucesPanSauce,
                column: .left
            ),
            Skill(
                id: "sauces.vinaigrette",
                categoryID: "sauces",
                title: "Make a Vinaigrette",
                shortName: "Vinaigrette",
                glyph: "drop.fill",
                shortDescription: "Fat and acid, held together long enough to dress something.",
                estimatedMinutes: 3,
                lesson: SkillLesson(
                    summary: "The simplest emulsion, and the fastest way to understand why oil "
                        + "and vinegar behave the way they do.",
                    steps: [
                        "Put your acid, salt and any mustard in a bowl.",
                        "Whisk while you add the oil in a thin steady stream.",
                        "Taste it on a leaf rather than off the spoon, and adjust.",
                    ],
                    watchFors: [
                        "Dumping the oil in all at once when you wanted it stable.",
                        "Following a ratio past the point where your mouth disagrees.",
                        "Dressing greens so heavily they collapse.",
                    ],
                    whyItMatters: "Three parts oil to one part acid is a useful place to start "
                        + "and it is not a law. Vinegars vary enormously in strength, and the "
                        + "only real test is tasting it on the thing you are dressing."
                ),
                visualCheck: .saucesVinaigrette,
                column: .right
            ),
            Skill(
                id: "sauces.emulsion",
                categoryID: "sauces",
                title: "Understand an Emulsion",
                shortName: "Emulsion",
                glyph: "drop.fill",
                shortDescription: "Why two things that separate can be made not to.",
                difficulty: .advanced,
                estimatedMinutes: 4,
                prerequisiteIDs: ["sauces.vinaigrette"],
                lesson: SkillLesson(
                    summary: "An emulsion is fat broken into droplets small enough to stay "
                        + "suspended in water, or the other way round. Once you can see one, "
                        + "you can see it in half the sauces you make.",
                    steps: [
                        "Identify which part is fat and which part is water.",
                        "Break the fat into tiny droplets by whisking or blending hard.",
                        "Add an emulsifier, like mustard or egg yolk, if you want it to last.",
                        "Learn what a broken one looks like: greasy, separated, grainy.",
                    ],
                    watchFors: [
                        "Adding fat faster than the mixture can take it.",
                        "Overheating anything held together by egg.",
                        "Assuming thick means stable, which it does not.",
                    ],
                    whyItMatters: "Vinaigrette, mayonnaise, hollandaise, beurre blanc and most "
                        + "buttered pan sauces are all the same idea at different temperatures. "
                        + "Learn it once."
                ),
                visualCheck: .saucesEmulsion,
                column: .center
            ),
            Skill(
                id: "sauces.thicken",
                categoryID: "sauces",
                title: "Thicken a Sauce",
                shortName: "Thickening",
                glyph: "drop.fill",
                shortDescription: "Pick a mechanism instead of adding flour and hoping.",
                difficulty: .intermediate,
                estimatedMinutes: 4,
                prerequisiteIDs: ["heat.reduce"],
                lesson: SkillLesson(
                    summary: "There are several ways to give a sauce body and they are not "
                        + "interchangeable. Choosing the right one is most of the skill.",
                    steps: [
                        "Decide the mechanism: reduce it, use a roux, use a starch slurry, "
                            + "puree something into it, or emulsify it.",
                        "Apply it properly. A starch needs to come back to a simmer to work.",
                        "Judge the finished body by how it coats a spoon, not by how it looks "
                            + "in the pan.",
                    ],
                    watchFors: [
                        "Lumps from flour going in dry.",
                        "Cornstarch added without being slaked in cold liquid first.",
                        "Judging thickness while it is still hot, when it will set further.",
                    ],
                    whyItMatters: "Thickness should be a decision rather than an accident. Every "
                        + "mechanism tastes different, and the wrong one makes a sauce cloudy, "
                        + "pasty or dull."
                ),
                visualCheck: .saucesThicken,
                column: .left
            ),
            Skill(
                id: "sauces.balance",
                categoryID: "sauces",
                title: "Balance a Sauce",
                shortName: "Balancing",
                glyph: "drop.fill",
                shortDescription: "Work out what it is missing before you add anything.",
                difficulty: .intermediate,
                estimatedMinutes: 4,
                prerequisiteIDs: ["basics.taste-as-you-go", "sauces.thicken"],
                lesson: SkillLesson(
                    summary: "Most sauces that are not working are not short of salt. Diagnosing "
                        + "what is actually wrong, before reaching for anything, is the "
                        + "whole skill.",
                    steps: [
                        "Taste it, from a clean spoon, cooled enough to taste properly.",
                        "Name the problem: flat, too rich, too sharp, too salty, or bitter.",
                        "Make ONE small adjustment.",
                        "Taste again, ideally with the food it is going on.",
                    ],
                    watchFors: [
                        "Reaching for salt reflexively.",
                        "Changing three things at once, so you never learn which one worked.",
                        "Judging a sauce on its own when it is going onto something bland.",
                    ],
                    whyItMatters: "A good sauce is a relationship rather than an intensity. It "
                        + "has to be right against the thing it is served with, which is why "
                        + "tasting it alone will mislead you."
                ),
                column: .right
            ),
        ]
    )
}
