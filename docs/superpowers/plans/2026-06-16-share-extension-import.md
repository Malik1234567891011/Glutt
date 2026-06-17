# In-extension Recipe Import (ReCime-style) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the entire recipe import inside the iOS share sheet — loading → editable preview → save → "Add more" / "View recipe" — instead of just stashing a URL for the app to handle later.

**Architecture:** The import pipeline (`RecipeImportService`, `DraftCleanup`, `LLMClient`) becomes shared code compiled into both the app and the `GluttShare` extension. A new shared `ImportPipeline` orchestrates the import with progress callbacks; a shared `ImportInbox` (app-group JSON queue) carries finished recipes from the extension to the app, which drains them into SwiftData via a new shared-app `RecipeFactory`. A "View recipe" deep link (`glutt://recipe?import=<uuid>`) opens the app to the just-imported recipe.

**Tech Stack:** Swift 5.10, SwiftUI, SwiftData, XCTest, XcodeGen (`project.yml`), iOS 17.

## Global Constraints

- iOS deployment target: **17.0**. Swift version: **5.10**. (verbatim from `project.yml`)
- App group identifier (both targets): **`group.com.omarlahmimi.glutt`**
- Custom URL scheme: **`glutt`** (already registered in `project.yml` `CFBundleURLSchemes`)
- App is **light-mode only** by design — do not add dark-mode variants.
- **AI is never load-bearing:** any `DraftCleanup`/`LLMClient` failure must return the original draft unchanged (existing behavior — preserve it).
- **No `Recipe` SwiftData schema change** — the "View recipe" correlation is resolved in-session, not persisted.
- The extension target must **not** compile `Vision`, OCR, or SwiftData `@Model` code (memory budget). Shared files must be free of those dependencies.
- XcodeGen owns the project: after creating any new file or editing `project.yml`, run `xcodegen generate` before building, or the new file won't be in the `.xcodeproj`.
- Match existing conventions: `enum` namespaces for stateless services, conventional-commit messages (`feat:`/`refactor:`/`fix:`), XCTest with `@testable import Glutt`.

**Test/build commands** (used throughout — substitute an available simulator from `xcrun simctl list devices available` if `iPhone 16` is absent):

```bash
# Run a single test class
xcodebuild test -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:GluttTests/<ClassName> 2>&1 | tail -30

# Build the app + extension
xcodebuild -scheme Glutt -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30
```

---

## File Structure

**New shared files** (app + `GluttShare` membership — added to `project.yml` in Task 8):
- `Glutt/Services/Import/ImportPipeline.swift` — orchestrates fetch + AI passes with progress callbacks.
- `Glutt/Services/Import/ImportInbox.swift` — app-group JSON queue of finished `ImportedRecipeDraft`s.
- `Glutt/Services/Import/ShareImportViewModel.swift` — `@Observable` state machine for the share-sheet UI (no SwiftUI, no SwiftData).

**New app-only files:**
- `Glutt/Services/Import/RecipeImportService+OCR.swift` — the Vision/OCR path, moved out of the shared service.
- `Glutt/Services/Import/RecipeFactory.swift` — builds a SwiftData `Recipe` from an `ImportedRecipeDraft`.

**New extension-only files:**
- `GluttShare/ShareRootView.swift` — SwiftUI surface for the four states.

**Modified files:**
- `Glutt/Services/Import/ImportedRecipeDraft.swift` — add `Codable`.
- `Glutt/Services/Import/RecipeImportService.swift` — drop OCR (and `Vision`/`UIKit` imports).
- `Glutt/Features/Import/ImportRecipeView.swift` — use `ImportPipeline`.
- `Glutt/Features/Import/ImportReviewView.swift` — use `RecipeFactory`.
- `Glutt/App/Router.swift` — `recipe` deep-link + in-session navigation resolution.
- `Glutt/App/RootView.swift` — drain the inbox; react to navigation target.
- `Glutt/Features/Recipes/RecipesView.swift` — programmatic navigation to the imported recipe.
- `GluttShare/ShareViewController.swift` — host the SwiftUI surface; open the app for "View recipe".
- `project.yml` — shared source membership + new extension file.

**New test files:**
- `GluttTests/ImportInboxTests.swift`, `GluttTests/ImportPipelineTests.swift`, `GluttTests/RecipeFactoryTests.swift`, `GluttTests/ShareImportViewModelTests.swift`, `GluttTests/RouterImportNavigationTests.swift`. (`@testable import Glutt` sees shared files because they are compiled into the `Glutt` target too.)

---

### Task 1: Make `ImportedRecipeDraft` Codable

**Files:**
- Modify: `Glutt/Services/Import/ImportedRecipeDraft.swift:5`
- Test: `GluttTests/ImportInboxTests.swift` (created here; reused in Task 4)

**Interfaces:**
- Produces: `ImportedRecipeDraft: Identifiable, Codable` — round-trips every stored property (including `id`) through `JSONEncoder`/`JSONDecoder`. `SourcePlatform` is already `Codable`.

- [ ] **Step 1: Write the failing test**

Create `GluttTests/ImportInboxTests.swift`:

```swift
import XCTest
@testable import Glutt

final class ImportedRecipeDraftCodableTests: XCTestCase {

    func testCodableRoundTripPreservesEverything() throws {
        var draft = ImportedRecipeDraft()
        draft.title = "Spicy Peanut Noodles"
        draft.summary = "Fast and fiery."
        draft.creator = "@cookfast"
        draft.sourceURL = "https://www.tiktok.com/@cookfast/video/1"
        draft.platform = .tiktok
        draft.caption = "recipe below"
        draft.servings = 3
        draft.prepMinutes = 5
        draft.cookMinutes = 15
        draft.ingredientLines = ["200g rice noodles", "2 tbsp peanut butter"]
        draft.stepTexts = ["Boil noodles.", "Toss with sauce."]
        draft.tags = ["quick", "spicy"]
        draft.calories = 520
        draft.proteinGrams = 18
        draft.issues = ["Cleaned up with AI — give it a once-over"]
        draft.stepsAreAISuggested = true

        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(ImportedRecipeDraft.self, from: data)

        XCTAssertEqual(decoded.id, draft.id)
        XCTAssertEqual(decoded.title, "Spicy Peanut Noodles")
        XCTAssertEqual(decoded.platform, .tiktok)
        XCTAssertEqual(decoded.ingredientLines, draft.ingredientLines)
        XCTAssertEqual(decoded.stepTexts, draft.stepTexts)
        XCTAssertEqual(decoded.servings, 3)
        XCTAssertEqual(decoded.calories, 520)
        XCTAssertEqual(decoded.issues, draft.issues)
        XCTAssertTrue(decoded.stepsAreAISuggested)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/ImportedRecipeDraftCodableTests 2>&1 | tail -30`
Expected: COMPILE FAILURE — `ImportedRecipeDraft` does not conform to `Codable` / `JSONEncoder.encode` is unavailable.

- [ ] **Step 3: Add the conformance**

In `Glutt/Services/Import/ImportedRecipeDraft.swift`, change the declaration on line 5 from:

```swift
struct ImportedRecipeDraft: Identifiable {
```

to:

```swift
struct ImportedRecipeDraft: Identifiable, Codable {
```

No other change — all stored properties are already `Codable` (`String?`, `Int?`, `[String]`, `Bool`, and `SourcePlatform: Codable`). Computed properties (`confidence`, `isSocialVideo`) and the static method are not encoded.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/ImportedRecipeDraftCodableTests 2>&1 | tail -30`
Expected: PASS (`Test Suite 'ImportedRecipeDraftCodableTests' passed`).

- [ ] **Step 5: Commit**

```bash
git add Glutt/Services/Import/ImportedRecipeDraft.swift GluttTests/ImportInboxTests.swift
git commit -m "feat: make ImportedRecipeDraft Codable for share-extension handoff"
```

---

### Task 2: Split the OCR path out of `RecipeImportService`

Makes `RecipeImportService` free of `Vision`/`UIKit` so it can compile in the extension. Pure refactor — no behavior change.

**Files:**
- Modify: `Glutt/Services/Import/RecipeImportService.swift`
- Create: `Glutt/Services/Import/RecipeImportService+OCR.swift`

**Interfaces:**
- Produces: `RecipeImportService.importFrom(urlString:)` and `importFrom(url:)` remain (now `Foundation`-only). `RecipeImportService.importFrom(imageData:)` still exists, now defined in the `+OCR` extension. `enum ImportError` stays in the base file (shared).

- [ ] **Step 1: Create the OCR extension file**

Create `Glutt/Services/Import/RecipeImportService+OCR.swift` with the OCR code moved verbatim from the base file:

```swift
import Foundation
import UIKit
import Vision

extension RecipeImportService {

    /// Screenshot / photo import (on-device OCR). App-only — the share
    /// extension never uses this path, so it stays out of the shared service.
    static func importFrom(imageData: Data) async throws -> ImportedRecipeDraft {
        guard let uiImage = UIImage(data: imageData), let cgImage = uiImage.cgImage else {
            throw ImportError.unreadableImage
        }

        let text = try await recognizeText(in: cgImage)
        guard !text.isEmpty else { throw ImportError.unreadableImage }

        var draft = TextRecipeParser.parse(text: text)
        draft.platform = .screenshot
        draft.issues.append("Imported from a screenshot — double-check quantities")
        return draft
    }

    private static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

- [ ] **Step 2: Remove the OCR code and unused imports from the base file**

In `Glutt/Services/Import/RecipeImportService.swift`:
- Change the top imports from `import Foundation` / `import UIKit` / `import Vision` to just `import Foundation`.
- Delete the entire `// MARK: - Screenshot / photo import (on-device OCR)` section: the `importFrom(imageData:)` method and the `recognizeText(in:)` method (lines 81–117 in the original). Leave `enum ImportError`, `userAgent`, `importFrom(urlString:)`, and `importFrom(url:)` intact.

- [ ] **Step 3: Regenerate the project**

Run: `xcodegen generate 2>&1 | tail -5`
Expected: `Created project at .../Glutt.xcodeproj`. (The new file lands in the `Glutt` target automatically via the `Glutt` source glob.)

- [ ] **Step 4: Build + run the existing import tests to confirm no regression**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/RecipeHTMLParserTests -only-testing:GluttTests/TextRecipeParserTests -only-testing:GluttTests/SocialMediaImportTests 2>&1 | tail -30`
Expected: PASS. The app still builds (OCR path still reachable through the extension), and the import parsers are unchanged.

- [ ] **Step 5: Commit**

```bash
git add Glutt/Services/Import/RecipeImportService.swift Glutt/Services/Import/RecipeImportService+OCR.swift Glutt.xcodeproj
git commit -m "refactor: split OCR out of RecipeImportService so the link path is extension-safe"
```

---

### Task 3: Extract `ImportPipeline` and adopt it in `ImportRecipeView`

One shared orchestrator for "fetch → AI cleanup → reconstruct → infer steps", with injectable seams for testing and a progress callback.

**Files:**
- Create: `Glutt/Services/Import/ImportPipeline.swift`
- Modify: `Glutt/Features/Import/ImportRecipeView.swift:185-208`
- Test: `GluttTests/ImportPipelineTests.swift`

**Interfaces:**
- Produces: `ImportPipeline.run(urlString:deps:progress:) async throws -> ImportedRecipeDraft`, where `progress` is `@MainActor @escaping (String) -> Void`. `ImportPipeline.Dependencies` with fields `fetch`, `wouldImprove`, `cleanUp`, `reconstruct`, `inferSteps` and a `.live` default wired to `RecipeImportService`/`DraftCleanup`.

- [ ] **Step 1: Write the failing test**

Create `GluttTests/ImportPipelineTests.swift`:

```swift
import XCTest
@testable import Glutt

@MainActor
final class ImportPipelineTests: XCTestCase {

    private func fakeDeps(
        fetched: ImportedRecipeDraft,
        cleanUp: @escaping (ImportedRecipeDraft) -> ImportedRecipeDraft = { $0 },
        reconstruct: @escaping (ImportedRecipeDraft) -> ImportedRecipeDraft = { $0 },
        inferSteps: @escaping (ImportedRecipeDraft) -> ImportedRecipeDraft = { $0 },
        wouldImprove: @escaping (ImportedRecipeDraft) -> Bool = { _ in true }
    ) -> ImportPipeline.Dependencies {
        ImportPipeline.Dependencies(
            fetch: { _ in fetched },
            wouldImprove: wouldImprove,
            cleanUp: { cleanUp($0) },
            reconstruct: { reconstruct($0) },
            inferSteps: { inferSteps($0) }
        )
    }

    func testReadingMessageAlwaysComesFirst() async throws {
        var messages: [String] = []
        let deps = fakeDeps(fetched: ImportedRecipeDraft(), wouldImprove: { _ in false })
        _ = try await ImportPipeline.run(urlString: "x", deps: deps) { messages.append($0) }
        XCTAssertEqual(messages.first, "Reading the recipe…")
    }

    func testCleanupRunsAndIsReflectedInResult() async throws {
        var fetched = ImportedRecipeDraft()
        fetched.platform = .tiktok
        let deps = fakeDeps(fetched: fetched, cleanUp: { d in
            var c = d
            c.ingredientLines = ["1 cup rice"]
            c.stepTexts = ["Cook the rice."]
            return c
        })
        var messages: [String] = []
        let result = try await ImportPipeline.run(urlString: "x", deps: deps) { messages.append($0) }
        XCTAssertTrue(messages.contains("Cleaning it up with AI…"))
        XCTAssertEqual(result.ingredientLines, ["1 cup rice"])
        XCTAssertEqual(result.stepTexts, ["Cook the rice."])
    }

    func testReconstructFiresForCaptionlessSocialVideo() async throws {
        var fetched = ImportedRecipeDraft()
        fetched.platform = .tiktok            // isSocialVideo == true, no ingredients
        let deps = fakeDeps(fetched: fetched, reconstruct: { d in
            var r = d
            r.ingredientLines = ["2 eggs"]
            r.stepTexts = ["Fry the eggs."]
            return r
        })
        var messages: [String] = []
        let result = try await ImportPipeline.run(urlString: "x", deps: deps) { messages.append($0) }
        XCTAssertTrue(messages.contains("No recipe in the caption — drafting the dish…"))
        XCTAssertEqual(result.ingredientLines, ["2 eggs"])
    }

    func testInferStepsFiresWhenIngredientsButNoSteps() async throws {
        var fetched = ImportedRecipeDraft()
        fetched.platform = .website
        fetched.ingredientLines = ["1 cup rice"]   // has ingredients, no steps
        let deps = fakeDeps(fetched: fetched, inferSteps: { d in
            var r = d
            r.stepTexts = ["Cook the rice."]
            r.stepsAreAISuggested = true
            return r
        })
        var messages: [String] = []
        let result = try await ImportPipeline.run(urlString: "x", deps: deps) { messages.append($0) }
        XCTAssertTrue(messages.contains("No method listed — drafting the steps…"))
        XCTAssertEqual(result.stepTexts, ["Cook the rice."])
        XCTAssertTrue(result.stepsAreAISuggested)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/ImportPipelineTests 2>&1 | tail -30`
Expected: COMPILE FAILURE — `ImportPipeline` is undefined.

- [ ] **Step 3: Create `ImportPipeline`**

Create `Glutt/Services/Import/ImportPipeline.swift`:

```swift
import Foundation

/// One orchestration of the link-import flow, shared by the in-app importer and
/// the share extension: fetch the page, then run the AI passes that improve it.
/// `progress` reports the user-facing status line for each phase.
enum ImportPipeline {

    /// Seams so the orchestration can be unit-tested without network/LLM calls.
    struct Dependencies {
        var fetch: (String) async throws -> ImportedRecipeDraft
        var wouldImprove: (ImportedRecipeDraft) -> Bool
        var cleanUp: (ImportedRecipeDraft) async -> ImportedRecipeDraft
        var reconstruct: (ImportedRecipeDraft) async -> ImportedRecipeDraft
        var inferSteps: (ImportedRecipeDraft) async -> ImportedRecipeDraft

        static let live = Dependencies(
            fetch: { try await RecipeImportService.importFrom(urlString: $0) },
            wouldImprove: DraftCleanup.wouldImprove,
            cleanUp: DraftCleanup.cleanUp,
            reconstruct: DraftCleanup.reconstruct,
            inferSteps: DraftCleanup.inferSteps
        )
    }

    static func run(
        urlString: String,
        deps: Dependencies = .live,
        progress: @MainActor @escaping (String) -> Void
    ) async throws -> ImportedRecipeDraft {
        await progress("Reading the recipe…")
        var draft = try await deps.fetch(urlString)

        if deps.wouldImprove(draft) {
            await progress("Cleaning it up with AI…")
            draft = await deps.cleanUp(draft)
        }
        if draft.ingredientLines.isEmpty, draft.isSocialVideo {
            await progress("No recipe in the caption — drafting the dish…")
            draft = await deps.reconstruct(draft)
        }
        if draft.stepTexts.isEmpty, !draft.ingredientLines.isEmpty {
            await progress("No method listed — drafting the steps…")
            draft = await deps.inferSteps(draft)
        }
        return draft
    }
}
```

- [ ] **Step 4: Regenerate, run the test to verify it passes**

```bash
xcodegen generate 2>&1 | tail -5
xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/ImportPipelineTests 2>&1 | tail -30
```
Expected: PASS (all four tests).

- [ ] **Step 5: Adopt the pipeline in `ImportRecipeView`**

In `Glutt/Features/Import/ImportRecipeView.swift`, replace the body of `startLinkImport()` (lines 185–208) with:

```swift
    private func startLinkImport() {
        phase = .loading("Reading the recipe…")
        let urlString = urlText
        Task {
            do {
                let draft = try await ImportPipeline.run(urlString: urlString) { message in
                    phase = .loading(message)
                }
                phase = .review(draft)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
```

(The photo-import path `startPhotoImport()` is unchanged — it still calls `RecipeImportService.importFrom(imageData:)` and the cleanup passes directly.)

- [ ] **Step 6: Build to confirm the app still compiles, then commit**

```bash
xcodebuild -scheme Glutt -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -15
git add Glutt/Services/Import/ImportPipeline.swift Glutt/Features/Import/ImportRecipeView.swift GluttTests/ImportPipelineTests.swift Glutt.xcodeproj
git commit -m "refactor: extract shared ImportPipeline; adopt it in ImportRecipeView"
```

---

### Task 4: `ImportInbox` — the app-group recipe queue

**Files:**
- Create: `Glutt/Services/Import/ImportInbox.swift`
- Test: `GluttTests/ImportInboxTests.swift` (append a class to the file from Task 1)

**Interfaces:**
- Produces: `struct ImportInbox` with `init(defaults: UserDefaults = ...)`, `func append(_ draft: ImportedRecipeDraft)`, `func drain() -> [ImportedRecipeDraft]`. `drain()` returns items in append order and clears the queue, including when stored data is corrupt.

- [ ] **Step 1: Write the failing test**

Append to `GluttTests/ImportInboxTests.swift`:

```swift
final class ImportInboxTests: XCTestCase {

    private let suiteName = "test.glutt.importinbox"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func draft(_ title: String) -> ImportedRecipeDraft {
        var d = ImportedRecipeDraft()
        d.title = title
        d.ingredientLines = ["1 thing"]
        return d
    }

    func testAppendThenDrainReturnsItemsInOrderThenEmpties() {
        let inbox = ImportInbox(defaults: defaults)
        inbox.append(draft("First"))
        inbox.append(draft("Second"))

        let drained = inbox.drain()
        XCTAssertEqual(drained.map(\.title), ["First", "Second"])

        // Draining a second time yields nothing.
        XCTAssertTrue(inbox.drain().isEmpty)
    }

    func testDrainOnEmptyInboxReturnsEmpty() {
        XCTAssertTrue(ImportInbox(defaults: defaults).drain().isEmpty)
    }

    func testCorruptDataDrainsToEmptyAndClears() {
        defaults.set(Data("not json".utf8), forKey: "importInboxItems")
        let inbox = ImportInbox(defaults: defaults)
        XCTAssertTrue(inbox.drain().isEmpty)
        XCTAssertNil(defaults.data(forKey: "importInboxItems"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/ImportInboxTests 2>&1 | tail -30`
Expected: COMPILE FAILURE — `ImportInbox` is undefined.

- [ ] **Step 3: Create `ImportInbox`**

Create `Glutt/Services/Import/ImportInbox.swift`:

```swift
import Foundation

/// Append-only queue of finished imported recipes, shared between the share
/// extension (which appends) and the app (which drains on next foreground).
/// Upgrades the old single-URL `PendingImportStore` handoff to whole recipes.
struct ImportInbox {
    static let appGroupID = "group.com.omarlahmimi.glutt"
    private static let key = "importInboxItems"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: ImportInbox.appGroupID)) {
        self.defaults = defaults ?? .standard
    }

    func append(_ draft: ImportedRecipeDraft) {
        var items = load()
        items.append(draft)
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Returns queued recipes in append order and clears the queue. Corrupt
    /// data is treated as empty and cleared, so it can never block future imports.
    func drain() -> [ImportedRecipeDraft] {
        let items = load()
        defaults.removeObject(forKey: Self.key)
        return items
    }

    private func load() -> [ImportedRecipeDraft] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([ImportedRecipeDraft].self, from: data)) ?? []
    }
}
```

- [ ] **Step 4: Regenerate, run the test to verify it passes**

```bash
xcodegen generate 2>&1 | tail -5
xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/ImportInboxTests 2>&1 | tail -30
```
Expected: PASS (all three tests).

- [ ] **Step 5: Commit**

```bash
git add Glutt/Services/Import/ImportInbox.swift GluttTests/ImportInboxTests.swift Glutt.xcodeproj
git commit -m "feat: add ImportInbox app-group queue for share-extension imports"
```

---

### Task 5: `RecipeFactory` — draft → SwiftData `Recipe`

Extracts the `draft → Recipe` mapping currently inside `ImportReviewView.save()` so the inbox drain and the in-app review screen build recipes identically.

**Files:**
- Create: `Glutt/Services/Import/RecipeFactory.swift`
- Modify: `Glutt/Features/Import/ImportReviewView.swift:249-309`
- Test: `GluttTests/RecipeFactoryTests.swift`

**Interfaces:**
- Produces: `RecipeFactory.make(from draft: ImportedRecipeDraft) -> Recipe` (parses ingredient lines via `IngredientLineParser`, builds steps with detected durations, copies source/nutrition/tags). `RecipeFactory.detectDuration(in:) -> Int?`.

- [ ] **Step 1: Write the failing test**

Create `GluttTests/RecipeFactoryTests.swift`:

```swift
import XCTest
@testable import Glutt

final class RecipeFactoryTests: XCTestCase {

    func testBuildsRecipeWithParsedIngredientsAndStepDurations() {
        var draft = ImportedRecipeDraft()
        draft.title = "  Spicy Peanut Noodles  "
        draft.creator = "@cookfast"
        draft.sourceURL = "https://www.tiktok.com/@cookfast/video/1"
        draft.platform = .tiktok
        draft.servings = 3
        draft.prepMinutes = 5
        draft.cookMinutes = 15
        draft.ingredientLines = ["200 g rice noodles", "", "2 tbsp peanut butter"]
        draft.stepTexts = ["Boil noodles for 8 minutes.", "Toss with sauce."]
        draft.tags = ["quick"]
        draft.calories = 520
        draft.proteinGrams = 18

        let recipe = RecipeFactory.make(from: draft)

        XCTAssertEqual(recipe.title, "Spicy Peanut Noodles")     // trimmed
        XCTAssertEqual(recipe.sourceCreator, "@cookfast")
        XCTAssertEqual(recipe.sourcePlatform, .tiktok)
        XCTAssertEqual(recipe.servings, 3)
        XCTAssertEqual(recipe.calories, 520)
        XCTAssertEqual(recipe.proteinGrams, 18)
        XCTAssertNotNil(recipe.importedAt)

        // Empty ingredient line is dropped; the rest parse into qty/unit/name.
        XCTAssertEqual(recipe.ingredients.count, 2)
        let noodles = recipe.ingredients.first { $0.name == "rice noodles" }
        XCTAssertEqual(noodles?.quantity, 200)
        XCTAssertEqual(noodles?.unit, "g")
        XCTAssertEqual(noodles?.sortIndex, 0)

        // "8 minutes" -> 480 seconds; second step has no duration.
        XCTAssertEqual(recipe.steps.count, 2)
        XCTAssertEqual(recipe.steps[0].durationSeconds, 480)
        XCTAssertNil(recipe.steps[1].durationSeconds)
    }

    func testMissingTitleAndServingsGetSafeDefaults() {
        let recipe = RecipeFactory.make(from: ImportedRecipeDraft())
        XCTAssertEqual(recipe.title, "")
        XCTAssertEqual(recipe.servings, 2)
        XCTAssertTrue(recipe.ingredients.isEmpty)
        XCTAssertTrue(recipe.steps.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/RecipeFactoryTests 2>&1 | tail -30`
Expected: COMPILE FAILURE — `RecipeFactory` is undefined.

- [ ] **Step 3: Create `RecipeFactory`**

Create `Glutt/Services/Import/RecipeFactory.swift`:

```swift
import Foundation

/// Builds a SwiftData `Recipe` from an `ImportedRecipeDraft`. One source of
/// truth for both the in-app review screen and the share-extension inbox drain.
enum RecipeFactory {

    static func make(from draft: ImportedRecipeDraft) -> Recipe {
        let recipe = Recipe(
            title: (draft.title ?? "").trimmingCharacters(in: .whitespaces),
            summary: draft.summary,
            sourceCreator: draft.creator,
            sourceURL: draft.sourceURL,
            sourcePlatform: draft.platform,
            sourceCaption: draft.caption,
            importedAt: .now,
            importConfidence: draft.confidence,
            imageURL: draft.imageURL,
            servings: draft.servings ?? 2,
            prepMinutes: draft.prepMinutes ?? 0,
            cookMinutes: draft.cookMinutes ?? 0,
            tags: draft.tags
        )
        recipe.calories = draft.calories
        recipe.proteinGrams = draft.proteinGrams

        recipe.ingredients = draft.ingredientLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, line in
                let parsed = IngredientLineParser.parse(line)
                return RecipeIngredient(
                    name: parsed.name,
                    quantity: parsed.quantity,
                    unit: parsed.unit,
                    note: parsed.note,
                    sortIndex: index
                )
            }

        recipe.steps = draft.stepTexts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, text in
                RecipeStep(index: index, text: text, durationSeconds: detectDuration(in: text))
            }

        return recipe
    }

    /// "simmer for 10 minutes" -> 600 seconds. Powers Cook Mode timers later.
    static func detectDuration(in text: String) -> Int? {
        let pattern = #"(\d+)\s*(?:-\s*\d+\s*)?(minutes|minute|mins|min|hours|hour|hrs|hr)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Int(text[numberRange])
        else { return nil }
        let unit = text[unitRange].lowercased()
        return unit.hasPrefix("h") ? value * 3600 : value * 60
    }
}
```

- [ ] **Step 4: Regenerate, run the test to verify it passes**

```bash
xcodegen generate 2>&1 | tail -5
xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/RecipeFactoryTests 2>&1 | tail -30
```
Expected: PASS (both tests).

- [ ] **Step 5: Refactor `ImportReviewView.save()` to use the factory**

In `Glutt/Features/Import/ImportReviewView.swift`, replace the entire `// MARK: - Save` section (the `save()` method and the private `detectDuration(in:)` method, lines 247–309) with:

```swift
    // MARK: - Save

    private func save() {
        var edited = draft
        edited.title = title.trimmingCharacters(in: .whitespaces)
        edited.servings = servings
        edited.prepMinutes = prepMinutes
        edited.cookMinutes = cookMinutes
        edited.ingredientLines = ingredientLines.map(\.text)
        edited.stepTexts = stepLines.map(\.text)

        let recipe = RecipeFactory.make(from: edited)
        context.insert(recipe)
        for collection in collections where selectedCollections.contains(collection.persistentModelID) {
            collection.recipes.append(recipe)
        }
        onDone()
    }
```

(`RecipeFactory.make` trims and drops empty ingredient/step lines, so the local filtering is no longer needed here. The `detectDuration` helper now lives in `RecipeFactory`.)

- [ ] **Step 6: Build, run the review/import tests, then commit**

```bash
xcodebuild -scheme Glutt -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -15
git add Glutt/Services/Import/RecipeFactory.swift Glutt/Features/Import/ImportReviewView.swift GluttTests/RecipeFactoryTests.swift Glutt.xcodeproj
git commit -m "refactor: extract RecipeFactory; share it between review screen and import inbox"
```

---

### Task 6: App-side drain + "View recipe" navigation

Drains the inbox into SwiftData on foreground, adds the `glutt://recipe?import=<uuid>` deep link, and navigates the Recipes tab to the imported recipe. Navigation resolution is order-independent and unit-tested; the SwiftUI wiring is build/manual-verified.

**Files:**
- Modify: `Glutt/App/Router.swift`
- Modify: `Glutt/App/RootView.swift`
- Modify: `Glutt/Features/Recipes/RecipesView.swift:78`, `:126-128`
- Test: `GluttTests/RouterImportNavigationTests.swift`

**Interfaces:**
- Consumes: `ImportInbox.drain()` (Task 4), `RecipeFactory.make(from:)` (Task 5).
- Produces on `Router`: `var recipeToOpenID: PersistentIdentifier?`, `func noteImported(_ map: [UUID: PersistentIdentifier])`, `func requestOpenRecipe(importID: UUID)`. Resolution sets `recipeToOpenID` when the requested import id has been drained, regardless of which arrived first.

- [ ] **Step 1: Write the failing test**

Create `GluttTests/RouterImportNavigationTests.swift`:

```swift
import SwiftData
import XCTest
@testable import Glutt

@MainActor
final class RouterImportNavigationTests: XCTestCase {

    /// A real PersistentIdentifier requires an inserted model.
    private func makeIdentifier() throws -> PersistentIdentifier {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recipe.self, configurations: config)
        let recipe = Recipe(title: "Test")
        container.mainContext.insert(recipe)
        return recipe.persistentModelID
    }

    func testResolvesWhenImportNotedBeforeOpenRequested() throws {
        let id = try makeIdentifier()
        let uuid = UUID()
        let router = Router()

        router.noteImported([uuid: id])
        XCTAssertNil(router.recipeToOpenID)          // nothing requested yet

        router.requestOpenRecipe(importID: uuid)
        XCTAssertEqual(router.recipeToOpenID, id)
        XCTAssertEqual(router.selectedTab, .recipes)
    }

    func testResolvesWhenOpenRequestedBeforeImportNoted() throws {
        let id = try makeIdentifier()
        let uuid = UUID()
        let router = Router()

        router.requestOpenRecipe(importID: uuid)
        XCTAssertNil(router.recipeToOpenID)          // not drained yet

        router.noteImported([uuid: id])
        XCTAssertEqual(router.recipeToOpenID, id)
    }

    func testUnmatchedImportLeavesTargetNil() throws {
        let id = try makeIdentifier()
        let router = Router()
        router.noteImported([UUID(): id])
        router.requestOpenRecipe(importID: UUID())    // different id
        XCTAssertNil(router.recipeToOpenID)
    }

    func testRecipeDeepLinkRequestsOpen() {
        let router = Router()
        let uuid = UUID()
        router.handle(url: URL(string: "glutt://recipe?import=\(uuid.uuidString)")!)
        XCTAssertEqual(router.selectedTab, .recipes)
        // No drain happened, so the concrete id is still pending — but the tab switched.
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/RouterImportNavigationTests 2>&1 | tail -30`
Expected: COMPILE FAILURE — `noteImported`, `requestOpenRecipe`, `recipeToOpenID` are undefined.

- [ ] **Step 3: Add navigation state to `Router`**

In `Glutt/App/Router.swift`:

1. Add `import SwiftData` below `import Foundation` (line 1).

2. Inside `final class Router`, after the `pendingImportURL` property (line 80), add:

```swift
    /// SwiftData id of a freshly-imported recipe to open (set once the inbox is
    /// drained AND a `glutt://recipe?import=` link is handled — order-independent).
    var recipeToOpenID: PersistentIdentifier?
    /// Import-uuid → SwiftData id for recipes drained this session.
    private var importedThisSession: [UUID: PersistentIdentifier] = [:]
    /// Import uuid requested by a "View recipe" deep link, awaiting its drain.
    private var pendingOpenImportID: UUID?
```

3. Add these methods inside the class (e.g. after `checkForSharedImport()`, line 144):

```swift
    /// Called after the inbox is drained, mapping each draft's id to its new recipe.
    func noteImported(_ map: [UUID: PersistentIdentifier]) {
        importedThisSession.merge(map) { _, new in new }
        resolvePendingNavigation()
    }

    /// Called when a `glutt://recipe?import=<uuid>` link is handled.
    func requestOpenRecipe(importID: UUID) {
        pendingOpenImportID = importID
        selectedTab = .recipes
        resolvePendingNavigation()
    }

    private func resolvePendingNavigation() {
        guard let importID = pendingOpenImportID,
              let id = importedThisSession[importID] else { return }
        recipeToOpenID = id
        pendingOpenImportID = nil
    }
```

4. In `handle(url:)`, add a `recipe` case before `default` (line 133):

```swift
        case "recipe":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let raw = components?.queryItems?.first(where: { $0.name == "import" })?.value,
               let uuid = UUID(uuidString: raw) {
                requestOpenRecipe(importID: uuid)
            } else {
                selectedTab = .recipes
            }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/RouterImportNavigationTests 2>&1 | tail -30`
Expected: PASS (all four tests).

- [ ] **Step 5: Drain the inbox in `RootView`**

In `Glutt/App/RootView.swift`:

1. After `@Environment(\.scenePhase) private var scenePhase` (line 6), add:

```swift
    @Environment(\.modelContext) private var context
```

2. Replace the `.onChange(of: scenePhase)` block (lines 39–43) with:

```swift
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                router.checkForSharedImport()
                drainImportInbox()
            }
        }
        .task { drainImportInbox() }
```

3. Add this method to `RootView` (e.g. after `body`, before `tabContent`):

```swift
    /// Materializes recipes the share extension finished into SwiftData, and
    /// tells the router which import ids map to which saved recipes (so a
    /// "View recipe" deep link can navigate to the right one).
    private func drainImportInbox() {
        let drafts = ImportInbox().drain()
        guard !drafts.isEmpty else { return }
        var map: [UUID: PersistentIdentifier] = [:]
        for draft in drafts {
            let recipe = RecipeFactory.make(from: draft)
            context.insert(recipe)
            map[draft.id] = recipe.persistentModelID
        }
        router.noteImported(map)
    }
```

- [ ] **Step 6: Navigate the Recipes tab to the imported recipe**

In `Glutt/Features/Recipes/RecipesView.swift`:

1. Add a navigation path state with the other `@State` properties (after line 19):

```swift
    @State private var navPath: [Recipe] = []
```

2. Change `NavigationStack {` (line 78) to:

```swift
        NavigationStack(path: $navPath) {
```

3. After the existing `.onChange(of: router.pendingAction) { handlePendingImport() }` (line 169), add:

```swift
            .onChange(of: router.recipeToOpenID) { openRequestedRecipe() }
            .onAppear(perform: openRequestedRecipe)
```

4. Add this method next to `handlePendingImport()` (after line 214):

```swift
    private func openRequestedRecipe() {
        guard let id = router.recipeToOpenID,
              let recipe = allRecipes.first(where: { $0.persistentModelID == id }) else { return }
        navPath = [recipe]
        router.recipeToOpenID = nil
    }
```

(The existing `.navigationDestination(for: Recipe.self)` already maps a `Recipe` in the path to `RecipeDetailView`.)

- [ ] **Step 7: Build, then commit**

```bash
xcodebuild -scheme Glutt -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -15
git add Glutt/App/Router.swift Glutt/App/RootView.swift Glutt/Features/Recipes/RecipesView.swift GluttTests/RouterImportNavigationTests.swift
git commit -m "feat: drain import inbox into SwiftData and deep-link to imported recipe"
```

---

### Task 7: `ShareImportViewModel` — the share-sheet state machine

Lives in the app target (so `GluttTests` can test it) and is given extension membership in Task 8. Pure logic — no SwiftUI, no SwiftData.

**Files:**
- Create: `Glutt/Services/Import/ShareImportViewModel.swift`
- Test: `GluttTests/ShareImportViewModelTests.swift`

**Interfaces:**
- Consumes: `ImportPipeline` (Task 3), `ImportInbox` (Task 4).
- Produces: `@MainActor @Observable final class ShareImportViewModel` with `enum State { case importing(String), preview, saved, failed(String) }`; `init(urlString:deps:inbox:)`; `private(set) var state`; `private(set) var draft: ImportedRecipeDraft?`; `var editableTitle: String`; `var editableServings: Int`; `func start() async`; `@discardableResult func save() -> UUID?`.

- [ ] **Step 1: Write the failing test**

Create `GluttTests/ShareImportViewModelTests.swift`:

```swift
import XCTest
@testable import Glutt

@MainActor
final class ShareImportViewModelTests: XCTestCase {

    private let suiteName = "test.glutt.sharevm"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func deps(returning draft: ImportedRecipeDraft) -> ImportPipeline.Dependencies {
        ImportPipeline.Dependencies(
            fetch: { _ in draft },
            wouldImprove: { _ in false },
            cleanUp: { $0 }, reconstruct: { $0 }, inferSteps: { $0 }
        )
    }

    private func deps(throwing error: Error) -> ImportPipeline.Dependencies {
        ImportPipeline.Dependencies(
            fetch: { _ in throw error },
            wouldImprove: { _ in false },
            cleanUp: { $0 }, reconstruct: { $0 }, inferSteps: { $0 }
        )
    }

    func testSuccessfulImportLandsInPreviewSeededWithEdits() async {
        var draft = ImportedRecipeDraft()
        draft.title = "Peanut Noodles"
        draft.servings = 4
        let vm = ShareImportViewModel(urlString: "x", deps: deps(returning: draft),
                                      inbox: ImportInbox(defaults: defaults))
        await vm.start()

        guard case .preview = vm.state else { return XCTFail("expected preview, got \(vm.state)") }
        XCTAssertEqual(vm.editableTitle, "Peanut Noodles")
        XCTAssertEqual(vm.editableServings, 4)
    }

    func testSaveAppliesEditsWritesToInboxAndReturnsID() async {
        var draft = ImportedRecipeDraft()
        draft.title = "Original"
        draft.servings = 2
        let inbox = ImportInbox(defaults: defaults)
        let vm = ShareImportViewModel(urlString: "x", deps: deps(returning: draft), inbox: inbox)
        await vm.start()

        vm.editableTitle = "My Better Title"
        vm.editableServings = 6
        let id = vm.save()

        guard case .saved = vm.state else { return XCTFail("expected saved, got \(vm.state)") }
        XCTAssertNotNil(id)
        let queued = inbox.drain()
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.title, "My Better Title")
        XCTAssertEqual(queued.first?.servings, 6)
        XCTAssertEqual(queued.first?.id, id)
    }

    func testFailedImportLandsInFailedState() async {
        let vm = ShareImportViewModel(urlString: "x", deps: deps(throwing: ImportError.fetchFailed),
                                      inbox: ImportInbox(defaults: defaults))
        await vm.start()
        guard case .failed(let message) = vm.state else { return XCTFail("expected failed, got \(vm.state)") }
        XCTAssertEqual(message, ImportError.fetchFailed.errorDescription)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/ShareImportViewModelTests 2>&1 | tail -30`
Expected: COMPILE FAILURE — `ShareImportViewModel` is undefined.

- [ ] **Step 3: Create `ShareImportViewModel`**

Create `Glutt/Services/Import/ShareImportViewModel.swift`:

```swift
import Foundation
import Observation

/// Drives the share-sheet import UI: run the pipeline, show an editable preview,
/// then write the finished recipe to the app-group inbox on save.
@MainActor
@Observable
final class ShareImportViewModel {

    enum State {
        case importing(String)
        case preview
        case saved
        case failed(String)
    }

    private(set) var state: State = .importing("Reading the recipe…")
    private(set) var draft: ImportedRecipeDraft?

    /// Quick edits, seeded from the draft once it's ready.
    var editableTitle: String = ""
    var editableServings: Int = 2

    private let urlString: String
    private let deps: ImportPipeline.Dependencies
    private let inbox: ImportInbox

    init(urlString: String,
         deps: ImportPipeline.Dependencies = .live,
         inbox: ImportInbox = ImportInbox()) {
        self.urlString = urlString
        self.deps = deps
        self.inbox = inbox
    }

    func start() async {
        do {
            let draft = try await ImportPipeline.run(urlString: urlString, deps: deps) { [weak self] message in
                guard let self, case .importing = self.state else { return }
                self.state = .importing(message)
            }
            self.draft = draft
            self.editableTitle = draft.title ?? ""
            self.editableServings = draft.servings ?? 2
            self.state = .preview
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    /// Applies the quick edits and queues the recipe. Returns the draft id so the
    /// host controller can build the `glutt://recipe?import=` link for "View recipe".
    @discardableResult
    func save() -> UUID? {
        guard var draft else { return nil }
        let trimmed = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { draft.title = trimmed }
        draft.servings = editableServings
        inbox.append(draft)
        self.draft = draft
        state = .saved
        return draft.id
    }
}
```

- [ ] **Step 4: Regenerate, run the test to verify it passes**

```bash
xcodegen generate 2>&1 | tail -5
xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/ShareImportViewModelTests 2>&1 | tail -30
```
Expected: PASS (all three tests).

- [ ] **Step 5: Commit**

```bash
git add Glutt/Services/Import/ShareImportViewModel.swift GluttTests/ShareImportViewModelTests.swift Glutt.xcodeproj
git commit -m "feat: add ShareImportViewModel state machine for share-sheet import"
```

---

### Task 8: Share-extension UI + wiring

Gives the shared files extension membership, builds the SwiftUI surface, and rewires `ShareViewController` to run the import in-sheet and open the app for "View recipe". Not unit-tested (extension UI) — verified by build and manual run.

**Files:**
- Modify: `project.yml` (GluttShare `sources`)
- Create: `GluttShare/ShareRootView.swift`
- Modify: `GluttShare/ShareViewController.swift` (full rewrite)

**Interfaces:**
- Consumes: `ShareImportViewModel` (Task 7), `Theme`/`Typography` design tokens, `PendingImportStore` (failure fallback).

- [ ] **Step 1: Add shared source membership in `project.yml`**

In `project.yml`, change the `GluttShare` target's `sources` list (line 52–53) from:

```yaml
    sources:
      - GluttShare
```

to:

```yaml
    sources:
      - GluttShare
      - path: Glutt/Models/Enums.swift
      - path: Glutt/Services/Import/ImportedRecipeDraft.swift
      - path: Glutt/Services/Import/RecipeImportService.swift
      - path: Glutt/Services/Import/RecipeHTMLParser.swift
      - path: Glutt/Services/Import/SocialMediaImport.swift
      - path: Glutt/Services/Import/TextRecipeParser.swift
      - path: Glutt/Services/Import/IngredientLineParser.swift
      - path: Glutt/Services/Import/ImportPipeline.swift
      - path: Glutt/Services/Import/ImportInbox.swift
      - path: Glutt/Services/Import/ShareImportViewModel.swift
      - path: Glutt/Services/Import/PendingImportStore.swift
      - path: Glutt/Services/AI/LLMClient.swift
      - path: Glutt/Services/AI/Secrets.swift
      - path: Glutt/Services/AI/DraftCleanup.swift
      - path: Glutt/DesignSystem/Theme.swift
      - path: Glutt/DesignSystem/Typography.swift
```

- [ ] **Step 2: Create the SwiftUI surface**

Create `GluttShare/ShareRootView.swift`:

```swift
import SwiftUI

/// The share-sheet UI. Terminal actions (open app, close) are owned by the host
/// controller, so they're passed in as closures.
struct ShareRootView: View {
    @State var viewModel: ShareImportViewModel
    let sourceURLString: String
    let onViewRecipe: (UUID) -> Void
    let onClose: () -> Void
    let onOpenInApp: (String) -> Void

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            switch viewModel.state {
            case .importing(let message): importing(message)
            case .preview:                preview
            case .saved:                  saved
            case .failed(let message):    failed(message)
            }
        }
        .task { await viewModel.start() }
    }

    // MARK: - States

    private func importing(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView().controlSize(.large)
            Text(message)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .padding(Theme.Spacing.lg)
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let urlString = viewModel.draft?.imageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Theme.Colors.accent.opacity(0.08))
                    }
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }

                TextField("Recipe title", text: $viewModel.editableTitle)
                    .font(.gluttTitle)
                if let creator = viewModel.draft?.creator {
                    Text("by \(creator)")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Stepper("Servings: \(viewModel.editableServings)",
                        value: $viewModel.editableServings, in: 1...24)
                    .font(.gluttBody)

                Text(summaryLine)
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Button("Save recipe") { viewModel.save() }
                    .buttonStyle(.gluttPrimary)
                Button("Discard", role: .destructive) { onClose() }
                    .font(.gluttCaption)
                    .frame(maxWidth: .infinity)
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var saved: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.accent)
            Text("Saved to Glutt")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Button("Add more recipes") { onClose() }
                .buttonStyle(.gluttPrimary)
            Button("View recipe") {
                if let id = viewModel.draft?.id { onViewRecipe(id) }
            }
            .font(.gluttHeadline)
            .foregroundStyle(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.lg)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.warning)
            Text(message)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Button("Open in Glutt") { onOpenInApp(sourceURLString) }
                .buttonStyle(.gluttPrimary)
            Button("Close") { onClose() }
                .font(.gluttCaption)
        }
        .padding(Theme.Spacing.lg)
    }

    private var summaryLine: String {
        let draft = viewModel.draft
        let ingredients = draft?.ingredientLines.count ?? 0
        let steps = draft?.stepTexts.count ?? 0
        let minutes = (draft?.prepMinutes ?? 0) + (draft?.cookMinutes ?? 0)
        var parts = ["\(ingredients) ingredients", "\(steps) steps"]
        if minutes > 0 { parts.append("\(minutes) min") }
        return parts.joined(separator: " · ")
    }
}
```

> Note: `.gluttPrimary`, `.gluttTitle`, `.gluttBody`, `.gluttCaption`, `.gluttHeadline`, and the `Theme.*` tokens come from the now-shared `Theme.swift`/`Typography.swift`. If the build reports any of these reference an app-only type, that token must be inlined here — but they are self-contained design primitives.

- [ ] **Step 3: Rewrite `ShareViewController`**

Replace the entire contents of `GluttShare/ShareViewController.swift` with:

```swift
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Runs the full recipe import inside the share sheet, then either closes
/// (staying in the source app) or opens Glutt to the imported recipe.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1)
        loadSharedURL { [weak self] urlString in
            self?.present(urlString: urlString)
        }
    }

    // MARK: - Shared URL

    private func loadSharedURL(_ completion: @escaping (String?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) })
        else { completion(nil); return }

        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { value, _ in
            let urlString = (value as? URL)?.absoluteString
            DispatchQueue.main.async { completion(urlString) }
        }
    }

    private func present(urlString: String?) {
        guard let urlString else { close(); return }

        let viewModel = ShareImportViewModel(urlString: urlString)
        let root = ShareRootView(
            viewModel: viewModel,
            sourceURLString: urlString,
            onViewRecipe: { [weak self] id in self?.openApp(path: "recipe?import=\(id.uuidString)") },
            onClose: { [weak self] in self?.close() },
            onOpenInApp: { [weak self] url in
                PendingImportStore.save(urlString: url)
                self?.openApp(path: "import?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)")
            }
        )

        let hosting = UIHostingController(rootView: root)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    // MARK: - Terminal actions

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Opens the host app via the custom scheme. `extensionContext.open` is the
    /// only sanctioned way for a share extension to launch its container app.
    private func openApp(path: String) {
        guard let url = URL(string: "glutt://\(path)") else { close(); return }
        extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
```

- [ ] **Step 4: Regenerate and build the extension**

```bash
xcodegen generate 2>&1 | tail -5
xcodebuild -scheme Glutt -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30
```
Expected: BUILD SUCCEEDED for both the app and `GluttShare`. If a shared file fails to compile in the extension because of an app-only dependency, that file must not be shared (re-check against Task 2's OCR split / the design's shared-file list).

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: all suites PASS (no regressions across the existing tests plus the five new ones).

- [ ] **Step 6: Manual verification (device or simulator)**

Run the app once so iOS registers the extension, then verify the flow end-to-end:
1. From Safari (or share a TikTok/recipe link), tap Share → **Glutt**. The sheet stays open and shows the loading messages, then an editable preview (title + servings).
2. Edit the title, tap **Save recipe** → the "Saved to Glutt" screen appears with **Add more recipes** / **View recipe**.
3. Tap **Add more recipes** → the sheet closes and you remain in the source app.
4. Repeat, tap **View recipe** → Glutt opens on the Recipes tab with the imported recipe's detail screen pushed, and the recipe is in the library.
5. Force a failure (share a non-recipe page) → the failed state shows **Open in Glutt** (which opens the app's importer with the URL) and **Close**.

- [ ] **Step 7: Commit**

```bash
git add project.yml GluttShare/ShareRootView.swift GluttShare/ShareViewController.swift Glutt.xcodeproj
git commit -m "feat: run recipe import inside the share sheet with save and view-recipe flow"
```

---

## Self-Review

**Spec coverage:**
- Flow / state machine (importing → preview → saved → add more/view recipe; failed) → Tasks 7 (logic) + 8 (UI). ✓
- Preview + quick edits (title, servings) → `ShareImportViewModel.editableTitle/editableServings` (Task 7), bound in `ShareRootView` (Task 8). ✓
- Full AI pipeline in-extension → `ImportPipeline` shared + extension membership (Tasks 3, 8). ✓
- Import inbox persistence → `ImportInbox` (Task 4), drained in `RootView` (Task 6). ✓
- Code sharing via `project.yml`, OCR split, `Codable` draft → Tasks 1, 2, 8. ✓
- `RecipeFactory` one-source-of-truth mapping → Task 5. ✓
- "View recipe" deep link + in-session correlation → Task 6 (Router) + Task 8 (`extensionContext.open`). ✓
- In-app flow unchanged except shared `RecipeFactory`/`ImportPipeline`; legacy `PendingImportStore` kept for the failure fallback → Tasks 3, 5, 6, 8. ✓
- Error handling (failed state, Instagram-blocked message via `ImportError`, AI non-load-bearing, corrupt-inbox safety) → Tasks 4, 7, 8. ✓
- Testing coverage (factory, inbox, draft codable, view model, router nav) → Tasks 1, 4, 5, 6, 7. ✓
- Out of scope (full editing in-sheet, image download in-extension, shared SwiftData store, screenshot-from-share) → not implemented. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code; commands have expected output. ✓

**Type consistency:** `ImportPipeline.Dependencies` field names (`fetch`, `wouldImprove`, `cleanUp`, `reconstruct`, `inferSteps`) match across Tasks 3 and 7. `ImportInbox(defaults:)`, `append`, `drain` consistent across Tasks 4, 6, 7. `RecipeFactory.make(from:)` consistent across Tasks 5, 6. Router `noteImported`/`requestOpenRecipe`/`recipeToOpenID` consistent across Tasks 6 and its test. `ShareImportViewModel` init/state/`save()` consistent across Tasks 7, 8. ✓
