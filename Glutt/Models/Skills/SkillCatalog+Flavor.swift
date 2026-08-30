import Foundation

/// Flavor and Seasoning, written from `docs/skills-instructor-deliverable.md`.
///
/// **Not one skill in this category has a visual rubric, and that is the
/// correct answer rather than an omission.** The instructor listed almost all
/// of them under "coachable but not visually certifiable", and the reasoning is
/// hard to argue with: a camera cannot taste. A perfectly seasoned sauce and a
/// bland one look identical, so a visual pass here would be Chef inventing an
/// opinion about flavour and presenting it as an observation.
///
/// What Chef can do with these is teach them, and later coach them through
/// conversation: she can hear a cook say "it tastes flat", offer the diagnosis
/// tree, and watch what they do about it. That is a genuinely different mode
/// from watching a grip, and it is not built yet. Until it is, these are
/// reading lessons, which is honest.
///
/// The one piece of received wisdom deliberately removed: **a raw potato does
/// not draw salt out of a dish.** The lesson teaches dilution and rebalancing
/// instead.
extension SkillCatalog {

    static let flavor = SkillCategory(
        id: "flavor",
        name: "Flavor & Seasoning",
        blurb: "The difference between food that is cooked and food that tastes good.",
        theme: .amber,
        skills: [
            Skill(
                id: "flavor.salt",
                categoryID: "flavor",
                title: "Salt Properly",
                shortName: "Salt",
                glyph: "sparkles",
                shortDescription: "Not more salt. Salt at the right moment, spread evenly.",
                estimatedMinutes: 3,
                prerequisiteIDs: ["basics.taste-as-you-go"],
                lesson: SkillLesson(
                    summary: "Salt does not just make food salty. It makes other flavours "
                        + "easier to taste, which is why an underseasoned dish reads as boring "
                        + "rather than as needing salt.",
                    steps: [
                        "Use one salt and get used to how much of it a pinch is.",
                        "Spread it evenly rather than in one spot.",
                        "Season components as you go, not everything at the end.",
                        "Taste before the last adjustment, always.",
                    ],
                    watchFors: [
                        "Salting a sauce fully before reducing it, which concentrates it.",
                        "Adding salt without tasting first.",
                        "Assuming flat means unsalted, when it often means no acid.",
                    ],
                    whyItMatters: "Different salts have very different volumes for the same "
                        + "weight, so a teaspoon of one is not a teaspoon of another. Pick one "
                        + "and learn your hand."
                ),
                column: .center
            ),
            Skill(
                id: "flavor.acid",
                categoryID: "flavor",
                title: "Understand Acid",
                shortName: "Acid",
                glyph: "sparkles",
                shortDescription: "The fix for food that is rich, heavy, or just dull.",
                estimatedMinutes: 3,
                prerequisiteIDs: ["flavor.salt"],
                lesson: SkillLesson(
                    summary: "Acid makes flavours feel clearer and cuts through richness. It is "
                        + "the second thing to reach for when something is not working, and it "
                        + "is the one most home cooks never reach for at all.",
                    steps: [
                        "Taste, and ask whether it is heavy or dull rather than unsalted.",
                        "Add a small amount of an acid that suits the dish.",
                        "Stir it through and taste again with the whole dish.",
                    ],
                    watchFors: [
                        "A big unmeasured squeeze, which is very hard to walk back.",
                        "Using acid to fix something that is actually a salt problem.",
                        "Boiling fresh citrus, which loses the brightness you added it for.",
                    ],
                    whyItMatters: "Lemon, vinegar, wine, tomatoes, yoghurt and fermented things "
                        + "are all acid. Which one you choose changes the dish as much as how "
                        + "much you add."
                ),
                column: .left
            ),
            Skill(
                id: "flavor.fat",
                categoryID: "flavor",
                title: "Understand Fat",
                shortName: "Fat",
                glyph: "sparkles",
                shortDescription: "A cooking medium, a texture, and how aroma reaches you.",
                estimatedMinutes: 3,
                prerequisiteIDs: ["flavor.acid"],
                lesson: SkillLesson(
                    summary: "Fat carries flavour, conducts heat, and gives food the texture "
                        + "that makes it feel satisfying. It is doing several jobs at once and "
                        + "the amount you need depends which job you are asking for.",
                    steps: [
                        "Work out which job the fat is doing in this dish.",
                        "Choose one that suits the heat and the flavour you want.",
                        "Use enough for the job rather than as little as possible.",
                        "Balance the richness with acid or salt at the end.",
                    ],
                    watchFors: [
                        "Using a delicate low smoke point oil for a hard sear.",
                        "Too little fat for the food to make proper contact with the pan.",
                        "A greasy split sauce from adding fat to something too hot.",
                    ],
                    whyItMatters: "Many aroma compounds dissolve in fat rather than in water, "
                        + "so a fat-free version of a dish is not the same dish with less fat. "
                        + "It is a dish that tastes of less."
                ),
                column: .right
            ),
            Skill(
                id: "flavor.umami",
                categoryID: "flavor",
                title: "Understand Umami",
                shortName: "Umami",
                glyph: "sparkles",
                shortDescription: "Savouriness, and how to build it rather than buy it.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["flavor.fat"],
                lesson: SkillLesson(
                    summary: "Umami is the savoury depth that makes food taste like it has been "
                        + "cooked for a long time. You build it with technique and ingredients, "
                        + "not with a magic powder.",
                    steps: [
                        "Find the savoury base you already have.",
                        "Deepen it: brown something, add stock, or use an aged or "
                            + "fermented ingredient.",
                        "Rebalance the salt and acid afterwards, because you have changed both.",
                    ],
                    watchFors: [
                        "Treating umami as an ingredient to add rather than a quality "
                            + "to develop.",
                        "Adding several savoury things at once and losing track.",
                        "Forgetting that most umami ingredients are also salty.",
                    ],
                    whyItMatters: "Browning, stock, mushrooms, tomato paste, anchovy, soy, miso "
                        + "and parmesan are all doing the same job. It is one part of balance "
                        + "rather than a separate trick."
                ),
                column: .center
            ),
            Skill(
                id: "flavor.fix-bland",
                categoryID: "flavor",
                title: "Fix Bland Food",
                shortName: "Fix bland",
                glyph: "sparkles",
                shortDescription: "Diagnose it before you add anything.",
                difficulty: .intermediate,
                estimatedMinutes: 4,
                prerequisiteIDs: ["flavor.umami"],
                lesson: SkillLesson(
                    summary: "Bland is a symptom rather than a diagnosis. Reaching straight for "
                        + "salt fixes it about half the time and makes it worse the other half.",
                    steps: [
                        "Taste, and decide which of these it is.",
                        "Bland and not salty: add a little salt.",
                        "Salty enough but dull or heavy: add acid, or something aromatic.",
                        "Watery: concentrate it rather than seasoning it.",
                        "Thin and lacking depth: add browning, stock, or a savoury ingredient.",
                    ],
                    watchFors: [
                        "Adding three things at once so you never learn which one worked.",
                        "More salt on something that is already salty and still flat.",
                        "Seasoning a sauce that is about to reduce by half.",
                    ],
                    whyItMatters: "The diagnosis is the skill. Once you can name what is "
                        + "missing, the fix is usually obvious and small."
                ),
                column: .left
            ),
            Skill(
                id: "flavor.fix-salty",
                categoryID: "flavor",
                title: "Fix Oversalted Food",
                shortName: "Fix salty",
                glyph: "sparkles",
                shortDescription: "Dilute it. The potato trick does not work.",
                difficulty: .intermediate,
                estimatedMinutes: 3,
                prerequisiteIDs: ["flavor.fix-bland"],
                lesson: SkillLesson(
                    summary: "There is only one thing that actually reduces saltiness, and that "
                        + "is having less salt per mouthful. Everything else is masking.",
                    steps: [
                        "Stop reducing it immediately, because that is making it worse.",
                        "Add unsalted bulk or liquid if the dish can take it.",
                        "Or split the batch and make more unsalted base to combine with it.",
                        "Only then rebalance with acid, fat or a little sweetness.",
                    ],
                    watchFors: [
                        "Putting a raw potato in. It absorbs salty liquid, not salt, so it "
                            + "does not change the concentration.",
                        "Carrying on reducing while you think about it.",
                        "Burying it in sugar.",
                    ],
                    whyItMatters: "Salt does not evaporate. Reducing a salty sauce removes water "
                        + "and leaves every grain of salt exactly where it was."
                ),
                column: .right
            ),
            Skill(
                id: "flavor.finish-acid",
                categoryID: "flavor",
                title: "Finish With Acid",
                shortName: "Finishing",
                glyph: "sparkles",
                shortDescription: "The last small thing that makes a dish sound sharper.",
                difficulty: .intermediate,
                estimatedMinutes: 2,
                prerequisiteIDs: ["flavor.fix-salty"],
                lesson: SkillLesson(
                    summary: "A small amount of fresh acid right at the end lifts a dish that "
                        + "has been cooking for a while. It is the most common last step in "
                        + "professional kitchens and the rarest in home ones.",
                    steps: [
                        "Taste the finished dish.",
                        "Add a small amount of something fresh and acidic.",
                        "Stir through and taste again, with the food rather than alone.",
                    ],
                    watchFors: [
                        "Doing it to every dish reflexively. Plenty do not need it.",
                        "A huge squeeze, which turns lift into sourness.",
                        "Adding it early and then cooking the freshness away.",
                    ],
                    whyItMatters: "Long cooking rounds everything off. A late hit of acid puts "
                        + "an edge back on without changing what the dish is."
                ),
                column: .center
            ),
        ]
    )
}
