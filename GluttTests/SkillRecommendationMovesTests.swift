import Testing
@testable import Glutt

/// The map stopped pointing anywhere the moment the first skill was learned:
/// no "next" node, and Polly, who stands beside it, disappeared with it. These
/// pin the hand-off from one recommendation to the next.
struct SkillRecommendationMovesTests {
    private func reader(learned: [String], opened: [String] = []) -> SkillsProgressReader {
        var rows: [SkillProgress] = []
        for id in learned {
            rows.append(SkillProgress(skillID: id, learnedAt: .now, xpAwarded: 20))
        }
        for id in opened {
            rows.append(SkillProgress(skillID: id))
        }
        return SkillsProgressReader(progress: rows)
    }

    @Test func firstSkillIsRecommendedOnAFreshMap() {
        let r = reader(learned: [])
        #expect(r.recommended?.id == SkillCatalog.authoredSkills.first?.id)
    }

    @Test func recommendationMovesOnAfterLearningTheFirstSkill() throws {
        let first = try #require(SkillCatalog.authoredSkills.first)
        let r = reader(learned: [first.id])
        let next = try #require(r.recommended)
        #expect(next.id != first.id)
        #expect(r.state(for: next) == .recommended)
    }

    /// The bug this file was written for. Opening a lesson and backing out used
    /// to leave the node `.inProgress`, which was checked before `.recommended`
    /// and so quietly removed the map's only pointer, Polly included.
    @Test func openingALessonDoesNotDowngradeTheRecommendedNode() throws {
        let first = try #require(SkillCatalog.authoredSkills.first)
        let r = reader(learned: [], opened: [first.id])
        #expect(r.recommended?.id == first.id)
        #expect(r.state(for: first) == .recommended)
    }

    /// A started skill that is *not* the recommendation still reads as started.
    @Test func anOtherStartedSkillStaysInProgress() throws {
        let authored = SkillCatalog.authoredSkills
        let first = try #require(authored.first)
        let later = try #require(authored.dropFirst().last)
        let r = reader(learned: [], opened: [first.id, later.id])
        #expect(r.state(for: later) == .inProgress)
    }

    /// `inProgressIDs` is a `Set`, so reading "where were they last" off its
    /// first element made the recommendation depend on hash order: same data,
    /// different region, on every launch.
    @Test func theRecommendationFollowsTheMostRecentlyOpenedSkill() throws {
        let authored = SkillCatalog.authoredSkills
        let early = try #require(authored.first)
        let late = try #require(authored.last { $0.categoryID != early.categoryID })

        var rows = [
            SkillProgress(skillID: early.id, startedAt: .now.addingTimeInterval(-600)),
            SkillProgress(skillID: late.id, startedAt: .now),
        ]
        #expect(SkillsProgressReader(progress: rows).recommended?.categoryID == late.categoryID)

        // Same rows, opposite order in the array. A set would shuffle; this
        // must not.
        rows.reverse()
        #expect(SkillsProgressReader(progress: rows).recommended?.categoryID == late.categoryID)
    }

    /// Finishing a lesson counts as being in that region. Without it, a cook
    /// one node from completing a region got sent to a different one because
    /// they had opened something there once and wandered off.
    @Test func finishingASkillKeepsTheRecommendationInThatRegion() throws {
        let authored = SkillCatalog.authoredSkills
        let home = try #require(authored.first).categoryID
        let elsewhere = try #require(authored.first { $0.categoryID != home })

        // Everything in the home region done except the last one, plus an old
        // abandoned lesson in another region.
        let homeSkills = authored.filter { $0.categoryID == home }
        let finished = homeSkills.dropLast()
        var rows = finished.map {
            SkillProgress(
                skillID: $0.id,
                startedAt: .now.addingTimeInterval(-60),
                learnedAt: .now,
                xpAwarded: 20
            )
        }
        rows.append(SkillProgress(skillID: elsewhere.id, startedAt: .now.addingTimeInterval(-9000)))

        let reader = SkillsProgressReader(progress: rows)
        #expect(reader.recommended?.categoryID == home)
        #expect(reader.recommended?.id == homeSkills.last?.id)
    }

    /// "Continue learning" resumes what they actually walked away from.
    @Test func continueResumesTheMostRecentlyOpenedSkill() throws {
        let authored = SkillCatalog.authoredSkills
        let early = try #require(authored.first)
        let late = try #require(authored.dropFirst().first)
        let rows = [
            SkillProgress(skillID: early.id, startedAt: .now.addingTimeInterval(-600)),
            SkillProgress(skillID: late.id, startedAt: .now),
        ]
        let target = try #require(SkillsProgressReader(progress: rows).continueTarget)
        #expect(target.skill.id == late.id)
        #expect(target.isResuming)
    }

    /// Polly is drawn beside the recommended node, so "is there a recommendation
    /// in a real progress state" is the same question as "is Polly on the map".
    @Test func thereIsAlwaysSomewhereToPointUntilEverythingIsLearned() {
        let all = SkillCatalog.authoredSkills.map(\.id)
        for prefix in [0, 1, 3, all.count - 1] {
            let r = reader(learned: Array(all.prefix(prefix)))
            #expect(r.recommended != nil, "no recommendation with \(prefix) learned")
        }
        #expect(reader(learned: all).recommended == nil)
    }
}
