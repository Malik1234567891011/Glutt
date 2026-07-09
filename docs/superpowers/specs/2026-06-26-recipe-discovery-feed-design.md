# Glutt — Recipe Discovery Feed ("Plates") Design Doc
**Status:** Design / handoff
**Date:** 2026-06-26
**Audience:** Senior engineer implementing in the Glutt iOS codebase (SwiftUI + SwiftData) with the Vercel proxy backend.
**One-line:** Turn recipe discovery into the emotional centerpiece of Glutt — a full-screen, swipeable, flip-to-reveal feed of gorgeous photo recipes with macros, ingredients, and instructions, that you can save into your cookbook in one gesture.
spoonacular api key:
9a0b8d9f0c25454bbeaad470688443ae
---

## 0. Why this exists (the spark)

The founder posted a TikTok slideshow: slide 1 = a beautiful photo of a finished meal / meal prep; slide 2 = the title + ingredients + instructions + **macros at the top (calories, protein, carbs, fat)** + serving size. It performed well enough that commenters asked for an app.

That exact feeling — *"ooh, that looks incredible → flip → here's how, and here's what's in it"* — is what we are productizing. The magic is:

1. **Aesthetic-first.** Photography leads, edge to edge. No clutter.
2. **One satisfying reveal.** Tap/flip from the hero photo to the "recipe card back" (ingredients + macros + steps + servings), mirroring the slideshow.
3. **Frictionless collecting.** Save to your cookbook with a single, delightful gesture.
4. **Fun, finite, gamified.** Not an infinite doom-scroll — a daily curated **deck** ("Today's Plate") you can complete, plus an optional endless "Explore" mode.

We already have the plumbing (Discover scaffold, import pipeline, image caching, nutrition, taste tags, pantry matching). What we're missing is (a) a beautiful immersive UI and (b) a **content source of macro-complete, photo-rich, structured recipes**. This doc specifies both.

---

## 1. Goals / Non-goals

### Goals
- A full-screen, vertically-paged, photo-led recipe feed that feels like Glutt's signature surface.
- A signature **flip interaction**: front = hero photo + headline stats; back = ingredients, full macros (cal/P/C/F), steps, serving stepper.
- One-gesture **Save** into the existing recipe library (with dedup + offline image durability).
- **Full macros** finally populated and displayed (we already have `carbGrams`/`fatGrams` on `Recipe`).
- A **content engine** that supplies macro-complete, photo-rich, structured recipes legally and at acceptable cost.
- **Personalization** using signals we already compute: taste tags, dietary rules, "can I make this now" pantry match, nutrition goals.
- A **gamified daily deck** ("Today's Plate") + streak + completion moment.

### Non-goals (for v1)
- Creator/user-generated recipe publishing (Phase 3, depends on accounts which are now in-scope — see `plan.md`).
- Video playback in the feed (the existing YouTube Discover on the Recipes tab stays **exactly as-is**; this feed is photo/slideshow-native and lives elsewhere).
- A 6th root tab — the feed is launched from a **"Discover" button on the Today tab**, not a new tab (see §3).
- Full per-ingredient macro editing UI (we display macros; editing stays in the recipe editor).

---

## 2. Naming

- The immersive experience (this doc): the **photo recipe feed**, surfaced via a **"Discover" button on the Today tab**. Internal/file name: **`RecipeFeedView` / "Plates"** to keep it distinct from the existing Recipes-tab Discover.
- The daily curated deck inside it: **"Today's Plate"**.
- The transient feed model in code: `FeedRecipe` (parallel to today's `DiscoverVideo`).
- **Decision (locked):** the existing YouTube **Discover stays exactly as-is** on the Recipes tab (the "Videos" experience). This new photo feed is a **separate surface entered from Today** — the two coexist. Two user-facing entry points is fine; keep them distinct internally:
  - `DiscoverView` / `DiscoverFeedViewModel` → **videos**, on the Recipes tab (unchanged).
  - `RecipeFeedView` / `FeedViewModel` → **photo feed ("Plates")**, opened from Today.

---

## 3. Where it lives (navigation)

**Decision (locked):** This feed is a **new surface launched from a "Discover" entry on the Today tab** (`TodayView`). The existing Discover (YouTube videos) on the Recipes tab is **left completely untouched** — the two are independent.

- **Entry point:** a prominent **"Discover" card/button on Today** — e.g. a hero "Today's Plate is ready 🍳" card showing the deck cover + a peek of 2–3 thumbnails + a couple of taste chips. Tapping it presents the immersive feed. (`TodayView` is the natural home: it's the daily landing surface, so a fresh daily deck belongs here.)
- **Presentation:** `fullScreenCover` (the same mechanism `RootView` already uses for Cook Mode + Onboarding) so the feed is edge-to-edge with no tab bar fighting the immersion.
- **No new root tab;** the 5-tab `GluttTabBar` is unchanged.
- **Deep link:** add host `glutt://plates` (opens the feed) — used by the "Today's Plate" notification. Do **not** repoint or reuse any existing Discover link; the Recipes-tab Discover keeps its current behavior.
- **Floating capture button:** suppress it while the feed is open via `router.floatingButtonSuppressors += 1` (as `RecipeDetailView` does).

**Future option (flagged, not v1):** if it becomes the primary acquisition surface, promote it to a real tab and rebalance `GluttTabBar`. The feed is a self-contained view + VM, so promotion is low-cost later.

---

## 4. The experience (interaction design)

### 4.1 Mental model — two axes + a flip

- **Vertical swipe = browse.** Up/down pages between recipes (one full-screen recipe per page), TikTok-style.
- **Flip = reveal.** Tap the card (or the explicit "Recipe ▸" tab/handle) flips it 180° to the back: ingredients + macros + steps + servings. Tap again (or "Done") flips back.
- **Horizontal gesture = decide (gamified).** Drag right to **Save** (into cookbook), drag left to **Skip / "not for me"** (a soft signal that tunes personalization). Card tilts and a stamp (heart / "skip") fades in as you drag; release past threshold commits with a spring + haptic. This is the "Tinder-for-recipes" delight, but layered cleanly on top of vertical paging.

> Implementation note: vertical paging is the container (`TabView(.page)` rotated to vertical, or a custom paging `ScrollView` with `.scrollTargetBehavior(.paging)` on iOS 17). The **horizontal** drag is a gesture on the card content with a translation threshold; below the threshold it rubber-bands back. Use `.highPriorityGesture` for the horizontal drag so it wins over the pager only once horizontal translation dominates (`abs(dx) > abs(dy)` and `dx` past a small activation distance). Keep vertical paging as the default so accidental skips are rare.

Provide a **buttons-also** path for accessibility and discoverability: a bottom action row (Save / Recipe / Skip) mirrors the gestures. Gestures are the delight; buttons are the floor.

### 4.2 Card front (the hook)

Edge-to-edge hero photo with a bottom gradient scrim (reuse the `RecipeImageView` priority chain + the gradient pattern from `RecipeDetailView.heroHeader`). Overlaid, bottom-aligned:

- **Title** (`Font.gluttLargeTitle`/`gluttTitle`, white, heavy).
- **Source/creator** line (small, secondary white). Attribution is **required** for API content — see §6.4.
- **Headline stat strip** — a compact, glanceable row:
  - ⏱ time (`recipe.timeLabel`), 🔥 calories, a single macro highlight (e.g. "48g protein"), and difficulty.
  - Use the existing `StatPill` family + Phosphor (`Ph.clock`, `Ph.flame`, `Ph.barbell`, `Ph.cellSignalMedium`).
- **"You can make this now" badge** when `PantryMatcher.match` says the pantry covers (most) ingredients — turns browsing into action. Tinted accent pill with `Ph.basket`.
- **Dietary fit chips** when relevant ("Halal ✓", "High-protein") derived from tags + `DietGuard`.
- **Flip affordance:** a clear "Recipe ▸" tab/handle (bottom-right) with `Ph.bookOpen` so users know there's a back. Subtle bounce on first appearance to teach it.
- **Top overlay controls:** close (`Ph.x`), and a small progress indicator for the deck ("3 / 12") — see gamification.

Motion: subtle parallax/scale on the hero as it becomes the focused page; the focused card sits at scale 1.0, neighbors at ~0.94 with reduced opacity (peek).

### 4.3 The flip → card back (the payoff)

3D flip (`rotation3DEffect` around the Y axis, spring animation, swap front/back content at the 90° midpoint, `.rotation3DEffect` with `perspective`). The back is the "slide 2" of the TikTok:

- **Macro header (the star).** A tasteful macro strip pinned at top:
  - Calories large and bold.
  - **Decision (locked): a tri-segment horizontal macro bar**, segments proportional by calorie contribution (protein ×4, carbs ×4, fat ×9 cal/g), with P / C / F labeled as colored pills beneath showing grams. Brand colors: protein = `accent` (herb green), carbs = `warning` (amber), fat = `tomato`. Honest "per serving" label. (Chosen over Apple-Activity rings: rings read as *progress toward a goal*, which would be misleading here — a bar reads as *composition*, which is what we're showing.)
  - If macros are estimated (not from a trusted source), show the `~` / "estimated" treatment we already use (`nutritionIsEstimated`, the `~` convention from `IngredientLineParser`).
- **Servings stepper** (reuse `GluttStepper`) — scales ingredient quantities live, exactly like `RecipeDetailView`.
- **Ingredients** — sectioned list (reuse `IngredientCategoryStyle` + the row styling from `RecipeDetailView.ingredientsTab`), with the "you have / missing" treatment from `PantryMatcher`.
- **Instructions** — numbered steps (reuse the `stepsTab` styling).
- **Primary CTA:** **Save to cookbook** (`.gluttPrimary`) + **Cook** (jumps into existing Cook Mode after save) + **Add to plan**.
- **Done/flip-back** affordance.

> The back is essentially a compact, scrollable `RecipeDetailView` minus the chrome. Heavily reuse existing detail sub-views to avoid divergence. Consider extracting shared sub-views (`IngredientsList`, `StepsList`, `MacroStrip`) so detail and feed-back stay visually identical.

### 4.4 Save interaction (the dopamine)

- Drag-right **or** Save button **or** double-tap the hero (Instagram-style heart burst).
- On commit: `Haptics.celebrate()`, a heart/check burst animation, the card does a quick "tuck into cookbook" motion, then auto-advance to the next recipe (mirror `DiscoverFeedViewModel.showNext()` auto-advance).
- A small toast: "Saved to your cookbook" with an "Undo" affordance.
- Dedup: if already saved (by `sourceURL`), show "Already in your cookbook" and skip the insert (reuse `DiscoverSaver.existingRecipe(forSourceURL:)`).

### 4.5 Gamification layer

- **Today's Plate (daily deck):** **Decision (locked): 12 recipes per day, refreshed once daily at 07:00 local time** (so it's ready as a "good morning, here's today's plate" moment; tie to the notification). A finite, hand-curatable set. Finishing the deck shows a celebratory **end card** ("That's today's plate 🍽 — you explored 12, saved 3") with a streak counter and a "come back tomorrow" hook. Finite = satisfying + cheaper (bounded API calls) + editorially controllable for quality. (Why 12: enough to feel substantial, short enough to *finish* in a sitting — completion is the gamified payoff. Why a fixed daily refresh: makes the deck a habit/ritual and lets us precompute it server-side for ~free, vs hammering the API per request.)
- **Streak:** "🔥 5-day streak" for opening the feed daily (store locally in `UserPrefs` / `UserDefaults`; no backend needed).
- **Discovery counter:** lifetime "recipes discovered / saved" — feeds Progress tab nicely later.
- **Themed decks / "collect the set":** "Meal-Prep Sunday", "15-minute dinners", "High-protein", "Halal favorites". Saving all of a deck unlocks a subtle badge. Reuses the existing `RecipeCollection` concept for the saved set.
- **Explore mode:** an optional endless feed (search- or taste-driven) for users who want more after the daily deck. Uses pagination tokens.
- **Reduced-motion / "calm" respect:** all confetti/parallax gated on `UIAccessibility.isReduceMotionEnabled`.

### 4.6 Aesthetic direction

- Edge-to-edge food photography; everything else floats on gradient scrims and frosted material (`.ultraThinMaterial`, already used in `RecipeDetailView` circle buttons).
- Brand: cream background, herb-green accent, rounded-everything, soft shadows — all via `Theme` tokens. Do **not** hardcode colors.
- Typography via the `Font.glutt*` ramp.
- Motion: spring flips, parallax hero, satisfying save burst. Haptics on every meaningful transition (`Haptics.selection`/`impact`/`celebrate`).
- Optional: a tasteful soft "page turn"/"save" sound (off by default; behind a setting).

---

## 5. Content sourcing strategy (the hard part)

This is what the founder was stuck on. Blindly scraping random recipe blogs for images is **not** viable: the images are copyrighted, quality is inconsistent, and it's legally and operationally fragile (we already do *user-initiated* scraping for imports, which is different from us *republishing* a curated feed). Here are the realistic options and the recommended hybrid.

### 5.1 Options & tradeoffs

| Source | Gives us | Pros | Cons |
|---|---|---|---|
| **Recipe APIs** (Spoonacular, Edamam, Tasty/RapidAPI, TheMealDB) | Title, **hosted licensed image**, structured ingredients, instructions, **full macros (cal/P/C/F)**, servings | Macro-complete + photos + structured = *exactly* the slideshow; scalable | Per-call cost & quotas; attribution required; image style varies; ToS limits on caching/redistribution |
| **Curated/owned catalog** | Hand-picked recipes + owned/licensed images | Best aesthetic control; guaranteed gorgeous first impression; no per-call cost | Manual; doesn't scale infinitely |
| **AI-generated recipe + AI image** (LLM + image model) | Infinite on-brand content | Full control, no licensing, infinite | Image gen cost/latency; AI food images can look uncanny; macro accuracy = our estimator |
| **Web scraping blogs** | Whatever the page has | "Free" | Copyright on images/text; brittle; legal risk — **rejected for a republished feed** |
| **Creator/user-generated** | The TikTok flywheel | Authentic, scalable, community | Needs accounts (now in-scope), moderation, upload tooling — **Phase 3** |

### 5.2 Recommended hybrid (the engine)

A **backend "Feed" service** that produces a normalized `FeedRecipe[]` from three layers, ranked together:

1. **Curated editorial layer (launch quality):** a small, hand-picked DB of beautiful recipes (start ~100–300) with owned/licensed images and verified macros. This guarantees the *first* impression is stunning and gives us full control over "Today's Plate". Authored as JSON/DB rows server-side; can also seed the daily deck.
2. **Recipe-API layer (scale + macros) — Decision (locked): Spoonacular.** Integrate Spoonacular (image + full macros + structured ingredients/instructions + servings + diet/intolerance tags) behind the proxy. Normalize responses into our `FeedRecipe` contract server-side so the client never sees provider-specific shapes. Respect Spoonacular ToS on caching/attribution. (Key handling + endpoint mapping in §7 and Appendix §18.)
3. **AI augmentation (gaps + variety):** when we want a recipe that doesn't exist in the above (e.g., personalized "high-protein halal 15-min" with the user's pantry), generate it with `LLMClient` and optionally an image model. Mark clearly as Glutt-generated (we already have `isAIGenerated` on the draft + the "estimated" macro treatment). Use sparingly (cost) — great for the "Explore"/"Surprise me" tail, not the curated deck.

> **Recommended v1 scope:** ship **layers 1 + 2** (curated deck + Spoonacular-backed Explore/search). Layer 3 is a fast-follow that reuses `PantryChef`/`LLMClient`.

### 5.3 Personalization inputs (we already have these)

- **Taste tags:** `RecipesView.tasteTags` (top tags across saved library). Already passed to Discover.
- **Dietary rules + allergies:** `UserPrefs.dietaryRules`, `allergies`; enforce with `DietGuard` (hard-filter allergy conflicts server- or client-side; surface rule conflicts as the existing warning, never silently hide).
- **"Can I make it now":** `PantryMatcher.match(recipe:pantry:)` → "You can make this now" badge + an optional "Cookable now" deck.
- **Nutrition goals:** `UserPrefs.nutritionMode` (cooking-only / light / gym) → e.g. surface protein-forward recipes in gym mode; show a "fits your protein goal" flag.

### 5.4 Licensing & attribution (compliance — do not skip)

- Every `FeedRecipe` carries `source`, `sourceURL`, `creator/attribution`, and a `license`/provider tag. Display attribution on the card front (small) and on the saved recipe (`Recipe.sourceCreator`/`sourceURL` already exist).
- Honor provider rules on **image hotlinking vs caching** and **how long results may be stored**. Spoonacular/Edamam each have specific terms — encode them in the backend (e.g., don't permanently cache full payloads if disallowed; cache thumbnails per ToS).
- When the user **saves** a recipe, we persist it to *their* library (personal use) and run image backfill — confirm this is within provider ToS (generally fine for personal save; verify per provider).

---

## 6. Data model & schema changes

### 6.1 Activate carbs/fat on `Recipe` (already present, unused)

`Recipe` already declares `carbGrams: Int?`, `fatGrams: Int?`, `nutritionIsEstimated: Bool`. **No migration needed** — just start populating them.

### 6.2 Extend `ImportedRecipeDraft` (the save chokepoint feeds through this)

Add: `carbGrams: Int?`, `fatGrams: Int?`. (`calories`/`proteinGrams` already exist.) This lets API-sourced full macros flow through the existing pipeline.

### 6.3 Extend `RecipeFactory.make(from:)`

Currently sets only `calories`/`proteinGrams`. Add `carbGrams`/`fatGrams`/`nutritionIsEstimated`. This is the **single chokepoint** so every save path benefits.

### 6.4 New transient model: `FeedRecipe`

Parallel to `DiscoverVideo` (transient, `Decodable`, never persisted). The client decodes this from the backend:

```jsonc
// GET {proxy}/feed/daily  and  /feed/search  and  /feed/personalized
{
  "deckTitle": "Today's Plate",          // for daily; null for search
  "recipes": [
    {
      "id": "spoonacular:715538",         // stable provider-scoped id (dedup)
      "title": "Creamy Lemon Chicken Rice Bowl",
      "imageURL": "https://.../715538.jpg",
      "source": "spoonacular",            // spoonacular | curated | glutt-ai
      "sourceURL": "https://.../recipe",  // canonical, used for dedup + attribution
      "creator": "Feast & Flavor",
      "license": "spoonacular",           // for attribution/compliance
      "summary": "Weeknight bowl ...",
      "servings": 4,
      "prepMinutes": 15,
      "cookMinutes": 30,
      "difficulty": "beginner",            // map to Difficulty
      "tags": ["high-protein","dinner","chicken"],
      "dietFlags": ["halal","gluten-free"],// optional, for fit chips + filtering
      "macros": {                          // PER SERVING
        "calories": 620, "protein": 48, "carbs": 55, "fat": 18,
        "estimated": false                 // false = trusted source
      },
      "ingredients": [                      // STRUCTURED — no client re-parsing needed
        { "raw": "600 g chicken thighs", "name": "chicken thighs", "quantity": 600, "unit": "g" },
        { "raw": "2 cups rice", "name": "rice", "quantity": 2, "unit": "cups" }
      ],
      "steps": ["Season the chicken ...", "Sear 4 min per side ...", "..."],
      "nutritionNote": null
    }
  ],
  "nextPageToken": "abc123"               // null for daily deck
}
```

Because the API gives **structured** ingredients/steps + macros, the save path can build an `ImportedRecipeDraft` **directly** (prefill `ingredientLines` = `raw` strings, `stepTexts` = `steps`, macros, servings) and skip scraping + most AI cleanup. Cheaper, faster, more reliable than the YouTube path.

### 6.5 Conversion: `FeedRecipe → ImportedRecipeDraft → RecipeFactory → Recipe`

Add a tiny mapper (e.g. `FeedRecipe.asDraft()` or `FeedRecipeSaver`) that builds a draft and routes through `RecipeFactory.make`. Reuse `DiscoverSaver`'s dedup + image-backfill trigger. **Important:** unlike YouTube Discover, this path should call `RecipeImageBackfill.ensure(for:in:)` on save so saved recipes are offline-durable (the current Discover save does *not* backfill — fix that here).

---

## 7. Backend design (Vercel proxy)

Follow the established pattern (`vercel-ai-proxy/api/discover/*.js` + `DiscoverService`).

### 7.1 New endpoints

| Endpoint | Method | Purpose | Caching |
|---|---|---|---|
| `/api/feed/daily` | GET | Today's curated deck (`?diet=&allergies=&tags=`) | Edge-cache per (day, diet) bucket — hours |
| `/api/feed/search?q=&pageToken=` | GET | Query-driven feed | Cache per query — 24h |
| `/api/feed/personalized` | GET/POST | Taste + diet + goals → ranked feed | Short cache; or compute live |
| `/api/feed/recipe?id=` | GET | Full detail hydrate if list is thin | 24h |

- Auth: `x-glutt-proxy-key` header check (same as Discover).
- **Secrets server-side only — `SPOONACULAR_API_KEY` is set in Vercel project env, NEVER committed to the repo or hardcoded in this doc or `Secrets.swift`** (same discipline we use for `OPENAI_API_KEY`/`YOUTUBE_API_KEY`). The founder holds the key; add it in Vercel → Project → Settings → Environment Variables. Add a presence flag to `api/health.js` for ops visibility. If the key was ever shared in plaintext (chat, screenshots), rotate it in the Spoonacular dashboard.
- **Normalization happens server-side**: provider response → the `FeedRecipe` JSON contract above. The client stays provider-agnostic; swapping providers later is a backend-only change.
- **Cost controls:** aggressive edge caching, bounded deck sizes, dedupe identical queries, and a daily-deck that's largely *curated* (cheap) rather than API-hammering. Consider a nightly job/precompute for "Today's Plate" rather than per-request API calls.
- **Diet/allergy filtering**: apply provider diet/intolerance params *and* a server-side allergy hard-filter before returning.

### 7.2 Curated content storage

For v1, the curated layer can be a JSON file / lightweight KV (e.g., Vercel KV / a static JSON in the repo served by the function). Schema = the `FeedRecipe` contract. This avoids standing up a full DB on day one while keeping editorial control. Graduate to a real DB when creator UGC (Phase 3) needs it.

---

## 8. Client architecture

Mirror the existing, test-friendly `DiscoverFeedViewModel.Dependencies` pattern exactly.

### 8.1 New/var files

Put new files under a **`Plates`** namespace so they never collide with the existing `Discover` (videos) code.

| File | Role |
|---|---|
| `Glutt/Services/Plates/FeedRecipe.swift` | Transient `Decodable` model + `FeedResponse` |
| `Glutt/Services/Plates/FeedService.swift` | Proxy client (`daily`, `search`, `personalized`) — clone of `DiscoverService` shape with injectable `transport` |
| `Glutt/Services/Plates/FeedRecipeSaver.swift` | `FeedRecipe → ImportedRecipeDraft → RecipeFactory`, dedup, image backfill (clone of `DiscoverSaver`) |
| `Glutt/Features/Plates/FeedViewModel.swift` | `@MainActor @Observable`; `Dependencies { daily; search; personalized; save }` + `.live`; deck/paging/save state |
| `Glutt/Features/Plates/RecipeFeedView.swift` | The immersive full-screen pager (vertical paging + gestures) |
| `Glutt/Features/Plates/FeedCardView.swift` | One recipe: front + flip + back |
| `Glutt/Features/Plates/MacroStrip.swift` | Reusable macro header (cal + P/C/F **tri-segment bar**) — used by feed back **and** `RecipeDetailView` |
| `Glutt/Features/Plates/DeckEndCardView.swift` | Gamified completion/streak card |
| `Glutt/Features/Plates/PlatesLauncherCard.swift` | The **Today-tab** entry card (deck cover + peek thumbnails + taste chips) that presents the feed via `fullScreenCover` |

Reuse: `RecipeImageView`, `RecipeImageBackfill`, `PantryMatcher`, `DietGuard`, `GluttStepper`, `StatPill`, `Chip`, `Theme`, `Ph`, `Haptics`, `ImportPipeline`/`RecipeFactory`, `Router`.

### 8.2 ViewModel sketch

```swift
@MainActor @Observable
final class FeedViewModel {
    enum Phase: Equatable { case idle, loading, loaded, empty, failed(String) }
    struct Dependencies {
        var daily: (_ diet: [String], _ allergies: [String], _ tags: [String]) async throws -> FeedResponse
        var search: (_ query: String, _ pageToken: String?) async throws -> FeedResponse
        var personalized: (_ taste: [String], _ diet: [String], _ goal: String) async throws -> FeedResponse
        var save: (_ recipe: FeedRecipe, _ context: ModelContext) async throws -> Recipe
        static let live = Dependencies(/* FeedService + FeedRecipeSaver */)
    }
    private(set) var phase: Phase = .idle
    private(set) var recipes: [FeedRecipe] = []
    private(set) var index = 0
    private(set) var savedIDs: Set<String> = []
    private(set) var skippedIDs: Set<String> = []
    var deckTitle: String?

    func loadDaily(diet:[String], allergies:[String], tags:[String]) async
    func search(_ q: String) async
    func showNext() async       // prefetch images when within 2 of end (reuse Discover pattern)
    func save(_ r: FeedRecipe, into: ModelContext) async
    func skip(_ r: FeedRecipe)  // record signal; advance
}
```

### 8.3 Paging + flip + swipe (implementation notes)

- **Vertical pager:** iOS 17 `ScrollView { LazyVStack { ForEach … } }` with `.scrollTargetBehavior(.paging)` + `.scrollTargetLayout()`, or a rotated `TabView(.page)`. Each page = full screen. Drive `index` via `.scrollPosition` / `onAppear` to trigger prefetch + skip/seen signals.
- **Flip:** `@State var isFlipped`; `rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (0,1,0), perspective: 0.6)`; show front when `< 90°`, back (counter-rotated 180°) when `>= 90°`; `.spring` animation; `Haptics.impact(.medium)` on flip.
- **Horizontal save/skip:** `DragGesture` on the card; track `dx`; tilt `rotationEffect(.degrees(dx/20))` + show "SAVE"/"SKIP" stamp opacity ∝ `dx`. Commit past threshold (~120pt) → save/skip + spring off-screen; else rubber-band back. Use `.highPriorityGesture` and only "claim" horizontal once `abs(dx) > abs(dy)` to avoid stealing vertical paging.
- **Prefetch images:** kick off `URLSession`/`AsyncImage` warm-up for the next 2–3 `imageURL`s when `index` advances (mirror `DiscoverFeedViewModel` prefetch-within-2 logic).
- **Reduce Motion:** disable parallax/flip-3D (cross-fade instead) and the skip-tilt when `accessibilityReduceMotion`.

### 8.4 Routing

- Add `glutt://plates` to `Router.handle(url:)`; switch to `.today`, set a `presentPlatesFeed` flag the Today launcher card observes (or open the `fullScreenCover` directly from `RootView`, like Cook Mode). **Do not touch the existing Recipes-tab Discover routing.**
- Notification "Today's Plate is ready" deep-links here.

---

## 9. Macros everywhere (honesty model)

- Display **per-serving** cal/P/C/F on the card back via `MacroStrip`; also add `MacroStrip` to `RecipeDetailView` so saved recipes show the same.
- **Trusted vs estimated:** API/curated macros → `nutritionIsEstimated = false`, shown crisply. AI/heuristic macros → `true`, shown with the `~`/"estimated" treatment we already use.
- **Backfill for saved-without-macros:** if a saved recipe lacks carbs/fat (e.g., older imports), we can extend `NutritionEstimator` later to estimate carbs/fat (the `per100g` table would need carb/fat columns). **Out of scope for v1**, but note the seam: `NutritionEstimator.Estimate` would gain `carbGrams`/`fatGrams`. For v1, feed recipes come with real macros, so this isn't blocking.

---

## 10. Saving & library integration

- Save → `FeedRecipeSaver` → dedup by `sourceURL`/provider id → `RecipeFactory.make(from: draft)` → insert + save → `RecipeImageBackfill.ensure`.
- Saved recipes appear in **My Recipes** immediately (same `Recipe` store).
- Optionally auto-add deck saves to a `RecipeCollection` named after the deck ("Today's Plate — Jun 26") for the "collect the set" gamification — reuse `RecipeCollection`.
- "Undo" within the toast deletes the just-inserted recipe (keep the `PersistentIdentifier`).

---

## 11. Performance, offline, cost

- **Image prefetch** next 2–3; cap concurrent like `RecipeImageBackfill` (≤20/sweep).
- **Daily deck cached locally** (e.g., encode `[FeedRecipe]` to disk/UserDefaults with a date stamp) so reopening is instant and the feed works briefly offline; saved recipes are already durable via SwiftData + backfilled images.
- **Backend caching** (edge cache + precomputed daily deck) is the main cost lever; the curated layer is ~free.
- **Bounded deck** (12/day) prevents runaway API usage; "Explore" mode paginates on demand.

---

## 12. Accessibility & edge cases

- VoiceOver: card front reads title + key stats; "Recipe" button flips; Save/Skip buttons labeled. Gestures must have button equivalents (they do).
- Reduce Motion handled (§8.3).
- **No network / empty / error:** reuse `EmptyStateView`; offer the cached daily deck; "Retry".
- **Dietary conflicts:** allergies hard-filtered out of the feed; rule conflicts shown via the existing `DietGuard` warning on the back — never silently dropped (user may cook for others, per existing philosophy).
- **Low-quality / missing image:** fall back to the `RecipeImageView` placeholder; consider hiding image-less recipes from the photo feed (photography is the point).
- **Duplicate of an already-saved recipe:** show "Already in your cookbook".

---

## 13. Analytics / success metrics

Instrument (whatever analytics layer exists or a lightweight event log):
- Feed opens / day, deck completion rate, recipes viewed, flips, saves, skips.
- Save rate per recipe (ranking signal), "cookable now" save lift, search → save funnel.
- Streak length, D1/D7 return from the "Today's Plate" notification.
North-star: **saves per active user** and **return rate** — discovery should drive library growth and retention.

---

## 14. Phasing / rollout

- **Phase 1 (MVP):** Immersive vertical feed + flip + **full 2-axis gestures (vertical browse + horizontal swipe-to-save / skip) AND button equivalents** (founder decision: ship both day one), **curated daily "Today's Plate" (12 recipes, daily 07:00 local)** + **Spoonacular-backed Explore/search**, full macros (cal/P/C/F) populated end-to-end, `MacroStrip` (tri-segment bar), dedup + image backfill, `glutt://plates` deep link + "Today's Plate" notification, Today-tab launcher card. Ships content layers 1+2.
- **Phase 2:** Personalized ranking (taste + diet + pantry "cookable now" deck + goals), themed decks + "collect the set" badges, streaks, AI "Surprise me / make it for my pantry" tail (layer 3), carbs/fat estimation backfill for legacy recipes.
- **Phase 3:** Creator/user-generated recipe cards (depends on accounts, now in-scope) — the TikTok flywheel: users publish their plate (photo + macros + steps) into the feed; moderation + reporting.

---

## 15. Concrete implementation checklist (handoff)

**Backend (`vercel-ai-proxy/`)**
- [ ] `api/feed/daily.js`, `api/feed/search.js`, `api/feed/personalized.js`, `api/feed/recipe.js` — normalize provider/curated → `FeedRecipe` contract (§6.4).
- [ ] Curated JSON/KV store of launch recipes (full macros + owned images).
- [ ] `SPOONACULAR_API_KEY` env; add presence flag to `api/health.js`; `x-glutt-proxy-key` auth; edge caching; allergy hard-filter.

**Model**
- [ ] `ImportedRecipeDraft`: add `carbGrams`, `fatGrams`.
- [ ] `RecipeFactory.make`: set `carbGrams`, `fatGrams`, `nutritionIsEstimated`.
- [ ] (No SwiftData migration needed — `Recipe.carbGrams/fatGrams` already exist.)

**Services**
- [ ] `FeedRecipe.swift` / `FeedResponse` (transient `Decodable`).
- [ ] `FeedService.swift` (proxy client, injectable `transport`, error enum) — clone `DiscoverService`.
- [ ] `FeedRecipeSaver.swift` (`FeedRecipe → draft → RecipeFactory`, dedup, **image backfill**) — clone/extend `DiscoverSaver`.

**UI**
- [ ] `FeedViewModel.swift` (`Dependencies` + `.live`, deck/paging/save/skip).
- [ ] `RecipeFeedView.swift` (vertical pager + gestures + reduce-motion).
- [ ] `FeedCardView.swift` (front + 3D flip + back; reuse detail sub-views).
- [ ] `MacroStrip.swift` (cal + P/C/F; used by feed back **and** `RecipeDetailView`).
- [ ] `DeckEndCardView.swift` (completion + streak).
- [ ] `PlatesLauncherCard.swift` (deck-cover launcher on the **Today tab**; presents the feed via `fullScreenCover`).
- [ ] Refactor: extract shared `IngredientsList` / `StepsList` from `RecipeDetailView` for reuse on the card back.

**Routing / glue**
- [ ] `Router`: `glutt://plates` deep link + present mechanism; suppress floating `+` while feed open.
- [ ] Add the Plates launcher card to `TodayView`. **Leave the Recipes-tab Discover (YouTube "Videos") completely unchanged.**
- [ ] "Today's Plate" local notification (daily, fires for the 07:00 refresh) + `glutt://plates` deep link.

**Tests** (mirror existing injection pattern)
- [ ] `FeedServiceTests` (decode contract, error paths) — model on `DiscoverServiceTests`.
- [ ] `FeedViewModelTests` (load/save/skip/paging/prefetch) — model on `DiscoverFeedViewModelTests`.
- [ ] `FeedRecipeSaverTests` (draft mapping, dedup, macros, backfill) — model on `DiscoverSaverTests`.
- [ ] `RecipeFactory` macro-mapping test (carbs/fat populated).

---

## 16. Decisions (locked by founder) + remaining open items

**Locked:**
1. **Navigation:** New photo feed is entered from a **"Discover" launcher card on the Today tab** (`fullScreenCover`). The existing **YouTube Discover on the Recipes tab stays exactly as-is** — the two coexist. (§2, §3)
2. **Recipe API provider: Spoonacular.** Key lives in Vercel env `SPOONACULAR_API_KEY` (never committed). Mapping in Appendix §18. (§5.2, §7)
3. **Gesture model: full 2-axis in v1** — vertical browse + flip + horizontal swipe-to-save/skip, **plus** button equivalents. (Founder: "both".) (§4.1, §14)
4. **Macro viz: tri-segment horizontal bar** (proportional by calorie contribution) + P/C/F gram pills. Not rings (rings imply goal-progress). (§4.3)
5. **"Today's Plate": 12 recipes, refreshed daily at 07:00 local.** (§4.5, §11)

**Still open (lower-stakes, can decide during build):**
6. **Flip vs pull-up sheet** for the reveal — recommend the 3D flip as the signature interaction (matches the TikTok slide-2). Confirm during prototyping if the flip feels good on-device.
7. **AI augmentation (content layer 3)** in v1 or Phase 2? Recommend **Phase 2** for cost.
8. **Auto-add deck saves to a dated `RecipeCollection`** ("Today's Plate — Jun 26") for "collect the set"? Recommend yes, but trivial to toggle.

---

## 17. Appendix — reuse map (so we don't reinvent)

- **Image chain & durability:** `RecipeImageView`, `RecipeImageBackfill.ensure/sweep`, `ImagePrep`.
- **Save chokepoint:** `ImportedRecipeDraft` → `RecipeFactory.make` → `context.insert/save`.
- **Dedup & save UX precedent:** `DiscoverSaver` (clone, but add image backfill).
- **Pantry "cookable now":** `PantryMatcher.match(recipe:pantry:)`.
- **Dietary safety:** `DietGuard.conflicts(...)`, `UserPrefs.dietaryRules/allergies`.
- **Detail UI to reuse on the card back:** `RecipeDetailView` (servings stepper `GluttStepper`, ingredient rows + `IngredientCategoryStyle`, steps tab, `StatPill`, scaling logic).
- **Proxy client precedent:** `DiscoverService` + `Secrets.aiProxyBaseURL`/`aiProxyClientKey`; LLM via `LLMClient.chatJSON` for layer 3.
- **Design tokens:** `Theme`, `Font.glutt*`, `Ph`, `Haptics`, button styles in `Buttons.swift`.
- **VM testability:** `Dependencies { … }; static let live` + injectable `transport` (see `DiscoverFeedViewModel`, `ImportPipeline`).

---

## 18. Appendix — Spoonacular integration (chosen provider)

All Spoonacular access is **server-side only** (Vercel functions). The client only ever sees the normalized `FeedRecipe` contract.

**Key & config**
- Env var: `SPOONACULAR_API_KEY` (Vercel project settings). **Never** in the repo, `Secrets.swift`, or this doc. If shared in plaintext anywhere, rotate it in the Spoonacular dashboard.
- Base: `https://api.spoonacular.com`. Pass the key as the `apiKey` query param server-side.

**Endpoints we'll use**
- `GET /recipes/complexSearch` with `addRecipeInformation=true&addRecipeNutrition=true&fillIngredients=true&number=12` → one call returns photo + macros + ingredients + steps + servings + diets for the whole deck/search. Filter with `diet`, `intolerances`, `query`, `type`, `maxReadyTime`, `sort`.
- `GET /recipes/{id}/information?includeNutrition=true` → hydrate a single recipe if a list result is thin.
- (Optional) `GET /recipes/random?number=…` for an "Explore/Surprise me" tail.

**Field mapping → `FeedRecipe` (server-side normalization)**

| `FeedRecipe` field | Spoonacular source |
|---|---|
| `id` | `id` (prefix e.g. `spoonacular:{id}`) |
| `title` | `title` |
| `imageURL` | `image` |
| `sourceURL` | `sourceUrl` |
| `creator` / attribution | `sourceName` / `creditsText` |
| `servings` | `servings` |
| `timeMinutes` | `readyInMinutes` |
| `calories` | `nutrition.nutrients[name=="Calories"].amount` |
| `proteinGrams` | `nutrition.nutrients[name=="Protein"].amount` |
| `carbGrams` | `nutrition.nutrients[name=="Carbohydrates"].amount` |
| `fatGrams` | `nutrition.nutrients[name=="Fat"].amount` |
| `nutritionIsEstimated` | `false` (provider-supplied) |
| `ingredients[]` (`raw`,`name`,`quantity`,`unit`) | `extendedIngredients[]` (`original`,`name`,`amount`,`unit`) or `nutrition.ingredients[]` |
| `steps[]` | `analyzedInstructions[].steps[].step` (fallback: split `instructions`) |
| `diets` / tags | `diets`, `dishTypes`, `cuisines`, plus boolean flags (`vegan`, `glutenFree`, …) |

**Cost & ToS controls**
- Spoonacular bills per "points"; `complexSearch` with nutrition is the cheapest way to get a full deck in one call — prefer it over N detail calls.
- **Precompute "Today's Plate" once daily** (the 07:00 refresh job) and edge-cache `/api/feed/daily` so normal opens cost **zero** Spoonacular points.
- Cache search results per (query, diet) bucket for ~24h.
- Attribution is **required** — always carry `creditsText`/`sourceName` + `sourceUrl` through to the card front and the saved `Recipe`. Verify current Spoonacular ToS on image hotlinking vs caching and on storing results; encode the chosen policy in the backend.
- Halal/other rules Spoonacular doesn't model directly: enforce with our own `DietGuard` + allergy hard-filter after normalization.
