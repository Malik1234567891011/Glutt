import CryptoKit
import Foundation
import SwiftData

/// The wire shape of a recipe, and the rules for turning a `Recipe` into it and
/// back again.
///
/// A recipe travels as **one document**, not three normalized tables. The server
/// never queries a recipe's insides — SwiftData is the query engine — so
/// normalizing would buy a multi-table transactional upsert on every save and
/// nothing else. Columns are promoted out of `body` only where we want to read
/// them without parsing the blob.
///
/// See docs/plan-recipe-sync.md for what is deliberately left out and why.
enum RecipeSyncBody {

    /// Bumped when the document shape changes, so a future reader can tell what
    /// it is looking at rather than guess.
    static let version = 1

    /// Long captions are kept (they carry the creator's own words) but capped —
    /// some sources paste an entire blog post into one.
    static let captionLimit = 2000

    // MARK: - Document

    struct Document: Codable, Equatable {
        var v: Int = RecipeSyncBody.version
        var summary: String?
        var servings: Int = 2
        var prepMinutes: Int = 0
        var cookMinutes: Int = 0
        var difficulty: String = Difficulty.beginner.rawValue
        var tags: [String] = []
        var notes: String = ""
        var rating: Int?
        var sourceCreator: String?
        var sourceCaption: String?
        /// ISO-8601 strings, not `Date` — see `SyncTime`.
        var createdAt: String?
        var importedAt: String?
        var importConfidence: Double?
        var imageAssetName: String?
        var nutrition: Nutrition = Nutrition()
        var collections: [String] = []
        var parentRemoteID: UUID?
        var versionLabel: String?
        var ingredients: [Ingredient] = []
        var steps: [Step] = []

        init(
            summary: String? = nil,
            servings: Int = 2,
            prepMinutes: Int = 0,
            cookMinutes: Int = 0,
            difficulty: String = Difficulty.beginner.rawValue,
            tags: [String] = [],
            notes: String = "",
            rating: Int? = nil,
            sourceCreator: String? = nil,
            sourceCaption: String? = nil,
            createdAt: String? = nil,
            importedAt: String? = nil,
            importConfidence: Double? = nil,
            imageAssetName: String? = nil,
            nutrition: Nutrition = Nutrition(),
            collections: [String] = [],
            parentRemoteID: UUID? = nil,
            versionLabel: String? = nil,
            ingredients: [Ingredient] = [],
            steps: [Step] = []
        ) {
            self.summary = summary
            self.servings = servings
            self.prepMinutes = prepMinutes
            self.cookMinutes = cookMinutes
            self.difficulty = difficulty
            self.tags = tags
            self.notes = notes
            self.rating = rating
            self.sourceCreator = sourceCreator
            self.sourceCaption = sourceCaption
            self.createdAt = createdAt
            self.importedAt = importedAt
            self.importConfidence = importConfidence
            self.imageAssetName = imageAssetName
            self.nutrition = nutrition
            self.collections = collections
            self.parentRemoteID = parentRemoteID
            self.versionLabel = versionLabel
            self.ingredients = ingredients
            self.steps = steps
        }

        /// Every key optional with a fallback. A document written by a newer or
        /// older build must never fail to decode — a strict decoder would drop
        /// the whole recipe over one renamed field, and losing a recipe is the
        /// exact thing this feature exists to prevent.
        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            v = try box.decodeIfPresent(Int.self, forKey: .v) ?? RecipeSyncBody.version
            summary = try box.decodeIfPresent(String.self, forKey: .summary)
            servings = try box.decodeIfPresent(Int.self, forKey: .servings) ?? 2
            prepMinutes = try box.decodeIfPresent(Int.self, forKey: .prepMinutes) ?? 0
            cookMinutes = try box.decodeIfPresent(Int.self, forKey: .cookMinutes) ?? 0
            difficulty = try box.decodeIfPresent(String.self, forKey: .difficulty)
                ?? Difficulty.beginner.rawValue
            tags = try box.decodeIfPresent([String].self, forKey: .tags) ?? []
            notes = try box.decodeIfPresent(String.self, forKey: .notes) ?? ""
            rating = try box.decodeIfPresent(Int.self, forKey: .rating)
            sourceCreator = try box.decodeIfPresent(String.self, forKey: .sourceCreator)
            sourceCaption = try box.decodeIfPresent(String.self, forKey: .sourceCaption)
            createdAt = try box.decodeIfPresent(String.self, forKey: .createdAt)
            importedAt = try box.decodeIfPresent(String.self, forKey: .importedAt)
            importConfidence = try box.decodeIfPresent(Double.self, forKey: .importConfidence)
            imageAssetName = try box.decodeIfPresent(String.self, forKey: .imageAssetName)
            nutrition = try box.decodeIfPresent(Nutrition.self, forKey: .nutrition) ?? Nutrition()
            collections = try box.decodeIfPresent([String].self, forKey: .collections) ?? []
            parentRemoteID = try box.decodeIfPresent(UUID.self, forKey: .parentRemoteID)
            versionLabel = try box.decodeIfPresent(String.self, forKey: .versionLabel)
            ingredients = try box.decodeIfPresent([Ingredient].self, forKey: .ingredients) ?? []
            steps = try box.decodeIfPresent([Step].self, forKey: .steps) ?? []
        }
    }

    struct Nutrition: Codable, Equatable {
        var cal: Int?
        var p: Int?
        var c: Int?
        var f: Int?
        var estimated: Bool = true

        init(cal: Int? = nil, p: Int? = nil, c: Int? = nil, f: Int? = nil, estimated: Bool = true) {
            self.cal = cal
            self.p = p
            self.c = c
            self.f = f
            self.estimated = estimated
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            cal = try box.decodeIfPresent(Int.self, forKey: .cal)
            p = try box.decodeIfPresent(Int.self, forKey: .p)
            c = try box.decodeIfPresent(Int.self, forKey: .c)
            f = try box.decodeIfPresent(Int.self, forKey: .f)
            estimated = try box.decodeIfPresent(Bool.self, forKey: .estimated) ?? true
        }
    }

    struct Ingredient: Codable, Equatable {
        var i: Int
        var name: String
        var qty: Double?
        var unit: String?
        var note: String?
        var optional: Bool = false
        var estimated: Bool = false
        var role: String?

        init(
            i: Int,
            name: String,
            qty: Double? = nil,
            unit: String? = nil,
            note: String? = nil,
            optional: Bool = false,
            estimated: Bool = false,
            role: String? = nil
        ) {
            self.i = i
            self.name = name
            self.qty = qty
            self.unit = unit
            self.note = note
            self.optional = optional
            self.estimated = estimated
            self.role = role
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            i = try box.decodeIfPresent(Int.self, forKey: .i) ?? 0
            name = try box.decodeIfPresent(String.self, forKey: .name) ?? ""
            qty = try box.decodeIfPresent(Double.self, forKey: .qty)
            unit = try box.decodeIfPresent(String.self, forKey: .unit)
            note = try box.decodeIfPresent(String.self, forKey: .note)
            optional = try box.decodeIfPresent(Bool.self, forKey: .optional) ?? false
            estimated = try box.decodeIfPresent(Bool.self, forKey: .estimated) ?? false
            role = try box.decodeIfPresent(String.self, forKey: .role)
        }
    }

    struct Step: Codable, Equatable {
        var i: Int
        var text: String
        var sec: Int?

        init(i: Int, text: String, sec: Int? = nil) {
            self.i = i
            self.text = text
            self.sec = sec
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            i = try box.decodeIfPresent(Int.self, forKey: .i) ?? 0
            text = try box.decodeIfPresent(String.self, forKey: .text) ?? ""
            sec = try box.decodeIfPresent(Int.self, forKey: .sec)
        }
    }

    // MARK: - Encoding

    /// Everything about a recipe that goes over the wire, promoted columns
    /// included. This — not the document alone — is what gets hashed, or a
    /// rename would never push.
    struct Snapshot: Equatable {
        var title: String
        var imageURL: String?
        var sourceURL: String?
        var sourcePlatform: String
        var isFavorite: Bool
        var body: Document
    }

    static func snapshot(of recipe: Recipe) -> Snapshot {
        Snapshot(
            title: recipe.title,
            imageURL: recipe.imageURL,
            sourceURL: recipe.sourceURL,
            sourcePlatform: recipe.sourcePlatform.rawValue,
            isFavorite: recipe.isFavorite,
            body: document(of: recipe)
        )
    }

    /// The names of the collections this recipe is in, resolved from the
    /// **collection** side rather than from `recipe.collections`.
    ///
    /// Reading `recipe.collections` directly is a crash waiting to happen. A
    /// recipe can still hold a reference to a collection whose row is gone, and
    /// SwiftData does not hand back nil for that: it hands back a live-looking
    /// object, and the first property you read off it is a `fatalError` that
    /// takes the process down. On a real device that killed the app on launch
    /// before it drew a frame, because the sync sweep runs from `RootView`'s
    /// startup task and touches every recipe.
    ///
    /// Walking the other way is immune: a fetch only ever returns rows that
    /// exist, so every collection here is real and `name` is safe to read. It
    /// also self-heals, since a dangling reference simply stops being reported.
    ///
    /// The fetch is per recipe, which is not free, but collections are a handful
    /// of rows and this runs on a background sync rather than in a view body.
    /// Correctness first: the alternative crashed the app.
    static func collectionNames(of recipe: Recipe) -> [String] {
        guard let context = recipe.modelContext else { return [] }
        let live = (try? context.fetch(FetchDescriptor<RecipeCollection>())) ?? []
        let id = recipe.persistentModelID
        return live
            .filter { collection in collection.recipes.contains { $0.persistentModelID == id } }
            .map(\.name)
            .sorted()
    }

    static func document(of recipe: Recipe) -> Document {
        Document(
            summary: recipe.summary,
            servings: recipe.servings,
            prepMinutes: recipe.prepMinutes,
            cookMinutes: recipe.cookMinutes,
            difficulty: recipe.difficulty.rawValue,
            tags: recipe.tags,
            notes: recipe.notes,
            rating: recipe.rating,
            sourceCreator: recipe.sourceCreator,
            sourceCaption: recipe.sourceCaption.map { String($0.prefix(captionLimit)) },
            createdAt: SyncTime.string(from: recipe.createdAt),
            importedAt: recipe.importedAt.map(SyncTime.string(from:)),
            importConfidence: recipe.importConfidence,
            imageAssetName: recipe.imageAssetName,
            nutrition: Nutrition(
                cal: recipe.calories,
                p: recipe.proteinGrams,
                c: recipe.carbGrams,
                f: recipe.fatGrams,
                estimated: recipe.nutritionIsEstimated
            ),
            // Sorted because a SwiftData to-many has no defined order, and an
            // order that wobbles between reads would look like an edit to the
            // hash and re-push the same recipe forever.
            collections: collectionNames(of: recipe),
            parentRemoteID: recipe.parentRecipe?.remoteID,
            versionLabel: recipe.versionLabel,
            ingredients: recipe.ingredients
                .sorted { $0.sortIndex < $1.sortIndex }
                .enumerated()
                .map { offset, ingredient in
                    Ingredient(
                        i: offset,
                        name: ingredient.name,
                        qty: ingredient.quantity,
                        unit: ingredient.unit,
                        note: ingredient.note,
                        optional: ingredient.isOptional,
                        estimated: ingredient.isEstimated,
                        role: ingredient.role?.rawValue
                    )
                },
            steps: recipe.sortedSteps.enumerated().map { offset, step in
                Step(i: offset, text: step.text, sec: step.durationSeconds)
            }
        )
    }

    // MARK: - Applying a pulled document

    /// Overwrites a local recipe with a pulled one. Last-write-wins per whole
    /// recipe: no field-level merge, no CRDTs. This is a one-phone-per-person
    /// app and the worst case is losing a single edit.
    ///
    /// Collections are resolved by name through `collectionsByName`, which the
    /// caller primes once per sweep so a hundred recipes don't each refetch.
    /// `parentRecipe` is left to the caller — parents have to be applied before
    /// children, which is a decision about the whole batch, not one recipe.
    @MainActor
    static func apply(
        _ snapshot: Snapshot,
        to recipe: Recipe,
        in context: ModelContext,
        collectionsByName: inout [String: RecipeCollection]
    ) {
        recipe.title = snapshot.title
        recipe.imageURL = snapshot.imageURL
        recipe.sourceURL = snapshot.sourceURL
        recipe.sourcePlatform = SourcePlatform(rawValue: snapshot.sourcePlatform) ?? .manual
        recipe.isFavorite = snapshot.isFavorite

        let body = snapshot.body
        recipe.summary = body.summary
        recipe.servings = body.servings
        recipe.prepMinutes = body.prepMinutes
        recipe.cookMinutes = body.cookMinutes
        recipe.difficulty = Difficulty(rawValue: body.difficulty) ?? .beginner
        recipe.tags = body.tags
        recipe.notes = body.notes
        recipe.rating = body.rating
        recipe.sourceCreator = body.sourceCreator
        recipe.sourceCaption = body.sourceCaption
        // Kept so a restored library sorts the way the user left it — the
        // recipes feed is ordered by this, and a shelf where everything arrived
        // at the same second is not the library they had.
        if let createdAt = SyncTime.date(from: body.createdAt) { recipe.createdAt = createdAt }
        recipe.importedAt = SyncTime.date(from: body.importedAt)
        recipe.importConfidence = body.importConfidence
        recipe.imageAssetName = body.imageAssetName
        recipe.calories = body.nutrition.cal
        recipe.proteinGrams = body.nutrition.p
        recipe.carbGrams = body.nutrition.c
        recipe.fatGrams = body.nutrition.f
        recipe.nutritionIsEstimated = body.nutrition.estimated
        recipe.versionLabel = body.versionLabel

        recipe.collections = body.collections.map { name in
            if let existing = collectionsByName[name] { return existing }
            let created = RecipeCollection(name: name)
            context.insert(created)
            collectionsByName[name] = created
            return created
        }

        // Replaced wholesale rather than diffed. Cascade delete takes the old
        // children with them, and a diff would be more code for a case that
        // happens at most a few dozen times per restore.
        for ingredient in recipe.ingredients { context.delete(ingredient) }
        recipe.ingredients = body.ingredients.map { line in
            let ingredient = RecipeIngredient(
                name: line.name,
                quantity: line.qty,
                unit: line.unit,
                note: line.note,
                isOptional: line.optional,
                isEstimated: line.estimated,
                role: line.role.flatMap(IngredientRole.init(rawValue:)),
                sortIndex: line.i
            )
            context.insert(ingredient)
            return ingredient
        }

        for step in recipe.steps { context.delete(step) }
        recipe.steps = body.steps.map { step in
            let created = RecipeStep(index: step.i, text: step.text, durationSeconds: step.sec)
            context.insert(created)
            return created
        }
    }

    // MARK: - Hashing

    /// Deterministic JSON for hashing. Sorted keys, and no date strategy to get
    /// wrong because the document holds no `Date` (see `SyncTime`) — so the same
    /// recipe hashes the same on every launch, which is what the whole
    /// change-tracking scheme rests on.
    static func makeEncoder(sortedKeys: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        if sortedKeys { encoder.outputFormatting = [.sortedKeys] }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    /// SHA256 of the snapshot. Different from the stored `syncedHash` means push.
    static func hash(_ snapshot: Snapshot) -> String {
        // Hashed as one blob so a change to any promoted column counts, without
        // needing a Codable shape that exists purely to be hashed.
        var input = Data()
        input.append(contentsOf: Array(snapshot.title.utf8))
        input.append(0)
        input.append(contentsOf: Array((snapshot.imageURL ?? "").utf8))
        input.append(0)
        input.append(contentsOf: Array((snapshot.sourceURL ?? "").utf8))
        input.append(0)
        input.append(contentsOf: Array(snapshot.sourcePlatform.utf8))
        input.append(0)
        input.append(snapshot.isFavorite ? 1 : 0)
        input.append(0)
        if let body = try? makeEncoder(sortedKeys: true).encode(snapshot.body) {
            input.append(body)
        }
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(of recipe: Recipe) -> String {
        hash(snapshot(of: recipe))
    }

    /// Shared with the Kitchen and prefs documents, which track their own
    /// changes the same way rather than inventing a second scheme.
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
