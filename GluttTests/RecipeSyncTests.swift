import SwiftData
import XCTest
@testable import Glutt

/// Records what the engine sends and replays what a server would answer.
/// Everything sync does is a plain function over this, so the whole feature is
/// testable without a network.
final class FakeSyncBackend: SyncBackend, @unchecked Sendable {
    var serverRecipes: [RemoteRecipe] = []
    var serverStates: [RemoteUserState] = []
    var serverDocuments: [String: Data] = [:]
    var serverImages: [String: Data] = [:]

    private(set) var upserted: [[RemoteRecipeUpsert]] = []
    private(set) var deletedIDs: [UUID] = []
    private(set) var upsertedStates: [RemoteUserState] = []
    var putDocuments: [String: Data] = [:]
    private(set) var uploadedImagePaths: [String] = []

    var upsertError: Error?
    var uploadError: Error?
    var downloadError: Error?

    var allUpserted: [RemoteRecipeUpsert] { upserted.flatMap { $0 } }

    func fetchRecipes(userID: UUID, since watermark: String?, limit: Int) async throws -> [RemoteRecipe] {
        let ordered = serverRecipes.sorted { $0.updatedAt < $1.updatedAt }
        guard let watermark, !watermark.isEmpty else { return Array(ordered.prefix(limit)) }
        return Array(ordered.filter { $0.updatedAt > watermark }.prefix(limit))
    }

    func upsertRecipes(_ rows: [RemoteRecipeUpsert]) async throws {
        if let upsertError { throw upsertError }
        upserted.append(rows)
    }

    func markRecipesDeleted(ids: [UUID], userID: UUID, at date: Date) async throws {
        deletedIDs.append(contentsOf: ids)
    }

    func fetchUserStates(userID: UUID) async throws -> [RemoteUserState] { serverStates }

    func upsertUserStates(_ rows: [RemoteUserState], userID: UUID) async throws {
        upsertedStates.append(contentsOf: rows)
    }

    func fetchDocument(userID: UUID, kind: String) async throws -> Data? { serverDocuments[kind] }

    func putDocument(userID: UUID, kind: String, body: Data) async throws {
        putDocuments[kind] = body
    }

    func uploadImage(path: String, data: Data) async throws {
        if let uploadError { throw uploadError }
        serverImages[path] = data
        uploadedImagePaths.append(path)
    }

    func downloadImage(path: String) async throws -> Data {
        if let downloadError { throw downloadError }
        guard let data = serverImages[path] else {
            throw NSError(domain: "fake", code: 404)
        }
        return data
    }
}

@MainActor
final class RecipeSyncTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
            PantryItem.self, GroceryItem.self, KitchenTool.self, UserPrefs.self,
            SyncTombstone.self,
        ])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        RecipeSync.setWatermark(nil, userID: userID)
        KitchenSync.clearChangeTracking(userID: userID)
        RecipeStateSync.clearChangeTracking(userID: userID)
        RecipeImageSync.resetFailedPathsForTesting()
    }

    override func tearDownWithError() throws {
        RecipeSync.setWatermark(nil, userID: userID)
        KitchenSync.clearChangeTracking(userID: userID)
        RecipeStateSync.clearChangeTracking(userID: userID)
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Identity

    func testNewRecipeGetsAnIdentityWithoutTouchingEveryInsertSite() {
        let recipe = Recipe(title: "Harissa Chicken")
        XCTAssertNotNil(recipe.remoteID)
    }

    func testBackfillGivesEveryPreExistingRecipeADistinctIdentity() throws {
        let recipes = (0 ..< 3).map { Recipe(title: "Dish \($0)") }
        for recipe in recipes {
            recipe.remoteID = nil          // as a row migrated from before the feature
            context.insert(recipe)
        }
        try context.save()

        XCTAssertEqual(RecipeIdentity.backfill(in: context), 3)
        let ids = recipes.compactMap(\.remoteID)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids).count, 3, "a shared default UUID is the failure this exists to avoid")
        XCTAssertEqual(RecipeIdentity.backfill(in: context), 0, "second launch finds nothing")
    }

    func testBundledContentIsNotTheUsersToBackUp() {
        let mine = Recipe(title: "My Ragu")
        let lesson = Recipe(title: "Fry an egg", tags: [CookingBasics.tag])
        let chefDish = Recipe(title: "Signature Dish", tags: ["\(ChefContent.tagPrefix)someone"])

        XCTAssertTrue(RecipeIdentity.isSyncable(mine))
        XCTAssertFalse(RecipeIdentity.isSyncable(lesson))
        XCTAssertFalse(RecipeIdentity.isSyncable(chefDish))
    }

    func testDeletingWritesATombstoneOnlyForTheUsersOwnRecipes() throws {
        let mine = Recipe(title: "My Ragu")
        let lesson = Recipe(title: "Fry an egg", tags: [CookingBasics.tag])
        context.insert(mine)
        context.insert(lesson)
        try context.save()

        RecipeIdentity.recordDeletion(of: mine, in: context)
        RecipeIdentity.recordDeletion(of: lesson, in: context)
        try context.save()

        let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones.first?.remoteID, mine.remoteID)
    }

    // MARK: - Hashing

    func testHashIsStableAcrossRepeatedReads() {
        let recipe = makeRecipe(title: "Lemon Chicken")
        XCTAssertEqual(RecipeSyncBody.hash(of: recipe), RecipeSyncBody.hash(of: recipe))
    }

    func testHashMovesForEveryFieldThatTravels() {
        let recipe = makeRecipe(title: "Lemon Chicken")

        var before = RecipeSyncBody.hash(of: recipe)
        recipe.title = "Lemon Chicken, better"
        XCTAssertNotEqual(RecipeSyncBody.hash(of: recipe), before, "a rename must push")

        // The one that motivates hashing over dirty flags: the detail screen
        // toggles this inline, with no save hook anywhere near it.
        before = RecipeSyncBody.hash(of: recipe)
        recipe.isFavorite.toggle()
        XCTAssertNotEqual(RecipeSyncBody.hash(of: recipe), before)

        before = RecipeSyncBody.hash(of: recipe)
        recipe.steps.append(RecipeStep(index: 9, text: "Rest for five minutes"))
        XCTAssertNotEqual(RecipeSyncBody.hash(of: recipe), before)

        before = RecipeSyncBody.hash(of: recipe)
        recipe.rating = 4
        XCTAssertNotEqual(RecipeSyncBody.hash(of: recipe), before)
    }

    func testHashIgnoresTheOrderSwiftDataHandsBackRelationships() {
        let recipe = makeRecipe(title: "Lemon Chicken")
        let weeknights = RecipeCollection(name: "Weeknights")
        let favourites = RecipeCollection(name: "Favourites")
        context.insert(weeknights)
        context.insert(favourites)

        recipe.collections = [weeknights, favourites]
        let one = RecipeSyncBody.hash(of: recipe)
        recipe.collections = [favourites, weeknights]
        XCTAssertEqual(RecipeSyncBody.hash(of: recipe), one,
                       "a to-many has no defined order; a wobbling hash would re-push forever")
    }

    func testCaptionIsCappedRatherThanCarryingAWholeBlogPost() {
        let recipe = makeRecipe(title: "Long Caption")
        recipe.sourceCaption = String(repeating: "a", count: 5000)
        let document = RecipeSyncBody.document(of: recipe)
        XCTAssertEqual(document.sourceCaption?.count, RecipeSyncBody.captionLimit)
    }

    // MARK: - Round trip

    func testARecipeSurvivesTheRoundTripIntact() throws {
        let original = makeRecipe(title: "Harissa Chicken Skillet")
        original.summary = "Weeknight, one pan."
        original.notes = "Less harissa next time."
        original.rating = 5
        original.isFavorite = true
        original.difficulty = .intermediate
        original.calories = 540
        original.proteinGrams = 32
        original.sourceCreator = "Someone"
        original.sourceURL = "https://example.com/harissa"
        original.sourcePlatform = .website
        original.importedAt = Date(timeIntervalSince1970: 1_700_000_000)
        original.importConfidence = 0.82
        let collection = RecipeCollection(name: "Weeknights")
        context.insert(collection)
        original.collections = [collection]
        try context.save()

        let snapshot = RecipeSyncBody.snapshot(of: original)
        // Through JSON, because that is what actually happens.
        let wire = try RecipeSyncBody.makeEncoder(sortedKeys: true).encode(snapshot.body)
        let decoded = try RecipeSyncBody.makeDecoder().decode(RecipeSyncBody.Document.self, from: wire)

        let restored = Recipe(title: "placeholder")
        context.insert(restored)
        var collections: [String: RecipeCollection] = [:]
        RecipeSyncBody.apply(
            RecipeSyncBody.Snapshot(
                title: snapshot.title,
                imageURL: snapshot.imageURL,
                sourceURL: snapshot.sourceURL,
                sourcePlatform: snapshot.sourcePlatform,
                isFavorite: snapshot.isFavorite,
                body: decoded
            ),
            to: restored,
            in: context,
            collectionsByName: &collections
        )
        try context.save()

        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.summary, original.summary)
        XCTAssertEqual(restored.notes, original.notes)
        XCTAssertEqual(restored.rating, 5)
        XCTAssertTrue(restored.isFavorite)
        XCTAssertEqual(restored.difficulty, .intermediate)
        XCTAssertEqual(restored.calories, 540)
        XCTAssertEqual(restored.sourcePlatform, .website)
        XCTAssertEqual(restored.importedAt?.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(restored.ingredients.count, original.ingredients.count)
        XCTAssertEqual(restored.sortedSteps.map(\.text), original.sortedSteps.map(\.text))
        XCTAssertEqual(restored.collections.map(\.name), ["Weeknights"])
        XCTAssertEqual(RecipeSyncBody.hash(of: restored), RecipeSyncBody.hash(of: original),
                       "a lossy round trip would re-push every recipe on every sweep")
    }

    func testADocumentMissingKeysStillDecodes() throws {
        // A body written by an older or newer build. Failing here would drop the
        // whole recipe, which is the one thing this feature exists to prevent.
        let sparse = Data(#"{"v":1,"title":"ignored"}"#.utf8)
        let document = try RecipeSyncBody.makeDecoder()
            .decode(RecipeSyncBody.Document.self, from: sparse)
        XCTAssertEqual(document.servings, 2)
        XCTAssertTrue(document.ingredients.isEmpty)
        XCTAssertEqual(document.difficulty, Difficulty.beginner.rawValue)
    }

    // MARK: - Matching

    func testMatchingFallsBackFromIdentityToURLToTitle() {
        let byID = makeRecipe(title: "By id")
        let byURL = makeRecipe(title: "By url")
        byURL.sourceURL = "https://example.com/a"
        let byTitle = makeRecipe(title: "  Creamy   Pasta ")
        byTitle.sourceCreator = "Chef Someone"
        let all = [byID, byURL, byTitle]

        XCTAssertIdentical(
            RecipeIdentity.localMatch(forRemoteID: byID.remoteID!, sourceURL: nil,
                                      title: "Something else", sourceCreator: nil, among: all),
            byID
        )
        XCTAssertIdentical(
            RecipeIdentity.localMatch(forRemoteID: UUID(), sourceURL: "https://example.com/a",
                                      title: "Different title", sourceCreator: nil, among: all),
            byURL
        )
        XCTAssertIdentical(
            RecipeIdentity.localMatch(forRemoteID: UUID(), sourceURL: nil,
                                      title: "creamy pasta", sourceCreator: "chef someone", among: all),
            byTitle
        )
        XCTAssertNil(
            RecipeIdentity.localMatch(forRemoteID: UUID(), sourceURL: nil,
                                      title: "Nothing like it", sourceCreator: nil, among: all)
        )
    }

    // MARK: - Push

    func testPushSendsChangedRecipesOnceAndThenGoesQuiet() async throws {
        let backend = FakeSyncBackend()
        let recipe = makeRecipe(title: "Harissa Chicken")
        try context.save()

        let first = try await RecipeSync.push(userID: userID, in: context, backend: backend)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(backend.allUpserted.first?.title, "Harissa Chicken")
        XCTAssertEqual(backend.allUpserted.first?.userID, userID)
        XCTAssertNotNil(recipe.syncedAt)

        let second = try await RecipeSync.push(userID: userID, in: context, backend: backend)
        XCTAssertEqual(second, 0, "an unchanged recipe must not be re-sent")

        recipe.isFavorite = true
        let third = try await RecipeSync.push(userID: userID, in: context, backend: backend)
        XCTAssertEqual(third, 1)
    }

    func testPushLeavesBundledContentAlone() async throws {
        let backend = FakeSyncBackend()
        context.insert(Recipe(title: "Fry an egg", tags: [CookingBasics.tag]))
        context.insert(Recipe(title: "Chef Dish", tags: ["\(ChefContent.tagPrefix)someone"]))
        try context.save()

        let pushed = try await RecipeSync.push(userID: userID, in: context, backend: backend)
        XCTAssertEqual(pushed, 0)
        XCTAssertTrue(backend.allUpserted.isEmpty)
    }

    func testPushSendsTombstonesAndForgetsThemOnceTheyLand() async throws {
        let backend = FakeSyncBackend()
        let deletedID = UUID()
        context.insert(SyncTombstone(remoteID: deletedID))
        try context.save()

        try await RecipeSync.push(userID: userID, in: context, backend: backend)

        XCTAssertEqual(backend.deletedIDs, [deletedID])
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    func testAFailedBatchStaysUnsyncedSoTheNextSweepRetriesIt() async throws {
        let backend = FakeSyncBackend()
        backend.upsertError = NSError(domain: "offline", code: 1)
        let recipe = makeRecipe(title: "Harissa Chicken")
        try context.save()

        do {
            _ = try await RecipeSync.push(userID: userID, in: context, backend: backend)
            XCTFail("expected the push to surface the failure")
        } catch {
            XCTAssertNil(recipe.syncedHash, "an optimistic hash would hide this recipe forever")
        }
    }

    // MARK: - Pull

    func testPullRestoresALibraryOntoAnEmptyPhone() async throws {
        let backend = FakeSyncBackend()
        backend.serverRecipes = [
            remoteRow(title: "Restored One", updatedAt: "2026-07-30T10:00:00Z"),
            remoteRow(title: "Restored Two", updatedAt: "2026-07-30T11:00:00Z"),
        ]

        let applied = try await RecipeSync.pull(userID: userID, in: context, backend: backend)

        XCTAssertEqual(applied, 2)
        let titles = try context.fetch(FetchDescriptor<Recipe>()).map(\.title).sorted()
        XCTAssertEqual(titles, ["Restored One", "Restored Two"])
        XCTAssertEqual(RecipeSync.watermark(userID: userID), "2026-07-30T11:00:00Z")
    }

    func testPulledRecipesArriveAlreadySyncedSoTheyAreNotPushedStraightBack() async throws {
        let backend = FakeSyncBackend()
        backend.serverRecipes = [remoteRow(title: "Restored", updatedAt: "2026-07-30T10:00:00Z")]

        try await RecipeSync.pull(userID: userID, in: context, backend: backend)
        let pushed = try await RecipeSync.push(userID: userID, in: context, backend: backend)

        XCTAssertEqual(pushed, 0)
    }

    func testPullAdoptsTheServerIdentityOntoARecipeMatchedByURL() async throws {
        // The one-time migration case: this phone pushed nothing, and a second
        // device restored the same recipe under an id minted elsewhere.
        let backend = FakeSyncBackend()
        let local = makeRecipe(title: "Harissa Chicken")
        local.sourceURL = "https://example.com/harissa"
        try context.save()

        let serverID = UUID()
        backend.serverRecipes = [
            remoteRow(id: serverID, title: "Harissa Chicken",
                      sourceURL: "https://example.com/harissa", updatedAt: "2026-07-30T10:00:00Z"),
        ]

        try await RecipeSync.pull(userID: userID, in: context, backend: backend)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Recipe>()).count, 1, "no duplicate library")
        XCTAssertEqual(local.remoteID, serverID)
    }

    func testATombstoneRowRemovesTheLocalRecipe() async throws {
        let backend = FakeSyncBackend()
        let local = makeRecipe(title: "Deleted Elsewhere")
        try context.save()

        backend.serverRecipes = [
            remoteRow(id: local.remoteID!, title: "Deleted Elsewhere",
                      updatedAt: "2026-07-30T10:00:00Z", deletedAt: "2026-07-30T10:00:00Z"),
        ]
        try await RecipeSync.pull(userID: userID, in: context, backend: backend)

        XCTAssertTrue(try context.fetch(FetchDescriptor<Recipe>()).isEmpty)
    }

    func testPullDoesNotOverwriteAnEditThatHasNotBeenSentYet() async throws {
        let backend = FakeSyncBackend()
        let local = makeRecipe(title: "Harissa Chicken")
        try context.save()
        try await RecipeSync.push(userID: userID, in: context, backend: backend)

        // The user renames it; the server still holds the old title.
        local.title = "Harissa Chicken, my way"
        backend.serverRecipes = [
            remoteRow(id: local.remoteID!, title: "Harissa Chicken", updatedAt: "2026-07-30T10:00:00Z"),
        ]

        try await RecipeSync.pull(userID: userID, in: context, backend: backend)

        XCTAssertEqual(local.title, "Harissa Chicken, my way")
    }

    func testMyVersionChainsSurviveTheRestore() async throws {
        let backend = FakeSyncBackend()
        let parentID = UUID()
        let childID = UUID()
        var childBody = RecipeSyncBody.Document()
        childBody.parentRemoteID = parentID
        childBody.versionLabel = "pantry version"

        backend.serverRecipes = [
            // Child first on purpose: applying in row order would lose the link.
            remoteRow(id: childID, title: "Ragu, pantry version",
                      updatedAt: "2026-07-30T10:00:00Z", body: childBody),
            remoteRow(id: parentID, title: "Ragu", updatedAt: "2026-07-30T11:00:00Z"),
        ]

        try await RecipeSync.pull(userID: userID, in: context, backend: backend)

        let all = try context.fetch(FetchDescriptor<Recipe>())
        let child = all.first { $0.remoteID == childID }
        let parent = all.first { $0.remoteID == parentID }
        XCTAssertNotNil(parent)
        XCTAssertIdentical(child?.parentRecipe, parent)
    }

    // MARK: - Sign out

    func testSigningOutTakesTheLibraryButLeavesWhatShipsInTheApp() throws {
        let mine = makeRecipe(title: "My Ragu")
        let lesson = Recipe(title: "Fry an egg", tags: [CookingBasics.tag])
        context.insert(lesson)
        context.insert(PantryItem(name: "eggs"))
        context.insert(SyncTombstone(remoteID: UUID()))
        try context.save()
        RecipeSync.setWatermark("2026-07-30T10:00:00Z", userID: userID)

        RecipeSync.purgeLocalUserData(userID: userID, in: context)

        let remaining = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(remaining.map(\.title), ["Fry an egg"])
        XCTAssertFalse(remaining.contains { $0 === mine })
        XCTAssertTrue(try context.fetch(FetchDescriptor<PantryItem>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
        XCTAssertNil(RecipeSync.watermark(userID: userID))
    }

    func testSigningOutDoesNotTombstoneTheLibraryItJustLeftOnTheServer() async throws {
        let backend = FakeSyncBackend()
        _ = makeRecipe(title: "My Ragu")
        try context.save()
        try await RecipeSync.push(userID: userID, in: context, backend: backend)

        RecipeSync.purgeLocalUserData(userID: userID, in: context)
        try await RecipeSync.push(userID: userID, in: context, backend: backend)

        XCTAssertTrue(backend.deletedIDs.isEmpty, "sign out is a local cleanup, not a delete")
    }

    // MARK: - Images

    func testAPhotoIsUploadedOnceAndThenPushedAsAPath() async throws {
        let backend = FakeSyncBackend()
        let recipe = makeRecipe(title: "With a photo")
        recipe.imageData = Data("jpeg-bytes".utf8)
        try context.save()
        try await RecipeSync.push(userID: userID, in: context, backend: backend)

        let uploaded = await RecipeImageSync.uploadSweep(userID: userID, in: context, backend: backend)

        XCTAssertEqual(uploaded, 1)
        XCTAssertEqual(recipe.remoteImagePath,
                       RecipeImageSync.storagePath(userID: userID, recipeID: recipe.remoteID!))
        // The path lives in a promoted column, outside the hashed body, so the
        // upload has to arrange its own push.
        let pushed = try await RecipeSync.push(userID: userID, in: context, backend: backend)
        XCTAssertEqual(pushed, 1)
        XCTAssertEqual(backend.allUpserted.last?.imagePath, recipe.remoteImagePath)

        let again = await RecipeImageSync.uploadSweep(userID: userID, in: context, backend: backend)
        XCTAssertEqual(again, 0)
    }

    func testARestoredRecipeGetsItsPhotoBack() async throws {
        let backend = FakeSyncBackend()
        let recipeID = UUID()
        let path = RecipeImageSync.storagePath(userID: userID, recipeID: recipeID)
        backend.serverImages[path] = Data("jpeg-bytes".utf8)
        backend.serverRecipes = [
            remoteRow(id: recipeID, title: "Restored", updatedAt: "2026-07-30T10:00:00Z",
                      imagePath: path),
        ]

        try await RecipeSync.pull(userID: userID, in: context, backend: backend)
        let downloaded = await RecipeImageSync.downloadSweep(in: context, backend: backend)

        XCTAssertEqual(downloaded, 1)
        let restored = try context.fetch(FetchDescriptor<Recipe>()).first
        XCTAssertEqual(restored?.imageData, Data("jpeg-bytes".utf8))
    }

    func testSignOutUploadsEveryPhotoRatherThanTheUsualFew() async throws {
        let backend = FakeSyncBackend()
        let count = RecipeImageSync.uploadsPerSweep + 3
        for index in 0 ..< count {
            let recipe = makeRecipe(title: "Photo \(index)")
            recipe.imageData = Data("jpeg-\(index)".utf8)
        }
        try context.save()

        // The routine sweep drips.
        let dripped = await RecipeImageSync.uploadSweep(userID: userID, in: context, backend: backend)
        XCTAssertEqual(dripped, RecipeImageSync.uploadsPerSweep)

        // Sign out cannot: these bytes are about to be deleted off the phone.
        let flushed = try await RecipeImageSync.uploadAll(userID: userID, in: context, backend: backend)
        XCTAssertEqual(flushed, 3)
        XCTAssertEqual(backend.uploadedImagePaths.count, count)
    }

    func testAFailedPhotoUploadStopsTheSignOutRatherThanLosingIt() async throws {
        let backend = FakeSyncBackend()
        backend.uploadError = NSError(domain: "offline", code: 1)
        let recipe = makeRecipe(title: "Only copy")
        recipe.imageData = Data("jpeg-bytes".utf8)
        try context.save()

        do {
            _ = try await RecipeImageSync.uploadAll(userID: userID, in: context, backend: backend)
            XCTFail("expected the failure to surface so sign out can offer to stay")
        } catch {
            XCTAssertNil(recipe.remoteImagePath)
        }
    }

    func testAMissingObjectIsNotRetriedAllSweepLong() async throws {
        let backend = FakeSyncBackend()
        backend.downloadError = NSError(domain: "gone", code: 404)
        let recipe = makeRecipe(title: "Restored")
        recipe.remoteImagePath = "recipes/x/y.jpg"
        try context.save()

        let downloaded = await RecipeImageSync.downloadSweep(in: context, backend: backend)

        XCTAssertEqual(downloaded, 0)
        XCTAssertNil(recipe.imageData, "imageURL is still there as the free fallback")
    }

    // MARK: - Bundled content state

    func testHeartsOnBundledContentTravelWithoutCopyingTheRecipe() async throws {
        let backend = FakeSyncBackend()
        let lesson = Recipe(title: "Fry an egg", tags: [CookingBasics.tag])
        lesson.isFavorite = true
        lesson.rating = 5
        context.insert(lesson)
        try context.save()

        try await RecipeStateSync.sync(userID: userID, in: context, backend: backend)

        XCTAssertEqual(backend.upsertedStates.count, 1)
        XCTAssertEqual(backend.upsertedStates.first?.contentKey, "basics:fry-an-egg")
        XCTAssertEqual(backend.upsertedStates.first?.rating, 5)
        XCTAssertTrue(backend.allUpserted.isEmpty, "the dish itself ships in the binary")
    }

    func testAHeartFromAnotherPhoneLandsOnTheLocalCopy() async throws {
        let backend = FakeSyncBackend()
        let lesson = Recipe(title: "Fry an egg", tags: [CookingBasics.tag])
        context.insert(lesson)
        try context.save()
        backend.serverStates = [
            RemoteUserState(contentKey: "basics:fry-an-egg", isFavorite: true, rating: 4, notes: nil),
        ]

        try await RecipeStateSync.sync(userID: userID, in: context, backend: backend)

        XCTAssertTrue(lesson.isFavorite)
        XCTAssertEqual(lesson.rating, 4)
        XCTAssertTrue(backend.upsertedStates.isEmpty, "already in agreement, nothing to say")
    }

    func testUnheartingReachesTheServerRatherThanBeingSkippedAsADefault() async throws {
        let backend = FakeSyncBackend()
        let lesson = Recipe(title: "Fry an egg", tags: [CookingBasics.tag])
        context.insert(lesson)
        try context.save()
        backend.serverStates = [
            RemoteUserState(contentKey: "basics:fry-an-egg", isFavorite: true, rating: nil, notes: nil),
        ]

        // Pull turns it on; the user turns it back off before the next sweep.
        try await RecipeStateSync.sync(userID: userID, in: context, backend: backend)
        lesson.isFavorite = false
        try await RecipeStateSync.sync(userID: userID, in: context, backend: backend)

        XCTAssertEqual(backend.upsertedStates.last?.contentKey, "basics:fry-an-egg")
        XCTAssertEqual(backend.upsertedStates.last?.isFavorite, false)
    }

    func testContentKeysDistinguishDishesByTheSameChef() {
        let one = Recipe(title: "Chipotle Chicken Bowl", tags: ["\(ChefContent.tagPrefix)someone"])
        let two = Recipe(title: "Green Shakshuka", tags: ["\(ChefContent.tagPrefix)someone"])
        XCTAssertEqual(RecipeStateSync.contentKey(for: one), "chef:someone:chipotle-chicken-bowl")
        XCTAssertNotEqual(RecipeStateSync.contentKey(for: one), RecipeStateSync.contentKey(for: two))
        XCTAssertNil(RecipeStateSync.contentKey(for: Recipe(title: "Mine")))
    }

    // MARK: - Kitchen and prefs

    func testTheKitchenTravelsAsOneDocument() async throws {
        let backend = FakeSyncBackend()
        let pantry = PantryItem(name: "Eggs", category: .dairy, roughQuantity: .half)
        context.insert(pantry)
        context.insert(GroceryItem(name: "Olive oil", quantityText: "1 bottle"))
        context.insert(KitchenTool(name: "Cast iron skillet", category: "Cookware"))
        try context.save()

        try await KitchenSync.sync(userID: userID, in: context, backend: backend)
        let sent = try XCTUnwrap(backend.putDocuments["kitchen"])
        let document = try RecipeSyncBody.makeDecoder()
            .decode(KitchenSync.KitchenDocument.self, from: sent)

        XCTAssertEqual(document.pantry.map(\.name), ["Eggs"])
        XCTAssertEqual(document.pantry.first?.quantity, RoughQuantity.half.rawValue)
        XCTAssertEqual(document.groceries.map(\.name), ["Olive oil"])
        XCTAssertEqual(document.tools.map(\.name), ["Cast iron skillet"])
    }

    func testAnUnchangedKitchenIsNotSentTwice() async throws {
        let backend = FakeSyncBackend()
        context.insert(PantryItem(name: "Eggs"))
        try context.save()

        try await KitchenSync.sync(userID: userID, in: context, backend: backend)
        let firstSend = backend.putDocuments["kitchen"]
        backend.serverDocuments["kitchen"] = firstSend
        backend.putDocuments.removeValue(forKey: "kitchen")

        try await KitchenSync.sync(userID: userID, in: context, backend: backend)
        XCTAssertNil(backend.putDocuments["kitchen"])
    }

    func testTheKitchenComesBackOnANewPhone() async throws {
        let backend = FakeSyncBackend()
        let document = KitchenSync.KitchenDocument(
            pantry: [KitchenSync.Pantry(name: "Eggs", category: "dairy", quantity: "half",
                                        location: "fridge", exact: "12", useSoon: nil)],
            groceries: [],
            tools: [KitchenSync.Tool(name: "Whisk", category: "Tools")]
        )
        backend.serverDocuments["kitchen"] = try RecipeSyncBody
            .makeEncoder(sortedKeys: true).encode(document)

        try await KitchenSync.sync(userID: userID, in: context, backend: backend)

        let pantry = try context.fetch(FetchDescriptor<PantryItem>())
        XCTAssertEqual(pantry.map(\.name), ["Eggs"])
        XCTAssertEqual(pantry.first?.roughQuantity, .half)
        XCTAssertEqual(pantry.first?.exactQuantity, "12")
        XCTAssertEqual(try context.fetch(FetchDescriptor<KitchenTool>()).map(\.name), ["Whisk"])
    }

    func testFoodRulesTravelButOnboardingFlagsDoNot() async throws {
        let backend = FakeSyncBackend()
        let prefs = UserPrefs.current(in: context)
        prefs.dietaryRules = [.vegetarian]
        prefs.allergies = ["peanuts"]
        prefs.hasCompletedOnboarding = true
        try context.save()

        try await KitchenSync.sync(userID: userID, in: context, backend: backend)
        let sent = try XCTUnwrap(backend.putDocuments["prefs"])
        let document = try RecipeSyncBody.makeDecoder()
            .decode(KitchenSync.PrefsDocument.self, from: sent)

        XCTAssertEqual(document.dietaryRules, [DietaryRule.vegetarian.rawValue])
        XCTAssertEqual(document.allergies, ["peanuts"])
        XCTAssertFalse(String(data: sent, encoding: .utf8)!.contains("hasCompletedOnboarding"),
                       "that describes the install, not the person")
    }

    // MARK: - Helpers

    @discardableResult
    private func makeRecipe(title: String) -> Recipe {
        let recipe = Recipe(title: title, servings: 2, prepMinutes: 10, cookMinutes: 25)
        recipe.ingredients = [
            RecipeIngredient(name: "chicken thighs", quantity: 500, unit: "g", sortIndex: 0),
            RecipeIngredient(name: "harissa", quantity: 2, unit: "tbsp", sortIndex: 1),
        ]
        recipe.steps = [
            RecipeStep(index: 0, text: "Rub the chicken"),
            RecipeStep(index: 1, text: "Roast for 25 minutes", durationSeconds: 1500),
        ]
        context.insert(recipe)
        return recipe
    }

    private func remoteRow(
        id: UUID = UUID(),
        title: String,
        sourceURL: String? = nil,
        updatedAt: String,
        deletedAt: String? = nil,
        imagePath: String? = nil,
        body: RecipeSyncBody.Document = RecipeSyncBody.Document()
    ) -> RemoteRecipe {
        let json: [String: Any?] = [
            "id": id.uuidString,
            "updated_at": updatedAt,
            "deleted_at": deletedAt,
            "title": title,
            "image_url": nil,
            "image_path": imagePath,
            "source_url": sourceURL,
            "source_platform": SourcePlatform.manual.rawValue,
            "is_favorite": false,
            "body": try! JSONSerialization.jsonObject(
                with: RecipeSyncBody.makeEncoder(sortedKeys: true).encode(body)
            ),
        ]
        let data = try! JSONSerialization.data(
            withJSONObject: json.compactMapValues { $0 }
        )
        return try! RecipeSyncBody.makeDecoder().decode(RemoteRecipe.self, from: data)
    }
}
