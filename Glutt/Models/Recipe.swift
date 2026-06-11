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

    var imageURL: String?
    @Attribute(.externalStorage) var imageData: Data?

    var servings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var difficulty: Difficulty
    var tags: [String]
    var notes: String

    // Nutrition (per serving, optional, only surfaced when nutrition mode is on)
    var calories: Int?
    var proteinGrams: Int?
    var carbGrams: Int?
    var fatGrams: Int?
    var nutritionIsEstimated: Bool

    var createdAt: Date

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
    var role: IngredientRole?
    var sortIndex: Int

    var recipe: Recipe?

    init(
        name: String,
        quantity: Double? = nil,
        unit: String? = nil,
        note: String? = nil,
        isOptional: Bool = false,
        role: IngredientRole? = nil,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.canonicalName = IngredientCanonicalizer.canonicalize(name)
        self.quantity = quantity
        self.unit = unit
        self.note = note
        self.isOptional = isOptional
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
