# Glutt — Plates (Recipe Discovery Feed) — Design Spec

**Status:** Approved design / ready for implementation planning
**Date:** 2026-06-26
**Audience:** Engineer implementing in the Glutt iOS codebase (SwiftUI + SwiftData) and the in-repo `vercel-ai-proxy/` backend.
**One-line:** A full-screen, swipeable, **flip-to-reveal** feed of photo recipes with full macros, ingredients, and instructions — saveable into the cookbook in one gesture — launched from the Today tab.

This spec supersedes the original handoff doc by reconciling it with a verified reconnaissance of the codebase (2026-06-26). Founder decisions are locked in §2.

---

## 1. Goal & scope

Turn recipe discovery into Glutt's emotional centerpiece: photography-first, one satisfying flip from hero photo → recipe back (macros + ingredients + steps + servings), frictionless save, and a finite gamified **daily deck** ("Today's Plate", 12 recipes).

**v1 ships:** immersive vertical photo feed + 3D flip + full 2-axis gestures (vertical browse, horizontal swipe-to-save/skip) **with button equivalents**; global cached daily deck + Spoonacular-backed Explore/search; full macros (cal/P/C/F) populated end-to-end; tri-segment `MacroStrip`; dedup + eager image backfill; `glutt://plates` deep link + 07:00 "Today's Plate" notification; Today-tab launcher card.

**Deferred to Phase 2 (explicitly out of v1):** AI "remix / use-what-I-have" tail (`LLMClient`/`PantryChef`); personalized per-user ranking; themed decks + "collect the set" badges; carb/fat estimation backfill for legacy recipes.

**Non-goals:** creator/UGC publishing (Phase 3); video in the feed (the existing YouTube Discover on the Recipes tab stays **exactly as-is**); a 6th root tab; per-ingredient macro editing.

---

## 2. Locked decisions

1. **Navigation:** Plates is launched from a **launcher card on the Today tab** (`TodayView`) presented as a **`fullScreenCover`** from `RootView`. The existing YouTube Discover on the Recipes tab is **untouched**. The two coexist; keep them distinct internally (`Discover*` = videos; `Plates*`/`Feed*` = photos).
2. **Provider:** **Spoonacular**, server-side only. Key in Vercel env `SPOONACULAR_API_KEY`, never committed. Client only ever sees the normalized `PlateCard` contract.
3. **Gestures:** full 2-axis in v1 — vertical browse + flip + horizontal swipe-to-save/skip, **plus** button equivalents.
4. **Macro viz:** **tri-segment horizontal bar** (proportional by calorie contribution: protein×4, carbs×4, fat×9 cal/g) + P/C/F gram pills. Brand colors: protein = `accent` (herb green), carbs = `warning` (amber), fat = `tomato`. Per-serving. Not rings.
5. **Today's Plate:** **12 recipes**, refreshed **daily at 07:00 local**.
6. **Reveal interaction (was open #6):** **3D flip to a purpose-built lightweight back** — NOT an embed of `RecipeDetailView` (which is a 29KB monolith with private, parent-coupled sub-views). The back is built from design-system parts.
7. **Daily deck source (was open):** **Global, date-seeded, edge-cached** Spoonacular deck — one 12-recipe deck/day for everyone, precomputed server-side so opens cost ≈0 quota. Allergy/diet hard-filtering applied client-side. (Explore/search is always live Spoonacular, cached per query.)
8. **Saved-plate collection (was open #8):** **No auto-collection.** Saved plates land in My Recipes like any save.
9. **AI layer (was open #7):** **Phase 2.** Spoonacular supplies structured recipes + macros; v1 needs no LLM.

---

## 3. Verified codebase facts (reconnaissance, 2026-06-26)

### Reuse map (verified present)
| Symbol | File | Status |
|---|---|---|
| `DiscoverFeedViewModel` (Dependencies struct, `Phase` enum, queue/prefetch/save) | `Glutt/Features/Discover/DiscoverFeedViewModel.swift` | clone template |
| `DiscoverService` (`typealias Transport`, `.live`, search/suggested, `x-glutt-proxy-key`) | `Glutt/Services/Discover/DiscoverService.swift` | clone template |
| `DiscoverError {notConfigured, badResponse(String)}` | same | reuse shape |
| `DiscoverSaver.save` / `existingRecipe(forSourceURL:in:)` (dedup → ImportPipeline → RecipeFactory → save; **no image backfill**) | `Glutt/Services/Discover/DiscoverSaver.swift` | clone + add backfill |
| `DiscoverVideo` / `DiscoverResponse` (transient `Decodable`) | `Glutt/Services/Discover/DiscoverVideo.swift` | model template |
| `Recipe.carbGrams: Int?`, `fatGrams: Int?`, `nutritionIsEstimated: Bool` | `Glutt/Models/Recipe.swift` (lines 38–40) | **already exist; no migration** |
| `RecipeImageBackfill.ensure(for:in:fetch:)` / `sweep` / `perSweepLimit = 20` | `Glutt/Services/Import/RecipeImageBackfill.swift` | reuse |
| `ImagePrep.prepareForVision(_:maxDimension:)` (1280px, 0.65 JPEG) | `Glutt/Services/AI/ImagePrep.swift` | reuse |
| `PantryMatcher.match(recipe:pantry:) -> MatchResult{owned,missing,missingOptional,ownedCount,totalCount,hasEverything}` | `Glutt/Services/PantryMatcher.swift` | reuse |
| `DietGuard.conflicts(in:rules:allergies:dislikes:) -> [Conflict]` (`isBlocking`) | `Glutt/Services/DietGuard.swift` | reuse |
| `UserPrefs.dietaryRules: [DietaryRule]`, `allergies: [String]`, `nutritionMode {cookingOnly, lightTracking, gymMode}` | `Glutt/Models/UserPrefs.swift`, `Glutt/Models/Enums.swift` | reuse |
| `RecipesView.tasteTags` (top-5 library tags) | `Glutt/Features/Recipes/RecipesView.swift` | reuse for Explore |
| `Theme`, `Font.glutt*`, `Ph` (~86 icons), `Haptics`, `StatPill`, `IconChip`, `Chip`, `GluttStepper`, `SegmentedTabs`, `RecipeImageView`, button styles | `Glutt/DesignSystem/**` | reuse |
| `Router` (`AppTab {today, recipes, plan, kitchen, progress}`, `handle(url:)`, `floatingButtonSuppressors: Int`) | `Glutt/App/Router.swift` | extend |
| `RootView` `fullScreenCover` pattern (Cook Mode `demoCookOnLaunch`, Onboarding) | `Glutt/App/RootView.swift` | mirror |
| `TodayView` card layout (insert launcher after `quickActionsRow`) | `Glutt/Features/Today/TodayView.swift` | extend |
| `ReminderScheduler` (`UNCalendarNotificationTrigger`, `userInfo["destination"]`) | `Glutt/Services/ReminderScheduler.swift` | extend |
| `vercel-ai-proxy/api/discover/{search,suggested}.js` (env key, `x-glutt-proxy-key` gate, cache headers) | `vercel-ai-proxy/api/discover/*.js` | endpoint template |
| `vercel-ai-proxy/api/health.js` (presence flags) | same | add flag |
| `Secrets.aiProxyBaseURL` (`https://glutt-sable.vercel.app/api`), `aiProxyClientKey` | `Glutt/Services/AI/Secrets.swift` | reuse |
| Discover test trio (`Transport` mocking, in-memory `ModelContext`) | `GluttTests/Discover*Tests.swift` | clone |

**Icons:** all required glyphs (`clock, flame, barbell, basket, bookOpen, x, heart, check, cellSignalMedium`) exist in `Ph`. (`Ph.cheese` exists too.) Missing: `sliders-horizontal, egg, orange-slice` — not needed for v1; if any filter UI wants them, add the SVG imageset + `Ph` case or fall back to an SF Symbol.

### Confirmed gotchas (drive design)
1. **Macros are dropped at 3 points** in the save chokepoint:
   - `ImportedRecipeDraft` has `calories`/`proteinGrams` but **lacks** `carbGrams`/`fatGrams`.
   - `RecipeFactory.make` sets only `calories`/`proteinGrams`/`imageData` — never `carbGrams`/`fatGrams`, and never updates `nutritionIsEstimated` (so every saved recipe is silently flagged `estimated = true`).
   - The AI `CleanedDraft` (DraftCleanup) Decodable shape has **no macro fields**, so macros returned by the LLM cleanup path are dropped.
2. **Carb/fat are unobtainable client-side** — `NutritionEstimator.per100g` has calories+protein columns only. The tri-segment bar **depends on Spoonacular** for complete macros and must degrade gracefully when carb/fat are nil.
3. **No `glutt://plates` route exists**; Plates is a `fullScreenCover` (not a tab), so the notification needs a new route + a Router presentation flag.
4. **`DiscoverSaver` skips `RecipeImageBackfill`** — a just-saved recipe shows its remote URL until the next foreground sweep. Plates will eager-backfill the saved hero.
5. **`RecipeDetailView` is a monolith** — sub-views (`ingredientRow`, `groceriesFooter`, `nutritionLine`) are private and parent-coupled; no reusable `MacroStrip` exists. The flip back is built fresh from stateless design-system components.

---

## 4. Data contract: `PlateCard`

Transient, `Decodable`, never persisted. Decoded from the backend.

```jsonc
// GET {proxy}/plates/deck   and   /plates/search
{
  "deckTitle": "Today's Plate",          // for daily; null for search
  "recipes": [
    {
      "id": "spoonacular:715538",         // stable provider-scoped id (dedup)
      "title": "Creamy Lemon Chicken Rice Bowl",
      "imageURL": "https://.../715538.jpg",
      "source": "spoonacular",            // spoonacular | curated | glutt-ai
      "sourceURL": "https://.../recipe",  // canonical — dedup + attribution
      "creator": "Feast & Flavor",        // sourceName / creditsText
      "license": "spoonacular",
      "summary": "Weeknight bowl ...",
      "servings": 4,
      "prepMinutes": 15,
      "cookMinutes": 30,
      "difficulty": "beginner",           // map to Difficulty {beginner,intermediate,advanced}
      "tags": ["high-protein","dinner","chicken"],
      "dietFlags": ["halal","gluten-free"],
      "macros": { "calories": 620, "protein": 48, "carbs": 55, "fat": 18, "estimated": false },
      "ingredients": [
        { "raw": "600 g chicken thighs", "name": "chicken thighs", "quantity": 600, "unit": "g" }
      ],
      "steps": ["Season the chicken ...", "Sear 4 min per side ...", "..."],
      "nutritionNote": null
    }
  ],
  "nextPageToken": "abc123"               // null for daily deck
}
```

Because ingredients/steps/macros arrive **structured**, the save path builds an `ImportedRecipeDraft` directly (`ingredientLines` = `raw[]`, `stepTexts` = `steps[]`, macros, servings) and **bypasses scraping + the macro-lossy AI cleanup path**.

---

## 5. Backend (`vercel-ai-proxy/`)

### Endpoints (clone the discover handler pattern)
| Endpoint | Method | Purpose | Caching |
|---|---|---|---|
| `api/plates/deck.js` | GET | Global daily deck: one Spoonacular `complexSearch` → normalize → 12 cards | edge `s-maxage` keyed by server (UTC) date bucket |
| `api/plates/search.js` | GET (`q`, `pageToken`, optional `diet`/`intolerances`) | Live Explore/search | per-(query,diet) ~24h |

- **Spoonacular call:** `GET /recipes/complexSearch?addRecipeInformation=true&addRecipeNutrition=true&fillIngredients=true&number=12` (+ `diet`, `intolerances`, `query`, `type`, `maxReadyTime`, `sort`). One call returns photo + macros + ingredients + steps + servings + diets — cheapest path; prefer over N detail calls.
- **Normalization (server-side):** map per §4 + Appendix A. Macros (`calories`/`protein`/`carbs`/`fat`) **always** included so the client never needs the carb/fat-less estimator.
- **Date-seeded global deck:** rotate the query/seed by **server (UTC) date** (mirror `discover/suggested.js` `ROTATING_QUERIES`) and edge-cache, so a day's deck is computed ~once and shared. The "07:00 **local**" refresh is a **client** concern: the client keys its local deck cache by local calendar date and refreshes (and the notification fires) at 07:00 local, pulling whatever the current global deck is. The two need not be perfectly aligned for v1.
- **Auth & secrets:** read `SPOONACULAR_API_KEY` from env; validate `x-glutt-proxy-key` when `GLUTT_PROXY_CLIENT_KEY` is set (same as discover). Add `has_SPOONACULAR_API_KEY` to `api/health.js`.
- **Attribution:** carry `creditsText`/`sourceName` + `sourceUrl` through to the card and saved recipe (provider ToS requirement).
- **Ownership split:** engineer writes the endpoint + health flag + normalization; **founder deploys to Vercel and sets the (rotated) `SPOONACULAR_API_KEY`** — deploy needs founder's Vercel auth.

### Security
The Spoonacular key was exposed in plaintext during handoff. **Rotate it** in the Spoonacular dashboard and store only the fresh value in Vercel env. Never commit it to the repo, `Secrets.swift`, or docs.

---

## 6. Model & save-path changes

1. **`ImportedRecipeDraft`** (`Glutt/Services/Import/ImportedRecipeDraft.swift`): add `carbGrams: Int?`, `fatGrams: Int?` (Codable, optional → backward-safe).
2. **`RecipeFactory.make(from:)`** (`Glutt/Services/Import/RecipeFactory.swift`): set `recipe.carbGrams`, `recipe.fatGrams`, and `recipe.nutritionIsEstimated = draft`-supplied value. This is the single chokepoint — every save path benefits.
3. **`PlateCard → ImportedRecipeDraft` mapper** (in `PlatesSaver`): write Spoonacular macros + `nutritionIsEstimated = (macros.estimated)` directly onto the draft; set `ingredientLines`, `stepTexts`, `servings`, `prep/cookMinutes`, `tags`, `sourceURL`, `creator`, `imageURL`, `difficulty`. Do **not** route through the AI `CleanedDraft` path (it drops macros).
4. No SwiftData migration (Recipe fields already exist).

---

## 7. Client architecture

New files (under `Plates`):

| File | Role |
|---|---|
| `Glutt/Services/Plates/PlateCard.swift` | transient `Decodable` `PlateCard` + `PlatesResponse` |
| `Glutt/Services/Plates/PlatesService.swift` | proxy client (`daily`, `search`), injectable `Transport`, error enum — clone of `DiscoverService` |
| `Glutt/Services/Plates/PlatesSaver.swift` | `PlateCard → ImportedRecipeDraft → RecipeFactory`, dedup, **eager image backfill** — clone/extend `DiscoverSaver` |
| `Glutt/Features/Plates/PlatesFeedViewModel.swift` | `@MainActor @Observable`; `Dependencies{daily, search, save}` + `.live`; deck/index/saved/skip/prefetch state |
| `Glutt/Features/Plates/RecipeFeedView.swift` | vertical pager + gestures + reduce-motion |
| `Glutt/Features/Plates/FeedCardView.swift` | front + 3D flip + custom back |
| `Glutt/Features/Plates/MacroStrip.swift` | tri-segment macro bar; used by feed back **and** `RecipeDetailView` |
| `Glutt/Features/Plates/DeckEndCardView.swift` | completion + streak |
| `Glutt/Features/Plates/PlatesLauncherCard.swift` | Today-tab launcher (presents feed via `fullScreenCover`) |
| `Glutt/Resources/PlatesSeedDeck.json` | bundled seed deck (offline / pre-deploy fallback) |

### ViewModel sketch
```swift
@MainActor @Observable
final class PlatesFeedViewModel {
    enum Phase: Equatable { case idle, loading, loaded, empty, failed(String) }
    struct Dependencies {
        var daily:  () async throws -> PlatesResponse
        var search: (_ query: String, _ pageToken: String?) async throws -> PlatesResponse
        var save:   (_ card: PlateCard, _ context: ModelContext) async throws -> Recipe
        static let live: Dependencies // PlatesService + PlatesSaver
    }
    private(set) var phase: Phase = .idle
    private(set) var recipes: [PlateCard] = []
    private(set) var index = 0
    private(set) var savedIDs: Set<String> = []
    private(set) var skippedIDs: Set<String> = []
    var deckTitle: String?

    func loadDaily() async       // cache by local date; bundled seed fallback; DietGuard hard-filter + sourceURL dedup
    func search(_ q: String) async
    func showNext() async        // prefetch next 2–3 images (Explore)
    func save(_ card: PlateCard, into: ModelContext) async
    func skip(_ card: PlateCard) // record signal; advance
}
```

### Paging / flip / swipe
- **Vertical pager:** `ScrollView { LazyVStack { ForEach } }` + `.scrollTargetBehavior(.paging)` + `.scrollTargetLayout()`; drive `index` via `.scrollPosition`/`onAppear`.
- **Flip:** `@State isFlipped`; `rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis:(0,1,0), perspective: 0.6)`; show front `< 90°`, counter-rotated back `≥ 90°`; spring; `Haptics.impact(.medium)`.
- **Horizontal save/skip:** `DragGesture`; tilt `rotationEffect(.degrees(dx/20))`, "SAVE"/"SKIP" stamp opacity ∝ `dx`; commit past ~120pt; else rubber-band. `.highPriorityGesture`, claim horizontal only when `abs(dx) > abs(dy)`.
- **Reduce Motion:** flip → cross-fade; disable parallax + tilt.

### Save UX
Drag-right / Save button / double-tap hero → `Haptics.celebrate()`, heart-burst, "tuck" motion, auto-advance (mirror `DiscoverFeedViewModel.showNext`), toast "Saved to your cookbook" with **Undo** (deletes by `PersistentIdentifier`). Dedup by `sourceURL` → "Already in your cookbook". On save, eager `RecipeImageBackfill.ensure` for the new recipe.

---

## 8. Card UI

### Front
Edge-to-edge `RecipeImageView` hero + bottom gradient scrim. Overlaid bottom-aligned: title (`Font.gluttLargeTitle`/`gluttTitle`, white, heavy); creator/attribution (small, required); **stat strip** (`StatPill` family + `Ph.clock`/`Ph.flame`/`Ph.barbell`/`Ph.cellSignalMedium`: time, calories, a macro highlight e.g. "48g protein", difficulty); **"You can make this now"** pill (`Ph.basket`) when `PantryMatcher.match` covers (most) ingredients; **diet fit chips** ("Halal ✓", "High-protein") from tags + `DietGuard`; **"Recipe ▸"** flip handle (`Ph.bookOpen`, bottom-right, subtle first-appearance bounce). Top overlay: close (`Ph.x`) + deck progress ("3 / 12"). Focused card scale 1.0, neighbors ~0.94 + reduced opacity (gated on Reduce Motion).

### Back (custom, built from design-system parts)
- **`MacroStrip`** pinned top: big bold calories; tri-segment bar (protein `accent` / carbs `warning` / fat `tomato`, widths ∝ calorie contribution); P/C/F gram pills beneath; honest "per serving". **Graceful degradation:** carb/fat nil → 2-segment or calories+protein only. Estimated → `~`/"estimated" treatment.
- **Servings stepper** (`GluttStepper`) scales quantities live (reuse `UnitConverter.display(scale:system:)`).
- **Ingredients** — sectioned (reuse `IngredientCategoryStyle` + `IconChip`), with `PantryMatcher` have/missing treatment.
- **Steps** — numbered (mirror `stepsTab` styling).
- **CTAs:** **Save to cookbook** (`.gluttPrimary`) + **Cook** (after save, present Cook Mode / push the saved recipe) + **Add to plan**. Done/flip-back affordance.

> Add `MacroStrip` to `RecipeDetailView` too (replacing the inline `nutritionLine`) so saved recipes show identical macros.

---

## 9. Navigation, notification, personalization, gamification

### Navigation
- `PlatesLauncherCard` on `TodayView` after `quickActionsRow` (deck cover + 2–3 peek thumbs + taste chips, "Today's Plate is ready 🍳").
- Present via `fullScreenCover` from `RootView`, mirroring `demoCookOnLaunch`. Add `router.pendingPresentPlates: Bool`; RootView presents when set (tab-independent). Increment `floatingButtonSuppressors` while open (mirror `RecipeDetailView`).
- `Router.handle(url:)`: add `glutt://plates` → sets `pendingPresentPlates`. Leave existing Discover routing untouched.

### Notification
Extend `ReminderScheduler` with a **daily 07:00 local** `UNCalendarNotificationTrigger` ("Today's Plate is ready"), `userInfo["destination"] = "plates"`; `NotificationRoutingDelegate` maps it to the `glutt://plates` presentation flag. (No notification categories exist today; none required for a tap-to-open.)

### Personalization (client-side, v1)
- `DietGuard` **hard-filters** allergy/rule conflicts out of the deck before display; dislikes surface as the existing soft warning on the back (never silently hidden — user may cook for others).
- `PantryMatcher` → "you can make this now" badge.
- `tasteTags` seed Explore queries.
- `nutritionMode` (`gymMode`) → optionally surface the protein highlight more prominently. (Light touch in v1.)

### Gamification (v1, lean)
- 12/day deck; `DeckEndCardView` on completion ("explored 12, saved 3", streak, "come back tomorrow").
- Streak (consecutive days opening the feed) + lifetime discovered/saved counters in `UserDefaults`.
- Deck dedup: filter already-saved `sourceURL`s + persist a "seen plate IDs" set so the next day doesn't repeat.

---

## 10. Performance, offline, cost

- Image prefetch next 2–3 (Explore); reuse `RecipeImageBackfill` concurrency discipline.
- Daily deck cached locally keyed by **local date** (encode `[PlateCard]` + date stamp); reopen is instant and works briefly offline. **Bundled `PlatesSeedDeck.json`** is the first-run / pre-deploy / offline fallback.
- Backend edge-cache + global date-seeded deck is the main cost lever; bounded 12/day prevents runaway quota; Explore paginates on demand.
- Timezone/midnight/DST: key the deck by local calendar date; invalidate stale decks on date change.

---

## 11. Accessibility & edge cases

- VoiceOver: front reads title + key stats; "Recipe" flips; Save/Skip/Recipe buttons labeled. Every gesture has a button equivalent.
- Reduce Motion (§7): flip → cross-fade; no parallax/tilt/confetti.
- No network / empty / error: reuse `EmptyStateView`; offer cached/seed deck; Retry.
- Dietary: allergies/rules hard-filtered out; dislikes shown via `DietGuard` warning on the back.
- Missing/low-quality image: `RecipeImageView` placeholder; prefer hiding image-less recipes (photography is the point).
- Duplicate of saved recipe: "Already in your cookbook".

---

## 12. Testing

Clone the Discover test trio (XCTest, mockable `Transport`, in-memory SwiftData `ModelContext`):
- `PlatesServiceTests` — request building (`q`, `pageToken`, header), response decode of the `PlateCard` contract, error paths. (Model on `DiscoverServiceTests`.)
- `PlatesFeedViewModelTests` — load daily, save→advance, skip→advance, save-error recovery, prefetch, local-date cache + seed fallback, DietGuard hard-filter, sourceURL dedup. (Model on `DiscoverFeedViewModelTests`.)
- `PlatesSaverTests` — draft mapping (ingredients/steps/macros/servings), dedup by `sourceURL`, macros land on `Recipe`, `nutritionIsEstimated` set correctly, eager backfill invoked. (Model on `DiscoverSaverTests`.)
- `RecipeFactoryMacroTests` — `carbGrams`/`fatGrams`/`nutritionIsEstimated` populated from a draft.

---

## 13. Implementation order (for the plan)

1. **Macro chokepoint** (`ImportedRecipeDraft` + `RecipeFactory` + `RecipeFactoryMacroTests`) — smallest, unblocks everything, no UI.
2. **`MacroStrip`** component + drop into `RecipeDetailView` (visible win, reused by the back).
3. **Backend** `api/plates/deck.js` + `api/plates/search.js` + health flag + normalization (founder deploys/sets key).
4. **Services** `PlateCard`/`PlatesResponse`, `PlatesService` (+ tests), `PlatesSaver` (+ eager backfill, + tests), bundled seed deck.
5. **ViewModel** `PlatesFeedViewModel` (+ tests).
6. **UI** `FeedCardView` (front + flip + back), `RecipeFeedView` (pager + gestures + reduce-motion), `DeckEndCardView`, `PlatesLauncherCard`.
7. **Glue** Router `glutt://plates` + `pendingPresentPlates`, RootView `fullScreenCover` + suppressor, TodayView launcher, `ReminderScheduler` 07:00 notification + delegate routing.
8. Build + `test_sim` (XcodeBuildMCP) + simulator UI verification.

---

## Appendix A — Spoonacular → `PlateCard` mapping (server-side)

| `PlateCard` field | Spoonacular source |
|---|---|
| `id` | `spoonacular:{id}` |
| `title` | `title` |
| `imageURL` | `image` |
| `sourceURL` | `sourceUrl` |
| `creator` | `sourceName` / `creditsText` |
| `servings` | `servings` |
| `prep/cookMinutes` | `cookMinutes = readyInMinutes`, `prepMinutes = 0` (Spoonacular gives only total time) |
| `macros.calories` | `nutrition.nutrients[name=="Calories"].amount` |
| `macros.protein` | `nutrition.nutrients[name=="Protein"].amount` |
| `macros.carbs` | `nutrition.nutrients[name=="Carbohydrates"].amount` |
| `macros.fat` | `nutrition.nutrients[name=="Fat"].amount` |
| `macros.estimated` | `false` |
| `ingredients[]` | `extendedIngredients[]` (`original`,`name`,`amount`,`unit`) |
| `steps[]` | `analyzedInstructions[].steps[].step` (fallback: split `instructions`) |
| `tags`/`dietFlags` | `diets`, `dishTypes`, `cuisines`, boolean flags (`vegan`, `glutenFree`, …) |

Halal/other rules Spoonacular doesn't model: enforce client-side with `DietGuard` + allergy hard-filter after normalization.
