# Durable Recipe Images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Download each imported recipe's image once, downscale it, and store the bytes in the durable `imageData` field so images survive cache purges and source-URL rot.

**Architecture:** A new `RecipeImageBackfill` service downloads a recipe's `imageURL`, runs it through the existing `ImagePrep` downscaler (1280px / JPEG q0.65), and writes the bytes to `recipe.imageData` (already `@Attribute(.externalStorage)`). A foreground sweep heals existing URL-only recipes; a per-recipe `ensure` call after link import caches new ones promptly. Display (`RecipeImageView`) already prefers `imageData`, so no display code changes.

**Tech Stack:** Swift, SwiftUI, SwiftData (`ModelContext`/`FetchDescriptor`), `URLSession`, existing `ImagePrep` utility. XcodeGen project (`project.yml` is source of truth). XCTest. Build/test via **XcodeBuildMCP** (`build_sim`, `test_sim`) — not raw xcodebuild.

## Global Constraints

- iOS 17+, SwiftUI + SwiftData. Match surrounding code style (existing service `enum` pattern, `ImagePrep`, in-memory `ModelContainer` test pattern).
- Reuse `ImagePrep.prepareForVision(_:maxDimension:)` with `maxDimension: 1280` — do NOT add a new downscaler.
- Never break the UI on failure: a failed/absent download leaves `imageURL` intact so `RecipeImageView`'s `AsyncImage` still renders live; only the local bytes are an upgrade.
- Only cache recipes that need it: `imageData == nil` AND `imageAssetName == nil` AND non-empty `imageURL`. Never re-download recipes that already have bytes or a bundled asset.
- SwiftData model mutation + `save()` happen on the main actor; the network download is awaited (runs off-main via `URLSession`).
- Per-sweep ceiling of **20** recipes; processed **sequentially** (keeps SwiftData main-actor-safe; small images make this fast). An in-memory `failedURLs` set prevents re-hammering dead URLs within one app run.
- After adding a new source/test file, run `xcodegen generate` before building (XcodeGen project).
- Use XcodeBuildMCP for all build/test. Keep every commit building.

---

### Task 1: `RecipeImageBackfill` service + unit tests

The whole caching service, built TDD. One file, one clear responsibility, fully unit-tested with an injected fetcher (no real network in tests).

**Files:**
- Create: `Glutt/Services/Import/RecipeImageBackfill.swift`
- Create: `GluttTests/RecipeImageBackfillTests.swift`

**Interfaces:**
- Consumes: `ImagePrep.prepareForVision(_ data: Data, maxDimension: CGFloat) -> Data?` (existing, in `Glutt/Services/AI/ImagePrep.swift`); `Recipe` (`imageData: Data?`, `imageURL: String?`, `imageAssetName: String?`); `RecipeFactory.make(from:)` + `ImportedRecipeDraft` (tests build recipes this way); SwiftData `ModelContext`/`FetchDescriptor`.
- Produces (used by Task 2):
  - `RecipeImageBackfill.Fetch = (URL) async throws -> Data`
  - `static func needsCaching(_ recipe: Recipe) -> Bool`
  - `static func downloadAndPrepare(from urlString: String, fetch: Fetch = defaultFetch) async -> Data?`
  - `@MainActor static func ensure(for recipe: Recipe, in context: ModelContext, fetch: Fetch = defaultFetch) async`
  - `@MainActor static func sweep(in context: ModelContext, fetch: Fetch = defaultFetch) async`
  - `@MainActor static func resetFailedURLsForTesting()`

- [ ] **Step 1: Write the failing tests**

Create `GluttTests/RecipeImageBackfillTests.swift`:

```swift
import SwiftData
import UIKit
import XCTest
@testable import Glutt

@MainActor
final class RecipeImageBackfillTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Recipe.self, configurations: config)
        context = container.mainContext
        RecipeImageBackfill.resetFailedURLsForTesting()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        RecipeImageBackfill.resetFailedURLsForTesting()
        try await super.tearDown()
    }

    // Build a recipe via the same path imports use.
    private func makeRecipe(imageURL: String? = nil, imageData: Data? = nil) -> Recipe {
        var draft = ImportedRecipeDraft()
        draft.title = "Test Dish"
        draft.ingredientLines = ["1 cup flour"]
        draft.stepTexts = ["Mix."]
        draft.imageURL = imageURL
        draft.imageData = imageData
        let recipe = RecipeFactory.make(from: draft)
        context.insert(recipe)
        return recipe
    }

    // A large JPEG so we can prove downscaling happened.
    private func bigJPEG(width: CGFloat = 2000, height: CGFloat = 1500) -> Data {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 1.0)!
    }

    // MARK: - needsCaching

    func testNeedsCachingTrueForUrlOnlyRecipe() {
        let recipe = makeRecipe(imageURL: "https://example.com/a.jpg")
        XCTAssertTrue(RecipeImageBackfill.needsCaching(recipe))
    }

    func testNeedsCachingFalseWhenDataPresent() {
        let recipe = makeRecipe(imageURL: "https://example.com/a.jpg", imageData: Data([0x1, 0x2]))
        XCTAssertFalse(RecipeImageBackfill.needsCaching(recipe))
    }

    func testNeedsCachingFalseWhenNoURL() {
        let recipe = makeRecipe(imageURL: nil)
        XCTAssertFalse(RecipeImageBackfill.needsCaching(recipe))
    }

    func testNeedsCachingFalseWhenURLBlank() {
        let recipe = makeRecipe(imageURL: "   ")
        XCTAssertFalse(RecipeImageBackfill.needsCaching(recipe))
    }

    // MARK: - downloadAndPrepare

    func testDownloadAndPrepareReturnsDownscaledBytes() async {
        let big = bigJPEG()
        let out = await RecipeImageBackfill.downloadAndPrepare(
            from: "https://example.com/a.jpg",
            fetch: { _ in big }
        )
        let data = try? XCTUnwrap(out)
        let image = data.flatMap { UIImage(data: $0) }
        XCTAssertNotNil(image)
        let longest = max(image!.size.width, image!.size.height)
        XCTAssertLessThanOrEqual(longest, 1280, "ImagePrep should cap the longest side at 1280")
        XCTAssertLessThan(out!.count, big.count, "Prepared bytes should be smaller than the 2000px original")
    }

    func testDownloadAndPrepareReturnsNilOnFetchFailure() async {
        struct Boom: Error {}
        let out = await RecipeImageBackfill.downloadAndPrepare(
            from: "https://example.com/a.jpg",
            fetch: { _ in throw Boom() }
        )
        XCTAssertNil(out)
    }

    func testDownloadAndPrepareReturnsNilForBadURL() async {
        let out = await RecipeImageBackfill.downloadAndPrepare(from: "", fetch: { _ in Data() })
        XCTAssertNil(out)
    }

    // MARK: - ensure

    func testEnsureStoresBytesForUrlOnlyRecipe() async {
        let recipe = makeRecipe(imageURL: "https://example.com/a.jpg")
        let big = bigJPEG()
        await RecipeImageBackfill.ensure(for: recipe, in: context, fetch: { _ in big })
        XCTAssertNotNil(recipe.imageData)
        XCTAssertNotNil(recipe.imageData.flatMap { UIImage(data: $0) })
    }

    func testEnsureNoOpWhenAlreadyHasData() async {
        let recipe = makeRecipe(imageURL: "https://example.com/a.jpg", imageData: Data([0x9]))
        var fetchCalls = 0
        await RecipeImageBackfill.ensure(for: recipe, in: context, fetch: { _ in
            fetchCalls += 1
            return Data()
        })
        XCTAssertEqual(fetchCalls, 0, "Should not download when bytes already exist")
        XCTAssertEqual(recipe.imageData, Data([0x9]))
    }

    func testEnsureMarksFailedURLAndSkipsSecondAttempt() async {
        struct Boom: Error {}
        let recipe = makeRecipe(imageURL: "https://example.com/dead.jpg")
        var fetchCalls = 0
        let fetch: RecipeImageBackfill.Fetch = { _ in fetchCalls += 1; throw Boom() }
        await RecipeImageBackfill.ensure(for: recipe, in: context, fetch: fetch)
        await RecipeImageBackfill.ensure(for: recipe, in: context, fetch: fetch)
        XCTAssertEqual(fetchCalls, 1, "A URL that failed this session must not be retried")
        XCTAssertNil(recipe.imageData)
    }

    // MARK: - sweep

    func testSweepOnlyCachesUrlOnlyRecipes() async {
        let urlOnly = makeRecipe(imageURL: "https://example.com/a.jpg")
        let hasData = makeRecipe(imageURL: "https://example.com/b.jpg", imageData: Data([0x7]))
        let noURL = makeRecipe(imageURL: nil)
        let big = bigJPEG()
        await RecipeImageBackfill.sweep(in: context, fetch: { _ in big })
        XCTAssertNotNil(urlOnly.imageData)
        XCTAssertEqual(hasData.imageData, Data([0x7]))   // untouched
        XCTAssertNil(noURL.imageData)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run via XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:GluttTests/RecipeImageBackfillTests"]`.
(First run `xcodegen generate` in the worktree so the new files are in the project.)
Expected: FAIL — `RecipeImageBackfill` is undefined (compile error).

- [ ] **Step 3: Implement the service**

Create `Glutt/Services/Import/RecipeImageBackfill.swift`:

```swift
import Foundation
import SwiftData

/// Downloads imported recipe images once and stores the bytes in `imageData`
/// so they survive `/Library/Caches` purges and source-URL rot. Display
/// (`RecipeImageView`) already prefers `imageData`, so once bytes exist the
/// durable copy is shown — no display changes needed.
enum RecipeImageBackfill {

    /// Network seam — injected in tests, real `URLSession` in the app.
    typealias Fetch = (URL) async throws -> Data

    static let defaultFetch: Fetch = { url in
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    /// Max images cached per sweep, so a large library heals over several
    /// foregrounds instead of spiking on one.
    static let perSweepLimit = 20

    /// URLs that failed this app run — not retried until next launch.
    @MainActor private static var failedURLs: Set<String> = []

    /// Needs caching iff it has a remote URL, no local bytes, and no bundled asset.
    static func needsCaching(_ recipe: Recipe) -> Bool {
        guard recipe.imageData == nil, recipe.imageAssetName == nil else { return false }
        guard let url = recipe.imageURL else { return false }
        return !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Download + downscale via `ImagePrep` (1280 / q0.65). `nil` on any failure.
    static func downloadAndPrepare(from urlString: String, fetch: Fetch = defaultFetch) async -> Data? {
        guard let url = URL(string: urlString),
              !urlString.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let raw = try? await fetch(url) else { return nil }
        return ImagePrep.prepareForVision(raw, maxDimension: 1280)
    }

    /// Cache one recipe's image if needed. Model mutation on the main actor;
    /// the `await`ed download runs off-main via `URLSession`.
    @MainActor
    static func ensure(for recipe: Recipe, in context: ModelContext, fetch: Fetch = defaultFetch) async {
        guard needsCaching(recipe), let urlString = recipe.imageURL else { return }
        guard !failedURLs.contains(urlString) else { return }
        guard let bytes = await downloadAndPrepare(from: urlString, fetch: fetch) else {
            failedURLs.insert(urlString)
            return
        }
        recipe.imageData = bytes
        try? context.save()
    }

    /// Heal up to `perSweepLimit` URL-only recipes, sequentially.
    @MainActor
    static func sweep(in context: ModelContext, fetch: Fetch = defaultFetch) async {
        guard let all = try? context.fetch(FetchDescriptor<Recipe>()) else { return }
        let pending = all.filter { needsCaching($0) && !failedURLs.contains($0.imageURL ?? "") }
            .prefix(perSweepLimit)
        for recipe in pending {
            await ensure(for: recipe, in: context, fetch: fetch)
        }
    }

    /// Test seam: clear the session failed-set between tests.
    @MainActor static func resetFailedURLsForTesting() { failedURLs.removeAll() }
}
```

- [ ] **Step 4: Regenerate the project and run the tests**

Run `xcodegen generate` in the worktree, then `test_sim` with `extraArgs: ["-only-testing:GluttTests/RecipeImageBackfillTests"]`.
Expected: PASS — all RecipeImageBackfillTests green, output pristine.

- [ ] **Step 5: Commit**

```bash
git add Glutt/Services/Import/RecipeImageBackfill.swift GluttTests/RecipeImageBackfillTests.swift project.yml Glutt.xcodeproj
git commit -m "feat(images): RecipeImageBackfill — download + store recipe image bytes"
```

---

### Task 2: Wire the triggers (foreground sweep + post-link-import cache)

Two call sites that invoke the Task 1 service. No new unit tests (integration glue); gate is a clean build + the app launching without crash.

**Files:**
- Modify: `Glutt/App/RootView.swift` (foreground + initial sweep)
- Modify: `Glutt/Features/Import/ImportReviewView.swift:297-312` (cache the just-saved link import)

**Interfaces:**
- Consumes: `RecipeImageBackfill.sweep(in:)`, `RecipeImageBackfill.ensure(for:in:)` (Task 1). Both `@MainActor async`; called from `Task {}` inside main-actor SwiftUI code (the task inherits the main actor).
- Produces: nothing for later tasks.

- [ ] **Step 1: Trigger the sweep from RootView**

In `Glutt/App/RootView.swift`, the `scenePhase` handler currently is:

```swift
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                router.checkForSharedImport()
                drainImportInbox()
            }
        }
        .task { drainImportInbox() }
```

Replace it with (adds a low-priority image sweep on both initial launch and each foreground; share-extension imports are drained first, then swept):

```swift
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                router.checkForSharedImport()
                drainImportInbox()
                Task { await RecipeImageBackfill.sweep(in: context) }
            }
        }
        .task { drainImportInbox() }
        .task { await RecipeImageBackfill.sweep(in: context) }
```

(`context` is the existing `@Environment(\.modelContext) private var context` already declared in `RootView`.)

- [ ] **Step 2: Cache link imports right after save**

In `Glutt/Features/Import/ImportReviewView.swift`, the `save()` function ends:

```swift
        let recipe = RecipeFactory.make(from: edited)
        context.insert(recipe)
        for collection in collections where selectedCollections.contains(collection.persistentModelID) {
            collection.recipes.append(recipe)
        }
        onDone()
    }
```

Change it to kick a prompt cache of the new recipe's image (non-blocking; until it finishes the live URL still renders):

```swift
        let recipe = RecipeFactory.make(from: edited)
        context.insert(recipe)
        for collection in collections where selectedCollections.contains(collection.persistentModelID) {
            collection.recipes.append(recipe)
        }
        Task { await RecipeImageBackfill.ensure(for: recipe, in: context) }
        onDone()
    }
```

(`context` is the existing `@Environment(\.modelContext)` in `ImportReviewView`. If the property is named differently, use the existing model-context property — confirm by reading the top of the file.)

- [ ] **Step 3: Build**

XcodeBuildMCP `build_sim`.
Expected: BUILD SUCCEEDED, 0 warnings. (If either `context` reference doesn't resolve, locate the existing model-context environment property in that file and use its name — do not add a new one.)

- [ ] **Step 4: Smoke-test on the simulator**

`build_run_sim` (use the `Glutt Beta` scheme for demo data: set the active profile's scheme to `Glutt Beta`, run, then restore it to `Glutt` when done).
Expected: app launches, Recipes tab shows recipe images, no crash from the sweep. `screenshot` to confirm. (Full URL→bytes durability is unit-proven in Task 1; this step only confirms the triggers don't crash and images still render.)

- [ ] **Step 5: Commit**

```bash
git add Glutt/App/RootView.swift Glutt/Features/Import/ImportReviewView.swift
git commit -m "feat(images): cache recipe images on foreground sweep + after link import"
```

---

## Final verification (after all tasks)

- [ ] `test_sim` with `-only-testing:GluttTests/RecipeImageBackfillTests` green; a broader run (`AskGluttTests`, `RecipeFactoryTests`, `ImportInboxDrainerTests`) still green (no regressions from the new file).
- [ ] `build_sim` clean, 0 warnings.
- [ ] Simulator: app launches; recipe images render; no crash.

## Self-review notes

- **Spec coverage:** new `RecipeImageBackfill` (service) → Task 1; `downloadAndPrepare`/`needsCaching`/`ensure`/`sweep`/failed-set → Task 1; 1280/q0.65 via `ImagePrep` → Task 1 (`maxDimension: 1280`); foreground sweep trigger → Task 2 Step 1; post-import cache → Task 2 Step 2; "no display/parsing/model changes" → honored (only RootView + ImportReviewView touched); graceful failure → `ensure` leaves URL + failed-set, unit-tested. Share-extension hardening & thumbnails → out of scope (absent). All covered.
- **Deliberate simplification vs spec:** the spec floated "small concurrency cap (e.g. 3)"; this plan processes the per-sweep batch **sequentially** instead — simpler and keeps all SwiftData mutation on the main actor with no `TaskGroup`/Sendable concerns. Still bounded (ceiling 20) and non-spiking, satisfying the design's intent. The share-import path needs no in-drainer trigger because RootView's `.active` block drains *then* sweeps on the same foreground.
- **Type consistency:** `Fetch`, `needsCaching`, `downloadAndPrepare`, `ensure`, `sweep`, `resetFailedURLsForTesting`, `perSweepLimit` identical across Task 1 (def), Task 1 tests, and Task 2 (calls).
- **No placeholders:** every code step is complete; the one conditional ("if `context` is named differently") names the exact fallback action.
