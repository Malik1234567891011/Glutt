import Foundation

/// Every skill Glutt teaches, in map order.
///
/// Static content, like `KitchenToolCatalog` and `ChefContent`. Nothing here is
/// user data and nothing changes at runtime, so it does not belong in SwiftData;
/// only `SkillProgress` does. That keeps adding a skill a data edit rather than
/// a migration.
///
/// Order is the map. The first three regions are written; everything after is
/// mapped so the world visibly keeps going (see `SkillCatalog+Upcoming`).
enum SkillCatalog {

    static let categories: [SkillCategory] = [
        cookingBasics,
        knifeSkills,
        heatControl,
        eggs,
        meat,
        sauces,
        flavor,
        intuition,
    ]

    /// Flat list, map order preserved.
    static let allSkills: [Skill] = categories.flatMap(\.skills)

    private static let skillsByID: [String: Skill] = Dictionary(
        allSkills.map { ($0.id, $0) },
        // Duplicate ids are a content bug, caught by `SkillCatalogTests`. Keep
        // the first so a mistake degrades rather than traps.
        uniquingKeysWith: { first, _ in first }
    )

    private static let categoriesByID: [String: SkillCategory] = Dictionary(
        categories.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static func skill(_ id: String) -> Skill? { skillsByID[id] }
    static func category(_ id: String) -> SkillCategory? { categoriesByID[id] }
    static func category(of skill: Skill) -> SkillCategory? { categoriesByID[skill.categoryID] }

    /// Skills that can be learned today, which is everything with a lesson.
    static var authoredSkills: [Skill] { allSkills.filter(\.isAuthored) }

    /// The prerequisites of a skill, resolved and in order. Ids that do not
    /// resolve are dropped rather than crashing; the tests are what stop them
    /// existing in the first place.
    static func prerequisites(of skill: Skill) -> [Skill] {
        skill.prerequisiteIDs.compactMap(skill(_:))
    }
}
