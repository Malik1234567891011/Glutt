# Durable Recipe Images — Design

**Date:** 2026-06-21
**Status:** Approved (design); pending spec review → implementation plan

## Summary

Imported recipe images disappear over time. Fix it by downloading each recipe's image **once**, downscaling it, and storing the bytes locally in `recipe.imageData` (already durable via `@Attribute(.externalStorage)`), instead of depending on a remote URL at render time. A background sweep on app foreground heals existing URL-only recipes; the same path runs after each import so new recipes are cached promptly.

## Problem / diagnosis

`Recipe` (`Glutt/Models/Recipe.swift`) can hold its image three ways:
- `imageAssetName` — bundled asset (seed data only)
- `imageData` — actual bytes, durable (`@Attribute(.externalStorage)`, SwiftData-managed)
- `imageURL` — a remote URL **string**, no local copy

`RecipeImageView` (`Glutt/DesignSystem/Components/RecipeImageView.swift`) renders in that priority order, falling back to `AsyncImage(url:)` for the URL case, then a placeholder.

**Root cause:** link imports (`RecipeHTMLParser`) save only `imageURL` — the picture is never downloaded. Every render re-fetches it via `AsyncImage`, whose only persistence is the system URL cache in `/Library/Caches`, which **iOS purges at will** (storage pressure, time). Remote URLs also rot (CDN expiry, auth/region walls, edited/deleted posts). When either happens there is no local copy → the image vanishes → placeholder. This is the user's "had an image, then it's gone."

(Share-extension imports do capture bytes but route through a fragile app-group `UserDefaults` queue; **hardening that path is explicitly out of scope** for this change — see Non-goals.)

## Goals

- An imported recipe's image survives cache purges and source-URL rot.
- Existing URL-only recipes in the library get healed automatically.
- No change to how images are displayed; no change to import parsing.
- Modest, bounded storage (~150–250 KB/image at 1280px).
- Graceful: failures never break the UI; the live URL still renders until bytes exist.

## Non-goals

- Hardening the share-extension `ImportInbox` handoff (separate, smaller reliability issue).
- Any second image size / thumbnail. One display-sized image per recipe.
- Changing `Recipe`, `RecipeImageView`, or importer parsing.
- Re-caching recipes that already have `imageData` or a bundled `imageAssetName`.

## Design

### New component: `RecipeImageBackfill`

A single small service (`Glutt/Services/Import/RecipeImageBackfill.swift`) with three responsibilities and an injectable fetcher for testability.

- **`typealias Fetch = (URL) async throws -> Data`** — the network seam. Default implementation uses `URLSession.shared`.

- **`static func downloadAndPrepare(from urlString: String, fetch: Fetch = defaultFetch) async -> Data?`**
  - Parse `urlString` → `URL`; fetch raw bytes; run through `ImagePrep.prepareForVision(_, maxDimension: 1280)` (existing utility — resize to ≤1280px longest edge + JPEG q0.65); return the prepared bytes. Returns `nil` on any failure (bad URL, network error, non-image / `ImagePrep` returns nil).

- **`static func needsCaching(_ recipe: Recipe) -> Bool`** (pure, unit-testable)
  - `true` iff `recipe.imageData == nil` **and** `recipe.imageURL` is non-empty **and** `recipe.imageAssetName == nil`.

- **`static func ensure(for recipe: Recipe, in context: ModelContext, fetch: Fetch = defaultFetch) async`**
  - If `!needsCaching(recipe)` → no-op.
  - Else `downloadAndPrepare(from: recipe.imageURL!)`; on success set `recipe.imageData = bytes` and `try? context.save()`. On failure: leave the recipe untouched (URL stays; `AsyncImage` still renders live) and record the URL in the session failed-set.

- **`static func sweep(in context: ModelContext, fetch: Fetch = defaultFetch) async`**
  - Fetch all recipes; filter to `needsCaching` and URL not in the session failed-set; process with a small concurrency cap (e.g. 3 at a time) and a per-sweep ceiling (e.g. 20 recipes) so a large library heals over a few foregrounds rather than spiking. (Ceiling is logged-not-silent: the sweep simply resumes next foreground.)

- **Session failed-set:** an in-memory `Set<String>` of URLs that failed this app run, so a dead URL isn't re-hammered every foreground. Not persisted (YAGNI) — cleared on next launch so transient failures and revived URLs get another chance.

### Triggers (both reuse `sweep`)

- **App foreground:** call `sweep(in:)` from `RootView`'s existing `scenePhase == .active` handler, alongside the current `drainImportInbox()`. Runs as a low-priority `Task`; never blocks UI.
- **After an import:** call `sweep(in:)` once the import materializes recipes — at the end of `ImportInboxDrainer.drain(...)` consumption (share path) and the link-import save path — so new recipes cache promptly without waiting for the next foreground.

> Using one entry point (`sweep`) for both triggers keeps it DRY; `sweep` naturally finds newly-inserted URL-only recipes. `ensure` is the per-recipe primitive `sweep` calls.

### Data flow

```
Import → Recipe(imageURL set, imageData nil)
        → sweep (post-import, and/or next foreground)
        → ensure → downloadAndPrepare (URLSession + ImagePrep 1280/q0.65)
        → recipe.imageData = bytes; context.save()
Display: RecipeImageView (unchanged) now hits the imageData branch → durable local image
```

### Error handling

- Bad/empty URL, network failure, non-image, or `ImagePrep` failure → `downloadAndPrepare` returns `nil` → `ensure` leaves the recipe as-is and adds the URL to the session failed-set. The UI still shows the live `AsyncImage` (or placeholder if that also fails). The next launch retries.
- `context.save()` failure → swallowed (`try?`); the recipe keeps its URL and is retried next sweep. No crash, no data loss.
- Offline: fetches fail fast → recipes stay URL-only → healed on a later foreground when back online.

### Storage

- ~150–250 KB per image at 1280px/q0.65. ~10 MB for 50 recipes, ~100 MB for 500, ~200 MB for 1000 — modest (one camera photo is 2–5 MB). Stored via the existing `.externalStorage` attribute (separate files outside the SQLite store). Net bandwidth *decreases* — no more repeated re-downloads after cache purges.

## Components touched

| Area | File | Change |
|---|---|---|
| Image caching service | `Glutt/Services/Import/RecipeImageBackfill.swift` (new) | `downloadAndPrepare`, `needsCaching`, `ensure`, `sweep`, injectable `Fetch`, session failed-set |
| Foreground trigger | `Glutt/App/RootView.swift` | call `sweep` in the `scenePhase == .active` block (low-priority Task) |
| Post-import trigger | `Glutt/Services/Import/ImportInboxDrainer.swift` (+ link-import save path) | call `sweep` after recipes are materialized |
| Tests | `GluttTests/RecipeImageBackfillTests.swift` (new) | predicate, `ensure` with in-memory context + injected fetcher, failed-set behavior |

No changes to `Recipe`, `RecipeImageView`, `RecipeHTMLParser`, `ImagePrep`, or `RecipeFactory` logic.

## Testing

- **`needsCaching` predicate:** returns true only for `imageData==nil && imageURL non-empty && imageAssetName==nil`; false for each excluded case (has bytes / has asset / nil-or-empty URL).
- **`ensure` success:** in-memory `ModelContext`, a recipe with a URL, an injected `fetch` returning a known JPEG → after `ensure`, `recipe.imageData != nil` and decodes to a `UIImage` no larger than 1280px on its longest side.
- **`ensure` no-op:** a recipe that already has `imageData` → injected fetch is never called; bytes unchanged.
- **Failed-set:** an injected `fetch` that throws → `imageData` stays nil; a second `ensure` in the same run does not call `fetch` again (URL is in the session failed-set).
- **(Sweep-level)** optional: a mixed set of recipes → only the URL-only ones are touched, respecting the per-sweep ceiling.
- Real network download is injected away (not unit-tested). Follow existing `GluttTests` patterns (in-memory `ModelContainer`, as in `ImportInboxDrainerTests`/`RecipeFactoryTests`).

## Rollout notes

Additive and self-contained: a new service plus two one-line trigger calls. Safe to ship behind no flag — worst case on any bug is "image stays URL-only," i.e. today's behavior. Verify on-simulator that an imported recipe's image persists after backgrounding/foregrounding.
