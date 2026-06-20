# Glutt Discover — Design Spec

**Date:** 2026-06-19
**Branch:** redesign
**Status:** Approved design, pending implementation plan

## Problem

Search today only ever searches the user's own saved recipes. A user searched
"tofu," got nothing (she had no tofu recipes saved), and concluded the app was
broken. The submit affordance ("arrow-up") also read as non-functional because
submitting an empty-result query produces a blank state. Two real gaps:

1. **Search can't reach beyond the library.** There is no path to discover new
   recipes the user hasn't already imported.
2. **No suggestions.** The user expected the app to help even with an empty
   library — "it should suggest recipes, not only search my uploads."

## Goal

Add a **Discover** mode: search a dish → watch a short cooking video → **Save**
(creates the full recipe) or **Show me next** (skip). Keep the existing
library search as a sibling mode. Make it impossible to hit the original
dead end.

## Key decision: discovery engine is YouTube, not TikTok

The user's first instinct was **live TikTok search**. Research (web-sourced,
adversarially verified, 2026) concluded this is the one path to avoid as a core
feature:

- **No official TikTok API** lets a third-party app keyword-search public videos
  and return playable media. The only official keyword-search endpoint (Research
  API) is academic/non-profit only, commercially prohibited, metadata-only, and
  ~1,000 req/day — unusable for a consumer app.
- **Unofficial scrapers** work technically but: break every few months
  (rotated request signatures); force downloading + re-hosting creators' videos
  (CDN URLs expire in hours, region-locked) — a copyright exposure; cost a few
  hundred $/mo plus storage; and carry **high App Store removal risk** (violates
  TikTok ToS + Apple 5.2.2/5.2.3; precedent: Meta's "OG App," pulled 2022).
  Hiding scraping server-side lowers detection odds, not the violation.
- **YouTube Data API v3** does real keyword search (`q`, `videoDuration=short`,
  `videoEmbeddable=true`) and the official IFrame player plays results in-app
  legally. API is free (quota-limited). Glutt's existing recipe-parsing/save
  engine is exactly the "native value-add" that clears Apple's minimum-
  functionality bar (a plain aggregator would be rejected; Glutt is not one).

**Decision:** Discover is powered by YouTube. TikTok stays available through the
existing paste/share import flow — it is simply never a live search source.

## Approved decisions (summary)

| Area | Decision |
|---|---|
| Discovery engine | YouTube Data API v3 (server-side) + official IFrame player in-app |
| Discovery UX | One card at a time: autoplaying clip + **Save** / **Show me next** |
| Mode toggle | Segmented `My Recipes \| Discover`, defaults to **My Recipes** |
| Library dead-end fix | Empty library-search state nudges → Discover, carrying the query over |
| Discover empty state | Show suggested clips immediately (curated/rotating + taste-profile-biased) |
| Save action | Generate the full recipe now via the existing import pipeline (non-blocking) |
| TikTok | Retained via existing paste/share import only — not a search source |

## Architecture

### Mode switch (Recipes screen)

A segmented control at the top of the Recipes screen:

```
[ My Recipes ]   Discover        ← defaults to My Recipes
🔍 search…
```

- **My Recipes** — unchanged: local semantic search over saved recipes
  (`RecipeSearchEngine`, reactive as-you-type). No changes to this engine.
- **Discover** — the new YouTube feed.
- **Safety net:** when a *My Recipes* search yields nothing, the empty state
  shows *"No saved tofu recipes — find some in Discover"* with a button that
  switches to Discover **with the query carried over** (immediately runs the
  Discover search for "tofu"). This directly closes the original dead end.

### Discover interaction

- Open Discover with no query → **immediately show suggested clips** (rotating
  popular/seasonal dishes, biased by the user's taste profile + cook history).
- User types a dish and **submits** — Discover search is **submit-driven**, not
  live-as-you-type (one deliberate action → one YouTube search; protects quota
  and removes the "nothing happened" confusion). The submit affordance is
  explicit and obvious.
- Results play **one card at a time**:
  - A short vertical cooking clip autoplays (muted, inline) via the official
    YouTube IFrame player.
  - Title + creator shown underneath.
  - **Save** → builds the full recipe (see below).
  - **Show me next** → advances the queue. Prefetch the next 1–2 cards; fetch
    the next results page when the queue runs low.

### Backend (existing Vercel proxy `glutt-sable.vercel.app/api`)

Two new endpoints. The YouTube API key lives only on the backend — never ships
in the app (same pattern as the existing LLM proxy key / `x-glutt-proxy-key`).

| Endpoint | Behavior |
|---|---|
| `GET /api/discover/search?q=&pageToken=` | Calls YouTube `search.list` (`type=video`, `videoDuration=short`, `videoEmbeddable=true`, safe-search), returns normalized list + `nextPageToken`. **Cached by normalized query** to protect quota. |
| `GET /api/discover/suggested` | Returns the empty-state feed from a curated, heavily-cached dish set, optionally biased by a taste-profile hint passed from the app. Near-zero quota cost. |

### iOS components (small, single-purpose)

- **`DiscoverService`** — networking client for the two endpoints (mirrors
  `LLMClient`). Returns `DiscoverVideo` values.
- **`DiscoverVideo`** — lightweight, **non-persisted** model: `videoId`, `title`,
  `creator`, `thumbnailURL`, `durationSeconds`, `watchURL`.
- **`DiscoverFeedViewModel`** — owns the queue, current card index, prefetch,
  pagination, and loading/error/saving state.
- **`YouTubePlayerView`** — a `WKWebView` wrapped in `UIViewRepresentable` that
  loads the YouTube IFrame player for a videoId, autoplay-muted-inline
  (`allowsInlineMediaPlayback = true`, no user-action gate on playback).
- **Discover view** — hosts the card + search field + suggested feed; bound to
  `DiscoverFeedViewModel`.
- **Segmented control** added to the Recipes screen search surface.

### Save flow

`Save` reuses the existing pipeline end to end:

1. Construct the watch URL (`https://www.youtube.com/watch?v={videoId}`).
2. Feed it into the existing **import pipeline** (YouTube path in
   `SocialMediaImport` → `DraftCleanup` LLM → `RecipeFactory` → SwiftData).
3. **Non-blocking:** the card shows inline progress, then "Saved ✓ — View," and
   auto-advances to the next clip (keeps her in the discovery flow).
4. Resulting recipe has `sourcePlatform = .youtube` and the source URL stored.
5. **Dedup:** if the video's source URL is already saved, the button reads
   "Already saved."

Bonus unlocked (optional, not required for v1): because the source URL is
stored, the saved recipe's detail screen can show a "Watch the video" embed
using the same `YouTubePlayerView`.

## Error handling

- No network / YouTube error → friendly retry on the feed.
- Clip won't embed / fails to play → auto-skip with a quiet "Open in YouTube"
  fallback.
- Empty results → *"No clips for 'tofu' — try another dish."*
- Save fails (pipeline error) → toast *"Couldn't build the recipe — try again,"*
  the clip stays in place.
- **Quota discipline** is first-class: submit-driven search + backend caching +
  curated suggestions. File for a YouTube Data API quota increase before launch.

## Testing

- **Unit:** `DiscoverService` JSON parsing (mocked responses); queue /
  pagination / prefetch logic in `DiscoverFeedViewModel`; dedup-on-save;
  watch-URL construction.
- **Reuse:** existing import-pipeline tests for the YouTube path.
- **Manual:** playback smoothness + autoplay; suggested feed on Discover open;
  search → Save → correct recipe; library empty-state → Discover handoff with
  query carried over.

## Scope guardrails (explicitly out)

- No TikTok live search.
- No video downloading / re-hosting.
- No native `AVPlayer` discovery feed (IFrame player only).
- No changes to the My Recipes local search engine.
- No new persisted video fields on `Recipe` (re-embed via the stored source URL).
- Vertical-swipe full-screen feed is a possible v2, not in this scope.

## Open / deferred

- Whether Save should *navigate to* the new recipe vs. stay in the feed —
  current decision is **stay in the feed** (non-blocking) with a "View" action.
  Revisit after dogfooding.
- Taste-profile signal sent to `/api/discover/suggested` — start with top
  tags/cuisines from cook history; refine later.
- YouTube quota-increase application is a launch dependency, not a build blocker.
