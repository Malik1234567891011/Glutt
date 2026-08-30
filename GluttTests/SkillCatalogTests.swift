import XCTest
@testable import Glutt

/// The catalog is hand written content, so these are the guards that stop a
/// typo becoming a broken map. Everything here is cheap and catches the kinds
/// of mistake that are invisible until someone taps the wrong node.
final class SkillCatalogTests: XCTestCase {

    func testEveryIDIsUnique() {
        let ids = SkillCatalog.allSkills.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate skill ids: \(duplicates(in: ids))")

        let categoryIDs = SkillCatalog.categories.map(\.id)
        XCTAssertEqual(Set(categoryIDs).count, categoryIDs.count)
    }

    func testEveryPrerequisiteResolves() {
        for skill in SkillCatalog.allSkills {
            for id in skill.prerequisiteIDs {
                XCTAssertNotNil(
                    SkillCatalog.skill(id),
                    "\(skill.id) requires \(id), which does not exist"
                )
            }
        }
    }

    /// A cycle would make a node permanently unreachable and is impossible to
    /// spot by reading.
    func testNoPrerequisiteCycles() {
        for skill in SkillCatalog.allSkills {
            var seen: Set<String> = []
            XCTAssertFalse(
                reachesItself(skill.id, from: skill.id, seen: &seen),
                "\(skill.id) is part of a prerequisite cycle"
            )
        }
    }

    func testEverySkillBelongsToItsCategory() {
        for category in SkillCatalog.categories {
            for skill in category.skills {
                XCTAssertEqual(skill.categoryID, category.id,
                               "\(skill.id) is filed under \(category.id) but claims \(skill.categoryID)")
            }
        }
    }

    /// Every region needs a way in, or a cook working through the map hits a
    /// wall of prerequisites and the region is unreachable.
    ///
    /// The rule used to be that each category contained a skill with NO
    /// prerequisites at all, which was right while the categories stood alone.
    /// It stopped being right once the later ones started building deliberately
    /// on the earlier ones: hollandaise should require an emulsion lesson, and
    /// Mother Sauces having no free-standing entry point is the curriculum
    /// working rather than a gap. What actually matters is that somebody who has
    /// worked through everything before a category can begin it, so that is what
    /// this checks now.
    func testEveryCategoryCanBeEnteredFromWhatCameBefore() {
        var seen: Set<String> = []
        for category in SkillCatalog.categories {
            let openable = category.skills.contains { skill in
                skill.prerequisiteIDs.allSatisfy(seen.contains)
            }
            XCTAssertTrue(
                openable,
                "\(category.id) cannot be started by a cook who has done everything before it"
            )
            for skill in category.skills { seen.insert(skill.id) }
        }
    }

    func testChallengesBuildOnSomething() {
        for skill in SkillCatalog.allSkills where skill.isChallenge {
            XCTAssertFalse(
                skill.prerequisiteIDs.isEmpty,
                "\(skill.id) is a mastery node with no prerequisites, which makes it just a big skill"
            )
        }
    }

    /// A prerequisite that lives in another region is fine and deliberate, but
    /// a prerequisite pointing *forward* in map order would ask a cook to learn
    /// something they have not scrolled to yet.
    func testPrerequisitesNeverPointForward() {
        var position: [String: Int] = [:]
        for (index, skill) in SkillCatalog.allSkills.enumerated() { position[skill.id] = index }

        for skill in SkillCatalog.allSkills {
            guard let mine = position[skill.id] else { continue }
            for id in skill.prerequisiteIDs {
                guard let theirs = position[id] else { continue }
                XCTAssertLessThan(theirs, mine,
                                  "\(skill.id) requires \(id), which appears later on the map")
            }
        }
    }

    // MARK: - Authored content

    func testEveryCategoryIsFullyAuthored() {
        for id in SkillCatalog.categories.map(\.id) {
            let category = SkillCatalog.category(id)
            XCTAssertNotNil(category, "missing category \(id)")
            for skill in category?.skills ?? [] {
                XCTAssertNotNil(skill.lesson, "\(skill.id) is in a written category but has no lesson")
            }
        }
    }

    /// There are no unwritten regions left. Every skill on the map has a
    /// lesson, which was the whole point of the exercise, and this replaces the
    /// test that used to assert the opposite.
    ///
    /// A skill added later with no lesson is fine and the map handles it. This
    /// just stops one being added by accident and never noticed.
    func testEverySkillOnTheMapHasBeenWritten() {
        let unwritten = SkillCatalog.allSkills.filter { $0.lesson == nil }.map(\.id)
        XCTAssertTrue(
            unwritten.isEmpty,
            "these skills are on the map with no lesson: \(unwritten)")
    }

    func testAuthoredLessonsAreComplete() {
        for skill in SkillCatalog.authoredSkills {
            guard let lesson = skill.lesson else { continue }
            XCTAssertFalse(lesson.summary.isEmpty, "\(skill.id) has an empty summary")
            XCTAssertGreaterThanOrEqual(lesson.steps.count, 2, "\(skill.id) has fewer than two steps")
            XCTAssertFalse(lesson.watchFors.isEmpty, "\(skill.id) has nothing to watch for")
            XCTAssertFalse(lesson.whyItMatters.isEmpty, "\(skill.id) does not say why it matters")
            XCTAssertFalse(skill.title.isEmpty)
            XCTAssertFalse(skill.shortDescription.isEmpty)
        }
    }

    /// `.claude/rules/ui-copy.md`: never a dash as punctuation in user facing
    /// copy. Hyphenated compounds like "soft-boiled" are fine, so this looks
    /// for em dashes, en dashes and the spaced hyphen specifically.
    func testCopyUsesNoDashesAsPunctuation() {
        for skill in SkillCatalog.allSkills {
            var strings = [skill.title, skill.shortDescription]
            if let lesson = skill.lesson {
                strings.append(lesson.summary)
                strings.append(lesson.whyItMatters)
                strings.append(contentsOf: lesson.steps)
                strings.append(contentsOf: lesson.watchFors)
            }
            for string in strings {
                XCTAssertFalse(string.contains("—"), "em dash in \(skill.id): \(string)")
                XCTAssertFalse(string.contains("–"), "en dash in \(skill.id): \(string)")
                XCTAssertFalse(string.contains(" - "), "spaced hyphen in \(skill.id): \(string)")
            }
        }

        for category in SkillCatalog.categories {
            for string in [category.name, category.blurb] {
                XCTAssertFalse(string.contains("—"), "em dash in \(category.id): \(string)")
                XCTAssertFalse(string.contains("–"), "en dash in \(category.id): \(string)")
                XCTAssertFalse(string.contains(" - "), "spaced hyphen in \(category.id): \(string)")
            }
        }
    }

    // MARK: - XP

    func testXPRewardsScaleWithDifficultyAndChallenge() {
        XCTAssertEqual(SkillXP.award(difficulty: .beginner, isChallenge: false), SkillXP.beginner)
        XCTAssertEqual(SkillXP.award(difficulty: .advanced, isChallenge: false), SkillXP.advanced)
        XCTAssertGreaterThan(
            SkillXP.award(difficulty: .beginner, isChallenge: true),
            SkillXP.award(difficulty: .beginner, isChallenge: false)
        )
    }

    func testTheMapIsBigEnoughToFeelLikeAWorld() {
        // Not a style assertion. A map this size is what makes scrolling reveal
        // something, and a regression that silently drops a region should fail.
        XCTAssertGreaterThanOrEqual(SkillCatalog.categories.count, 8)
        XCTAssertGreaterThanOrEqual(SkillCatalog.allSkills.count, 50)
        XCTAssertGreaterThanOrEqual(SkillCatalog.authoredSkills.count, 30)
    }

    // MARK: - Helpers

    private func duplicates(in ids: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for id in ids { counts[id, default: 0] += 1 }
        return counts.filter { $0.value > 1 }.keys.sorted()
    }

    private func reachesItself(_ target: String, from id: String, seen: inout Set<String>) -> Bool {
        guard let skill = SkillCatalog.skill(id) else { return false }
        for next in skill.prerequisiteIDs {
            if next == target { return true }
            guard seen.insert(next).inserted else { continue }
            if reachesItself(target, from: next, seen: &seen) { return true }
        }
        return false
    }
}
