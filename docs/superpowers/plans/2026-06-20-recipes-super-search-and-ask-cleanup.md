# Recipes Super-Search, Ask Cleanup & Card/Detail Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the AI "super search" onto the Recipes search bar (with meal-slot/time/mood folded in), strip the Ask sheet to invent-only, improve the no-match → Discover hand-off, lift the Cook button above the tab bar, and de-scrunch grid stat pills.

**Architecture:** The Recipes search already runs the on-device semantic engine (`RecipeSearchEngine`) per keystroke. We add an LLM ranking pass (factored out of `AskGlutt`) that fires on submit: it reorders/annotates the on-device results and writes a conversational headline, degrading silently to on-device order when AI is off or fails. The Ask sheet (`WhatToCookView`) is reduced to only the Invent feature; the now-orphaned recommender (`MealRecommender`) and old `AskGlutt.ask` path are deleted. Two UI fixes (Cook-button inset, compact grid pills) are independent.

**Tech Stack:** SwiftUI (iOS 17+), SwiftData, on-device `NLEmbedding`, backend-proxied LLM (`LLMClient`), XcodeGen (`project.yml` is source of truth), XCTest. Build/run/test via **XcodeBuildMCP** (`build_run_sim`, `test_sim`, `screenshot`) — not raw xcodebuild.

## Global Constraints

- iOS 17+, SwiftUI + SwiftData. Match surrounding code style (Theme tokens, `Ph` icons, `.gluttPrimary`/`.gluttSecondary`, `.cardStyle()`).
- **Every AI feature must degrade gracefully without the LLM.** `LLMClient.isConfigured == false` → no error, fall back to on-device behavior.
- Never invent recipes in search; the LLM only ranks the user's existing recipes.
- LLM calls are **on submit only**, never per keystroke. Timeout 20s.
- After adding/removing any source file, run `xcodegen generate` before building (project is XcodeGen-generated).
- Use XcodeBuildMCP for all build/run/test/screenshot. Confirm `session_show_defaults` once per session before the first build.
- Keep every commit building. Tasks are ordered so the build stays green.

---

### Task 1: AskGlutt — add the Recipes-search ranking layer

Adds a reusable, testable LLM ranking pass that operates over on-device search results. Additive only — the existing `AskGlutt.ask` stays until Task 5.

**Files:**
- Modify: `Glutt/Services/AI/AskGlutt.swift` (add members; touch nothing existing)
- Create: `GluttTests/AskGluttTests.swift`

**Interfaces:**
- Consumes: `RecipeSearchEngine.SearchResult` (`{ recipe: Recipe, score: Double, reasons: [String] }`), `LLMClient.chatJSON`, `Recipe.totalMinutes`, `PantryItem`.
- Produces (used by Task 2):
  - `AskGlutt.RankedResult { let recipe: Recipe; let reasons: [String]; let badge: String? }`
  - `AskGlutt.RankedSearch { var headline: String?; var results: [RankedResult]; var usedAI: Bool }`
  - `static func rankSearch(query: String, results: [RecipeSearchEngine.SearchResult], pantry: [PantryItem]) async -> RankedSearch`
  - `AskGlutt.Pick { let index: Int; let reason: String?; let badge: String? }` and `static func reorder<T>(_ items: [T], picks: [Pick]) -> [(item: T, reason: String?, badge: String?)]` (both `internal`, for tests)

- [ ] **Step 1: Write the failing tests**

Create `GluttTests/AskGluttTests.swift`:

```swift
import XCTest
@testable import Glutt

final class AskGluttTests: XCTestCase {

    func testReorderPutsPicksFirstThenRemainderInOriginalOrder() {
        let items = ["a", "b", "c", "d"]
        let picks = [
            AskGlutt.Pick(index: 2, reason: "r2", badge: "B2"),
            AskGlutt.Pick(index: 0, reason: "r0", badge: nil),
        ]
        let out = AskGlutt.reorder(items, picks: picks)
        XCTAssertEqual(out.map(\.item), ["c", "a", "b", "d"])
        XCTAssertEqual(out[0].reason, "r2")
        XCTAssertEqual(out[0].badge, "B2")
        XCTAssertEqual(out[1].reason, "r0")
        XCTAssertNil(out[1].badge)
        XCTAssertNil(out[2].reason)   // "b" was not picked
        XCTAssertNil(out[3].reason)   // "d" was not picked
    }

    func testReorderSkipsOutOfRangeAndDuplicatePicks() {
        let items = ["a", "b"]
        let picks = [
            AskGlutt.Pick(index: 5, reason: "x", badge: nil),   // out of range
            AskGlutt.Pick(index: 1, reason: "r1", badge: nil),
            AskGlutt.Pick(index: 1, reason: "dup", badge: nil), // duplicate
        ]
        let out = AskGlutt.reorder(items, picks: picks)
        XCTAssertEqual(out.map(\.item), ["b", "a"])
        XCTAssertEqual(out[0].reason, "r1")
    }

    func testReorderWithNoPicksKeepsOriginalOrderAndNoAnnotations() {
        let out = AskGlutt.reorder(["a", "b", "c"], picks: [])
        XCTAssertEqual(out.map(\.item), ["a", "b", "c"])
        XCTAssertTrue(out.allSatisfy { $0.reason == nil && $0.badge == nil })
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Use XcodeBuildMCP `test_sim` (scheme `Glutt`).
Expected: FAIL — `AskGlutt.Pick` / `AskGlutt.reorder` not found (compile error).

- [ ] **Step 3: Add `Pick` + `reorder` to AskGlutt**

In `Glutt/Services/AI/AskGlutt.swift`, inside `enum AskGlutt`, add (place after the `Answer` struct):

```swift
    // MARK: - Recipes-search ranking

    /// One model pick, mapping a position in the candidate list to a reason/badge.
    struct Pick {
        let index: Int
        let reason: String?
        let badge: String?
    }

    /// Pure reordering: picked items first (in pick order, de-duplicated, bounds-checked),
    /// then the untouched remainder in original order. No network, no SwiftData — testable.
    static func reorder<T>(_ items: [T], picks: [Pick]) -> [(item: T, reason: String?, badge: String?)] {
        var used = Set<Int>()
        var out: [(item: T, reason: String?, badge: String?)] = []
        for pick in picks {
            guard items.indices.contains(pick.index), !used.contains(pick.index) else { continue }
            used.insert(pick.index)
            out.append((items[pick.index], pick.reason, pick.badge))
        }
        for (i, item) in items.enumerated() where !used.contains(i) {
            out.append((item, nil, nil))
        }
        return out
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Use XcodeBuildMCP `test_sim`.
Expected: PASS (3 tests in `AskGluttTests`).
(If the new test file isn't picked up, run `xcodegen generate` first, then `test_sim`.)

- [ ] **Step 5: Add the `rankSearch` entry + result types + LLM request**

In `Glutt/Services/AI/AskGlutt.swift`, inside `enum AskGlutt`, add:

```swift
    struct RankedResult {
        let recipe: Recipe
        let reasons: [String]
        let badge: String?
    }

    struct RankedSearch {
        var headline: String?
        var results: [RankedResult]
        var usedAI: Bool
    }

    /// Rank/annotate the user's on-device search hits with one LLM round trip.
    /// Falls back to the on-device order (no headline) when AI is off or fails.
    /// Never drops a recipe — only reorders and annotates.
    static func rankSearch(
        query: String,
        results: [RecipeSearchEngine.SearchResult],
        pantry: [PantryItem]
    ) async -> RankedSearch {
        let passthrough = results.map {
            RankedResult(recipe: $0.recipe, reasons: $0.reasons, badge: nil)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !results.isEmpty, LLMClient.isConfigured else {
            return RankedSearch(headline: nil, results: passthrough, usedAI: false)
        }
        guard let llm = await requestRanking(query: trimmed, results: results, pantry: pantry) else {
            return RankedSearch(headline: nil, results: passthrough, usedAI: false)
        }
        let picks = llm.picks.map { Pick(index: $0.index, reason: $0.reason, badge: $0.badge) }
        let ranked = reorder(results, picks: picks).map { entry in
            RankedResult(
                recipe: entry.item.recipe,
                reasons: entry.reason.map { [$0] } ?? entry.item.reasons,
                badge: entry.badge
            )
        }
        return RankedSearch(headline: llm.headline, results: ranked, usedAI: true)
    }

    private static func requestRanking(
        query: String,
        results: [RecipeSearchEngine.SearchResult],
        pantry: [PantryItem]
    ) async -> LLMAnswer? {
        let system = """
        You are Glutt, a no-nonsense kitchen sidekick. The user is searching THEIR OWN
        saved recipes (numbered below). Pick the ones that best fit their query —
        never invent recipes, only choose from the list.

        Return JSON: {"headline": str, "picks": [{"index": int, "reason": str, "badge": str}]}
        - picks: 1-4 recipes, best first; index refers to the numbered list. Omit ones that don't fit.
        - reason: one short, specific, casual sentence tied to their request ("creamy and ready in 25 min").
        - badge: 1-3 words ("Closest match", "Fastest", "Uses your salmon").
        - headline: one friendly line summarizing what you found. Keep it clean-ish.
        - Respect explicit constraints (time, cravings, ingredients, meal type, mood) strictly.
        """

        let list = results.enumerated().map { index, result -> String in
            let recipe = result.recipe
            var line = "\(index). \(recipe.title) — \(recipe.totalMinutes) min"
            if !recipe.tags.isEmpty { line += ", tags: \(recipe.tags.joined(separator: "/"))" }
            if let rating = recipe.rating { line += ", rated \(rating)/5" }
            return line
        }.joined(separator: "\n")

        let useSoon = pantry.filter { $0.useSoonDate != nil && $0.roughQuantity != .out }.map(\.name)
        var user = "User searched: \"\(query)\"\n\nTheir recipes:\n\(list)"
        if !useSoon.isEmpty {
            user += "\n\nIngredients that need using soon: \(useSoon.joined(separator: ", "))"
        }

        do {
            return try await LLMClient.chatJSON(
                LLMAnswer.self,
                system: system,
                user: user,
                temperature: 0.4,
                timeout: 20
            )
        } catch {
            return nil
        }
    }
```

> Note: `LLMAnswer` (with its `Pick` decode shape `{index, reason, badge}`) already exists privately in `AskGlutt.swift` (used by the old `askLLM`). `requestRanking` reuses it. Do not redefine it.

- [ ] **Step 6: Build to verify it compiles**

Use XcodeBuildMCP `build_sim` (or `build_run_sim`).
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Glutt/Services/AI/AskGlutt.swift GluttTests/AskGluttTests.swift
git commit -m "feat(search): add AskGlutt.rankSearch ranking layer for recipes search"
```

---

### Task 2: RecipesView — improved no-match → Discover hand-off

Small, self-contained: swap the existing "Nothing matches" empty-state for a warmer hand-off that carries the query into Discover. Defined first so Task 3's wiring can reference it.

**Files:**
- Modify: `Glutt/Features/Recipes/RecipesView.swift`

**Interfaces:**
- Consumes: `segment`, `discoverModel.search`, `searchText`.
- Produces: `discoverHandoff` computed view (referenced by Task 3).

- [ ] **Step 1: Add the `discoverHandoff` view**

Add to `RecipesView` (near the other private views, e.g. after `recipeLink`):

```swift
    /// Shown when the library has nothing matching the query — points the user to Discover,
    /// carrying the same query into the Discover feed.
    private var discoverHandoff: some View {
        EmptyStateView(
            icon: "sparkle.magnifyingglass",
            title: "Nothing like that in your kitchen yet",
            message: "You don't have a recipe for “\(searchText)” — but Discover probably does. Want me to go look?",
            actionLabel: "Find it in Discover",
            action: {
                Haptics.impact(.light)
                segment = .discover
                Task { await discoverModel.search(searchText) }
            }
        )
    }
```

- [ ] **Step 2: Swap the inline empty-state for `discoverHandoff`**

In `body`, in the non-empty-search branch, replace the existing inline empty-state (original lines 156–166):

```swift
                        let results = searchResults
                        if results.isEmpty {
                            EmptyStateView(
                                icon: "magnifyingglass",
                                title: "Nothing matches",
                                message: "Try describing it differently — or discover new recipes for \"\(searchText)\".",
                                actionLabel: "Find some in Discover",
                                action: {
                                    segment = .discover
                                    Task { await discoverModel.search(searchText) }
                                }
                            )
                        } else {
```

with:

```swift
                        let results = searchResults
                        if results.isEmpty {
                            discoverHandoff
                        } else {
```

(Leave the rest of the branch — the `LazyVStack` of `recipeLink`s — unchanged for now; Task 3 reworks it.)

- [ ] **Step 3: Build**

XcodeBuildMCP `build_sim`. Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Simulator check**

`build_run_sim`, search a term the library lacks (e.g. "tofu with an asian flair").
Expected: the new hand-off card; tapping "Find it in Discover" switches to the Discover tab and runs the query. `screenshot` to confirm.

- [ ] **Step 5: Commit**

```bash
git add Glutt/Features/Recipes/RecipesView.swift
git commit -m "feat(search): warmer no-match -> Discover hand-off with seeded query"
```

---

### Task 3: RecipesView — wire the super search on submit

The list filters live as you type (unchanged). On Return, fire `rankSearch`, show a headline banner, a thinking indicator, and AI-reordered/annotated results. Stale answers are dropped when the query changes. `discoverHandoff` (Task 2) already exists.

**Files:**
- Modify: `Glutt/Features/Recipes/RecipesView.swift`

**Interfaces:**
- Consumes: `AskGlutt.rankSearch`, `AskGlutt.RankedResult` (Task 1), `discoverHandoff` (Task 2), existing `recipeLink(_:reasons:)`, `searchResults`, `discoverModel`.
- Produces: nothing for later tasks.

- [ ] **Step 1: Add AI search state**

In `RecipesView`, after `@State private var discoverModel = DiscoverFeedViewModel()` (line 23), add:

```swift
    @State private var aiHeadline: String?
    @State private var aiResults: [AskGlutt.RankedResult]?
    /// The trimmed query the AI answer corresponds to (for staleness checks).
    @State private var aiQuery = ""
    @State private var isRanking = false
```

- [ ] **Step 2: Replace the non-empty search branch to render AI results when fresh**

In `body`, replace the search-results `else` branch (now `} else {` after `if results.isEmpty { discoverHandoff }`, originally lines 154–175) so the whole branch reads:

```swift
                    } else {
                        let results = searchResults
                        if results.isEmpty {
                            discoverHandoff
                        } else {
                            if isRanking {
                                rankingIndicator
                            }
                            if let aiResults, aiQuery == searchText.trimmingCharacters(in: .whitespaces) {
                                if let aiHeadline, !aiHeadline.isEmpty {
                                    searchHeadlineBanner(aiHeadline)
                                }
                                LazyVStack(spacing: Theme.Spacing.md) {
                                    ForEach(aiResults, id: \.recipe.persistentModelID) { result in
                                        recipeLink(result.recipe, reasons: aiReasons(for: result))
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                            } else {
                                LazyVStack(spacing: Theme.Spacing.md) {
                                    ForEach(results, id: \.recipe.persistentModelID) { result in
                                        recipeLink(result.recipe, reasons: result.reasons)
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                    }
```

- [ ] **Step 3: Update `onSubmit` to run the AI pass on My Recipes**

Replace the existing `.onSubmit(of: .search)` block (lines 189–193) with:

```swift
            .onSubmit(of: .search) {
                if segment == .discover {
                    Task { await discoverModel.search(searchText) }
                } else {
                    runAIRanking()
                }
            }
            .onChange(of: searchText) {
                // Editing the query invalidates a stale AI answer.
                if searchText.trimmingCharacters(in: .whitespaces) != aiQuery {
                    aiResults = nil
                    aiHeadline = nil
                }
            }
```

- [ ] **Step 4: Add the helper views + `runAIRanking`**

Add these methods to `RecipesView` (e.g. just after `discoverHandoff`):

```swift
    private func runAIRanking() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let results = searchResults
        guard !query.isEmpty, !results.isEmpty else { return }
        Haptics.impact(.light)
        isRanking = true
        aiResults = nil
        aiHeadline = nil
        Task {
            let outcome = await AskGlutt.rankSearch(query: query, results: results, pantry: pantryItems)
            // Only apply if the query hasn't changed since we fired.
            if searchText.trimmingCharacters(in: .whitespaces) == query {
                aiResults = outcome.results
                aiHeadline = outcome.headline
                aiQuery = query
            }
            isRanking = false
        }
    }

    private func aiReasons(for result: AskGlutt.RankedResult) -> [String] {
        var chips: [String] = []
        if let badge = result.badge, !badge.isEmpty { chips.append(badge) }
        chips.append(contentsOf: result.reasons)
        return Array(chips.prefix(3))
    }

    private var rankingIndicator: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView()
            Text("Glutt's thinking…")
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func searchHeadlineBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Ph.sparkle.regular
                .resizable().scaledToFit().frame(width: 18, height: 18)
                .foregroundStyle(Theme.Colors.accent)
            Text(text)
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.horizontal, Theme.Spacing.md)
    }
```

- [ ] **Step 5: Build**

XcodeBuildMCP `build_sim`. Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Simulator check**

`build_run_sim`, go to Recipes, type a query (instant filter), press Return.
Expected: brief "Glutt's thinking…", then a headline banner + reordered results with reason/badge chips. With AI off, results just stay in on-device order, no error.
`screenshot` to confirm.

- [ ] **Step 7: Commit**

```bash
git add Glutt/Features/Recipes/RecipesView.swift
git commit -m "feat(search): AI super-search on Recipes (headline + ranked results on submit)"
```

---

### Task 4: WhatToCookView — strip to Invent-only

Replace the whole file. Removes the free-text ask, the meal-slot/time/mood recommender, the results/shuffle UI, and all their state. Keeps only Invent. Adds an AI-off notice (Invent requires the LLM). `invent` now passes `maxMinutes: nil` (the time chips that fed it are gone; the hint field covers time preferences).

**Files:**
- Modify (full replace): `Glutt/Features/Assistant/WhatToCookView.swift`

**Interfaces:**
- Consumes: `PantryChef.invent`, `InventionPaywallHook`, `ImportedRecipeDraft`, `ImportReviewView`, `MealType`, `UserPrefs.current`, `LLMClient.isConfigured`.
- Produces: still a no-arg `WhatToCookView()` (TodayView's sheet keeps working).
- Stops consuming: `AskGlutt.ask`, `MealRecommender` (enables Task 5 deletion).

- [ ] **Step 1: Replace the file contents**

Overwrite `Glutt/Features/Assistant/WhatToCookView.swift` with:

```swift
import SwiftData
import SwiftUI

/// "Invent a dish from what I have" — Glutt spins up an original recipe built
/// around the user's on-hand ingredients. Search and recommendations now live
/// on the Recipes page; this sheet does invention only.
struct WhatToCookView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantryItems: [PantryItem]

    @State private var isInventing = false
    @State private var inventMealType: MealType?
    @State private var inventHint = ""
    /// The current inline idea shown for review before saving.
    @State private var inventedDraft: ImportedRecipeDraft?
    /// Separate handle for the full review/save sheet.
    @State private var reviewDraft: ImportedRecipeDraft?
    /// Titles proposed this session, so "Something else" never repeats them.
    @State private var inventedTitles: [String] = []
    @State private var inventError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if LLMClient.isConfigured {
                        inventCard
                    } else {
                        aiOffNotice
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Invent a dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $reviewDraft) { draft in
                NavigationStack {
                    ImportReviewView(draft: draft) {
                        reviewDraft = nil
                        inventedDraft = nil
                    }
                    .navigationTitle("Your new recipe")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { reviewDraft = nil }
                        }
                    }
                }
            }
            .alert("Couldn't invent a dish", isPresented: Binding(
                get: { inventError != nil },
                set: { if !$0 { inventError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(inventError ?? "")
            }
        }
    }

    private var aiOffNotice: some View {
        EmptyStateView(
            icon: "sparkles",
            title: "Invention needs the AI service",
            message: "This build isn't connected to Glutt's AI yet, so dish invention is unavailable. You can still browse and search your recipes on the Recipes tab."
        )
    }

    // MARK: - Invent from pantry

    private var onHandItems: [PantryItem] {
        pantryItems.filter { $0.roughQuantity != .out }
    }

    private var canInvent: Bool {
        LLMClient.isConfigured && onHandItems.count >= 2
    }

    private var inventCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Ph.magicWand.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(canInvent ? Theme.Colors.accent : Theme.Colors.textSecondary)
                Text("Invent a dish from what I have")
                    .font(.gluttHeadline)
                    .foregroundStyle(canInvent ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            }

            if canInvent {
                Text("A brand-new recipe built around your \(pantryPreview) — not one of your saved ones.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                inventControls

                if let draft = inventedDraft {
                    inventedPreview(draft)
                }
            } else {
                Text("Add a couple of things to your kitchen and Glutt will spin up an original recipe from what you have.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Button {
                } label: {
                    Text("Make something new")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttPrimary)
                .disabled(true)
            }
        }
        .cardStyle()
    }

    /// Meal-type chips + an optional free-text steer, then the generate button.
    private var inventControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    selectableChip("Any", isSelected: inventMealType == nil) {
                        inventMealType = nil
                    }
                    ForEach(MealType.allCases) { type in
                        selectableChip(type.label, isSelected: inventMealType == type) {
                            inventMealType = type
                        }
                    }
                }
            }

            TextField("Optional: \"feed 4\", \"something light\", \"quick & easy\"", text: $inventHint, axis: .vertical)
                .font(.gluttBody)
                .lineLimit(1...2)
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

            Button {
                Haptics.impact(.medium)
                invent(excludingCurrent: false)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if isInventing { ProgressView().tint(.white) }
                    Text(isInventing ? "Cooking up an idea…" : "Make something new")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.gluttPrimary)
            .disabled(isInventing)
        }
    }

    private func inventedPreview(_ draft: ImportedRecipeDraft) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(draft.title ?? "New dish")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            if let summary = draft.summary, !summary.isEmpty {
                Text(summary)
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            HStack(spacing: Theme.Spacing.md) {
                if let servings = draft.servings {
                    Label("\(servings) servings", systemImage: "person.2")
                }
                let mins = (draft.prepMinutes ?? 0) + (draft.cookMinutes ?? 0)
                if mins > 0 {
                    Label("\(mins) min", systemImage: "clock")
                }
            }
            .font(.gluttCaption)
            .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    reviewDraft = draft
                } label: {
                    Text("Save this recipe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttSecondary)
                Button {
                    invent(excludingCurrent: true)
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        if isInventing { ProgressView() }
                        Text("Something else")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttSecondary)
                .disabled(isInventing)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var pantryPreview: String {
        let names = onHandItems
            .sorted { ($0.useSoonDate != nil ? 0 : 1) < ($1.useSoonDate != nil ? 0 : 1) }
            .prefix(3)
            .map { $0.name.lowercased() }
        switch names.count {
        case 0: return "ingredients"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]), and more"
        }
    }

    /// - Parameter excludingCurrent: when true (the "Something else" path), the
    ///   dish currently on screen is added to the avoid-list so the model is
    ///   forced to return a clearly different idea.
    private func invent(excludingCurrent: Bool) {
        guard !isInventing else { return }
        if excludingCurrent, let current = inventedDraft?.title {
            if !inventedTitles.contains(current) { inventedTitles.append(current) }
        }
        // Premium gate: AI recipe invention is a paid feature (currently open for
        // the free launch). The hook runs the block immediately when ungated.
        InventionPaywallHook.presentBeforeInventing {
            isInventing = true
            let prefs = UserPrefs.current(in: context)
            let hint = inventHint.trimmingCharacters(in: .whitespacesAndNewlines)
            let avoid = Array(inventedTitles.suffix(6))
            Task {
                let draft = await PantryChef.invent(
                    pantry: pantryItems,
                    prefs: prefs,
                    hint: hint.isEmpty ? nil : hint,
                    maxMinutes: nil,
                    mealType: inventMealType,
                    avoidTitles: avoid
                )
                isInventing = false
                if let draft {
                    Haptics.notify(.success)
                    inventedDraft = draft
                    if let title = draft.title, !inventedTitles.contains(title) {
                        inventedTitles.append(title)
                    }
                } else {
                    inventError = "Glutt couldn't spin up a dish from your pantry right now. Add a few more items, or try again."
                }
            }
        }
    }

    private func selectableChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.gluttCaption.weight(.medium))
                .foregroundStyle(isSelected ? .white : Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.08))
                .clipShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build**

XcodeBuildMCP `build_sim`. Expected: BUILD SUCCEEDED. (`AskGlutt.ask` and `MealRecommender` are now unused but still present — that's fine; Task 5 removes them.)

- [ ] **Step 3: Simulator check**

`build_run_sim`, open the Ask/Invent sheet (via Today "Ask" for now). Expected: only the Invent card (plus AI-off notice path if applicable). `screenshot` to confirm.

- [ ] **Step 4: Commit**

```bash
git add Glutt/Features/Assistant/WhatToCookView.swift
git commit -m "refactor(assistant): reduce Ask sheet to invent-only"
```

---

### Task 5: Remove orphaned recommender + old AskGlutt paths

After Task 4, nothing calls `AskGlutt.ask` or `MealRecommender`. Delete them. Replace `AskGlutt.swift` with the trimmed version (keeps only `RecipeSearchEngine`-based ranking from Task 1).

**Files:**
- Modify (full replace): `Glutt/Services/AI/AskGlutt.swift`
- Delete: `Glutt/Services/AI/MealRecommender.swift`

**Interfaces:**
- Removes: `AskGlutt.ask`, `AskGlutt.Answer`, `AskGlutt.Candidate`, `AskGlutt.candidateList`, `AskGlutt.askLLM`, and all of `MealRecommender`.
- Keeps: `AskGlutt.Pick`, `reorder`, `RankedResult`, `RankedSearch`, `rankSearch`, `requestRanking`, `LLMAnswer`.

- [ ] **Step 1: Verify nothing else references the removed symbols**

```bash
grep -rn "MealRecommender" Glutt --include="*.swift" | grep -v "MealRecommender.swift"
grep -rn "AskGlutt.ask\b\|AskGlutt.Answer" Glutt GluttTests --include="*.swift"
```
Expected: no results (both empty). If anything prints, stop and resolve it before deleting.

- [ ] **Step 2: Replace `AskGlutt.swift` with the trimmed version**

Overwrite `Glutt/Services/AI/AskGlutt.swift` with:

```swift
import Foundation

/// Recipes-search ranking: take the user's on-device semantic search hits and,
/// when the LLM is configured, reorder + annotate them and write a one-line
/// headline. One round trip; graceful on-device fallback when AI is off.
enum AskGlutt {

    struct RankedResult {
        let recipe: Recipe
        let reasons: [String]
        let badge: String?
    }

    struct RankedSearch {
        var headline: String?
        var results: [RankedResult]
        var usedAI: Bool
    }

    /// One model pick, mapping a position in the candidate list to a reason/badge.
    struct Pick {
        let index: Int
        let reason: String?
        let badge: String?
    }

    // MARK: - Entry point

    /// Rank/annotate the user's on-device search hits with one LLM round trip.
    /// Falls back to the on-device order (no headline) when AI is off or fails.
    /// Never drops a recipe — only reorders and annotates.
    static func rankSearch(
        query: String,
        results: [RecipeSearchEngine.SearchResult],
        pantry: [PantryItem]
    ) async -> RankedSearch {
        let passthrough = results.map {
            RankedResult(recipe: $0.recipe, reasons: $0.reasons, badge: nil)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !results.isEmpty, LLMClient.isConfigured else {
            return RankedSearch(headline: nil, results: passthrough, usedAI: false)
        }
        guard let llm = await requestRanking(query: trimmed, results: results, pantry: pantry) else {
            return RankedSearch(headline: nil, results: passthrough, usedAI: false)
        }
        let picks = llm.picks.map { Pick(index: $0.index, reason: $0.reason, badge: $0.badge) }
        let ranked = reorder(results, picks: picks).map { entry in
            RankedResult(
                recipe: entry.item.recipe,
                reasons: entry.reason.map { [$0] } ?? entry.item.reasons,
                badge: entry.badge
            )
        }
        return RankedSearch(headline: llm.headline, results: ranked, usedAI: true)
    }

    // MARK: - Pure reordering (testable)

    /// Picked items first (in pick order, de-duplicated, bounds-checked), then the
    /// untouched remainder in original order. No network, no SwiftData.
    static func reorder<T>(_ items: [T], picks: [Pick]) -> [(item: T, reason: String?, badge: String?)] {
        var used = Set<Int>()
        var out: [(item: T, reason: String?, badge: String?)] = []
        for pick in picks {
            guard items.indices.contains(pick.index), !used.contains(pick.index) else { continue }
            used.insert(pick.index)
            out.append((items[pick.index], pick.reason, pick.badge))
        }
        for (i, item) in items.enumerated() where !used.contains(i) {
            out.append((item, nil, nil))
        }
        return out
    }

    // MARK: - LLM ranking

    private struct LLMAnswer: Decodable {
        struct Pick: Decodable {
            let index: Int
            let reason: String
            let badge: String?
        }
        let headline: String?
        let picks: [Pick]
    }

    private static func requestRanking(
        query: String,
        results: [RecipeSearchEngine.SearchResult],
        pantry: [PantryItem]
    ) async -> LLMAnswer? {
        let system = """
        You are Glutt, a no-nonsense kitchen sidekick. The user is searching THEIR OWN
        saved recipes (numbered below). Pick the ones that best fit their query —
        never invent recipes, only choose from the list.

        Return JSON: {"headline": str, "picks": [{"index": int, "reason": str, "badge": str}]}
        - picks: 1-4 recipes, best first; index refers to the numbered list. Omit ones that don't fit.
        - reason: one short, specific, casual sentence tied to their request ("creamy and ready in 25 min").
        - badge: 1-3 words ("Closest match", "Fastest", "Uses your salmon").
        - headline: one friendly line summarizing what you found. Keep it clean-ish.
        - Respect explicit constraints (time, cravings, ingredients, meal type, mood) strictly.
        """

        let list = results.enumerated().map { index, result -> String in
            let recipe = result.recipe
            var line = "\(index). \(recipe.title) — \(recipe.totalMinutes) min"
            if !recipe.tags.isEmpty { line += ", tags: \(recipe.tags.joined(separator: "/"))" }
            if let rating = recipe.rating { line += ", rated \(rating)/5" }
            return line
        }.joined(separator: "\n")

        let useSoon = pantry.filter { $0.useSoonDate != nil && $0.roughQuantity != .out }.map(\.name)
        var user = "User searched: \"\(query)\"\n\nTheir recipes:\n\(list)"
        if !useSoon.isEmpty {
            user += "\n\nIngredients that need using soon: \(useSoon.joined(separator: ", "))"
        }

        do {
            return try await LLMClient.chatJSON(
                LLMAnswer.self,
                system: system,
                user: user,
                temperature: 0.4,
                timeout: 20
            )
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 3: Delete MealRecommender**

```bash
git rm Glutt/Services/AI/MealRecommender.swift
xcodegen generate
```

- [ ] **Step 4: Build + run tests**

XcodeBuildMCP `build_sim` then `test_sim`.
Expected: BUILD SUCCEEDED; `AskGluttTests` still pass.

- [ ] **Step 5: Commit**

```bash
git add Glutt/Services/AI/AskGlutt.swift project.yml Glutt.xcodeproj
git commit -m "refactor(ai): drop orphaned MealRecommender and legacy AskGlutt.ask path"
```

---

### Task 6: TodayView — re-point the three assistant entry points

Split per decision: "Ask" quick action → renamed "Invent" opening the invent sheet; "Nothing planned" card and "Find a recipe" button → jump to the Recipes tab (the new super search).

**Files:**
- Modify: `Glutt/Features/Today/TodayView.swift`

**Interfaces:**
- Consumes: `router.selectedTab` (`AppTab`, settable), `AppTab.recipes`, `isAskingWhatToCook`.

- [ ] **Step 1: Rename the "Ask" quick action to "Invent"**

In `quickActionsRow` (around lines 451–454), replace:

```swift
            quickAction("Ask", icon: Ph.sparkle.regular) {
                Haptics.selection()
                isAskingWhatToCook = true
            }
```

with:

```swift
            quickAction("Invent", icon: Ph.magicWand.regular) {
                Haptics.selection()
                isAskingWhatToCook = true
            }
```

- [ ] **Step 2: Re-point the "Nothing planned" empty-day card to Recipes**

In `emptyDayCard` (around lines 410–433), replace the button action and copy:

```swift
    private var emptyDayCard: some View {
        Button {
            Haptics.impact(.light)
            router.selectedTab = .recipes
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                Ph.sparkle.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Theme.Colors.accent)
                Text("Nothing planned — find something to cook")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Search your recipes or discover something new")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .buttonStyle(.plain)
        .cardStyle()
    }
```

- [ ] **Step 3: Re-point the "Find a recipe" use-soon button to Recipes**

Around line 513, replace:

```swift
            Button("Find a recipe") {
                ...
                isAskingWhatToCook = true
            }
```

with (keep the surrounding modifiers/styling as-is; only change label + action body):

```swift
            Button("Find a recipe") {
                Haptics.impact(.light)
                router.selectedTab = .recipes
            }
```

> Verify the exact existing lines (512–517) and preserve any haptics/styling already present; only the navigation target changes from `isAskingWhatToCook = true` to `router.selectedTab = .recipes`.

- [ ] **Step 4: Build**

XcodeBuildMCP `build_sim`. Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Simulator check**

`build_run_sim`. From Today: "Invent" opens the invent sheet; the empty-day card and "Find a recipe" switch to the Recipes tab. `screenshot` each.

- [ ] **Step 6: Commit**

```bash
git add Glutt/Features/Today/TodayView.swift
git commit -m "feat(today): Ask->Invent quick action; plan cards jump to Recipes search"
```

---

### Task 7: Lift the Cook button above the tab bar

Keep the tab bar; ensure the Cook bar renders fully above it. Introduce a shared height constant and verify on-simulator (this is a visual bug — confirm with screenshots, tune the value if needed).

**Files:**
- Modify: `Glutt/DesignSystem/Components/GluttTabBar.swift`
- Modify: `Glutt/Features/Recipes/RecipesView.swift`
- Modify: `Glutt/Features/Recipes/RecipeDetailView.swift`

**Interfaces:**
- Produces: `GluttTabBar.reservedHeight: CGFloat`.

- [ ] **Step 1: Add a shared reserved-height constant**

In `Glutt/DesignSystem/Components/GluttTabBar.swift`, add inside `struct GluttTabBar` (top of the struct, before `body`):

```swift
    /// Vertical footprint the bar occupies over content. Screens that pin
    /// content/CTAs to the bottom use this to clear the bar. Keep in sync with
    /// the bar's layout (top padding + glyph/label height).
    static let reservedHeight: CGFloat = 76
```

- [ ] **Step 2: Use the constant in RecipesView**

In `Glutt/Features/Recipes/RecipesView.swift` line 179, replace:

```swift
            .contentMargins(.bottom, 76, for: .scrollContent)
```

with:

```swift
            .contentMargins(.bottom, GluttTabBar.reservedHeight, for: .scrollContent)
```

- [ ] **Step 3: Lift the Cook bar above the floating tab bar**

In `Glutt/Features/Recipes/RecipeDetailView.swift`, update `cookBar` (around lines 389–402) so it clears the tab bar. Change its trailing padding/background block to:

```swift
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, GluttTabBar.reservedHeight)
        .background(Theme.Colors.background.opacity(0.95))
```

(Previously it had `.padding(.bottom, Theme.Spacing.sm)`. The bar floats over content, so the Cook button must be lifted by the bar's footprint.)

- [ ] **Step 4: Build + simulator verify (tune the value)**

`build_run_sim`, open a recipe from Recipes, `screenshot`.
Acceptance: the Cook button is fully visible and tappable, sitting just above the tab bar with a small, even gap — no overlap and no large dead space.
If there's a large gap → the global safe-area inset is already partially accounting for the bar; reduce the `.padding(.bottom, …)` (e.g. to `GluttTabBar.reservedHeight - 34` to discount the home indicator) and re-screenshot.
If still overlapped → increase toward `GluttTabBar.reservedHeight`.
Tap the Cook button to confirm it's hittable (not just visible). Verify on one home-indicator sim (e.g. iPhone 15) and one without if available.

- [ ] **Step 5: Commit**

```bash
git add Glutt/DesignSystem/Components/GluttTabBar.swift Glutt/Features/Recipes/RecipesView.swift Glutt/Features/Recipes/RecipeDetailView.swift
git commit -m "fix(recipes): lift Cook button above the bottom tab bar"
```

---

### Task 8: Compact grid stat pills (Time + Difficulty only)

In grid view, render only Time + Difficulty, with a short difficulty label so two pills never crush. List/detail keep all four pills.

**Files:**
- Modify: `Glutt/Models/Enums.swift` (add `Difficulty.shortLabel`)
- Modify: `Glutt/DesignSystem/Components/RecipeCard.swift` (add `compact` flag)
- Modify: `Glutt/Features/Recipes/RecipesView.swift` (`recipeLink` `compact` param; grid passes `true`)

**Interfaces:**
- Produces: `Difficulty.shortLabel: String`; `RecipeCard(recipe:pantryMatch:compact:)` with `compact` defaulting to `false`; `recipeLink(_:reasons:compact:)`.

- [ ] **Step 1: Add a short difficulty label**

In `Glutt/Models/Enums.swift`, inside `enum Difficulty`, add after `var label`:

```swift
    /// Compact label for tight layouts (grid cards).
    var shortLabel: String {
        switch self {
        case .beginner: return "Easy"
        case .intermediate: return "Med"
        case .advanced: return "Hard"
        }
    }
```

- [ ] **Step 2: Add `compact` to RecipeCard and branch the stat row**

In `Glutt/DesignSystem/Components/RecipeCard.swift`, add the property after `pantryMatch`:

```swift
    /// Tight layouts (2-up grid) show only Time + Difficulty to avoid crushing.
    var compact: Bool = false
```

Replace `statRow` (lines 72–86) with:

```swift
    @ViewBuilder private var statRow: some View {
        HStack(spacing: 8) {
            StatPill.time(recipe.timeLabel)
            StatPill.difficulty(compact ? recipe.difficulty.shortLabel : recipe.difficulty.label)
            if !compact {
                if let rating = recipe.rating {
                    StatPill.rating("\(rating)")
                }
                if let pantryMatch, pantryMatch.total > 0 {
                    StatPill(icon: Ph.basket.fill,
                             text: "\(pantryMatch.owned)/\(pantryMatch.total)",
                             foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
                }
            }
            Spacer(minLength: 0)
        }
    }
```

- [ ] **Step 3: Thread `compact` through `recipeLink` and the grid**

In `Glutt/Features/Recipes/RecipesView.swift`, change the `recipeLink` signature (line 247) to:

```swift
    private func recipeLink(_ recipe: Recipe, reasons: [String], compact: Bool = false) -> some View {
```

and update the `RecipeCard(...)` call inside it (lines 251–254) to pass `compact`:

```swift
                RecipeCard(
                    recipe: recipe,
                    pantryMatch: (match.ownedCount, match.totalCount),
                    compact: compact
                )
```

Then in the grid branch (line 141), change the call to:

```swift
                                        recipeLink(recipe, reasons: [], compact: true)
```

(Leave the list-view and search-results calls as-is — they default to `compact: false`.)

- [ ] **Step 4: Build**

XcodeBuildMCP `build_sim`. Expected: BUILD SUCCEEDED. (`CollectionDetailView`'s `RecipeCard(recipe:)` still compiles — `compact` and `pantryMatch` both default.)

- [ ] **Step 5: Simulator verify**

`build_run_sim`, Recipes → toggle the grid icon. Expected: two clean pills per card (e.g. "30 min" + "Med"), no scrunch; list view still shows all four pills. `screenshot` both.

- [ ] **Step 6: Commit**

```bash
git add Glutt/Models/Enums.swift Glutt/DesignSystem/Components/RecipeCard.swift Glutt/Features/Recipes/RecipesView.swift
git commit -m "fix(recipes): de-scrunch grid cards (compact Time+Difficulty pills)"
```

---

## Final verification (after all tasks)

- [ ] `test_sim` green (AskGluttTests pass).
- [ ] Manual sweep on simulator (`screenshot` each):
  - Recipes: type → instant filter; submit → headline + reordered + reason/badge chips; AI-off path stays silent.
  - Search a missing dish → improved Discover hand-off → tap → Discover tab runs the query.
  - Ask/Invent sheet: only the Invent feature; AI-off shows the notice.
  - Today: "Invent" opens invent; empty-day card & "Find a recipe" jump to Recipes.
  - Recipe detail: Cook button fully visible + tappable above the tab bar.
  - Grid view: pills no longer scrunched; list view unchanged.
- [ ] `git log --oneline` shows one focused commit per task.

## Out of scope (documented in the spec, deferred)

- **Image persistence** (download-on-import, backfill, durable storage). The disappearing-image cause is diagnosed in the design doc; no code change this round.
- No new discrete meal-slot/time/mood filter chips (AI interprets them from the query text).

## Self-review notes

- **Spec coverage:** §A→Tasks 1 + 3; §B→Task 1 (LLM prompt respects constraints) + Task 3; §C→Tasks 4–5; §D→Task 2; §E→Task 7; §F→Task 8; images→out of scope. All covered.
- **Green builds:** ordering keeps `AskGlutt.ask`/`MealRecommender` alive until their last caller (`WhatToCookView`) is cleaned in Task 4, then removed in Task 5.
- **Type consistency:** `RankedResult`/`RankedSearch`/`Pick`/`reorder`/`rankSearch` names identical across Tasks 1, 2, 5; `compact` defaulted everywhere; `GluttTabBar.reservedHeight` shared by Tasks 7.
