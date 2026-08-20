import Foundation

/// Regions that are mapped but not yet written.
///
/// These exist on purpose. A map that stopped after three categories would say
/// "this is all there is"; a map that keeps going says "there is a whole world
/// of this and you have seen the start of it". That curiosity is the point of
/// the whole feature, and it is why these nodes carry real titles rather than
/// grey placeholders: "Understand an Emulsion" makes someone want to tap it
/// long before we have written it.
///
/// Every skill here has `lesson: nil`, which is the single mechanism the rest
/// of the app keys off. Authoring one later means filling in the optional. No
/// schema change, no UI change, no migration.
extension SkillCatalog {

    /// Small helper so a mapped region stays readable at a glance.
    private static func upcoming(
        _ id: String,
        _ category: String,
        _ title: String,
        _ column: SkillColumn = .center,
        difficulty: SkillDifficulty = .beginner,
        prerequisites: [String] = [],
        isChallenge: Bool = false,
        glyph: String = "circle.dashed"
    ) -> Skill {
        Skill(
            id: id,
            categoryID: category,
            title: title,
            shortName: title,
            glyph: glyph,
            shortDescription: "Coming soon.",
            difficulty: difficulty,
            prerequisiteIDs: prerequisites,
            lesson: nil,
            isChallenge: isChallenge,
            column: column
        )
    }

    static let eggs = SkillCategory(
        id: "eggs",
        name: "Eggs",
        blurb: "The cheapest way to practise heat control there is.",
        theme: .amber,
        skills: [
            upcoming("eggs.crack", "eggs", "Crack an Egg", .center, glyph: "oval.fill"),
            upcoming("eggs.scrambled", "eggs", "Scrambled Eggs", .left, glyph: "oval.fill"),
            upcoming("eggs.fried", "eggs", "Fried Egg", .right, glyph: "oval.fill"),
            upcoming("eggs.soft-boiled", "eggs", "Soft-Boiled Egg", .left, glyph: "oval.fill"),
            upcoming("eggs.hard-boiled", "eggs", "Hard-Boiled Egg", .right, glyph: "oval.fill"),
            upcoming("eggs.poached", "eggs", "Poached Egg", .center, difficulty: .intermediate, glyph: "oval.fill"),
            upcoming("eggs.omelette", "eggs", "Omelette", .left, difficulty: .intermediate, glyph: "oval.fill"),
            upcoming("eggs.challenge", "eggs", "Egg Mastery", .center,
                     difficulty: .advanced,
                     prerequisites: ["eggs.scrambled", "eggs.poached", "eggs.omelette"],
                     isChallenge: true, glyph: "oval.fill"),
        ]
    )

    static let meat = SkillCategory(
        id: "meat",
        name: "Meat",
        blurb: "Season it, sear it, know its temperature, let it rest.",
        theme: .peach,
        skills: [
            upcoming("meat.season", "meat", "Season Meat", .center, glyph: "flame"),
            upcoming("meat.dry", "meat", "Dry Meat Before Searing", .left, glyph: "flame"),
            upcoming("meat.temperature", "meat", "Understand Internal Temperature", .right, difficulty: .intermediate, glyph: "flame"),
            upcoming("meat.sear", "meat", "Sear Meat", .center, difficulty: .intermediate, glyph: "flame"),
            upcoming("meat.baste", "meat", "Baste a Steak", .left, difficulty: .intermediate, glyph: "flame"),
            upcoming("meat.rest", "meat", "Rest Meat", .right, glyph: "flame"),
            upcoming("meat.butterfly", "meat", "Butterfly a Chicken Breast", .left, difficulty: .advanced, glyph: "flame"),
            upcoming("meat.challenge-steak", "meat", "Cook a Great Steak", .center,
                     difficulty: .advanced,
                     prerequisites: ["meat.sear", "meat.temperature", "meat.baste", "meat.rest"],
                     isChallenge: true, glyph: "flame"),
        ]
    )

    static let sauces = SkillCategory(
        id: "sauces",
        name: "Sauces",
        blurb: "Where the brown bits in the pan turn into the best part of dinner.",
        theme: .plum,
        skills: [
            upcoming("sauces.fond", "sauces", "What Is Fond?", .center, glyph: "drop.fill"),
            upcoming("sauces.pan-sauce", "sauces", "Make a Pan Sauce", .left, difficulty: .intermediate, glyph: "drop.fill"),
            upcoming("sauces.vinaigrette", "sauces", "Make a Vinaigrette", .right, glyph: "drop.fill"),
            upcoming("sauces.emulsion", "sauces", "Understand an Emulsion", .center, difficulty: .advanced, glyph: "drop.fill"),
            upcoming("sauces.thicken", "sauces", "Thicken a Sauce", .left, difficulty: .intermediate, glyph: "drop.fill"),
            upcoming("sauces.balance", "sauces", "Balance a Sauce", .right, difficulty: .intermediate, glyph: "drop.fill"),
        ]
    )

    static let flavor = SkillCategory(
        id: "flavor",
        name: "Flavor & Seasoning",
        blurb: "Salt, fat, acid and heat, and what to reach for when something tastes flat.",
        theme: .ember,
        skills: [
            upcoming("flavor.salt", "flavor", "Salt Properly", .center, glyph: "sparkles"),
            upcoming("flavor.acid", "flavor", "Understand Acid", .left, glyph: "sparkles"),
            upcoming("flavor.fat", "flavor", "Understand Fat", .right, glyph: "sparkles"),
            upcoming("flavor.umami", "flavor", "Understand Umami", .center, difficulty: .intermediate, glyph: "sparkles"),
            upcoming("flavor.fix-bland", "flavor", "Fix Bland Food", .left, difficulty: .intermediate, glyph: "sparkles"),
            upcoming("flavor.fix-salty", "flavor", "Fix Oversalted Food", .right, difficulty: .intermediate, glyph: "sparkles"),
            upcoming("flavor.finish-acid", "flavor", "Finish With Acid", .center, difficulty: .intermediate, glyph: "sparkles"),
        ]
    )

    static let intuition = SkillCategory(
        id: "intuition",
        name: "Cooking Intuition",
        blurb: "The difference between following a recipe and actually cooking.",
        theme: .sky,
        skills: [
            upcoming("intuition.why-bland", "intuition", "Know Why Food Tastes Bland", .center, difficulty: .intermediate, glyph: "lightbulb"),
            upcoming("intuition.substitute", "intuition", "Make Substitutions", .left, difficulty: .intermediate, glyph: "lightbulb"),
            upcoming("intuition.recover", "intuition", "Recover From Overcooking", .right, difficulty: .advanced, glyph: "lightbulb"),
            upcoming("intuition.timing", "intuition", "Time Multiple Components", .center, difficulty: .advanced, glyph: "lightbulb"),
            upcoming("intuition.scale", "intuition", "Adjust a Recipe for More People", .left, difficulty: .intermediate, glyph: "lightbulb"),
            upcoming("intuition.no-recipe", "intuition", "Cook Without a Recipe", .center,
                     difficulty: .advanced,
                     prerequisites: ["intuition.why-bland", "intuition.substitute", "intuition.timing"],
                     isChallenge: true, glyph: "lightbulb"),
        ]
    )
}
