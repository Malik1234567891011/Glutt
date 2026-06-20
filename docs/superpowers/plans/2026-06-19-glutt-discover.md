# Glutt Discover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Discover" mode to the Recipes screen that searches YouTube for short cooking videos, plays them one card at a time, and saves any clip as a full recipe via the existing import pipeline.

**Architecture:** A `My Recipes | Discover` segmented control sits atop the existing Recipes screen. Discover calls two new endpoints on the existing Vercel proxy (`/api/discover/search`, `/api/discover/suggested`) which wrap the YouTube Data API v3 (the YouTube key never ships in the app). Results decode into a non-persisted `DiscoverVideo`, play in a `WKWebView` running YouTube's official IFrame player, and **Save** reuses `ImportPipeline.run` → `RecipeFactory.make` → `ModelContext.insert/save` to produce a normal SwiftData `Recipe`.

**Tech Stack:** Swift, SwiftUI, SwiftData, Observation (`@Observable`), `WKWebView`/`UIViewRepresentable`, XCTest, Vercel serverless (Node) + YouTube Data API v3.

## Global Constraints

- **Persistence:** SwiftData. `Recipe` is the `@Model`. New `DiscoverVideo` is **NOT persisted** — it is a transient `Decodable` value type. Do not add a SwiftData model or `@Query` for discovery results.
- **Networking mirrors `LLMClient`:** read config from `Secrets.aiProxyBaseURL` / `Secrets.aiProxyClientKey`; send the proxy key in the header named exactly `x-glutt-proxy-key`; use `URLSession`'s async `data(for:)`; model errors with a `LocalizedError` enum. (`Glutt/Services/AI/LLMClient.swift`, `Glutt/Services/AI/Secrets.swift`.)
- **Testability:** the codebase has **no URLSession mock**. Make every networked type accept an injected transport closure (the same dependency-injection style as `ImportPipeline.Dependencies`). Keep all JSON parsing in pure functions tested with fixtures (the established pattern: `RecipeHTMLParser`, `IngredientLineParser` are pure + fixture-tested).
- **Save reuses existing import:** do NOT write a new importer. Call `ImportPipeline.run(urlString:deps:progress:)` → `RecipeFactory.make(from:)` → `context.insert(recipe)` → `try context.save()`.
- **No video downloading / re-hosting, no `AVPlayer`.** Playback is the official YouTube IFrame player in a `WKWebView` only.
- **Styling:** match the redesign system — use the existing `SegmentedTabs` component and `Theme.Colors` / `Theme.Spacing` / `Theme.Radius`. The app-wide accent tint is already applied at `RootView`.
- **Concurrency:** SwiftData contexts and the view model are `@MainActor`. The view model uses `@Observable`.
- **Test framework:** XCTest, `@testable import Glutt`. SwiftData tests use `ModelConfiguration(isStoredInMemoryOnly: true)` and `@MainActor`.
- **Adding files to the build:** after creating any new `.swift` file, ensure it is a member of the correct target — `Glutt` for app code, `GluttTests` for tests. If the Xcode 16 project uses file-system-synchronized folder groups, files are picked up automatically; otherwise add target membership in Xcode before building.
- **Test command (adjust simulator if needed):**
  ```bash
  cd /Users/omarlahmimi/Documents/Glutt
  xcodebuild test -project Glutt.xcodeproj -scheme Glutt \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:GluttTests/<Class>/<method>
  ```
  If that simulator isn't installed, run `xcodebuild -showdestinations -project Glutt.xcodeproj -scheme Glutt` and substitute an available destination.

## Proxy contract (agreed request/response shape — both Task 1 and Task 9 depend on this)

`GET {base}/discover/search?q=<query>&pageToken=<token?>`
`GET {base}/discover/suggested?tags=<comma,separated?>`

Both return the same JSON shape:
```json
{
  "videos": [
    {
      "videoId": "dQw4w9WgXcQ",
      "title": "Crispy Tofu Stir-Fry",
      "creator": "Wok Wednesdays",
      "thumbnailURL": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
      "durationSeconds": 187
    }
  ],
  "nextPageToken": "CAUQAA"
}
```
`creator`, `thumbnailURL`, `durationSeconds`, and `nextPageToken` may be absent/null.

## File structure

| File | Responsibility |
|---|---|
| `Glutt/Services/Discover/DiscoverVideo.swift` (create) | Transient `DiscoverVideo` + `DiscoverResponse` decodables; `watchURL` helper |
| `Glutt/Services/Discover/DiscoverService.swift` (create) | Networking to the two proxy endpoints; injectable transport; `DiscoverError` |
| `Glutt/Services/Discover/DiscoverSaver.swift` (create) | Dedup-by-`sourceURL` + import→Recipe→persist |
| `Glutt/Features/Discover/YouTubePlayerView.swift` (create) | `YouTubeEmbed.html(videoId:)` pure builder + `WKWebView` representable |
| `Glutt/Features/Discover/DiscoverFeedViewModel.swift` (create) | Queue, pagination, prefetch, save/loading state; injectable deps |
| `Glutt/Features/Discover/DiscoverCardView.swift` (create) | One-card UI: player + title/creator + Save / Show me next |
| `Glutt/Features/Discover/DiscoverView.swift` (create) | Suggested-on-open, results host, empty/error states |
| `Glutt/Features/Recipes/RecipesView.swift` (modify) | `My Recipes \| Discover` segment, submit-to-search wiring, empty-state nudge |
| `Glutt/Features/Recipes/RecipeDetailView.swift` (modify, optional Task 10) | "Watch the video" embed for YouTube-sourced recipes |
| `GluttTests/Discover*Tests.swift` (create) | Unit tests per component |
| *(separate `glutt-sable` Vercel repo)* | `/api/discover/search` + `/api/discover/suggested` |

---

### Task 1: `DiscoverVideo` + `DiscoverResponse` decoding

**Files:**
- Create: `Glutt/Services/Discover/DiscoverVideo.swift`
- Test: `GluttTests/DiscoverVideoTests.swift`

**Interfaces:**
- Produces: `struct DiscoverVideo: Decodable, Identifiable, Equatable` with `let videoId: String`, `let title: String`, `let creator: String?`, `let thumbnailURL: String?`, `let durationSeconds: Int?`; computed `var id: String { videoId }` and `var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(videoId)")! }`. `struct DiscoverResponse: Decodable, Equatable` with `let videos: [DiscoverVideo]` and `let nextPageToken: String?`.

- [ ] **Step 1: Write the failing test**

```swift
// GluttTests/DiscoverVideoTests.swift
import XCTest
@testable import Glutt

final class DiscoverVideoTests: XCTestCase {
    func testDecodesResponseAndBuildsWatchURL() throws {
        let json = """
        {
          "videos": [
            { "videoId": "abc123", "title": "Crispy Tofu", "creator": "Wok Wed",
              "thumbnailURL": "https://i.ytimg.com/vi/abc123/hqdefault.jpg", "durationSeconds": 187 }
          ],
          "nextPageToken": "CAUQAA"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DiscoverResponse.self, from: json)

        XCTAssertEqual(response.videos.count, 1)
        XCTAssertEqual(response.nextPageToken, "CAUQAA")
        let video = response.videos[0]
        XCTAssertEqual(video.videoId, "abc123")
        XCTAssertEqual(video.title, "Crispy Tofu")
        XCTAssertEqual(video.creator, "Wok Wed")
        XCTAssertEqual(video.durationSeconds, 187)
        XCTAssertEqual(video.id, "abc123")
        XCTAssertEqual(video.watchURL.absoluteString, "https://www.youtube.com/watch?v=abc123")
    }

    func testDecodesWithMissingOptionalFields() throws {
        let json = """
        { "videos": [ { "videoId": "x1", "title": "Plain" } ] }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(DiscoverResponse.self, from: json)
        XCTAssertNil(response.nextPageToken)
        XCTAssertNil(response.videos[0].creator)
        XCTAssertNil(response.videos[0].durationSeconds)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Glutt.xcodeproj -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/DiscoverVideoTests`
Expected: FAIL — `cannot find 'DiscoverResponse' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Glutt/Services/Discover/DiscoverVideo.swift
import Foundation

/// A YouTube cooking clip surfaced in Discover. Transient — never persisted.
struct DiscoverVideo: Decodable, Identifiable, Equatable {
    let videoId: String
    let title: String
    let creator: String?
    let thumbnailURL: String?
    let durationSeconds: Int?

    var id: String { videoId }

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }
}

/// One page of Discover results from the proxy.
struct DiscoverResponse: Decodable, Equatable {
    let videos: [DiscoverVideo]
    let nextPageToken: String?
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Glutt/Services/Discover/DiscoverVideo.swift GluttTests/DiscoverVideoTests.swift
git commit -m "feat(discover): DiscoverVideo + DiscoverResponse decoding"
```

---

### Task 2: `DiscoverService` networking (injectable transport)

**Files:**
- Create: `Glutt/Services/Discover/DiscoverService.swift`
- Test: `GluttTests/DiscoverServiceTests.swift`

**Interfaces:**
- Consumes: `DiscoverResponse`, `Secrets.aiProxyBaseURL`, `Secrets.aiProxyClientKey`.
- Produces: `struct DiscoverService` with `typealias Transport = (URLRequest) async throws -> (Data, URLResponse)`; stored `var transport`, `var baseURL`, `var clientKey`; `func search(query: String, pageToken: String?) async throws -> DiscoverResponse`; `func suggested(tags: [String]) async throws -> DiscoverResponse`; `static let live = DiscoverService()`. `enum DiscoverError: LocalizedError { case notConfigured, badResponse(String) }`.

- [ ] **Step 1: Write the failing test**

```swift
// GluttTests/DiscoverServiceTests.swift
import XCTest
@testable import Glutt

final class DiscoverServiceTests: XCTestCase {
    private func ok(_ json: String, url: URL) -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (json.data(using: .utf8)!, response)
    }

    func testSearchBuildsRequestAndDecodes() async throws {
        var captured: URLRequest?
        let service = DiscoverService(
            transport: { request in
                captured = request
                return self.ok(#"{ "videos": [ { "videoId": "v1", "title": "Tofu" } ], "nextPageToken": "N" }"#,
                               url: request.url!)
            },
            baseURL: "https://example.test/api",
            clientKey: "secret-key"
        )

        let result = try await service.search(query: "tofu stir fry", pageToken: "PAGE2")

        XCTAssertEqual(result.videos.first?.videoId, "v1")
        XCTAssertEqual(result.nextPageToken, "N")
        let url = try XCTUnwrap(captured?.url)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://example.test/api/discover/search"))
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(comps.queryItems?.first { $0.name == "q" }?.value, "tofu stir fry")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "pageToken" }?.value, "PAGE2")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "x-glutt-proxy-key"), "secret-key")
    }

    func testSuggestedSendsTags() async throws {
        var captured: URLRequest?
        let service = DiscoverService(
            transport: { request in
                captured = request
                return self.ok(#"{ "videos": [] }"#, url: request.url!)
            },
            baseURL: "https://example.test/api",
            clientKey: "k"
        )
        _ = try await service.suggested(tags: ["tofu", "high-protein"])
        let comps = URLComponents(url: captured!.url!, resolvingAgainstBaseURL: false)!
        XCTAssertTrue(comps.path.hasSuffix("/discover/suggested"))
        XCTAssertEqual(comps.queryItems?.first { $0.name == "tags" }?.value, "tofu,high-protein")
    }

    func testNon2xxThrowsBadResponse() async {
        let service = DiscoverService(
            transport: { request in
                let r = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return ("boom".data(using: .utf8)!, r)
            },
            baseURL: "https://example.test/api",
            clientKey: "k"
        )
        do {
            _ = try await service.search(query: "x", pageToken: nil)
            XCTFail("expected throw")
        } catch let DiscoverError.badResponse(detail) {
            XCTAssertTrue(detail.contains("500"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testEmptyBaseURLThrowsNotConfigured() async {
        let service = DiscoverService(transport: { _ in (Data(), URLResponse()) }, baseURL: "", clientKey: "")
        do {
            _ = try await service.search(query: "x", pageToken: nil)
            XCTFail("expected throw")
        } catch DiscoverError.notConfigured {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `... -only-testing:GluttTests/DiscoverServiceTests`
Expected: FAIL — `cannot find 'DiscoverService' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Glutt/Services/Discover/DiscoverService.swift
import Foundation

enum DiscoverError: LocalizedError {
    case notConfigured
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Discovery isn't available in this build."
        case .badResponse(let detail): "Couldn't load videos: \(detail)"
        }
    }
}

/// Talks to the Glutt proxy's Discover endpoints. Mirrors `LLMClient`'s
/// transport + auth, but takes an injectable `transport` so it is testable.
struct DiscoverService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var baseURL: String = Secrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    var clientKey: String = Secrets.aiProxyClientKey.trimmingCharacters(in: .whitespacesAndNewlines)

    static let live = DiscoverService()

    func search(query: String, pageToken: String?) async throws -> DiscoverResponse {
        var items = [URLQueryItem(name: "q", value: query)]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await get(path: "discover/search", queryItems: items)
    }

    func suggested(tags: [String]) async throws -> DiscoverResponse {
        var items: [URLQueryItem] = []
        if !tags.isEmpty { items.append(URLQueryItem(name: "tags", value: tags.joined(separator: ","))) }
        return try await get(path: "discover/suggested", queryItems: items)
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> DiscoverResponse {
        guard !baseURL.isEmpty else { throw DiscoverError.notConfigured }
        guard var comps = URLComponents(string: "\(baseURL)/\(path)") else {
            throw DiscoverError.badResponse("Bad URL")
        }
        comps.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = comps.url else { throw DiscoverError.badResponse("Bad URL") }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"
        if !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        }

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DiscoverError.badResponse("HTTP \(code)")
        }
        do {
            return try JSONDecoder().decode(DiscoverResponse.self, from: data)
        } catch {
            throw DiscoverError.badResponse("Unexpected response shape")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Glutt/Services/Discover/DiscoverService.swift GluttTests/DiscoverServiceTests.swift
git commit -m "feat(discover): DiscoverService with injectable transport"
```

---

### Task 3: `DiscoverSaver` — dedup + import → Recipe → persist

**Files:**
- Create: `Glutt/Services/Discover/DiscoverSaver.swift`
- Test: `GluttTests/DiscoverSaverTests.swift`

**Interfaces:**
- Consumes: `DiscoverVideo`, `Recipe`, `ImportedRecipeDraft`, `RecipeFactory.make(from:)`, `ImportPipeline.run(urlString:deps:progress:)`.
- Produces: `enum DiscoverSaver` with `static func existingRecipe(forSourceURL: String, in: ModelContext) -> Recipe?` and `@MainActor static func save(video: DiscoverVideo, importDraft: (String) async throws -> ImportedRecipeDraft = DiscoverSaver.liveImport, into context: ModelContext) async throws -> Recipe`, plus `static func liveImport(_ urlString: String) async throws -> ImportedRecipeDraft`.

- [ ] **Step 1: Write the failing test**

```swift
// GluttTests/DiscoverSaverTests.swift
import XCTest
import SwiftData
@testable import Glutt

final class DiscoverSaverTests: XCTestCase {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    @MainActor
    func testSaveCreatesYouTubeRecipeFromDraft() async throws {
        let context = try makeContext()
        let video = DiscoverVideo(videoId: "abc123", title: "Crispy Tofu",
                                  creator: "Wok Wed", thumbnailURL: nil, durationSeconds: nil)

        var draft = ImportedRecipeDraft()
        draft.title = "Crispy Tofu"
        draft.platform = .youtube
        draft.sourceURL = video.watchURL.absoluteString
        draft.ingredientLines = ["200 g firm tofu"]
        draft.stepTexts = ["Press the tofu", "Fry until golden"]

        let recipe = try await DiscoverSaver.save(video: video, importDraft: { _ in draft }, into: context)

        XCTAssertEqual(recipe.sourcePlatform, .youtube)
        XCTAssertEqual(recipe.sourceURL, "https://www.youtube.com/watch?v=abc123")
        let all = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(all.count, 1)
    }

    @MainActor
    func testSaveDedupsBySourceURLWithoutImporting() async throws {
        let context = try makeContext()
        let video = DiscoverVideo(videoId: "abc123", title: "Crispy Tofu",
                                  creator: nil, thumbnailURL: nil, durationSeconds: nil)
        let preexisting = Recipe(title: "Already here",
                                 sourceURL: video.watchURL.absoluteString,
                                 sourcePlatform: .youtube)
        context.insert(preexisting)
        try context.save()

        var importCalled = false
        let recipe = try await DiscoverSaver.save(
            video: video,
            importDraft: { _ in importCalled = true; return ImportedRecipeDraft() },
            into: context
        )

        XCTAssertFalse(importCalled, "should not re-import a video already saved")
        XCTAssertEqual(recipe.persistentModelID, preexisting.persistentModelID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Recipe>()).count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `... -only-testing:GluttTests/DiscoverSaverTests`
Expected: FAIL — `cannot find 'DiscoverSaver' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Glutt/Services/Discover/DiscoverSaver.swift
import Foundation
import SwiftData

/// Turns a discovered YouTube clip into a saved `Recipe`, reusing the
/// existing import pipeline. Dedups by `sourceURL` so re-saving is a no-op.
enum DiscoverSaver {
    static func existingRecipe(forSourceURL sourceURL: String, in context: ModelContext) -> Recipe? {
        var descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.sourceURL == sourceURL })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func liveImport(_ urlString: String) async throws -> ImportedRecipeDraft {
        try await ImportPipeline.run(urlString: urlString) { _ in }
    }

    @MainActor
    static func save(
        video: DiscoverVideo,
        importDraft: (String) async throws -> ImportedRecipeDraft = DiscoverSaver.liveImport,
        into context: ModelContext
    ) async throws -> Recipe {
        let sourceURL = video.watchURL.absoluteString
        if let existing = existingRecipe(forSourceURL: sourceURL, in: context) {
            return existing
        }
        var draft = try await importDraft(sourceURL)
        // Guarantee provenance even if the pipeline couldn't read the page.
        draft.sourceURL = sourceURL
        draft.platform = .youtube
        if draft.title == nil || draft.title?.isEmpty == true { draft.title = video.title }
        if draft.imageURL == nil { draft.imageURL = video.thumbnailURL }
        if draft.creator == nil { draft.creator = video.creator }

        let recipe = RecipeFactory.make(from: draft)
        context.insert(recipe)
        try context.save()
        return recipe
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Glutt/Services/Discover/DiscoverSaver.swift GluttTests/DiscoverSaverTests.swift
git commit -m "feat(discover): DiscoverSaver — dedup + import to Recipe"
```

---

### Task 4: `YouTubeEmbed.html` builder + `YouTubePlayerView`

**Files:**
- Create: `Glutt/Features/Discover/YouTubePlayerView.swift`
- Test: `GluttTests/YouTubeEmbedTests.swift`

**Interfaces:**
- Produces: `enum YouTubeEmbed { static func html(videoId: String) -> String }`; `struct YouTubePlayerView: UIViewRepresentable` with `let videoId: String`.

- [ ] **Step 1: Write the failing test**

```swift
// GluttTests/YouTubeEmbedTests.swift
import XCTest
@testable import Glutt

final class YouTubeEmbedTests: XCTestCase {
    func testHTMLEmbedsVideoIdWithInlineMutedAutoplay() {
        let html = YouTubeEmbed.html(videoId: "abc123")
        XCTAssertTrue(html.contains("abc123"))
        XCTAssertTrue(html.contains("playsinline=1"))
        XCTAssertTrue(html.contains("autoplay=1"))
        XCTAssertTrue(html.contains("mute=1"))
        XCTAssertTrue(html.contains("youtube.com/embed/abc123"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `... -only-testing:GluttTests/YouTubeEmbedTests`
Expected: FAIL — `cannot find 'YouTubeEmbed' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Glutt/Features/Discover/YouTubePlayerView.swift
import SwiftUI
import WebKit

/// Pure builder for the YouTube IFrame player page. Separated so it is unit-testable.
enum YouTubeEmbed {
    static func html(videoId: String) -> String {
        """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;background:#000;height:100%;overflow:hidden}
        iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="https://www.youtube.com/embed/\(videoId)?playsinline=1&autoplay=1&mute=1&controls=1&rel=0&modestbranding=1"
          allow="autoplay; encrypted-media" allowfullscreen></iframe>
        </body></html>
        """
    }
}

/// Plays a YouTube video via the official IFrame player inside a WKWebView.
struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload only when the video changes to avoid restarting playback on every redraw.
        guard context.coordinator.loadedVideoId != videoId else { return }
        context.coordinator.loadedVideoId = videoId
        webView.loadHTMLString(YouTubeEmbed.html(videoId: videoId),
                               baseURL: URL(string: "https://www.youtube.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedVideoId: String?
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Glutt/Features/Discover/YouTubePlayerView.swift GluttTests/YouTubeEmbedTests.swift
git commit -m "feat(discover): YouTube IFrame player view + html builder"
```

---

### Task 5: `DiscoverFeedViewModel` — queue, pagination, save state

**Files:**
- Create: `Glutt/Features/Discover/DiscoverFeedViewModel.swift`
- Test: `GluttTests/DiscoverFeedViewModelTests.swift`

**Interfaces:**
- Consumes: `DiscoverVideo`, `DiscoverResponse`, `DiscoverService`, `DiscoverSaver`, `Recipe`, `ModelContext`.
- Produces: `@MainActor @Observable final class DiscoverFeedViewModel` with nested `enum Phase: Equatable { case idle, loading, loaded, empty, failed(String) }` and `struct Dependencies`. Public surface: `var phase`, `var videos`, `var currentIndex`, `var savedVideoIDs: Set<String>`, `var savingVideoID: String?`, computed `var current: DiscoverVideo?`; methods `func loadSuggested(tags: [String]) async`, `func search(_ query: String) async`, `func showNext() async`, `func save(_ video: DiscoverVideo, into context: ModelContext) async`.

**Notes:** Prefetch rule — after `showNext()` advances, if `currentIndex >= videos.count - 2` and a `nextPageToken` exists, append the next page. Keep `Dependencies` injectable so the test never touches the network or SwiftData.

- [ ] **Step 1: Write the failing test**

```swift
// GluttTests/DiscoverFeedViewModelTests.swift
import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class DiscoverFeedViewModelTests: XCTestCase {
    private func video(_ id: String) -> DiscoverVideo {
        DiscoverVideo(videoId: id, title: "T-\(id)", creator: nil, thumbnailURL: nil, durationSeconds: nil)
    }

    func testSearchPopulatesQueueAndSetsLoaded() async {
        let deps = DiscoverFeedViewModel.Dependencies(
            search: { _, _ in DiscoverResponse(videos: [self.video("a"), self.video("b")], nextPageToken: nil) },
            suggested: { _ in DiscoverResponse(videos: [], nextPageToken: nil) },
            save: { v, _ in Recipe(title: v.title) }
        )
        let vm = DiscoverFeedViewModel(deps: deps)
        await vm.search("tofu")
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.videos.count, 2)
        XCTAssertEqual(vm.current?.videoId, "a")
    }

    func testEmptyResultsSetEmptyPhase() async {
        let deps = DiscoverFeedViewModel.Dependencies(
            search: { _, _ in DiscoverResponse(videos: [], nextPageToken: nil) },
            suggested: { _ in DiscoverResponse(videos: [], nextPageToken: nil) },
            save: { v, _ in Recipe(title: v.title) }
        )
        let vm = DiscoverFeedViewModel(deps: deps)
        await vm.search("asdfqwer")
        XCTAssertEqual(vm.phase, .empty)
    }

    func testShowNextFetchesNextPageNearEnd() async {
        var calls = 0
        let deps = DiscoverFeedViewModel.Dependencies(
            search: { _, token in
                calls += 1
                if token == nil {
                    return DiscoverResponse(videos: [self.video("a"), self.video("b")], nextPageToken: "P2")
                } else {
                    return DiscoverResponse(videos: [self.video("c"), self.video("d")], nextPageToken: nil)
                }
            },
            suggested: { _ in DiscoverResponse(videos: [], nextPageToken: nil) },
            save: { v, _ in Recipe(title: v.title) }
        )
        let vm = DiscoverFeedViewModel(deps: deps)
        await vm.search("pasta")            // page 1: a, b ; index 0
        await vm.showNext()                  // index 1 -> within 2 of end, token P2 -> fetch page 2
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(vm.videos.map(\.videoId), ["a", "b", "c", "d"])
        XCTAssertEqual(vm.current?.videoId, "b")
    }

    func testSaveMarksVideoSavedAndAdvances() async throws {
        let schema = Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let deps = DiscoverFeedViewModel.Dependencies(
            search: { _, _ in DiscoverResponse(videos: [self.video("a"), self.video("b")], nextPageToken: nil) },
            suggested: { _ in DiscoverResponse(videos: [], nextPageToken: nil) },
            save: { v, ctx in let r = Recipe(title: v.title); ctx.insert(r); return r }
        )
        let vm = DiscoverFeedViewModel(deps: deps)
        await vm.search("tofu")
        await vm.save(vm.current!, into: context)
        XCTAssertTrue(vm.savedVideoIDs.contains("a"))
        XCTAssertNil(vm.savingVideoID)
        XCTAssertEqual(vm.current?.videoId, "b")    // auto-advanced
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `... -only-testing:GluttTests/DiscoverFeedViewModelTests`
Expected: FAIL — `cannot find 'DiscoverFeedViewModel' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Glutt/Features/Discover/DiscoverFeedViewModel.swift
import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class DiscoverFeedViewModel {
    enum Phase: Equatable {
        case idle, loading, loaded, empty
        case failed(String)
    }

    struct Dependencies {
        var search: (_ query: String, _ pageToken: String?) async throws -> DiscoverResponse
        var suggested: (_ tags: [String]) async throws -> DiscoverResponse
        var save: (_ video: DiscoverVideo, _ context: ModelContext) async throws -> Recipe

        static let live = Dependencies(
            search: { try await DiscoverService.live.search(query: $0, pageToken: $1) },
            suggested: { try await DiscoverService.live.suggested(tags: $0) },
            save: { try await DiscoverSaver.save(video: $0, into: $1) }
        )
    }

    private(set) var phase: Phase = .idle
    private(set) var videos: [DiscoverVideo] = []
    private(set) var currentIndex = 0
    private(set) var savedVideoIDs: Set<String> = []
    private(set) var savingVideoID: String?

    private var nextPageToken: String?
    private var query: String = ""
    private var isSuggested = false
    private let deps: Dependencies

    init(deps: Dependencies = .live) { self.deps = deps }

    var current: DiscoverVideo? {
        videos.indices.contains(currentIndex) ? videos[currentIndex] : nil
    }

    func loadSuggested(tags: [String]) async {
        isSuggested = true
        query = ""
        phase = .loading
        do {
            let page = try await deps.suggested(tags)
            apply(firstPage: page)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSuggested = false
        self.query = trimmed
        phase = .loading
        do {
            let page = try await deps.search(trimmed, nil)
            apply(firstPage: page)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func showNext() async {
        guard !videos.isEmpty else { return }
        if currentIndex < videos.count - 1 { currentIndex += 1 }
        await prefetchIfNeeded()
    }

    func save(_ video: DiscoverVideo, into context: ModelContext) async {
        savingVideoID = video.videoId
        do {
            _ = try await deps.save(video, context)
            savedVideoIDs.insert(video.videoId)
            savingVideoID = nil
            await showNext()
        } catch {
            savingVideoID = nil
            phase = .failed(error.localizedDescription)
        }
    }

    private func apply(firstPage page: DiscoverResponse) {
        videos = page.videos
        currentIndex = 0
        nextPageToken = page.nextPageToken
        phase = page.videos.isEmpty ? .empty : .loaded
    }

    private func prefetchIfNeeded() async {
        guard let token = nextPageToken, currentIndex >= videos.count - 2 else { return }
        do {
            let page = isSuggested
                ? try await deps.suggested([])   // suggested paging falls back to refresh; tokenized below
                : try await deps.search(query, token)
            videos.append(contentsOf: page.videos)
            nextPageToken = page.nextPageToken
        } catch {
            // Soft-fail: keep the current queue; the user can still browse what loaded.
            nextPageToken = nil
        }
    }
}
```

> Note: suggested-feed paging reuses `suggested([])`; if you later want true pagination for suggestions, add a `pageToken` parameter to the `suggested` dependency. Out of scope for v1 — the suggested feed is short by design.

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Glutt/Features/Discover/DiscoverFeedViewModel.swift GluttTests/DiscoverFeedViewModelTests.swift
git commit -m "feat(discover): feed view model — queue, pagination, save state"
```

---

### Task 6: `DiscoverCardView` — one-card UI

**Files:**
- Create: `Glutt/Features/Discover/DiscoverCardView.swift`

**Interfaces:**
- Consumes: `DiscoverVideo`, `YouTubePlayerView`, `Theme`.
- Produces: `struct DiscoverCardView: View` with `let video: DiscoverVideo`, `let isSaving: Bool`, `let isSaved: Bool`, `let onSave: () -> Void`, `let onNext: () -> Void`.

This task is UI assembly with no new branching logic, so it has no unit test; it is verified by build + manual check in Task 8.

- [ ] **Step 1: Write the view**

```swift
// Glutt/Features/Discover/DiscoverCardView.swift
import SwiftUI

struct DiscoverCardView: View {
    let video: DiscoverVideo
    let isSaving: Bool
    let isSaved: Bool
    let onSave: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            YouTubePlayerView(videoId: video.videoId)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.segment, style: .continuous))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(video.title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                if let creator = video.creator {
                    Text(creator)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button(action: onNext) {
                    Text("Show me next")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onSave) {
                    Group {
                        if isSaving { ProgressView() }
                        else { Text(isSaved ? "Saved ✓" : "Save") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || isSaved)
            }
            .tint(Theme.Colors.accent)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project Glutt.xcodeproj -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Discover/DiscoverCardView.swift
git commit -m "feat(discover): one-card view (player + save/next)"
```

---

### Task 7: `DiscoverView` — suggested-on-open, results host, states

**Files:**
- Create: `Glutt/Features/Discover/DiscoverView.swift`

**Interfaces:**
- Consumes: `DiscoverFeedViewModel`, `DiscoverCardView`, `EmptyStateView`, `ModelContext`.
- Produces: `struct DiscoverView: View` with `@Bindable var model: DiscoverFeedViewModel` and a `tasteTags: [String]` input for the suggested feed.

UI assembly bound to the view model; verified by build + manual check in Task 8.

- [ ] **Step 1: Write the view**

```swift
// Glutt/Features/Discover/DiscoverView.swift
import SwiftUI
import SwiftData

struct DiscoverView: View {
    @Bindable var model: DiscoverFeedViewModel
    let tasteTags: [String]
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
            case .empty:
                EmptyStateView(icon: "magnifyingglass",
                               title: "No clips found",
                               message: "Try another dish — like “tofu stir fry” or “lemon chicken”.")
            case .failed(let message):
                EmptyStateView(icon: "wifi.slash",
                               title: "Couldn’t load videos",
                               message: message,
                               actionLabel: "Try again",
                               action: { Task { await retry() } })
            case .loaded:
                if let video = model.current {
                    DiscoverCardView(
                        video: video,
                        isSaving: model.savingVideoID == video.videoId,
                        isSaved: model.savedVideoIDs.contains(video.videoId),
                        onSave: { Task { await model.save(video, into: context) } },
                        onNext: { Task { await model.showNext() } }
                    )
                } else {
                    EmptyStateView(icon: "checkmark.circle",
                                   title: "That’s everything",
                                   message: "Search another dish to keep discovering.")
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .task {
            if model.phase == .idle { await model.loadSuggested(tags: tasteTags) }
        }
    }

    private func retry() async {
        if model.videos.isEmpty { await model.loadSuggested(tags: tasteTags) }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project Glutt.xcodeproj -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Discover/DiscoverView.swift
git commit -m "feat(discover): Discover screen with suggested feed + states"
```

---

### Task 8: Integrate into `RecipesView` — segment, submit-to-search, empty-state nudge

**Files:**
- Modify: `Glutt/Features/Recipes/RecipesView.swift` (segment state near line 14-22; insert control after the `ChipRow` at line 101; branch the body around the `if searchText.isEmpty` block at lines 103-148; extend the search-mode `EmptyStateView` at lines 134-139; `.searchable` at line 161)

**Interfaces:**
- Consumes: `DiscoverView`, `DiscoverFeedViewModel`, `SegmentedTabs`.
- Produces: a `RecipeSegment` enum local to `RecipesView`; no new external interface.

**Behavior to implement:**
- Add `enum RecipeSegment: Int, CaseIterable { case myRecipes, discover }` and `@State private var segment: RecipeSegment = .myRecipes`, plus `@State private var discoverModel = DiscoverFeedViewModel()`.
- Insert a `SegmentedTabs(titles: ["My Recipes", "Discover"], selection: <binding to segment.rawValue>)` after the `ChipRow` (line 101).
- When `segment == .discover`, render `DiscoverView(model: discoverModel, tasteTags: tasteTags)` instead of the browse/search branch. (`tasteTags` = top tags from the user's recipes/cook history; for v1 derive a simple list — see code.)
- Discover search is **submit-driven**: add `.onSubmit(of: .search) { ... }` alongside `.searchable`; on submit, if `segment == .discover`, call `Task { await discoverModel.search(searchText) }`. In `.myRecipes` the existing reactive local search is unchanged.
- Extend the search-mode "Nothing matches" `EmptyStateView` (lines 134-139) with `actionLabel: "Find some in Discover"` and `action:` that sets `segment = .discover` and triggers `Task { await discoverModel.search(searchText) }` (carry the query over).

- [ ] **Step 1: Add the segment enum and state**

In `RecipesView.swift`, near the other `@State` declarations (around lines 14-22), add:

```swift
    enum RecipeSegment: Int, CaseIterable { case myRecipes, discover }
    @State private var segment: RecipeSegment = .myRecipes
    @State private var discoverModel = DiscoverFeedViewModel()
```

Add a derived taste-tag list as a computed property near `visibleRecipes`:

```swift
    /// Simple taste hint for the suggested feed: the most common tags across saved recipes.
    private var tasteTags: [String] {
        let counts = libraryRecipes.flatMap { $0.tags }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
    }
```

- [ ] **Step 2: Insert the segmented control after the filter chips**

Immediately after `ChipRow(labels: filterChips, selection: $selectedFilter)` (line 101) and before `if searchText.isEmpty {` (line 103), insert:

```swift
            SegmentedTabs(
                titles: ["My Recipes", "Discover"],
                selection: Binding(
                    get: { segment.rawValue },
                    set: { segment = RecipeSegment(rawValue: $0) ?? .myRecipes }
                )
            )
            .padding(.horizontal, Theme.Spacing.md)
```

- [ ] **Step 3: Branch the body on the segment**

Wrap the existing browse/search block (the whole `if searchText.isEmpty { ... } else { ... }`, lines 103-148) so it only renders for `.myRecipes`, and render Discover otherwise:

```swift
            if segment == .discover {
                DiscoverView(model: discoverModel, tasteTags: tasteTags)
            } else if searchText.isEmpty {
                // ...existing browse-mode content (collections/category/chips/countHeader/grid) unchanged...
            } else {
                // ...existing search-mode content unchanged, with the EmptyStateView change from Step 5...
            }
```

- [ ] **Step 4: Wire submit-to-search**

Find the `.searchable(text: $searchText, prompt: ...)` modifier (line 161) and add an `.onSubmit(of: .search)` right after it:

```swift
        .onSubmit(of: .search) {
            if segment == .discover {
                Task { await discoverModel.search(searchText) }
            }
        }
```

- [ ] **Step 5: Add the "Find some in Discover" nudge to the library empty state**

Replace the search-mode `EmptyStateView` (lines 134-139) with:

```swift
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Nothing matches",
                    message: "Try describing it differently — or discover new recipes for “\(searchText)”.",
                    actionLabel: "Find some in Discover",
                    action: {
                        segment = .discover
                        Task { await discoverModel.search(searchText) }
                    }
                )
```

- [ ] **Step 6: Build and run the full test suite**

Run:
```bash
cd /Users/omarlahmimi/Documents/Glutt
xcodebuild test -project Glutt.xcodeproj -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED and all tests pass (existing + the new `Discover*` tests).

- [ ] **Step 7: Manual verification (simulator)**

Launch the app, open Recipes:
1. Confirm the `My Recipes | Discover` control appears under the search bar; My Recipes is selected and behaves exactly as before.
2. Search a dish you have NO saved recipe for → confirm the empty state shows "Find some in Discover"; tap it → lands in Discover with results for that query.
3. Tap Discover with the search empty → suggested clips appear and autoplay (muted).
4. Type a dish, submit → results load one card at a time; "Show me next" advances; "Save" shows progress then "Saved ✓" and advances; the recipe appears in My Recipes with the YouTube source.
5. Re-save the same clip → it dedups (no duplicate in My Recipes).

- [ ] **Step 8: Commit**

```bash
git add Glutt/Features/Recipes/RecipesView.swift
git commit -m "feat(discover): wire My Recipes | Discover segment into Recipes screen"
```

---

### Task 9: Backend — Vercel proxy `/discover/search` + `/discover/suggested`

**Files:** *(separate `glutt-sable` Vercel repo — not in this iOS project)*
- Create: `api/discover/search.js` (or `.ts`)
- Create: `api/discover/suggested.js`
- Config: set `YOUTUBE_API_KEY` env var in the Vercel project; reuse the existing `x-glutt-proxy-key` check used by the chat endpoint.

This task lives in the backend repo, so it has no XCTest cycle. It is verified with `curl`. The iOS side is already fully unit-tested against the agreed JSON contract, so iOS work is not blocked by this — but the feature is not usable end-to-end until this ships.

- [ ] **Step 1: Implement `/api/discover/search`**

Behavior: validate `x-glutt-proxy-key`; read `q` and optional `pageToken`; call YouTube Data API `search.list` with `part=snippet`, `type=video`, `q`, `videoDuration=short`, `videoEmbeddable=true`, `safeSearch=moderate`, `maxResults=10`, `pageToken`; map items into the agreed shape; **cache by normalized `q`+`pageToken`** (e.g. Vercel KV or in-function memo with a TTL) to protect quota. Reference call:

```js
// api/discover/search.js  (Vercel serverless function, Node)
export default async function handler(req, res) {
  if (req.headers['x-glutt-proxy-key'] !== process.env.GLUTT_PROXY_KEY) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  const q = (req.query.q || '').toString().trim();
  if (!q) return res.status(400).json({ error: 'missing q' });
  const pageToken = (req.query.pageToken || '').toString();

  const url = new URL('https://www.googleapis.com/youtube/v3/search');
  url.searchParams.set('key', process.env.YOUTUBE_API_KEY);
  url.searchParams.set('part', 'snippet');
  url.searchParams.set('type', 'video');
  url.searchParams.set('q', `${q} recipe`);
  url.searchParams.set('videoDuration', 'short');
  url.searchParams.set('videoEmbeddable', 'true');
  url.searchParams.set('safeSearch', 'moderate');
  url.searchParams.set('maxResults', '10');
  if (pageToken) url.searchParams.set('pageToken', pageToken);

  const r = await fetch(url);
  if (!r.ok) return res.status(502).json({ error: 'youtube error' });
  const data = await r.json();
  const videos = (data.items || [])
    .filter(it => it.id && it.id.videoId)
    .map(it => ({
      videoId: it.id.videoId,
      title: it.snippet.title,
      creator: it.snippet.channelTitle,
      thumbnailURL: it.snippet.thumbnails?.high?.url ?? null,
      durationSeconds: null, // optionally enrich via videos.list?part=contentDetails
    }));
  res.setHeader('Cache-Control', 's-maxage=86400, stale-while-revalidate');
  return res.status(200).json({ videos, nextPageToken: data.nextPageToken ?? null });
}
```

- [ ] **Step 2: Implement `/api/discover/suggested`**

Behavior: validate the key; read optional `tags`; pick a dish query from a curated rotating list, optionally biased by `tags`; either call `search.list` with that query or serve a curated `videoId` list. Return the same shape. Cache aggressively (these are near-static).

- [ ] **Step 3: Verify with curl against the deployed endpoints**

```bash
curl -s -H "x-glutt-proxy-key: <key>" \
  "https://glutt-sable.vercel.app/api/discover/search?q=tofu" | jq '.videos[0]'
curl -s -H "x-glutt-proxy-key: <key>" \
  "https://glutt-sable.vercel.app/api/discover/suggested" | jq '.videos | length'
```
Expected: a JSON object matching the agreed contract (`videos[]` with `videoId`/`title`, optional `nextPageToken`).

- [ ] **Step 4: File a YouTube Data API quota-increase request** before launch (default ~10,000 units/day ≈ 100 searches/day; `search.list` costs 100 units/call). Note this is a launch dependency, not a build blocker.

- [ ] **Step 5: Commit (in the backend repo)**

```bash
git add api/discover/search.js api/discover/suggested.js
git commit -m "feat: discover search + suggested endpoints (YouTube Data API)"
```

---

### Task 10 (optional): "Watch the video" embed on recipe detail

**Files:**
- Modify: `Glutt/Features/Recipes/RecipeDetailView.swift`

**Interfaces:**
- Consumes: `YouTubePlayerView`, `Recipe.sourceURL`, `Recipe.sourcePlatform`.

Because the saved recipe stores its YouTube `sourceURL`, the detail screen can replay the original clip with the same player. Pure helper extracted for testability.

- [ ] **Step 1: Write the failing test**

```swift
// add to GluttTests/YouTubeEmbedTests.swift
func testExtractsVideoIdFromWatchURL() {
    XCTAssertEqual(YouTubeEmbed.videoId(from: "https://www.youtube.com/watch?v=abc123"), "abc123")
    XCTAssertEqual(YouTubeEmbed.videoId(from: "https://youtu.be/xyz789"), "xyz789")
    XCTAssertNil(YouTubeEmbed.videoId(from: "https://example.com/foo"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `... -only-testing:GluttTests/YouTubeEmbedTests/testExtractsVideoIdFromWatchURL`
Expected: FAIL — `type 'YouTubeEmbed' has no member 'videoId'`.

- [ ] **Step 3: Add the extractor to `YouTubeEmbed`**

```swift
    static func videoId(from urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString) else { return nil }
        if comps.host?.contains("youtu.be") == true {
            return comps.path.split(separator: "/").last.map(String.init)
        }
        if comps.host?.contains("youtube.com") == true {
            return comps.queryItems?.first { $0.name == "v" }?.value
        }
        return nil
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Render the player in detail when the source is YouTube**

In `RecipeDetailView.swift`, where source/header content renders, add (guarded):

```swift
if recipe.sourcePlatform == .youtube,
   let urlString = recipe.sourceURL,
   let id = YouTubeEmbed.videoId(from: urlString) {
    YouTubePlayerView(videoId: id)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.segment, style: .continuous))
}
```

- [ ] **Step 6: Build, then commit**

Run: `xcodebuild build -project Glutt.xcodeproj -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

```bash
git add Glutt/Features/Discover/YouTubePlayerView.swift GluttTests/YouTubeEmbedTests.swift Glutt/Features/Recipes/RecipeDetailView.swift
git commit -m "feat(discover): play original YouTube clip on recipe detail"
```

---

## Self-Review

**Spec coverage** (against `2026-06-19-glutt-discover-design.md`):
- Mode switch `My Recipes | Discover`, library default → Task 8 (Steps 1-3).
- Library dead-end nudge → Discover with query carried over → Task 8 (Step 5).
- Discover suggested-on-open → Task 5 (`loadSuggested`) + Task 7 (`.task`).
- Submit-driven Discover search → Task 8 (Step 4).
- One card at a time + Save / Show me next → Task 5 + Task 6.
- Autoplaying official IFrame playback (no AVPlayer, no download) → Task 4.
- Save reuses import pipeline, non-blocking, auto-advance, dedup → Task 3 + Task 5 (`save`).
- Backend `/discover/search` + `/discover/suggested`, key server-side, caching, quota → Task 9.
- Error/empty states → Task 7; failure handling in VM → Task 5.
- Testing strategy (parsing, VM logic, dedup, reuse import tests) → Tasks 1-5 tests.
- Optional detail embed → Task 10.
- Out-of-scope guardrails (no TikTok search, no persisted video model) → honored: `DiscoverVideo` is transient; no TikTok code added.

**Placeholder scan:** no TBD/TODO; every code step is complete. The only deferred item (true suggested-feed pagination) is explicitly scoped out with a code comment, not a silent gap.

**Type consistency:** `DiscoverVideo`/`DiscoverResponse` (Task 1) are consumed unchanged in Tasks 2/3/5/6/7. `DiscoverService.search/suggested` signatures match the VM `Dependencies` closures (Task 5). `DiscoverSaver.save(video:importDraft:into:)` matches its test and the `Dependencies.live.save` adapter. `YouTubeEmbed.html(videoId:)` / `.videoId(from:)` consistent across Tasks 4 and 10. `RecipeSegment` is used consistently in Task 8.
