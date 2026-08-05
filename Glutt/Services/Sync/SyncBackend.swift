import Foundation
import Supabase

// MARK: - Wire types

/// A recipe row as it comes back from the server.
///
/// `updatedAt` stays a **string**, deliberately. It is the pull watermark, and
/// the next request sends it back verbatim as a `>` filter — so it never gets
/// parsed, reformatted, or rounded into a value that skips a row.
struct RemoteRecipe: Decodable, Sendable {
    var id: UUID
    var updatedAt: String
    var deletedAt: String?
    var title: String
    var imageURL: String?
    var imagePath: String?
    var sourceURL: String?
    var sourcePlatform: String?
    var isFavorite: Bool
    var body: RecipeSyncBody.Document

    var isDeleted: Bool { deletedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case title
        case imageURL = "image_url"
        case imagePath = "image_path"
        case sourceURL = "source_url"
        case sourcePlatform = "source_platform"
        case isFavorite = "is_favorite"
        case body
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(UUID.self, forKey: .id)
        updatedAt = try box.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        deletedAt = try box.decodeIfPresent(String.self, forKey: .deletedAt)
        title = try box.decodeIfPresent(String.self, forKey: .title) ?? ""
        imageURL = try box.decodeIfPresent(String.self, forKey: .imageURL)
        imagePath = try box.decodeIfPresent(String.self, forKey: .imagePath)
        sourceURL = try box.decodeIfPresent(String.self, forKey: .sourceURL)
        sourcePlatform = try box.decodeIfPresent(String.self, forKey: .sourcePlatform)
        isFavorite = try box.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        body = try box.decodeIfPresent(RecipeSyncBody.Document.self, forKey: .body)
            ?? RecipeSyncBody.Document()
    }
}

struct RemoteRecipeUpsert: Encodable, Sendable {
    var id: UUID
    var userID: UUID
    var title: String
    var imageURL: String?
    var imagePath: String?
    var sourceURL: String?
    var sourcePlatform: String?
    var isFavorite: Bool
    var body: RecipeSyncBody.Document
    /// Always nil from a live push. Sent explicitly so re-creating a recipe that
    /// once carried a tombstone clears it rather than resurrecting a deleted row.
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case imageURL = "image_url"
        case imagePath = "image_path"
        case sourceURL = "source_url"
        case sourcePlatform = "source_platform"
        case isFavorite = "is_favorite"
        case body
        case deletedAt = "deleted_at"
    }
}

struct RemoteUserState: Codable, Sendable {
    var userID: UUID?
    var contentKey: String
    var isFavorite: Bool
    var rating: Int?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case contentKey = "content_key"
        case isFavorite = "is_favorite"
        case rating
        case notes
    }

    init(userID: UUID? = nil, contentKey: String, isFavorite: Bool, rating: Int?, notes: String?) {
        self.userID = userID
        self.contentKey = contentKey
        self.isFavorite = isFavorite
        self.rating = rating
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        userID = try box.decodeIfPresent(UUID.self, forKey: .userID)
        contentKey = try box.decodeIfPresent(String.self, forKey: .contentKey) ?? ""
        isFavorite = try box.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        rating = try box.decodeIfPresent(Int.self, forKey: .rating)
        notes = try box.decodeIfPresent(String.self, forKey: .notes)
    }
}

// MARK: - Seam

/// Everything sync needs from the network, in one protocol so the engine can be
/// tested without one.
///
/// Documents move as raw JSON `Data` rather than as a generic payload: the
/// engine already owns the encoding (it has to, for hashing), and a generic here
/// would only push that knowledge into two places.
protocol SyncBackend: Sendable {
    func fetchRecipes(userID: UUID, since watermark: String?, limit: Int) async throws -> [RemoteRecipe]
    func upsertRecipes(_ rows: [RemoteRecipeUpsert]) async throws
    /// Tombstones a batch. An `update` rather than an upsert because a recipe
    /// that was deleted before it was ever pushed has no row to write, and a row
    /// with no title would violate the schema.
    func markRecipesDeleted(ids: [UUID], userID: UUID, at date: Date) async throws

    func fetchUserStates(userID: UUID) async throws -> [RemoteUserState]
    func upsertUserStates(_ rows: [RemoteUserState], userID: UUID) async throws

    func fetchDocument(userID: UUID, kind: String) async throws -> Data?
    func putDocument(userID: UUID, kind: String, body: Data) async throws

    func uploadImage(path: String, data: Data) async throws
    func downloadImage(path: String) async throws -> Data
}

// MARK: - Supabase

/// The real backend. Every table it touches is RLS-guarded on `auth.uid()`, so
/// the `user_id` values sent here are a convenience for the writer, not the
/// thing that keeps one user out of another's library.
struct SupabaseSyncBackend: SyncBackend {
    static let imageBucket = "recipe-images"

    private var client: SupabaseClient { Backend.client }
    private var decoder: JSONDecoder { RecipeSyncBody.makeDecoder() }

    func fetchRecipes(userID: UUID, since watermark: String?, limit: Int) async throws -> [RemoteRecipe] {
        var query = client
            .from("recipes")
            .select()
            .eq("user_id", value: userID.uuidString)
        if let watermark, !watermark.isEmpty {
            query = query.gt("updated_at", value: watermark)
        }
        let data = try await query
            // Ascending so the last row's `updated_at` is the new watermark,
            // decided by the server rather than by comparing strings here.
            .order("updated_at", ascending: true)
            .limit(limit)
            .execute()
            .data
        return try decoder.decode([RemoteRecipe].self, from: data)
    }

    func upsertRecipes(_ rows: [RemoteRecipeUpsert]) async throws {
        guard !rows.isEmpty else { return }
        try await client
            .from("recipes")
            .upsert(rows, onConflict: "id", returning: .minimal)
            .execute()
    }

    func markRecipesDeleted(ids: [UUID], userID: UUID, at date: Date) async throws {
        guard !ids.isEmpty else { return }
        try await client
            .from("recipes")
            .update(["deleted_at": SyncTime.string(from: date)], returning: .minimal)
            .eq("user_id", value: userID.uuidString)
            .in("id", values: ids.map(\.uuidString))
            .execute()
    }

    func fetchUserStates(userID: UUID) async throws -> [RemoteUserState] {
        let data = try await client
            .from("recipe_user_state")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .data
        return try decoder.decode([RemoteUserState].self, from: data)
    }

    func upsertUserStates(_ rows: [RemoteUserState], userID: UUID) async throws {
        guard !rows.isEmpty else { return }
        let stamped = rows.map {
            RemoteUserState(
                userID: userID,
                contentKey: $0.contentKey,
                isFavorite: $0.isFavorite,
                rating: $0.rating,
                notes: $0.notes
            )
        }
        try await client
            .from("recipe_user_state")
            .upsert(stamped, onConflict: "user_id,content_key", returning: .minimal)
            .execute()
    }

    func fetchDocument(userID: UUID, kind: String) async throws -> Data? {
        let data = try await client
            .from("user_documents")
            .select("body")
            .eq("user_id", value: userID.uuidString)
            .eq("kind", value: kind)
            .limit(1)
            .execute()
            .data
        struct Wrapper: Decodable { let body: AnyJSON }
        guard let wrapper = try decoder.decode([Wrapper].self, from: data).first else { return nil }
        return try RecipeSyncBody.makeEncoder(sortedKeys: false).encode(wrapper.body)
    }

    func putDocument(userID: UUID, kind: String, body: Data) async throws {
        // Round-tripped through `AnyJSON` so the bytes land in the jsonb column
        // as an object. Handing PostgREST a `String` would store the document as
        // a quoted JSON *string* instead — valid jsonb, useless to read back.
        let json = try decoder.decode(AnyJSON.self, from: body)
        struct Row: Encodable {
            let user_id: String
            let kind: String
            let body: AnyJSON
        }
        try await client
            .from("user_documents")
            .upsert(
                Row(user_id: userID.uuidString, kind: kind, body: json),
                onConflict: "user_id,kind",
                returning: .minimal
            )
            .execute()
    }

    func uploadImage(path: String, data: Data) async throws {
        try await client.storage
            .from(Self.imageBucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
    }

    func downloadImage(path: String) async throws -> Data {
        try await client.storage.from(Self.imageBucket).download(path: path)
    }
}
