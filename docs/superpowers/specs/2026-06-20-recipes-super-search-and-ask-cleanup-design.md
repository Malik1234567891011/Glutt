# Recipes Super-Search, Ask Cleanup, and Recipe-Card/Detail Fixes — Design

**Date:** 2026-06-20
**Status:** Approved (design); pending spec review → implementation plan

## Summary

Five related changes to the Glutt iOS app, plus one diagnosis-only finding:

1. **Move the AI "super search"** from the Ask sheet onto the Recipes page search bar, so the Recipes search becomes "more than autocomplete."
2. **Fold meal-slot / time-budget / mood filtering into that search** (AI interprets it from natural language; no new chips).
3. **Strip the Ask sheet down to Invent-only.**
4. **Improve the "no match → Discover" hand-off** (already half-built) with warmer copy and AI-driven triggering.
5. **Fix the bottom tab bar covering the Cook button** on recipe detail (keep the bar; lift Cook above it).
6. **Fix scrunched stat pills in grid view** (grid cards show Time + Difficulty only; list keeps all four).

Diagnosis-only (no code change this round): **why imported images disappear.**

## Background / current state (as found)

### The Ask sheet — `WhatToCookView`
- File: `Glutt/Features/Assistant/WhatToCookView.swift`. Presented as a `.sheet` from `TodayView` (`TodayView.swift:103`), reachable from several Today entry points (quick action, empty-state card, "use these soon" card, `-ask` deep link).
- It contains **four** feature areas, not two:
  - `askCard` (lines ~135–161) — free-text "super search" → `AskGlutt.ask(...)`.
  - `inventCard` (lines ~177–214) + `inventControls` + `inventedPreview()` — "Invent a dish from what I have" → `PantryChef.invent(...)`. **Keep this only.**
  - `questionCard` (lines ~383–439) — meal-slot / time-budget / mood chips → `MealRecommender`. **Remove.**
  - Results UI: `recommendationCard()` (lines ~458–531), shuffle button, headline display. **Remove.**

### The "super search" — `AskGlutt`
- File: `Glutt/Services/AI/AskGlutt.swift`.
- `AskGlutt.ask(query:recipes:pantry:leftovers:sessions:prefs:) async -> Answer`.
- Two stages: (1) `candidateList(...)` — offline heuristics blending `RecipeSearchEngine` semantic hits + `MealRecommender` recommendability, top 12; (2) `askLLM(...)` — one LLM round trip (`LLMClient.chatJSON`, temp 0.5, 20s timeout) that returns `{ headline, picks:[{index, reason, badge}] }`. Falls back to top-4 candidates if `!LLMClient.isConfigured` or the call fails.
- `Answer { recommendations: [MealRecommender.Recommendation]; headline: String?; usedAI: Bool }`.
- The LLM system prompt already says: "Never invent recipes," "Respect explicit constraints (time, cravings, ingredients) strictly." This is why meal-slot/time/mood can be AI-interpreted from free text.

### The Recipes page — `RecipesView`
- File: `Glutt/Features/Recipes/RecipesView.swift`.
- Search is **already on-device semantic** (not a plain autocomplete): `searchResults` (line 97) calls `RecipeSearchEngine.search(query:recipes:sessions:)`. Driven by `.searchable(text:$searchText, prompt:"creamy chicken thing with lemon…")` (line 188).
- `.onSubmit(of:.search)` (lines 189–193) currently only searches the Discover feed when `segment == .discover`. **This is the hook point for the AI pass on My Recipes.**
- **No-match → Discover already exists** (lines 156–166): an `EmptyStateView` titled "Nothing matches" with action "Find some in Discover" that switches `segment = .discover` and runs `discoverModel.search(searchText)`.
- Existing filters: filter chips (`cookedBefore`, `needsCleanup`, tags), category circles, collections row, sort order (Recently saved / A–Z / Quickest). **No meal-slot/time/mood filters today.**
- Results render via `recipeLink(recipe, reasons:)` (line 247) which already shows reason chips under a card when `reasons` is non-empty.
- Scroll content already reserves `.contentMargins(.bottom, 76, ...)` (line 179) for the tab bar — the magic `76`.

### Recipe card & stat pills
- `Glutt/DesignSystem/Components/RecipeCard.swift` — `statRow` is an `HStack(spacing: 8)` of `StatPill.time`, `StatPill.difficulty`, optional rating pill, optional pantry pill, then `Spacer`. No responsive rule → pills crush in the ~half-width grid cell.
- `Glutt/DesignSystem/Components/StatPill.swift` — fixed internal padding (12×7).
- Grid is a 2-column `LazyVGrid` (RecipesView lines 137–143); grid path calls `recipeLink(recipe, reasons: [])`.

### Tab bar & Cook button
- `Glutt/DesignSystem/Components/GluttTabBar.swift` — custom bar; `.ignoresSafeArea(edges:.bottom)` (line 40); intrinsic height ~56pt.
- `Glutt/App/RootView.swift` — `TabView { … }.safeAreaInset(edge:.bottom){ GluttTabBar(...) }` (lines 30–31). Floating "+" capture button offset `y: -78` (line 101).
- `Glutt/Features/Recipes/RecipeDetailView.swift` — `cookBar` pinned via `.safeAreaInset(edge:.bottom){ cookBar }` (line 53). Detail already suppresses the floating capture button via `router.floatingButtonSuppressors += 1 / -= 1` on appear/disappear (lines 75–76), so the only overlap is the tab bar itself.

### Images (diagnosis only)
- `Recipe` model (`Glutt/Models/Recipe.swift`): `imageURL: String?`, `imageAssetName: String?`, `@Attribute(.externalStorage) imageData: Data?`.
- Display priority in `RecipeImageView.swift`: bundled asset → `imageData` (durable, SwiftData-managed) → `imageURL` via `AsyncImage` (cached only in `/Library/Caches`, OS-purgeable) → placeholder.
- Link imports (`RecipeHTMLParser`) typically save only `imageURL`. Share-extension imports save bytes but route through an app-group `UserDefaults` queue (`ImportInbox`) drained-and-cleared on launch.

## Goals

- Recipes search bar feels like an AI assistant, not autocomplete, while staying instant per-keystroke.
- Ask sheet does exactly one thing: invent a dish from what you have.
- A user searching for something they don't own is gracefully routed to Discover.
- Cook button is always fully visible and tappable.
- Grid cards look intentional and uncrowded.
- No functionality silently lost in the consolidation.

## Non-goals (this round)

- **No image-persistence code changes** (download-on-import, backfill, file storage). Diagnosis documented; fix deferred.
- No new discrete meal-slot/time/mood filter chips on Recipes (AI interprets from text instead).
- No change to Discover's own ranking/feed beyond receiving a seeded query (already supported).
- No change to `MealRecommender` itself (it stays; still used by Today and by `AskGlutt` candidate scoring).

## Design

### A. Recipes search becomes the super search

**Interaction model**
- **Per keystroke:** unchanged — `searchResults` (on-device `RecipeSearchEngine`) filters live. Fast, free, offline.
- **On submit (Return) in `segment == .myRecipes`:** run an AI ranking pass and enter an "AI-answered" display state for the current query:
  - Show a **headline banner** above results (the model's one-liner).
  - **Re-order** results to the AI's picks first; annotate those cards with the AI's `reason` + `badge` via the existing `recipeLink(reasons:)` path.
  - Keep the remaining on-device matches listed beneath the AI picks (nothing hidden).
  - While awaiting the LLM (≤20s), keep on-device results visible with a subtle "Glutt's thinking…" indicator; never block the list.
  - If `!LLMClient.isConfigured` or the call fails/times out → silently remain in plain on-device ranking (no banner, no error).
- Editing the query again (new keystrokes) drops back to the live on-device state until the next submit, so the AI banner never goes stale against a changed query.

**Reusing `AskGlutt`**
- Reuse `AskGlutt`'s LLM ranking rather than duplicate it. Two viable shapes (decide in the plan):
  - (i) Call `AskGlutt.ask(...)` and intersect/order its `recommendations` against the on-device `searchResults`; or
  - (ii) Factor the LLM ranking step (`askLLM`) into a small reusable entry that accepts the on-device candidate list directly, so Recipes search ranks the *same set the user sees* rather than the diet-filtered cookable subset.
- **Preference:** (ii). Recipes search should rank/annotate over the full visible match set (including recipes without steps yet), not silently drop non-cookable recipes the way `candidateList` does. The headline + reasons + badges come from the model; the candidate set comes from `RecipeSearchEngine`.
- The LLM pass must **never invent** recipes (existing system-prompt rule) and must respect explicit time/craving/meal constraints (existing rule) — this is what delivers requirement B.

**State (RecipesView additions, illustrative)**
- `aiHeadline: String?`, `aiRankedIDs: [PersistentIdentifier]` (or ordered recipes), `aiReasons: [ID: (reason, badge)]`, `isAIThinking: Bool`, `aiQuery: String` (the query the AI answer corresponds to, for staleness checks).

### B. Meal-slot / time / mood folded into search
- No UI changes. The AI pass interprets "quick," "light," "dinner," "comfort," "15 min," etc. from the query text (existing system-prompt behavior).
- Existing "Quickest first" sort and tag filter chips remain available and compose with search.

### C. Ask sheet → Invent-only
- In `WhatToCookView`, remove `askCard`, `questionCard`, `recommendationCard()`, the shuffle button, the headline display, and the ask/recommend state (`askText`, `isAsking`, `headline`, `recommendations`, `maxMinutes`, `mood`, `mealSlot`, and the `ask()` / `generate()` functions). Keep all invent state and `inventCard` / `inventControls` / `inventedPreview()`.
- Retitle the sheet to reflect its single purpose (e.g. nav title "Invent a dish"). Update entry-point labels on Today that previously implied "ask/what to cook" so they read correctly for an invent-only destination (audit `TodayView` quick action + empty-state + "use these soon" buttons; reword or re-point as appropriate).
- `AskGlutt` is **not** deleted — it now serves Recipes search. `MealRecommender` is **not** deleted.
- Confirm no other caller depends on the removed `WhatToCookView` sub-views.

### D. No-match → Discover (improve existing)
- Keep the `EmptyStateView` hand-off in `RecipesView` (lines ~156–166) but:
  - Trigger it both when on-device `searchResults` is empty **and** when the AI pass concludes nothing in the library fits.
  - Rewrite copy to be warmer and specific to the typed query. Proposed:
    - **Title:** "Nothing like that in your kitchen yet"
    - **Message:** "You don't have a recipe for "{query}" — but Discover probably does. Want me to go look?"
    - **Action:** "Find it in Discover →" — sets `segment = .discover` and runs `discoverModel.search(searchText)` (unchanged behavior; seeds the same query).
- Use `{query}` = the user's `searchText` verbatim (trimmed) in the message.

### E. Cook button above the tab bar
- Keep the tab bar visible (per decision). Make the Cook bar render as a panel fully above `GluttTabBar`, both visible and tappable, with **no overlap and no large dead gap**.
- Replace the magic `76` with a single shared constant for the tab bar's reserved height (e.g. `GluttTabBar.reservedHeight`), used by both `RecipesView.contentMargins` and the Cook-bar lift, so they can't drift.
- Reconcile the two bottom `safeAreaInset`s so the detail's `cookBar` clears the global bar. Exact mechanism (extra bottom inset on `cookBar` vs. restructuring the inset stacking vs. dropping `ignoresSafeArea` on the bar) to be pinned down via **systematic-debugging + on-simulator screenshot** — the acceptance test is visual, so implementation must verify in the simulator, not by reasoning alone.
- The floating "+" capture button is already suppressed on detail (`floatingButtonSuppressors`), so no additional overlap handling is needed there.

### F. Grid cards: Time + Difficulty only
- Add a `compact: Bool` (default `false`) to `RecipeCard`. When `true`, `statRow` renders only `StatPill.time` + `StatPill.difficulty` (drop rating + pantry pills), single row.
- Thread it through: grid branch in `RecipesView` calls `recipeLink(recipe, reasons: [], compact: true)`; `recipeLink` passes `compact` to `RecipeCard`. List/detail paths keep `compact: false` → all four pills.
- Keep grid layout (2-column `LazyVGrid`) as-is otherwise; the fix is purely which pills render.

## Components touched

| Area | File(s) | Change |
|---|---|---|
| Recipes search AI layer | `RecipesView.swift`, `AskGlutt.swift` | Add AI submit pass, headline banner, AI ordering/annotation; factor reusable LLM ranking |
| Ask cleanup | `WhatToCookView.swift`, `TodayView.swift` | Remove all non-invent UI/state; retitle; fix entry-point labels |
| No-match → Discover | `RecipesView.swift` | New copy; trigger from AI pass too |
| Cook button | `RecipeDetailView.swift`, `GluttTabBar.swift`, `RootView.swift`/`RecipesView.swift` | Shared height constant; lift Cook above bar; verify on sim |
| Grid pills | `RecipeCard.swift`, `RecipesView.swift` | `compact` mode → Time + Difficulty only in grid |
| Images | (spec only) | Diagnosis documented; no code change |

## Error handling / edge cases

- **AI off / not configured / timeout / network error:** Recipes search degrades silently to on-device ranking; no banner, no error toast.
- **Empty query submit:** no AI call; show normal library.
- **Query changes after an AI answer:** AI banner/ordering invalidated (staleness check via `aiQuery`); revert to live on-device until next submit.
- **AI returns picks not in the visible set:** ignore those indices (guard like existing `candidates.indices.contains`).
- **Zero candidates / AI says nothing fits:** show improved Discover hand-off.
- **Diet rules:** Recipes search shows the user's full library matches; the LLM must not surface recipes that violate hard diet/allergy rules in its *picks* (reuse `DietGuard` to filter what the model is allowed to elevate, even though the raw list may still show everything). Confirm desired behavior in the plan.
- **Cook bar:** must clear the bar on devices with and without a home indicator; verify both (e.g. an older + newer simulator).

## Testing

- **Unit:** the reusable LLM-ranking adapter — given a fixed candidate list + a mocked `LLMClient` JSON response, returns expected ordering/headline; on decode failure or timeout returns nil/falls back. (Follow existing test patterns in `GluttTests`.)
- **Unit:** no-match condition correctly identifies empty/again-empty results.
- **Manual / simulator (XcodeBuildMCP):**
  - Recipes: type → instant filter; submit → headline + reordered + reasons; toggle AI-off path.
  - Search a term the library lacks → improved Discover card → tap → lands in Discover with the query run.
  - Ask sheet shows only Invent; all former entry points still land somewhere correct.
  - Recipe detail: Cook button fully visible + tappable above the tab bar (screenshot, both home-indicator and non-home-indicator sims).
  - Grid view: pills no longer scrunched; list view still shows all four.

## Rollout / sequencing notes

- Independent, parallelizable slices: (F) grid pills, (E) Cook button, (C) Ask cleanup, and (A/B/D) the search super-charge. (A) and (D) are coupled (same view, same state). Do (A/B/D) together; (C) depends on (A) only insofar as `AskGlutt` must remain after Ask loses `askCard` — verify `AskGlutt` has no remaining hard dependency on removed `WhatToCookView` code (it doesn't; it's a free function in Services).

## Appendix: Image-loss diagnosis (deferred fix)

**Why images vanish:**
- **Link imports save only a URL string**, not bytes. `RecipeImageView` shows them via `AsyncImage`, whose only persistence is the system URL cache in `/Library/Caches` — which **iOS purges at will** (storage pressure, time). Many source URLs also rot (CDN/auth/region/edited post). Result: "had an image, then it's gone."
- **Share-extension imports save bytes** but pass through an app-group `UserDefaults` queue (`ImportInbox`) that is drained-and-cleared on launch — fragile if interrupted, and `UserDefaults` is not meant for large blobs.

**Recommended future fix (out of scope now):**
- At import time, **download the remote image once and persist the bytes** to `Recipe.imageData` (already `@Attribute(.externalStorage)`), so display no longer depends on a live URL or the purgeable cache.
- One-time **background backfill** for existing URL-only recipes.
- Harden the share-extension handoff (don't clear the inbox until bytes are confirmed materialized into SwiftData).
