import Foundation

/// One small, specific thing a cook can learn.
///
/// Skills are **reference content**, not user data: they ship with the app,
/// never change at runtime, and are the same for everybody. So they live in
/// static Swift like `KitchenToolCatalog` and `ChefContent` rather than in
/// SwiftData. Only a cook's *progress* is persisted (`SkillProgress`), which
/// keeps adding "Caramelize Onions" a one line data edit with no migration.
///
/// Keep them narrow. "Dice an Onion" is a skill; "Learn Knife Skills" is a
/// category. If the title needs an "and" it is probably two skills.
struct Skill: Identifiable, Hashable, Sendable {
    let id: String
    let categoryID: String
    let title: String
    /// What the node says on the map. The full `title` is for the lesson.
    ///
    /// Separate because they want different things. "Know When Food Is Done" is
    /// the right lesson title and a terrible map label: wrapped to three lines
    /// around a circle it turns a spacious map into a cramped one. "Doneness"
    /// says the same thing in one line and lets the node breathe.
    let shortName: String
    /// SF Symbol drawn inside the node.
    ///
    /// Nodes used to be identical dots, which made the map impossible to
    /// remember. A glyph per skill means a cook recognises the thermometer or
    /// the flame on sight, which is what turns a list of circles into a place.
    let glyph: String
    /// One line, shown under the title on the lesson screen and in the
    /// Continue Learning card. Not a lesson, a promise.
    let shortDescription: String
    let difficulty: SkillDifficulty
    let estimatedMinutes: Int
    let prerequisiteIDs: [String]

    /// The teaching itself. **Nil means mapped but not yet written.**
    ///
    /// This is deliberate rather than a gap. The map is meant to show a cook
    /// how far the world goes, so regions we have not authored yet still
    /// appear with their node titles, and writing one later is filling in this
    /// optional with no schema change and no UI change.
    let lesson: SkillLesson?

    /// Mastery node: combines several smaller skills and is drawn larger.
    let isChallenge: Bool

    /// Reserved for the animated demonstration that will sit above the text.
    /// Always nil today; the lesson screen already leaves the slot for it, so
    /// adding animation later is content work rather than a rebuild.
    let animationAsset: String?

    /// Layout hint for the staggered map. Cheap and handcrafted, which is the
    /// whole point: no physics engine, no freeform 2D canvas.
    let column: SkillColumn

    init(
        id: String,
        categoryID: String,
        title: String,
        shortName: String? = nil,
        glyph: String = "circle.fill",
        shortDescription: String,
        difficulty: SkillDifficulty = .beginner,
        estimatedMinutes: Int = 2,
        prerequisiteIDs: [String] = [],
        lesson: SkillLesson? = nil,
        isChallenge: Bool = false,
        animationAsset: String? = nil,
        column: SkillColumn = .center
    ) {
        self.id = id
        self.categoryID = categoryID
        self.title = title
        self.shortName = shortName ?? title
        self.glyph = glyph
        self.shortDescription = shortDescription
        self.difficulty = difficulty
        self.estimatedMinutes = estimatedMinutes
        self.prerequisiteIDs = prerequisiteIDs
        self.lesson = lesson
        self.isChallenge = isChallenge
        self.animationAsset = animationAsset
        self.column = column
    }

    /// What finishing this is worth. Derived rather than stored so the numbers
    /// can be retuned in one place (`SkillXP`) instead of across 60 literals.
    var xp: Int { SkillXP.award(difficulty: difficulty, isChallenge: isChallenge) }

    /// Whether there is anything to read yet.
    var isAuthored: Bool { lesson != nil }
}

enum SkillDifficulty: String, Sendable, CaseIterable {
    case beginner
    case intermediate
    case advanced

    var label: String {
        switch self {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }
}

/// Where a node sits across the width of the map. Three columns read as a path
/// when staggered and stay legible on the narrowest phone.
enum SkillColumn: Sendable {
    case left
    case center
    case right

    /// Horizontal position as a fraction of the map's usable width.
    var unitX: Double {
        switch self {
        case .left: 0.22
        case .center: 0.5
        case .right: 0.78
        }
    }
}

/// The written lesson. Structured rather than one blob so the screen can render
/// real sections, and so an animation can later sit above `summary` without
/// anything else moving.
struct SkillLesson: Hashable, Sendable {
    /// "What you're learning", one or two sentences.
    let summary: String
    /// "How to do it".
    let steps: [String]
    /// "Things to watch for".
    let watchFors: [String]
    /// "Why this matters", the line that turns a rule into understanding.
    let whyItMatters: String

    init(summary: String, steps: [String], watchFors: [String], whyItMatters: String) {
        self.summary = summary
        self.steps = steps
        self.watchFors = watchFors
        self.whyItMatters = whyItMatters
    }
}

/// XP in one place so the curve can be retuned without touching content.
enum SkillXP {
    static let beginner = 20
    static let intermediate = 30
    static let advanced = 40
    static let challengeBonus = 35

    static func award(difficulty: SkillDifficulty, isChallenge: Bool) -> Int {
        let base: Int
        switch difficulty {
        case .beginner: base = beginner
        case .intermediate: base = intermediate
        case .advanced: base = advanced
        }
        return isChallenge ? base + challengeBonus : base
    }
}
