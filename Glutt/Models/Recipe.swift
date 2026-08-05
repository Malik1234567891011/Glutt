import Foundation
import SwiftData

@Model
final class Recipe {
    var title: String
    var summary: String?

    // Source preservation (original creator/link is never lost)
    var sourceCreator: String?
    var sourceURL: String?
    var sourcePlatform: SourcePlatform
    var sourceCaption: String?
    var importedAt: Date?

    /// 0.0–1.0 confidence from the import pipeline. Nil for manually created recipes.
    var importConfidence: Double?

    // Background technique-clip pipeline (Supabase / media-worker). Soft fields —
    // cook + Polly work while these are nil or mid-flight.
    /// Platform media id (YouTube video id / TikTok numeric id).
    var mediaExternalID: String?
    var mediaSourceAssetID: String?
    var mediaJobID: String?
    /// queued | analysing | indexed | ready | failed
    var mediaStatus: String?
    /// 0...1 best-effort progress for detail UI.
    var mediaProgress: Double?
    var mediaStatusDetail: String?

    var imageURL: String?
    /// Name of a bundled asset-catalog image (used by seed/sample content).
    var imageAssetName: String?
    @Attribute(.externalStorage) var imageData: Data?

    var servings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var difficulty: Difficulty
    var tags: [String]
    var notes: String
    /// Private 1–5 rating. Nil until the user rates it.
    var rating: Int?
    /// User-marked favorite (the detail-screen heart).
    var isFavorite: Bool = false

    // Nutrition (per serving, optional, only surfaced when nutrition mode is on)
    var calories: Int?
    var proteinGrams: Int?
    var carbGrams: Int?
    var fatGrams: Int?
    var nutritionIsEstimated: Bool

    var createdAt: Date

    // MARK: - Sync (see docs/plan-recipe-sync.md)

    /// Stable cross-device identity. `persistentModelID` is local and dies with
    /// the store, so after a reinstall it is this that matches a pulled row to
    /// a local one.
    ///
    /// Optional so the SwiftData migration stays lightweight — and, crucially,
    /// **not** `= UUID()`: a defaulted value in a lightweight migration is
    /// evaluated once for the schema, so every existing row would come back
    /// carrying the *same* id. New recipes get theirs in `init` (which runs per
    /// instance, and never when materializing a stored row); pre-existing ones
    /// are filled in by `RecipeIdentity.backfill`.
    var remoteID: UUID?

    /// SHA256 of the sync body as last pushed. Different from the current body
    /// means this recipe has local changes to send. Nil = never pushed.
    ///
    /// A hash rather than a dirty flag because recipe mutations happen inline
    /// all over the view layer (the detail screen toggles `isFavorite`
    /// directly), and any scheme needing a `touch()` at every mutation site
    /// would silently miss one.
    var syncedHash: String?
    var syncedAt: Date?

    /// Storage object key for this recipe's photo, once its bytes have been
    /// uploaded. Nil means the photo lives only on this phone (or only at
    /// `imageURL`, which is the free fallback and also the one that rots).
    var remoteImagePath: String?

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient]

    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe)
    var steps: [RecipeStep]

    var collections: [RecipeCollection]

    /// Versioning: "my version", "pantry version", etc. point back to the original.
    var parentRecipe: Recipe?
    @Relationship(inverse: \Recipe.parentRecipe)
    var versions: [Recipe]
    var versionLabel: String?

    var totalMinutes: Int { prepMinutes + cookMinutes }

    /// Best-effort total time for display and sorting. When the source gave us
    /// explicit prep/cook minutes we trust those; otherwise (common with
    /// imported/AI recipes that come back as 0) we estimate from the timers
    /// detected in the steps plus a buffer for the hands-on prep and
    /// transitions that those timers never capture.
    var estimatedMinutes: Int {
        let explicit = prepMinutes + cookMinutes
        if explicit > 0 { return explicit }
        guard !steps.isEmpty else { return 0 }
        let timedMinutes = steps.compactMap(\.durationSeconds).reduce(0, +) / 60
        let untimedSteps = steps.filter { $0.durationSeconds == nil }.count
        // ~4 min of untimed hands-on work per step, plus a small base buffer
        // whenever there were any explicit timers to anchor to.
        let buffer = untimedSteps * 4 + (timedMinutes > 0 ? 5 : 0)
        return timedMinutes + buffer
    }

    /// True when `estimatedMinutes` is a guess rather than authored times,
    /// so the UI can show it as "~25 min" instead of implying precision.
    var minutesAreEstimated: Bool {
        prepMinutes + cookMinutes == 0 && estimatedMinutes > 0
    }

    /// Ready-to-show time label: "30 min", "1 hr 10", "~25 min", or "—" when
    /// unknown. Anything an hour or over reads in hours, because "150 min" is
    /// a number you have to do arithmetic on.
    var timeLabel: String {
        let minutes = estimatedMinutes
        guard minutes > 0 else { return "—" }
        let prefix = minutesAreEstimated ? "~" : ""
        guard minutes >= 60 else { return "\(prefix)\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(prefix)\(hours) hr" : "\(prefix)\(hours) hr \(rest)"
    }

    var sortedSteps: [RecipeStep] {
        steps.sorted { $0.index < $1.index }
    }

    init(
        title: String,
        summary: String? = nil,
        sourceCreator: String? = nil,
        sourceURL: String? = nil,
        sourcePlatform: SourcePlatform = .manual,
        sourceCaption: String? = nil,
        importedAt: Date? = nil,
        importConfidence: Double? = nil,
        imageURL: String? = nil,
        servings: Int = 2,
        prepMinutes: Int = 0,
        cookMinutes: Int = 0,
        difficulty: Difficulty = .beginner,
        tags: [String] = [],
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.title = title
        self.summary = summary
        self.sourceCreator = sourceCreator
        self.sourceURL = sourceURL
        self.sourcePlatform = sourcePlatform
        self.sourceCaption = sourceCaption
        self.importedAt = importedAt
        self.importConfidence = importConfidence
        self.imageURL = imageURL
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.difficulty = difficulty
        self.tags = tags
        self.notes = notes
        self.nutritionIsEstimated = true
        self.createdAt = createdAt
        // Every recipe born in this process gets its identity here, which is
        // one place instead of the dozen `context.insert(recipe)` sites.
        self.remoteID = UUID()
        self.ingredients = []
        self.steps = []
        self.collections = []
        self.versions = []
    }
}

@Model
final class RecipeIngredient {
    var name: String
    /// Canonical name used for pantry matching ("scallions" -> "green onion").
    var canonicalName: String
    var quantity: Double?
    var unit: String?
    var note: String?
    var isOptional: Bool
    /// True when the amount is Glutt's approximate estimate (the source gave
    /// none). Shown as "~/approx" so the user knows to verify and adjust.
    var isEstimated: Bool = false
    var role: IngredientRole?
    var sortIndex: Int

    var recipe: Recipe?

    init(
        name: String,
        quantity: Double? = nil,
        unit: String? = nil,
        note: String? = nil,
        isOptional: Bool = false,
        isEstimated: Bool = false,
        role: IngredientRole? = nil,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.canonicalName = IngredientCanonicalizer.canonicalize(name)
        self.quantity = quantity
        self.unit = unit
        self.note = note
        self.isOptional = isOptional
        self.isEstimated = isEstimated
        self.role = role
        self.sortIndex = sortIndex
    }
}

@Model
final class RecipeStep {
    var index: Int
    var text: String
    /// Detected timer duration for this step, if any.
    var durationSeconds: Int?

    var recipe: Recipe?

    init(index: Int, text: String, durationSeconds: Int? = nil) {
        self.index = index
        self.text = text
        self.durationSeconds = durationSeconds
    }
}

@Model
final class RecipeCollection {
    var name: String
    var createdAt: Date

    @Relationship(inverse: \Recipe.collections)
    var recipes: [Recipe]

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.recipes = []
    }
}
