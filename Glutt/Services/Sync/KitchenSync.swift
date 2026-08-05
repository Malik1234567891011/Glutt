import Foundation
import SwiftData

/// The Kitchen and the food rules, as one small jsonb document each.
///
/// Small, genuinely valuable on a new phone (nobody wants to retype their
/// pantry), and never queried server-side — which is exactly the shape that
/// deserves a document rather than tables of its own.
///
/// Cook history and Polly's logs are deliberately not here: per-device, high
/// volume, low restore value.
@MainActor
enum KitchenSync {

    /// `nonisolated` because the document structs below default to it, and they
    /// are decoded off the main actor by the Postgrest client.
    nonisolated static let version = 1

    // MARK: - Documents

    struct KitchenDocument: Codable, Equatable {
        var v: Int = KitchenSync.version
        var pantry: [Pantry] = []
        var groceries: [Grocery] = []
        var tools: [Tool] = []

        init(v: Int = KitchenSync.version, pantry: [Pantry] = [], groceries: [Grocery] = [], tools: [Tool] = []) {
            self.v = v
            self.pantry = pantry
            self.groceries = groceries
            self.tools = tools
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            v = try box.decodeIfPresent(Int.self, forKey: .v) ?? KitchenSync.version
            pantry = try box.decodeIfPresent([Pantry].self, forKey: .pantry) ?? []
            groceries = try box.decodeIfPresent([Grocery].self, forKey: .groceries) ?? []
            tools = try box.decodeIfPresent([Tool].self, forKey: .tools) ?? []
        }

        var isEmpty: Bool { pantry.isEmpty && groceries.isEmpty && tools.isEmpty }
    }

    struct Pantry: Codable, Equatable {
        var name: String
        var category: String
        var quantity: String
        var location: String
        var exact: String?
        /// ISO-8601, see `SyncTime`.
        var useSoon: String?
    }

    struct Grocery: Codable, Equatable {
        var name: String
        var qty: Double?
        var unit: String?
        var qtyText: String?
        var category: String
        var checked: Bool
        var optional: Bool
        var hint: String?
        var sources: [String]
    }

    struct Tool: Codable, Equatable {
        var name: String
        var category: String
    }

    struct PrefsDocument: Codable, Equatable {
        var v: Int = KitchenSync.version
        var displayName: String?
        var goals: [String] = []
        var dietaryRules: [String] = []
        var allergies: [String] = []
        var dislikedIngredients: [String] = []
        var nutritionMode: String?
        var dailyCalorieGoal: Int?
        var dailyProteinGoal: Int?
        var tasteProfile: [String] = []

        init(
            v: Int = KitchenSync.version,
            displayName: String? = nil,
            goals: [String] = [],
            dietaryRules: [String] = [],
            allergies: [String] = [],
            dislikedIngredients: [String] = [],
            nutritionMode: String? = nil,
            dailyCalorieGoal: Int? = nil,
            dailyProteinGoal: Int? = nil,
            tasteProfile: [String] = []
        ) {
            self.v = v
            self.displayName = displayName
            self.goals = goals
            self.dietaryRules = dietaryRules
            self.allergies = allergies
            self.dislikedIngredients = dislikedIngredients
            self.nutritionMode = nutritionMode
            self.dailyCalorieGoal = dailyCalorieGoal
            self.dailyProteinGoal = dailyProteinGoal
            self.tasteProfile = tasteProfile
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            v = try box.decodeIfPresent(Int.self, forKey: .v) ?? KitchenSync.version
            displayName = try box.decodeIfPresent(String.self, forKey: .displayName)
            goals = try box.decodeIfPresent([String].self, forKey: .goals) ?? []
            dietaryRules = try box.decodeIfPresent([String].self, forKey: .dietaryRules) ?? []
            allergies = try box.decodeIfPresent([String].self, forKey: .allergies) ?? []
            dislikedIngredients = try box.decodeIfPresent([String].self, forKey: .dislikedIngredients) ?? []
            nutritionMode = try box.decodeIfPresent(String.self, forKey: .nutritionMode)
            dailyCalorieGoal = try box.decodeIfPresent(Int.self, forKey: .dailyCalorieGoal)
            dailyProteinGoal = try box.decodeIfPresent(Int.self, forKey: .dailyProteinGoal)
            tasteProfile = try box.decodeIfPresent([String].self, forKey: .tasteProfile) ?? []
        }
    }

    // MARK: - Sweep

    static func sync(
        userID: UUID,
        in context: ModelContext,
        backend: any SyncBackend = SupabaseSyncBackend()
    ) async throws {
        try await syncDocument(
            kind: "kitchen",
            userID: userID,
            backend: backend,
            local: { readKitchen(in: context) },
            apply: { document in writeKitchen(document, in: context) },
            isWorthCreating: { !$0.isEmpty }
        )
        try await syncDocument(
            kind: "prefs",
            userID: userID,
            backend: backend,
            local: { readPrefs(in: context) },
            apply: { document in writePrefs(document, in: context) },
            isWorthCreating: { _ in true }
        )
    }

    /// Pull, then push if the local copy has moved since it was last sent.
    ///
    /// The `lastSentHash` check is what stops the pull from eating fresh local
    /// edits: a local document that differs from what this device last pushed is
    /// newer than anything the server can be holding for it, so it wins and gets
    /// sent. Same rule the recipe sweep uses, for the same reason.
    ///
    /// A **nil** hash is the opposite case and has to be read as such: this
    /// device has never synced this document, so it is a restore, and the server
    /// wins. Treating nil as "local edits" would leave a new phone staring at an
    /// empty Kitchen and then overwrite the real one with it.
    private static func syncDocument<Document: Codable & Equatable>(
        kind: String,
        userID: UUID,
        backend: any SyncBackend,
        local: () -> Document,
        apply: (Document) -> Void,
        isWorthCreating: (Document) -> Bool
    ) async throws {
        let encoder = RecipeSyncBody.makeEncoder(sortedKeys: true)
        let before = local()
        let beforeData = try encoder.encode(before)
        let beforeHash = hashString(beforeData)
        let lastSent = lastSentHash(kind: kind, userID: userID)
        let hasLocalEdits = lastSent != nil && beforeHash != lastSent

        if !hasLocalEdits,
           let remoteData = try await backend.fetchDocument(userID: userID, kind: kind),
           let remote = try? RecipeSyncBody.makeDecoder().decode(Document.self, from: remoteData) {
            if remote != before { apply(remote) }
            setLastSentHash(hashString(try encoder.encode(remote)), kind: kind, userID: userID)
            return
        }

        guard beforeHash != lastSent else { return }
        // `isWorthCreating` gates only the *first* write, so an empty Kitchen on
        // a phone that has never had one stays out of the database. Once a
        // document exists, emptying it is an edit like any other and has to
        // reach the server, or clearing the pantry here would never clear it
        // anywhere else.
        guard lastSent != nil || isWorthCreating(before) else { return }
        try await backend.putDocument(userID: userID, kind: kind, body: beforeData)
        setLastSentHash(beforeHash, kind: kind, userID: userID)
    }

    // MARK: - Kitchen

    static func readKitchen(in context: ModelContext) -> KitchenDocument {
        let pantry = ((try? context.fetch(FetchDescriptor<PantryItem>())) ?? [])
            .sorted { $0.canonicalName < $1.canonicalName }
            .map {
                Pantry(
                    name: $0.name,
                    category: $0.category.rawValue,
                    quantity: $0.roughQuantity.rawValue,
                    location: $0.location.rawValue,
                    exact: $0.exactQuantity,
                    useSoon: $0.useSoonDate.map(SyncTime.string(from:))
                )
            }
        let groceries = ((try? context.fetch(FetchDescriptor<GroceryItem>())) ?? [])
            .sorted { $0.canonicalName < $1.canonicalName }
            .map {
                Grocery(
                    name: $0.name,
                    qty: $0.quantity,
                    unit: $0.unit,
                    qtyText: $0.quantityText,
                    category: $0.category.rawValue,
                    checked: $0.isChecked,
                    optional: $0.isOptional,
                    hint: $0.substitutionHint,
                    sources: $0.sourceRecipeTitles
                )
            }
        let tools = ((try? context.fetch(FetchDescriptor<KitchenTool>())) ?? [])
            .sorted { $0.canonicalName < $1.canonicalName }
            .map { Tool(name: $0.name, category: $0.category) }
        return KitchenDocument(pantry: pantry, groceries: groceries, tools: tools)
    }

    /// Replaces the Kitchen wholesale. A document is one value — merging item by
    /// item would need per-item identity the Kitchen models do not have, and
    /// would resurrect anything the user deleted on the other phone.
    static func writeKitchen(_ document: KitchenDocument, in context: ModelContext) {
        for item in (try? context.fetch(FetchDescriptor<PantryItem>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<GroceryItem>())) ?? [] { context.delete(item) }
        for tool in (try? context.fetch(FetchDescriptor<KitchenTool>())) ?? [] { context.delete(tool) }

        for entry in document.pantry {
            let item = PantryItem(
                name: entry.name,
                category: GroceryCategory(rawValue: entry.category) ?? .other,
                roughQuantity: RoughQuantity(rawValue: entry.quantity) ?? .full,
                location: StorageLocation(rawValue: entry.location) ?? .pantry,
                useSoonDate: SyncTime.date(from: entry.useSoon),
                exactQuantity: entry.exact
            )
            context.insert(item)
        }
        for entry in document.groceries {
            let item = GroceryItem(
                name: entry.name,
                quantityText: entry.qtyText,
                category: GroceryCategory(rawValue: entry.category) ?? .other,
                isOptional: entry.optional,
                substitutionHint: entry.hint,
                sourceRecipeTitles: entry.sources
            )
            item.quantity = entry.qty
            item.unit = entry.unit
            item.isChecked = entry.checked
            context.insert(item)
        }
        for entry in document.tools {
            context.insert(KitchenTool(name: entry.name, category: entry.category))
        }
        try? context.save()
    }

    // MARK: - Prefs

    /// Onboarding flags (`hasCompletedOnboarding` and friends) are left out on
    /// purpose: they describe this install, not this person, and restoring a
    /// "already onboarded" onto a fresh phone would skip a flow that has to run.
    static func readPrefs(in context: ModelContext) -> PrefsDocument {
        let prefs = UserPrefs.current(in: context)
        return PrefsDocument(
            displayName: prefs.displayName,
            goals: prefs.goals,
            dietaryRules: prefs.dietaryRules.map(\.rawValue),
            allergies: prefs.allergies,
            dislikedIngredients: prefs.dislikedIngredients,
            nutritionMode: prefs.nutritionMode.rawValue,
            dailyCalorieGoal: prefs.dailyCalorieGoal,
            dailyProteinGoal: prefs.dailyProteinGoal,
            tasteProfile: prefs.tasteProfile
        )
    }

    static func writePrefs(_ document: PrefsDocument, in context: ModelContext) {
        let prefs = UserPrefs.current(in: context)
        prefs.displayName = document.displayName
        prefs.goals = document.goals
        prefs.dietaryRules = document.dietaryRules.compactMap(DietaryRule.init(rawValue:))
        prefs.allergies = document.allergies
        prefs.dislikedIngredients = document.dislikedIngredients
        if let mode = document.nutritionMode.flatMap(NutritionMode.init(rawValue:)) {
            prefs.nutritionMode = mode
        }
        prefs.dailyCalorieGoal = document.dailyCalorieGoal
        prefs.dailyProteinGoal = document.dailyProteinGoal
        prefs.tasteProfile = document.tasteProfile
        try? context.save()
    }

    // MARK: - Change tracking

    static func lastSentKey(kind: String, userID: UUID) -> String {
        "glutt.sync.document.\(kind).\(userID.uuidString)"
    }

    static func lastSentHash(kind: String, userID: UUID) -> String? {
        UserDefaults.standard.string(forKey: lastSentKey(kind: kind, userID: userID))
    }

    static func setLastSentHash(_ hash: String?, kind: String, userID: UUID) {
        let key = lastSentKey(kind: kind, userID: userID)
        if let hash {
            UserDefaults.standard.set(hash, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func clearChangeTracking(userID: UUID) {
        for kind in ["kitchen", "prefs"] {
            setLastSentHash(nil, kind: kind, userID: userID)
        }
    }

    private static func hashString(_ data: Data) -> String {
        RecipeSyncBody.hash(data)
    }
}
