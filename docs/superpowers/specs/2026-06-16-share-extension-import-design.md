# In-extension recipe import (ReCime-style)

**Date:** 2026-06-16
**Status:** Approved design — ready for implementation planning

## Problem

When a user shares a link to Glutt today, the share extension (`GluttShare/ShareViewController.swift`)
only stashes the URL in the app group and shows "Saved! Open Glutt to review the import," then
dismisses. All real work — fetch, parse, AI cleanup, review, save — happens later inside the main
app the next time it is opened. The share interaction is a dead end: it never shows the recipe and
forces a context switch into the app.

## Goal

Run the entire import inside the share sheet, ReCime-style. The window stays open and walks the
user through:

```
importing ─▶ preview ─┬─▶ saved ─┬─▶ "Add more recipes" → close window (user stays in TikTok/IG)
   │                  │          └─▶ "View recipe"       → open Glutt to that recipe
   │                  └─▶ Discard → close window
   └─▶ failed ─▶ "Close"  (Instagram-blocked keeps the screenshot tip + "Open in Glutt")
```

The user never gets handed off to the app unless they explicitly choose "View recipe."

## Decisions (locked during brainstorming)

1. **Edit depth in the sheet:** preview + quick edits. The recipe preview is read-only except for
   an editable **title** and a **servings** stepper. Full ingredient/step editing and
   collection-picking stay in the app.
2. **Import quality:** full AI pipeline. The extension runs the same
   `DraftCleanup` cleanup / reconstruct / infer-steps passes the app uses today. Quality over
   raw speed; loading states cover the wait.
3. **Persistence:** import inbox (not a shared SwiftData store). The extension writes a finished,
   self-contained recipe payload into the app group; the app drains it into SwiftData on next
   foreground or when deep-linked open. No database migration, small extension footprint.

## Architecture

### Flow / state machine

The extension becomes a small SwiftUI surface hosted in `ShareViewController` via
`UIHostingController`, driven by one view model with these states:

- **importing** — animated loading showing the live status line the pipeline already emits
  ("Reading the recipe…" → "Cleaning it up with AI…" → "Drafting the steps…"). Runs the full
  pipeline: `RecipeImportService.importFrom(url:)` then the `DraftCleanup` passes
  (`wouldImprove`/`cleanUp`, `reconstruct` for caption-less social video, `inferSteps` when steps
  are missing) — mirroring `ImportRecipeView.startLinkImport()`.
- **preview** — recipe image, editable title, `by @creator`, editable servings stepper, and
  read-only summary counts ("🥢 8 ingredients · 📝 6 steps · 20 min") with tap-to-expand
  ingredient/step lists. Buttons: **Save recipe** / **Discard**.
- **saved** — confirmation with **Add more recipes** and **View recipe**.
- **failed** — friendly error from `ImportError.errorDescription`. The Instagram-blocked case keeps
  its honest screenshot guidance and offers **Open in Glutt** (falls back to the legacy
  stash-URL-and-open path).

Actions:
- **Save recipe** → apply edited title/servings to the draft, `ImportInbox.append(draft)`, go to **saved**.
- **Discard** → `extensionContext.completeRequest` (close, return to source app).
- **Add more recipes** → `extensionContext.completeRequest` (close; user stays in the source app).
- **View recipe** → `extensionContext.open(glutt://recipe?import=<draftID>)`, then complete.
- **Close** (failed) → complete.
- **Open in Glutt** (failed) → `PendingImportStore.save(urlString:)` + `extensionContext.open(glutt://import?url=…)`.

### Code sharing (via `project.yml`)

Add shared file membership to the `GluttShare` target — no new framework. Files compiled into both
the app and the extension:

- **Import core:** `ImportedRecipeDraft`, `RecipeHTMLParser`, `SocialMediaImport`,
  `IngredientLineParser`, `Enums` (for `SourcePlatform`).
- **AI:** `LLMClient`, `Secrets`, `DraftCleanup`, `ImagePrep`.
- **Link-import path of `RecipeImportService`.** Split the Vision/OCR `importFrom(imageData:)` (and
  `recognizeText`) into a new app-only file `RecipeImportService+OCR.swift`, leaving the
  link-import path (`importFrom(urlString:)`, `importFrom(url:)`) — which has no `Vision`/UIKit
  dependency — in the shared file. The extension never compiles `Vision`.
- **Design tokens:** `Theme`, `Typography` for visual consistency with the app.
- **New:** `ImportInbox` (app-group store).

`ImportedRecipeDraft` gains `Codable` conformance; it is the inbox payload. Its existing `id: UUID`
is the correlation key for the "View recipe" deep link.

### Persistence — the Import Inbox

New `ImportInbox` (shared) replaces the single-URL `PendingImportStore` as the handoff mechanism,
upgrading it from "a URL" to "a queue of finished recipes":

- `ImportInbox.append(_ draft: ImportedRecipeDraft)` — extension calls on **Save**, with edited
  title/servings already applied. Persists as a JSON array in the app-group container
  (`group.com.omarlahmimi.glutt`). Append-only so multiple "Add more" saves queue up.
- `ImportInbox.drain() -> [ImportedRecipeDraft]` — app reads and clears the queue.

`PendingImportStore` is retained only for the failure fallback ("Open in Glutt").

### draft → Recipe mapping (`RecipeFactory`)

The `draft → Recipe` construction currently inside `ImportReviewView.save()` (building
`RecipeIngredient` via `IngredientLineParser`, `RecipeStep` with `detectDuration`, copying
nutrition/tags/source fields) is extracted into a shared **`RecipeFactory.make(from: ImportedRecipeDraft) -> Recipe`**.
Both the in-app review screen and the inbox drain call it — one source of truth. `RecipeFactory`
lives in the app target (it builds SwiftData models); the extension never uses it.

### App-side drain & "View recipe" deep link

- `RootView`'s `scenePhase == .active` handler replaces `router.checkForSharedImport()` with
  `drainImportInbox(into: modelContext)`: drains the inbox, builds each `Recipe` via
  `RecipeFactory`, inserts into the context, and records an in-session `draftID → Recipe` map.
- `Router.handle(url:)` gains a `recipe` case: `glutt://recipe?import=<draftID>` sets
  `recipeToOpenImportID`.
- On launch/foreground the app drains first, then if `recipeToOpenImportID` matches a just-drained
  recipe it switches to the **Recipes** tab and pushes `RecipeDetailView` for it. No `Recipe`
  schema change — correlation is in-session during drain. If no match (already drained on a prior
  launch), fall back to the Recipes tab.

### In-app flow unchanged

The `+` button → `ImportRecipeView` (paste link / screenshot) keeps its current behavior; it only
changes internally to call `RecipeFactory`. The legacy "stash URL → open app" path survives solely
as the extension's failure fallback.

## Error handling

- Import errors surface via existing `ImportError.errorDescription`. The extension shows the
  **failed** state with **Close**; Instagram-blocked additionally keeps the screenshot tip and
  offers **Open in Glutt**.
- AI passes remain non-load-bearing: any `DraftCleanup` failure returns the original draft (as
  today), so a degraded preview still shows rather than an error.
- `ImportInbox` read/write failures are non-fatal: a failed append surfaces a "couldn't save"
  message in the sheet; a failed/corrupt drain is logged and the queue cleared to avoid a poison
  pill blocking future imports.

## Testing

- `RecipeFactory.make(from:)` — pure unit tests: ingredient parsing (qty/unit/name/note), step
  duration detection, nutrition/tags/source field mapping.
- `ImportInbox` round-trip — append → drain → empty, and multi-item queue order, against a test
  app-group suite.
- `ImportedRecipeDraft` `Codable` round-trip — all fields including issues/flags survive.
- Extension state machine — importing → preview → saved → (add more | view recipe), and
  importing → failed, as a testable view model with the import pipeline injected/mocked.

## Out of scope (future)

- Full ingredient/step editing and collection-picking inside the extension.
- Downloading/caching the recipe image inside the extension (the app's `AsyncImage` handles the
  remote URL on open).
- A shared live SwiftData store (revisit only if the app needs to see new recipes while already
  foregrounded — not part of this flow).
- Screenshot/photo import from the share extension (remains an in-app path).
