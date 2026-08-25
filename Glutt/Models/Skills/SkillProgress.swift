import Foundation
import SwiftData

/// What a cook has done with one skill.
///
/// The only part of Skills that is user data, and therefore the only part in
/// SwiftData. A row exists once a skill has been opened; before that, absence
/// means untouched.
///
/// Deliberately keyed by `skillID` string rather than a relationship to a
/// `Skill`, because skills are static content that ships with the app. That
/// also means a row survives its skill being renamed or reordered, and a row
/// for a skill we later remove is simply ignored rather than dangling. Given
/// what a dangling `RecipeCollection` reference did to launch, that is worth
/// being deliberate about.
@Model
final class SkillProgress {
    /// `Skill.id` from the static catalog.
    var skillID: String
    /// When the lesson was first opened. Drives "Continue learning".
    var startedAt: Date?
    /// When the cook marked it learned. Nil means started but not finished.
    var learnedAt: Date?

    /// When Polly watched them do it properly.
    ///
    /// Deliberately separate from `learnedAt`, because they are different
    /// claims. Learned is "I have been taught this and I say I can do it".
    /// Mastered is "this was seen, and it was right". Only the second one is
    /// worth anything to a cook wondering whether they actually hold a knife
    /// correctly, and only the second one is a thing no article can give them.
    var masteredAt: Date?

    /// XP as awarded at the time, not recomputed from the catalog.
    ///
    /// A snapshot on purpose: `SkillXP` exists to be retuned, and retuning it
    /// should change what future skills are worth rather than silently
    /// rewriting someone's level overnight.
    var xpAwarded: Int

    init(
        skillID: String,
        startedAt: Date? = .now,
        learnedAt: Date? = nil,
        masteredAt: Date? = nil,
        xpAwarded: Int = 0
    ) {
        self.skillID = skillID
        self.startedAt = startedAt
        self.learnedAt = learnedAt
        self.masteredAt = masteredAt
        self.xpAwarded = xpAwarded
    }

    var isLearned: Bool { learnedAt != nil }
    var isMastered: Bool { masteredAt != nil }
    var isInProgress: Bool { learnedAt == nil && startedAt != nil }
}

/// How a skill looks on the map.
enum SkillState: Equatable, Sendable {
    case notStarted
    /// The one Glutt is pointing at right now.
    case recommended
    case inProgress
    case learned
    /// Mapped but not written yet. Tappable, but there is nothing to read.
    case comingSoon
}
