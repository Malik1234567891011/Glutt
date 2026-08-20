import Foundation

/// Levels, XP and what to learn next.
///
/// Pure functions over a set of learned skill ids, deliberately knowing nothing
/// about SwiftData or SwiftUI, so all of it is testable without a store and the
/// numbers can be retuned in one place.
enum SkillProgression {

    // MARK: - Levels

    /// XP needed to leave level `level`. Gentle curve: early levels come fast,
    /// which is when someone decides whether this is worth doing at all.
    static func xpToClear(level: Int) -> Int {
        guard level >= 1 else { return baseLevelCost }
        return baseLevelCost + (level - 1) * levelStep
    }

    static let baseLevelCost = 100
    static let levelStep = 25
    /// A ceiling so a corrupt XP value cannot spin the loop below forever.
    static let maxLevel = 99

    /// Level from total XP. Level 1 is where everybody starts.
    static func level(forXP xp: Int) -> Int {
        var level = 1
        var remaining = max(0, xp)
        while level < maxLevel {
            let cost = xpToClear(level: level)
            if remaining < cost { break }
            remaining -= cost
            level += 1
        }
        return level
    }

    /// XP earned inside the current level, and what the level costs. Together
    /// these are the progress bar.
    static func levelProgress(forXP xp: Int) -> (level: Int, into: Int, needed: Int) {
        var level = 1
        var remaining = max(0, xp)
        while level < maxLevel {
            let cost = xpToClear(level: level)
            if remaining < cost { break }
            remaining -= cost
            level += 1
        }
        return (level, remaining, xpToClear(level: level))
    }

    // MARK: - Counting

    static func totalXP(learned: [SkillProgress]) -> Int {
        learned.filter(\.isLearned).reduce(0) { $0 + $1.xpAwarded }
    }

    /// How many of a category's skills are learned. Counts against everything
    /// in the region, written or not, because that is what the cook sees.
    static func learnedCount(in category: SkillCategory, learnedIDs: Set<String>) -> Int {
        category.skills.reduce(0) { $0 + (learnedIDs.contains($1.id) ? 1 : 0) }
    }

    // MARK: - State

    static func state(
        for skill: Skill,
        learnedIDs: Set<String>,
        inProgressIDs: Set<String>,
        recommendedID: String?
    ) -> SkillState {
        if learnedIDs.contains(skill.id) { return .learned }
        if !skill.isAuthored { return .comingSoon }
        // Recommendation beats in-progress, and the order is the whole point.
        // It used to be the other way around, so opening a lesson and backing
        // out downgraded that node from the loudest thing on the map to a quiet
        // outline, permanently. The map then pointed at nothing and Polly, who
        // stands beside the recommended node, vanished with it. Having started
        // something is more reason to point at it, not less.
        if skill.id == recommendedID { return .recommended }
        if inProgressIDs.contains(skill.id) { return .inProgress }
        return .notStarted
    }

    /// Whether every prerequisite has been learned.
    ///
    /// Note this gates *recommendation*, never access. Section 7 of the brief
    /// is explicit: someone who can already make hollandaise should not have to
    /// pass "how to hold a knife" first, so prerequisites are advice.
    static func prerequisitesMet(for skill: Skill, learnedIDs: Set<String>) -> Bool {
        skill.prerequisiteIDs.allSatisfy(learnedIDs.contains)
    }

    static func unmetPrerequisites(for skill: Skill, learnedIDs: Set<String>) -> [Skill] {
        skill.prerequisiteIDs
            .filter { !learnedIDs.contains($0) }
            .compactMap(SkillCatalog.skill(_:))
    }

    // MARK: - What to learn next

    /// The single skill Glutt points at.
    ///
    /// Prefers to finish the region the cook is already in, so the map does not
    /// send someone bouncing between categories. Falls back to the first
    /// available skill in map order, and returns nil only when every written
    /// skill is done.
    static func recommended(
        learnedIDs: Set<String>,
        preferringCategory categoryID: String? = nil
    ) -> Skill? {
        let available = SkillCatalog.authoredSkills.filter {
            !learnedIDs.contains($0.id) && prerequisitesMet(for: $0, learnedIDs: learnedIDs)
        }
        guard !available.isEmpty else {
            // Everything reachable is done. Offer anything still unlearned so
            // the map never dead ends on someone who skipped around.
            return SkillCatalog.authoredSkills.first { !learnedIDs.contains($0.id) }
        }
        if let categoryID, let sameRegion = available.first(where: { $0.categoryID == categoryID }) {
            return sameRegion
        }
        return available.first
    }

    /// What to offer after finishing `skill`: stay in the region if there is
    /// anything left in it.
    static func next(after skill: Skill, learnedIDs: Set<String>) -> Skill? {
        recommended(learnedIDs: learnedIDs, preferringCategory: skill.categoryID)
    }
}
