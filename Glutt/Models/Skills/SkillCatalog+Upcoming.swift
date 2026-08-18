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
        isChallenge: Bool = false
    ) -> Skill {
        Skill(
            id: id,
            categoryID: category,
            title: title,
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
            upcoming("eggs.crack", "eggs", "Crack an Egg", .center),
            upcoming("eggs.scrambled", "eggs", "Scrambled Eggs", .left),
            upcoming("eggs.fried", "eggs", "Fried Egg", .right),
            upcoming("eggs.soft-boiled", "eggs", "Soft-Boiled Egg", .left),
            upcoming("eggs.hard-boiled", "eggs", "Hard-Boiled Egg", .right),
            upcoming("eggs.poached", "eggs", "Poached Egg", .center, difficulty: .intermediate),
            upcoming("eggs.omelette", "eggs", "Omelette", .left, difficulty: .intermediate),
            upcoming("eggs.challenge", "eggs", "Egg Mastery", .center,
                     difficulty: .advanced,
                     prerequisites: ["eggs.scrambled", "eggs.poached", "eggs.omelette"],
                     isChallenge: true),
        ]
    )

    static let meat = SkillCategory(
        id: "meat",
        name: "Meat",
        blurb: "Season it, sear it, know its temperature, let it rest.",
        theme: .peach,
        skills: [
            upcoming("meat.season", "meat", "Season Meat", .center),
            upcoming("meat.dry", "meat", "Dry Meat Before Searing", .left),
            upcoming("meat.temperature", "meat", "Understand Internal Temperature", .right, difficulty: .intermediate),
            upcoming("meat.sear", "meat", "Sear Meat", .center, difficulty: .intermediate),
            upcoming("meat.baste", "meat", "Baste a Steak", .left, difficulty: .intermediate),
            upcoming("meat.rest", "meat", "Rest Meat", .right),
            upcoming("meat.butterfly", "meat", "Butterfly a Chicken Breast", .left, difficulty: .advanced),
            upcoming("meat.challenge-steak", "meat", "Cook a Great Steak", .center,
                     difficulty: .advanced,
                     prerequisites: ["meat.sear", "meat.temperature", "meat.baste", "meat.rest"],
                     isChallenge: true),
        ]
    )

    static let sauces = SkillCategory(
        id: "sauces",
        name: "Sauces",
        blurb: "Where the brown bits in the pan turn into the best part of dinner.",
        theme: .sand,
        skills: [
            upcoming("sauces.fond", "sauces", "What Is Fond?", .center),
            upcoming("sauces.pan-sauce", "sauces", "Make a Pan Sauce", .left, difficulty: .intermediate),
            upcoming("sauces.vinaigrette", "sauces", "Make a Vinaigrette", .right),
            upcoming("sauces.emulsion", "sauces", "Understand an Emulsion", .center, difficulty: .advanced),
            upcoming("sauces.thicken", "sauces", "Thicken a Sauce", .left, difficulty: .intermediate),
            upcoming("sauces.balance", "sauces", "Balance a Sauce", .right, difficulty: .intermediate),
        ]
    )

    static let flavor = SkillCategory(
        id: "flavor",
        name: "Flavor & Seasoning",
        blurb: "Salt, fat, acid and heat, and what to reach for when something tastes flat.",
        theme: .peach,
        skills: [
            upcoming("flavor.salt", "flavor", "Salt Properly", .center),
            upcoming("flavor.acid", "flavor", "Understand Acid", .left),
            upcoming("flavor.fat", "flavor", "Understand Fat", .right),
            upcoming("flavor.umami", "flavor", "Understand Umami", .center, difficulty: .intermediate),
            upcoming("flavor.fix-bland", "flavor", "Fix Bland Food", .left, difficulty: .intermediate),
            upcoming("flavor.fix-salty", "flavor", "Fix Oversalted Food", .right, difficulty: .intermediate),
            upcoming("flavor.finish-acid", "flavor", "Finish With Acid", .center, difficulty: .intermediate),
        ]
    )

    static let intuition = SkillCategory(
        id: "intuition",
        name: "Cooking Intuition",
        blurb: "The difference between following a recipe and actually cooking.",
        theme: .herb,
        skills: [
            upcoming("intuition.why-bland", "intuition", "Know Why Food Tastes Bland", .center, difficulty: .intermediate),
            upcoming("intuition.substitute", "intuition", "Make Substitutions", .left, difficulty: .intermediate),
            upcoming("intuition.recover", "intuition", "Recover From Overcooking", .right, difficulty: .advanced),
            upcoming("intuition.timing", "intuition", "Time Multiple Components", .center, difficulty: .advanced),
            upcoming("intuition.scale", "intuition", "Adjust a Recipe for More People", .left, difficulty: .intermediate),
            upcoming("intuition.no-recipe", "intuition", "Cook Without a Recipe", .center,
                     difficulty: .advanced,
                     prerequisites: ["intuition.why-bland", "intuition.substitute", "intuition.timing"],
                     isChallenge: true),
        ]
    )
}
