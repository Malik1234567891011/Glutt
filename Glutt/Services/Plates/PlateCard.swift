import Foundation

/// A photo recipe surfaced in the Plates feed. Transient — never persisted
/// until the user saves it (then it goes through the normal import chokepoint).
struct PlateCard: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let imageURL: String?
    let source: String
    let sourceURL: String?
    let creator: String?
    let license: String?
    let summary: String?
    let servings: Int?
    let prepMinutes: Int?
    let cookMinutes: Int?
    let difficulty: String?
    let tags: [String]
    let dietFlags: [String]
    let macros: PlateMacros?
    let ingredients: [PlateIngredient]
    let steps: [String]
    let nutritionNote: String?

    // Optional-tolerant decoding: arrays default to empty, scalars to nil.
    enum CodingKeys: String, CodingKey {
        case id, title, imageURL, source, sourceURL, creator, license, summary
        case servings, prepMinutes, cookMinutes, difficulty, tags, dietFlags
        case macros, ingredients, steps, nutritionNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "spoonacular"
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        creator = try c.decodeIfPresent(String.self, forKey: .creator)
        license = try c.decodeIfPresent(String.self, forKey: .license)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        servings = try c.decodeIfPresent(Int.self, forKey: .servings)
        prepMinutes = try c.decodeIfPresent(Int.self, forKey: .prepMinutes)
        cookMinutes = try c.decodeIfPresent(Int.self, forKey: .cookMinutes)
        difficulty = try c.decodeIfPresent(String.self, forKey: .difficulty)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        dietFlags = try c.decodeIfPresent([String].self, forKey: .dietFlags) ?? []
        macros = try c.decodeIfPresent(PlateMacros.self, forKey: .macros)
        ingredients = try c.decodeIfPresent([PlateIngredient].self, forKey: .ingredients) ?? []
        steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
        nutritionNote = try c.decodeIfPresent(String.self, forKey: .nutritionNote)
    }
}

struct PlateMacros: Decodable, Equatable {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let estimated: Bool

    private func rounded(_ v: Double?) -> Int? { v.map { Int($0.rounded()) } }
    var caloriesInt: Int? { rounded(calories) }
    var proteinInt: Int? { rounded(protein) }
    var carbsInt: Int? { rounded(carbs) }
    var fatInt: Int? { rounded(fat) }
}

struct PlateIngredient: Decodable, Equatable {
    let raw: String
    let name: String?
    let quantity: Double?
    let unit: String?
}

/// One page (or the daily deck) of Plates results from the proxy.
struct PlatesResponse: Decodable, Equatable {
    let deckTitle: String?
    let recipes: [PlateCard]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey { case deckTitle, recipes, nextPageToken }

    init(deckTitle: String?, recipes: [PlateCard], nextPageToken: String?) {
        self.deckTitle = deckTitle
        self.recipes = recipes
        self.nextPageToken = nextPageToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deckTitle = try c.decodeIfPresent(String.self, forKey: .deckTitle)
        recipes = try c.decodeIfPresent([PlateCard].self, forKey: .recipes) ?? []
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

/// Encodable mirror used only to persist the daily deck cache. Kept separate so
/// the wire models stay decode-only and match the server contract exactly.
struct EncodablePlates: Encodable {
    let deckTitle: String?
    let recipes: [Card]
    let nextPageToken: String?

    struct Card: Encodable {
        let id, title, source: String
        let imageURL, sourceURL, creator, license, summary, difficulty, nutritionNote: String?
        let servings, prepMinutes, cookMinutes: Int?
        let tags, dietFlags, steps: [String]
        let macros: Macros?
        let ingredients: [Ingredient]
    }
    struct Macros: Encodable { let calories, protein, carbs, fat: Double?; let estimated: Bool }
    struct Ingredient: Encodable { let raw: String; let name: String?; let quantity: Double?; let unit: String? }

    init(_ r: PlatesResponse) {
        deckTitle = r.deckTitle
        nextPageToken = r.nextPageToken
        recipes = r.recipes.map { c in
            Card(id: c.id, title: c.title, source: c.source,
                 imageURL: c.imageURL, sourceURL: c.sourceURL, creator: c.creator,
                 license: c.license, summary: c.summary, difficulty: c.difficulty,
                 nutritionNote: c.nutritionNote,
                 servings: c.servings, prepMinutes: c.prepMinutes, cookMinutes: c.cookMinutes,
                 tags: c.tags, dietFlags: c.dietFlags, steps: c.steps,
                 macros: c.macros.map { Macros(calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat, estimated: $0.estimated) },
                 ingredients: c.ingredients.map { Ingredient(raw: $0.raw, name: $0.name, quantity: $0.quantity, unit: $0.unit) })
        }
    }
}
