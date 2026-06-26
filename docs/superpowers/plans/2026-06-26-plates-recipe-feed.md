# Plates (Recipe Discovery Feed) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a full-screen, swipeable, flip-to-reveal photo recipe feed ("Plates") with full macros, one-gesture save, a global daily deck, and Spoonacular-backed Explore — launched from the Today tab.

**Architecture:** Clone the proven Discover (videos) three-layer stack (`Service` + `Saver` + `@Observable ViewModel` + transient `Decodable` model) into a `Plates` namespace, pointed at two new Spoonacular endpoints on the in-repo Vercel proxy. Build the immersive UI (vertical pager + 3D flip + horizontal swipe) from existing design-system components. Thread full macros (cal/P/C/F) through the single save chokepoint (`ImportedRecipeDraft` → `RecipeFactory` → `Recipe`).

**Tech Stack:** SwiftUI (iOS 17+), SwiftData, XcodeGen, XCTest, Node.js (Vercel serverless), Spoonacular API.

**Spec:** `docs/superpowers/specs/2026-06-26-plates-recipe-feed-design.md`

## Global Constraints

- **iOS deployment target:** 17.0. Swift 5.10. Portrait-only, Light appearance only.
- **XcodeGen:** `project.yml` is source of truth; `Glutt.xcodeproj` is generated. Target `Glutt` sources = the `Glutt/` folder (glob); `GluttTests` = the `GluttTests/` folder (glob). **After creating ANY new file, run `xcodegen generate` before building or testing** — new files are not in the project until regenerated. `.json` files placed under `Glutt/` are added as bundle resources automatically.
- **Build/test tooling:** Use XcodeBuildMCP, not raw `xcodebuild`. Before the first build/test, call `session_show_defaults`; if unset, set scheme `Glutt` + an iOS 17+ simulator via `session_set_defaults`. Build = `build_sim`; test = `test_sim` (scheme `Glutt`, which runs `GluttTests`). Granular fallback for a single test: `xcodebuild test -only-testing:GluttTests/<Class>/<test>`.
- **No hardcoded colors/fonts/icons:** use `Theme.Colors.*`, `Font.glutt*`, `Ph.*`, `Haptics.*` only.
- **Secrets:** never commit the Spoonacular key. It lives only in Vercel env `SPOONACULAR_API_KEY`. The key shared in handoff is considered compromised — founder rotates it. Backend deploy + env are the founder's responsibility.
- **Macros are per-serving.** Trusted sources set `nutritionIsEstimated = false`; estimated set `true`.
- **Test framework:** XCTest (`@testable import Glutt`). Save-path tests use an in-memory `ModelContainer(for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])`.
- **Brand macro colors:** protein = `Theme.Colors.accent`, carbs = `Theme.Colors.warning`, fat = `Theme.Colors.tomato`.

---

## File Structure

**New (iOS):**
- `Glutt/Services/Plates/PlateCard.swift` — transient `Decodable` models (`PlateCard`, `PlateMacros`, `PlateIngredient`, `PlatesResponse`).
- `Glutt/Services/Plates/PlatesService.swift` — proxy client + `PlatesError` (clone of `DiscoverService`).
- `Glutt/Services/Plates/PlateCardMapper.swift` — `PlateCard → ImportedRecipeDraft`.
- `Glutt/Services/Plates/PlatesSaver.swift` — dedup + `RecipeFactory` + eager image backfill.
- `Glutt/Services/Plates/PlatesSeedDeck.swift` — bundled-seed decode/load.
- `Glutt/Services/Plates/PlatesDeckFilter.swift` — pure deck filter (diet hard-filter + saved dedup).
- `Glutt/Features/Plates/MacroBreakdown.swift` — pure tri-segment proportion math.
- `Glutt/Features/Plates/MacroStrip.swift` — macro bar view.
- `Glutt/Features/Plates/PlatesFeedViewModel.swift` — `@Observable` deck/index/save/skip + cache fallback.
- `Glutt/Features/Plates/FeedCardView.swift` — front + 3D flip + back.
- `Glutt/Features/Plates/RecipeFeedView.swift` — vertical pager + gestures + reduce-motion.
- `Glutt/Features/Plates/DeckEndCardView.swift` — completion + streak.
- `Glutt/Features/Plates/PlatesStreak.swift` — streak/counters in `UserDefaults`.
- `Glutt/Features/Plates/PlatesLauncherCard.swift` — Today-tab launcher.
- `Glutt/Resources/PlatesSeedDeck.json` — bundled seed deck.

**New (backend):**
- `vercel-ai-proxy/api/plates/deck.js`, `vercel-ai-proxy/api/plates/search.js`.

**New (tests):**
- `GluttTests/RecipeFactoryMacroTests.swift`, `MacroBreakdownTests.swift`, `PlateCardDecodeTests.swift`, `PlatesServiceTests.swift`, `PlatesSaverTests.swift`, `PlatesDeckFilterTests.swift`, `PlatesFeedViewModelTests.swift`, `PlatesSeedDeckTests.swift`, `PlatesStreakTests.swift`.

**Modified:**
- `Glutt/Services/Import/ImportedRecipeDraft.swift` — add `carbGrams`, `fatGrams`, `nutritionIsEstimated`.
- `Glutt/Services/Import/RecipeFactory.swift` — set the three new fields.
- `Glutt/Features/Recipes/RecipeDetailView.swift` — use `MacroStrip`.
- `Glutt/App/Router.swift` — `glutt://plates` + `pendingPresentPlates`.
- `Glutt/App/RootView.swift` — Plates `fullScreenCover`.
- `Glutt/App/GluttApp.swift` — route `destination == "plates"`.
- `Glutt/Services/ReminderScheduler.swift` — daily 07:00 Plates reminder.
- `Glutt/Features/Today/TodayView.swift` — insert `PlatesLauncherCard`.
- `vercel-ai-proxy/api/health.js` — `has_SPOONACULAR_API_KEY` flag.

---

## Task 1: Macro chokepoint (draft + factory)

**Files:**
- Modify: `Glutt/Services/Import/ImportedRecipeDraft.swift`
- Modify: `Glutt/Services/Import/RecipeFactory.swift:25-27`
- Test: `GluttTests/RecipeFactoryMacroTests.swift`

**Interfaces:**
- Produces: `ImportedRecipeDraft.carbGrams: Int?`, `.fatGrams: Int?`, `.nutritionIsEstimated: Bool` (default `true`); `RecipeFactory.make(from:)` now sets `recipe.carbGrams`, `recipe.fatGrams`, `recipe.nutritionIsEstimated`.

- [ ] **Step 1: Write the failing test**

Create `GluttTests/RecipeFactoryMacroTests.swift`:

```swift
import XCTest
@testable import Glutt

final class RecipeFactoryMacroTests: XCTestCase {
    func testMakeCarriesFullMacrosAndTrustedFlag() {
        var draft = ImportedRecipeDraft()
        draft.title = "Lemon Chicken Bowl"
        draft.calories = 620
        draft.proteinGrams = 48
        draft.carbGrams = 55
        draft.fatGrams = 18
        draft.nutritionIsEstimated = false

        let recipe = RecipeFactory.make(from: draft)

        XCTAssertEqual(recipe.calories, 620)
        XCTAssertEqual(recipe.proteinGrams, 48)
        XCTAssertEqual(recipe.carbGrams, 55)
        XCTAssertEqual(recipe.fatGrams, 18)
        XCTAssertFalse(recipe.nutritionIsEstimated)
    }

    func testMakeDefaultsToEstimatedWhenDraftSaysSo() {
        var draft = ImportedRecipeDraft()
        draft.title = "Guess Bowl"
        // nutritionIsEstimated defaults to true on the draft
        let recipe = RecipeFactory.make(from: draft)
        XCTAssertTrue(recipe.nutritionIsEstimated)
        XCTAssertNil(recipe.carbGrams)
        XCTAssertNil(recipe.fatGrams)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `xcodegen generate`, then `test_sim`. Expected: FAIL — `ImportedRecipeDraft` has no `carbGrams`/`fatGrams`/`nutritionIsEstimated`, won't compile.

- [ ] **Step 3: Add the draft fields**

In `Glutt/Services/Import/ImportedRecipeDraft.swift`, after the `proteinGrams` line (`var proteinGrams: Int?`), add:

```swift
    var carbGrams: Int?
    var fatGrams: Int?
    /// False only when macros come from a trusted source (e.g. Spoonacular).
    /// Defaults to true so heuristic/AI imports are honestly flagged.
    var nutritionIsEstimated: Bool = true
```

- [ ] **Step 4: Set the fields in the factory**

In `Glutt/Services/Import/RecipeFactory.swift`, replace the block:

```swift
        recipe.calories = draft.calories
        recipe.proteinGrams = draft.proteinGrams
        recipe.imageData = draft.imageData
```

with:

```swift
        recipe.calories = draft.calories
        recipe.proteinGrams = draft.proteinGrams
        recipe.carbGrams = draft.carbGrams
        recipe.fatGrams = draft.fatGrams
        recipe.nutritionIsEstimated = draft.nutritionIsEstimated
        recipe.imageData = draft.imageData
```

- [ ] **Step 5: Run test to verify it passes**

Run `test_sim`. Expected: `RecipeFactoryMacroTests` passes; full suite still green.

- [ ] **Step 6: Commit**

```bash
git add Glutt/Services/Import/ImportedRecipeDraft.swift Glutt/Services/Import/RecipeFactory.swift GluttTests/RecipeFactoryMacroTests.swift
git commit -m "feat(plates): thread carbs/fat/estimated through the save chokepoint"
```

---

## Task 2: MacroBreakdown (pure) + MacroStrip view

**Files:**
- Create: `Glutt/Features/Plates/MacroBreakdown.swift`
- Create: `Glutt/Features/Plates/MacroStrip.swift`
- Test: `GluttTests/MacroBreakdownTests.swift`

**Interfaces:**
- Produces:
  - `struct MacroBreakdown { let calories: Int?; let protein: Int?; let carbs: Int?; let fat: Int?; let isEstimated: Bool; var hasFullMacros: Bool; var proteinFraction: Double; var carbFraction: Double; var fatFraction: Double; init(calories:protein:carbs:fat:isEstimated:) }`
  - `struct MacroStrip: View { init(calories: Int?, protein: Int?, carbs: Int?, fat: Int?, isEstimated: Bool); init(recipe: Recipe) }`

- [ ] **Step 1: Write the failing test**

Create `GluttTests/MacroBreakdownTests.swift`:

```swift
import XCTest
@testable import Glutt

final class MacroBreakdownTests: XCTestCase {
    func testFractionsUseCalorieContribution() {
        // protein 48*4=192, carbs 55*4=220, fat 18*9=162; total 574
        let b = MacroBreakdown(calories: 620, protein: 48, carbs: 55, fat: 18, isEstimated: false)
        XCTAssertTrue(b.hasFullMacros)
        XCTAssertEqual(b.proteinFraction, 192.0 / 574.0, accuracy: 0.0001)
        XCTAssertEqual(b.carbFraction, 220.0 / 574.0, accuracy: 0.0001)
        XCTAssertEqual(b.fatFraction, 162.0 / 574.0, accuracy: 0.0001)
        XCTAssertEqual(b.proteinFraction + b.carbFraction + b.fatFraction, 1.0, accuracy: 0.0001)
    }

    func testNotFullWhenCarbOrFatMissing() {
        let b = MacroBreakdown(calories: 400, protein: 30, carbs: nil, fat: nil, isEstimated: true)
        XCTAssertFalse(b.hasFullMacros)
    }

    func testZeroMacrosDoNotDivideByZero() {
        let b = MacroBreakdown(calories: 0, protein: 0, carbs: 0, fat: 0, isEstimated: true)
        XCTAssertFalse(b.hasFullMacros)
        XCTAssertEqual(b.proteinFraction, 0)
        XCTAssertEqual(b.carbFraction, 0)
        XCTAssertEqual(b.fatFraction, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `xcodegen generate`, then `test_sim`. Expected: FAIL — `MacroBreakdown` undefined.

- [ ] **Step 3: Implement MacroBreakdown**

Create `Glutt/Features/Plates/MacroBreakdown.swift`:

```swift
import Foundation

/// Pure macro math for the tri-segment bar. Segments are proportional to each
/// macro's *calorie* contribution (protein ×4, carbs ×4, fat ×9 cal/g), which
/// is what "composition" means — not raw grams.
struct MacroBreakdown {
    let calories: Int?
    let protein: Int?
    let carbs: Int?
    let fat: Int?
    let isEstimated: Bool

    init(calories: Int?, protein: Int?, carbs: Int?, fat: Int?, isEstimated: Bool) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.isEstimated = isEstimated
    }

    /// True only when all three macro grams are present and their calorie sum > 0.
    var hasFullMacros: Bool {
        guard let p = protein, let c = carbs, let f = fat else { return false }
        return (p * 4 + c * 4 + f * 9) > 0
    }

    private var totalMacroCalories: Double {
        Double((protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9)
    }

    var proteinFraction: Double { fraction((protein ?? 0) * 4) }
    var carbFraction: Double { fraction((carbs ?? 0) * 4) }
    var fatFraction: Double { fraction((fat ?? 0) * 9) }

    private func fraction(_ macroCalories: Int) -> Double {
        let total = totalMacroCalories
        guard total > 0 else { return 0 }
        return Double(macroCalories) / total
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run `test_sim`. Expected: `MacroBreakdownTests` passes.

- [ ] **Step 5: Implement MacroStrip view**

Create `Glutt/Features/Plates/MacroStrip.swift`:

```swift
import SwiftUI

/// The macro header: big calorie number + a tri-segment composition bar
/// (protein/carbs/fat by calorie share) + gram pills. Degrades to
/// calories+protein when carb/fat are missing. Honest "per serving".
struct MacroStrip: View {
    let breakdown: MacroBreakdown

    init(calories: Int?, protein: Int?, carbs: Int?, fat: Int?, isEstimated: Bool) {
        self.breakdown = MacroBreakdown(calories: calories, protein: protein,
                                        carbs: carbs, fat: fat, isEstimated: isEstimated)
    }

    init(recipe: Recipe) {
        self.init(calories: recipe.calories, protein: recipe.proteinGrams,
                  carbs: recipe.carbGrams, fat: recipe.fatGrams,
                  isEstimated: recipe.nutritionIsEstimated)
    }

    private var prefix: String { breakdown.isEstimated ? "~" : "" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                if let cal = breakdown.calories {
                    Text("\(prefix)\(cal)")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("cal")
                        .font(.gluttCaption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Text(breakdown.isEstimated ? "estimated · per serving" : "per serving")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if breakdown.hasFullMacros {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        segment(width: geo.size.width * breakdown.proteinFraction, color: Theme.Colors.accent)
                        segment(width: geo.size.width * breakdown.carbFraction, color: Theme.Colors.warning)
                        segment(width: geo.size.width * breakdown.fatFraction, color: Theme.Colors.tomato)
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
            }

            HStack(spacing: Theme.Spacing.sm) {
                gramPill("P", grams: breakdown.protein, color: Theme.Colors.accent)
                gramPill("C", grams: breakdown.carbs, color: Theme.Colors.warning)
                gramPill("F", grams: breakdown.fat, color: Theme.Colors.tomato)
            }
        }
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }

    @ViewBuilder
    private func gramPill(_ letter: String, grams: Int?, color: Color) -> some View {
        if let grams {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("\(letter) \(prefix)\(grams)g")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

#Preview("Full / degraded") {
    VStack(spacing: 24) {
        MacroStrip(calories: 620, protein: 48, carbs: 55, fat: 18, isEstimated: false)
        MacroStrip(calories: 400, protein: 30, carbs: nil, fat: nil, isEstimated: true)
    }
    .padding()
    .background(Theme.Colors.card)
}
```

- [ ] **Step 6: Build to verify it compiles**

Run `xcodegen generate`, then `build_sim`. Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Glutt/Features/Plates/MacroBreakdown.swift Glutt/Features/Plates/MacroStrip.swift GluttTests/MacroBreakdownTests.swift
git commit -m "feat(plates): add MacroBreakdown math + tri-segment MacroStrip"
```

---

## Task 3: Use MacroStrip in RecipeDetailView

**Files:**
- Modify: `Glutt/Features/Recipes/RecipeDetailView.swift`

**Interfaces:**
- Consumes: `MacroStrip(recipe:)` from Task 2.

- [ ] **Step 1: Locate the existing nutrition display**

Open `Glutt/Features/Recipes/RecipeDetailView.swift` and find the private computed property that renders nutrition (named `nutritionLine`, referenced in `contentSheet`). Read its current body so the replacement matches the surrounding gating (it is shown only when `prefs.nutritionMode.showsNutrition`).

- [ ] **Step 2: Replace its body with MacroStrip**

Replace the *contents* of the `nutritionLine` computed property so it returns `MacroStrip(recipe: recipe)` wrapped in the same conditional/padding it used before. Concretely, the property body becomes:

```swift
    @ViewBuilder
    private var nutritionLine: some View {
        if prefs.nutritionMode.showsNutrition,
           recipe.calories != nil || recipe.proteinGrams != nil {
            MacroStrip(recipe: recipe)
                .padding(.top, Theme.Spacing.sm)
        }
    }
```

Keep the property name `nutritionLine` so its call site in `contentSheet` is unchanged. If the existing property is not `@ViewBuilder`, add the attribute. Preserve any `prefs` accessor already used in the file (do not introduce a new one).

- [ ] **Step 3: Build to verify**

Run `xcodegen generate` (no new files, but safe), then `build_sim`. Expected: build succeeds. Spot-check the preview / a sim run that a saved recipe with macros shows the tri-segment bar.

- [ ] **Step 4: Commit**

```bash
git add Glutt/Features/Recipes/RecipeDetailView.swift
git commit -m "feat(plates): show MacroStrip on the recipe detail screen"
```

---

## Task 4: Backend — Spoonacular endpoints + health flag

**Files:**
- Create: `vercel-ai-proxy/api/plates/deck.js`
- Create: `vercel-ai-proxy/api/plates/search.js`
- Modify: `vercel-ai-proxy/api/health.js`

**Interfaces:**
- Produces: `GET /api/plates/deck` and `GET /api/plates/search?q=&pageToken=` returning the `PlatesResponse` JSON contract (`{deckTitle, recipes:[PlateCard], nextPageToken}`). Macros rounded to integers.

> No JS unit-test runner exists in this repo (consistent with the existing `discover/*` handlers). Verify with `node --check` for syntax, and a post-deploy `curl`. The contract's correctness is enforced client-side by `PlateCardDecodeTests` (Task 5) against this exact shape.

- [ ] **Step 1: Create the shared normalizer + deck handler**

Create `vercel-ai-proxy/api/plates/deck.js`:

```js
// Today's Plate: a global, date-seeded deck of 12 photo recipes from
// Spoonacular. One complexSearch call returns photo + macros + ingredients +
// steps + servings, normalized into Glutt's PlateCard contract. Edge-cached by
// UTC date so normal opens cost ~0 Spoonacular points.

function resolveSpoonacularKey() {
  return (process.env.SPOONACULAR_API_KEY || "").trim();
}

const ROTATING_QUERIES = [
  "high protein dinner",
  "easy weeknight dinner",
  "healthy meal prep",
  "30 minute dinner",
  "one pan dinner",
  "chicken dinner",
  "vegetarian dinner",
  "comfort food dinner",
  "mediterranean dinner",
  "budget family dinner",
];

function nutrient(nutrition, name) {
  const list = (nutrition && nutrition.nutrients) || [];
  const hit = list.find((n) => n && n.name === name);
  return hit ? Math.round(hit.amount) : null;
}

function normalizeRecipe(r) {
  const nutrition = r.nutrition || {};
  const ingredients = (r.extendedIngredients || []).map((ing) => ({
    raw: ing.original || ing.originalString || ing.name || "",
    name: ing.name || null,
    quantity: typeof ing.amount === "number" ? ing.amount : null,
    unit: ing.unit || null,
  }));
  const steps = [];
  const instr = r.analyzedInstructions || [];
  for (const block of instr) {
    for (const s of block.steps || []) {
      if (s && s.step) steps.push(s.step);
    }
  }
  const diets = Array.isArray(r.diets) ? r.diets : [];
  const dishTypes = Array.isArray(r.dishTypes) ? r.dishTypes : [];
  return {
    id: `spoonacular:${r.id}`,
    title: r.title || "",
    imageURL: r.image || null,
    source: "spoonacular",
    sourceURL: r.sourceUrl || null,
    creator: r.creditsText || r.sourceName || null,
    license: "spoonacular",
    summary: typeof r.summary === "string" ? r.summary.replace(/<[^>]+>/g, "").slice(0, 280) : null,
    servings: typeof r.servings === "number" ? r.servings : null,
    prepMinutes: 0,
    cookMinutes: typeof r.readyInMinutes === "number" ? r.readyInMinutes : null,
    difficulty: "beginner",
    tags: [...new Set([...dishTypes, ...diets])],
    dietFlags: diets,
    macros: {
      calories: nutrient(nutrition, "Calories"),
      protein: nutrient(nutrition, "Protein"),
      carbs: nutrient(nutrition, "Carbohydrates"),
      fat: nutrient(nutrition, "Fat"),
      estimated: false,
    },
    ingredients,
    steps,
    nutritionNote: null,
  };
}

function imageWorthy(card) {
  return Boolean(card.imageURL) && card.steps.length > 0 && card.ingredients.length > 0;
}

export default async function handler(req, res) {
  res.setHeader("x-glutt-proxy-version", "plates-2026-06-26-1");

  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = resolveSpoonacularKey();
  const expectedProxyKey = process.env.GLUTT_PROXY_CLIENT_KEY || "";

  if (!apiKey) {
    return res.status(500).json({ error: "Server misconfigured: missing SPOONACULAR_API_KEY" });
  }
  if (expectedProxyKey) {
    const incomingKey = req.headers["x-glutt-proxy-key"] || "";
    if (incomingKey !== expectedProxyKey) {
      return res.status(401).json({ error: "Unauthorized" });
    }
  }

  const dayIndex = Math.floor(Date.now() / 86400000);
  const query = ROTATING_QUERIES[dayIndex % ROTATING_QUERIES.length];

  const url = new URL("https://api.spoonacular.com/recipes/complexSearch");
  url.searchParams.set("apiKey", apiKey);
  url.searchParams.set("query", query);
  url.searchParams.set("number", "12");
  url.searchParams.set("addRecipeInformation", "true");
  url.searchParams.set("addRecipeNutrition", "true");
  url.searchParams.set("fillIngredients", "true");
  url.searchParams.set("instructionsRequired", "true");
  url.searchParams.set("sort", "popularity");

  try {
    const upstream = await fetch(url);
    if (!upstream.ok) {
      const detail = await upstream.text();
      return res.status(502).json({ error: "Spoonacular request failed", detail: detail.slice(0, 300) });
    }
    const data = await upstream.json();
    const recipes = (data.results || []).map(normalizeRecipe).filter(imageWorthy);

    // Date-seeded + globally shared → cache hard so a day's deck is one call.
    res.setHeader("Cache-Control", "s-maxage=43200, stale-while-revalidate=86400");
    return res.status(200).json({ deckTitle: "Today's Plate", recipes, nextPageToken: null });
  } catch (error) {
    return res.status(502).json({
      error: "Spoonacular request failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
```

- [ ] **Step 2: Create the search handler**

Create `vercel-ai-proxy/api/plates/search.js`. It reuses the same normalization (duplicated locally — Vercel functions are independent files and the existing `discover/*` handlers each inline their own `mapItems`, so we follow that convention rather than adding a shared module):

```js
// Explore/search: live Spoonacular complexSearch by query, paginated via
// offset. Cached per (query) for a day. Same PlateCard contract as deck.js.

function resolveSpoonacularKey() {
  return (process.env.SPOONACULAR_API_KEY || "").trim();
}

function nutrient(nutrition, name) {
  const list = (nutrition && nutrition.nutrients) || [];
  const hit = list.find((n) => n && n.name === name);
  return hit ? Math.round(hit.amount) : null;
}

function normalizeRecipe(r) {
  const nutrition = r.nutrition || {};
  const ingredients = (r.extendedIngredients || []).map((ing) => ({
    raw: ing.original || ing.originalString || ing.name || "",
    name: ing.name || null,
    quantity: typeof ing.amount === "number" ? ing.amount : null,
    unit: ing.unit || null,
  }));
  const steps = [];
  for (const block of r.analyzedInstructions || []) {
    for (const s of block.steps || []) {
      if (s && s.step) steps.push(s.step);
    }
  }
  const diets = Array.isArray(r.diets) ? r.diets : [];
  const dishTypes = Array.isArray(r.dishTypes) ? r.dishTypes : [];
  return {
    id: `spoonacular:${r.id}`,
    title: r.title || "",
    imageURL: r.image || null,
    source: "spoonacular",
    sourceURL: r.sourceUrl || null,
    creator: r.creditsText || r.sourceName || null,
    license: "spoonacular",
    summary: typeof r.summary === "string" ? r.summary.replace(/<[^>]+>/g, "").slice(0, 280) : null,
    servings: typeof r.servings === "number" ? r.servings : null,
    prepMinutes: 0,
    cookMinutes: typeof r.readyInMinutes === "number" ? r.readyInMinutes : null,
    difficulty: "beginner",
    tags: [...new Set([...dishTypes, ...diets])],
    dietFlags: diets,
    macros: {
      calories: nutrient(nutrition, "Calories"),
      protein: nutrient(nutrition, "Protein"),
      carbs: nutrient(nutrition, "Carbohydrates"),
      fat: nutrient(nutrition, "Fat"),
      estimated: false,
    },
    ingredients,
    steps,
    nutritionNote: null,
  };
}

const PAGE_SIZE = 12;

export default async function handler(req, res) {
  res.setHeader("x-glutt-proxy-version", "plates-2026-06-26-1");

  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = resolveSpoonacularKey();
  const expectedProxyKey = process.env.GLUTT_PROXY_CLIENT_KEY || "";
  if (!apiKey) {
    return res.status(500).json({ error: "Server misconfigured: missing SPOONACULAR_API_KEY" });
  }
  if (expectedProxyKey) {
    const incomingKey = req.headers["x-glutt-proxy-key"] || "";
    if (incomingKey !== expectedProxyKey) {
      return res.status(401).json({ error: "Unauthorized" });
    }
  }

  const q = (req.query.q || "").toString().trim();
  if (!q) {
    return res.status(400).json({ error: "Missing q" });
  }
  const offset = Math.max(0, parseInt((req.query.pageToken || "0").toString(), 10) || 0);

  const url = new URL("https://api.spoonacular.com/recipes/complexSearch");
  url.searchParams.set("apiKey", apiKey);
  url.searchParams.set("query", q);
  url.searchParams.set("number", String(PAGE_SIZE));
  url.searchParams.set("offset", String(offset));
  url.searchParams.set("addRecipeInformation", "true");
  url.searchParams.set("addRecipeNutrition", "true");
  url.searchParams.set("fillIngredients", "true");
  url.searchParams.set("instructionsRequired", "true");

  try {
    const upstream = await fetch(url);
    if (!upstream.ok) {
      const detail = await upstream.text();
      return res.status(502).json({ error: "Spoonacular request failed", detail: detail.slice(0, 300) });
    }
    const data = await upstream.json();
    const recipes = (data.results || []).map(normalizeRecipe).filter((c) => c.imageURL);
    const total = typeof data.totalResults === "number" ? data.totalResults : 0;
    const nextOffset = offset + PAGE_SIZE;
    const nextPageToken = nextOffset < total ? String(nextOffset) : null;

    res.setHeader("Cache-Control", "s-maxage=86400, stale-while-revalidate=604800");
    return res.status(200).json({ deckTitle: null, recipes, nextPageToken });
  } catch (error) {
    return res.status(502).json({
      error: "Spoonacular request failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
```

- [ ] **Step 3: Add the health presence flag**

In `vercel-ai-proxy/api/health.js`, inside the `env: { ... }` object, add after the `has_YOUTUBE_API_KEY` line:

```js
      has_SPOONACULAR_API_KEY: Boolean((process.env.SPOONACULAR_API_KEY || "").trim()),
```

- [ ] **Step 4: Syntax-check**

Run:

```bash
node --check vercel-ai-proxy/api/plates/deck.js && node --check vercel-ai-proxy/api/plates/search.js && node --check vercel-ai-proxy/api/health.js
```

Expected: no output (exit 0).

- [ ] **Step 5: Commit**

```bash
git add vercel-ai-proxy/api/plates/deck.js vercel-ai-proxy/api/plates/search.js vercel-ai-proxy/api/health.js
git commit -m "feat(plates): add Spoonacular-backed deck + search proxy endpoints"
```

> **Founder action (out of band):** rotate the Spoonacular key, set `SPOONACULAR_API_KEY` in Vercel env, deploy. Verify: `curl https://glutt-sable.vercel.app/api/health` shows `has_SPOONACULAR_API_KEY: true`; `curl 'https://glutt-sable.vercel.app/api/plates/deck' -H 'x-glutt-proxy-key: <key>'` returns 12 recipes.

---

## Task 5: PlateCard models + decode test

**Files:**
- Create: `Glutt/Services/Plates/PlateCard.swift`
- Test: `GluttTests/PlateCardDecodeTests.swift`

**Interfaces:**
- Produces:
  - `struct PlateCard: Decodable, Identifiable, Equatable` — `id, title, imageURL?, source, sourceURL?, creator?, license?, summary?, servings?, prepMinutes?, cookMinutes?, difficulty?, tags:[String], dietFlags:[String], macros: PlateMacros?, ingredients:[PlateIngredient], steps:[String], nutritionNote?`.
  - `struct PlateMacros: Decodable, Equatable` — `calories: Double?, protein: Double?, carbs: Double?, fat: Double?, estimated: Bool` + rounded `Int?` accessors `caloriesInt/proteinInt/carbsInt/fatInt`.
  - `struct PlateIngredient: Decodable, Equatable` — `raw: String, name: String?, quantity: Double?, unit: String?`.
  - `struct PlatesResponse: Decodable, Equatable` — `deckTitle: String?, recipes: [PlateCard], nextPageToken: String?`.

- [ ] **Step 1: Write the failing test**

Create `GluttTests/PlateCardDecodeTests.swift`:

```swift
import XCTest
@testable import Glutt

final class PlateCardDecodeTests: XCTestCase {
    private let json = """
    {
      "deckTitle": "Today's Plate",
      "recipes": [
        {
          "id": "spoonacular:715538",
          "title": "Creamy Lemon Chicken Rice Bowl",
          "imageURL": "https://img.test/715538.jpg",
          "source": "spoonacular",
          "sourceURL": "https://feast.test/recipe",
          "creator": "Feast & Flavor",
          "license": "spoonacular",
          "summary": "Weeknight bowl",
          "servings": 4,
          "prepMinutes": 0,
          "cookMinutes": 30,
          "difficulty": "beginner",
          "tags": ["high-protein","dinner"],
          "dietFlags": ["gluten free"],
          "macros": { "calories": 620, "protein": 48, "carbs": 55, "fat": 18, "estimated": false },
          "ingredients": [
            { "raw": "600 g chicken thighs", "name": "chicken thighs", "quantity": 600, "unit": "g" }
          ],
          "steps": ["Season the chicken", "Sear 4 min per side"],
          "nutritionNote": null
        }
      ],
      "nextPageToken": null
    }
    """

    func testDecodesContract() throws {
        let resp = try JSONDecoder().decode(PlatesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.deckTitle, "Today's Plate")
        XCTAssertNil(resp.nextPageToken)
        let card = try XCTUnwrap(resp.recipes.first)
        XCTAssertEqual(card.id, "spoonacular:715538")
        XCTAssertEqual(card.servings, 4)
        XCTAssertEqual(card.macros?.caloriesInt, 620)
        XCTAssertEqual(card.macros?.carbsInt, 55)
        XCTAssertEqual(card.macros?.estimated, false)
        XCTAssertEqual(card.ingredients.first?.raw, "600 g chicken thighs")
        XCTAssertEqual(card.steps.count, 2)
    }

    func testToleratesDecimalMacrosAndMissingOptionals() throws {
        let minimal = """
        { "recipes": [ {
          "id": "x:1", "title": "T", "source": "spoonacular",
          "tags": [], "dietFlags": [],
          "macros": { "calories": 612.6, "protein": 47.4, "carbs": null, "fat": null, "estimated": true },
          "ingredients": [], "steps": []
        } ] }
        """
        let resp = try JSONDecoder().decode(PlatesResponse.self, from: Data(minimal.utf8))
        let card = try XCTUnwrap(resp.recipes.first)
        XCTAssertNil(card.imageURL)
        XCTAssertEqual(card.macros?.caloriesInt, 613)
        XCTAssertNil(card.macros?.carbsInt)
        XCTAssertEqual(card.macros?.estimated, true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `xcodegen generate`, then `test_sim`. Expected: FAIL — `PlatesResponse` undefined.

- [ ] **Step 3: Implement the models**

Create `Glutt/Services/Plates/PlateCard.swift`:

```swift
import Foundation

/// A photo recipe surfaced in the Plates feed. Transient — never persisted
/// until the user saves it (then it goes through the normal import chokepoint).
struct PlateCard: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let imageURL: String?
    let source: String
    let sourceURL: String?
    let creator: String?
    let license: String?
    let summary: String?
    let servings: Int?
    let prepMinutes: Int?
    let cookMinutes: Int?
    let difficulty: String?
    let tags: [String]
    let dietFlags: [String]
    let macros: PlateMacros?
    let ingredients: [PlateIngredient]
    let steps: [String]
    let nutritionNote: String?

    // Optional-tolerant decoding: arrays default to empty, scalars to nil.
    enum CodingKeys: String, CodingKey {
        case id, title, imageURL, source, sourceURL, creator, license, summary
        case servings, prepMinutes, cookMinutes, difficulty, tags, dietFlags
        case macros, ingredients, steps, nutritionNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "spoonacular"
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        creator = try c.decodeIfPresent(String.self, forKey: .creator)
        license = try c.decodeIfPresent(String.self, forKey: .license)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        servings = try c.decodeIfPresent(Int.self, forKey: .servings)
        prepMinutes = try c.decodeIfPresent(Int.self, forKey: .prepMinutes)
        cookMinutes = try c.decodeIfPresent(Int.self, forKey: .cookMinutes)
        difficulty = try c.decodeIfPresent(String.self, forKey: .difficulty)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        dietFlags = try c.decodeIfPresent([String].self, forKey: .dietFlags) ?? []
        macros = try c.decodeIfPresent(PlateMacros.self, forKey: .macros)
        ingredients = try c.decodeIfPresent([PlateIngredient].self, forKey: .ingredients) ?? []
        steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
        nutritionNote = try c.decodeIfPresent(String.self, forKey: .nutritionNote)
    }
}

struct PlateMacros: Decodable, Equatable {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let estimated: Bool

    private func rounded(_ v: Double?) -> Int? { v.map { Int($0.rounded()) } }
    var caloriesInt: Int? { rounded(calories) }
    var proteinInt: Int? { rounded(protein) }
    var carbsInt: Int? { rounded(carbs) }
    var fatInt: Int? { rounded(fat) }
}

struct PlateIngredient: Decodable, Equatable {
    let raw: String
    let name: String?
    let quantity: Double?
    let unit: String?
}

/// One page (or the daily deck) of Plates results from the proxy.
struct PlatesResponse: Decodable, Equatable {
    let deckTitle: String?
    let recipes: [PlateCard]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey { case deckTitle, recipes, nextPageToken }

    init(deckTitle: String?, recipes: [PlateCard], nextPageToken: String?) {
        self.deckTitle = deckTitle
        self.recipes = recipes
        self.nextPageToken = nextPageToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deckTitle = try c.decodeIfPresent(String.self, forKey: .deckTitle)
        recipes = try c.decodeIfPresent([PlateCard].self, forKey: .recipes) ?? []
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run `test_sim`. Expected: `PlateCardDecodeTests` passes.

- [ ] **Step 5: Commit**

```bash
git add Glutt/Services/Plates/PlateCard.swift GluttTests/PlateCardDecodeTests.swift
git commit -m "feat(plates): add transient PlateCard contract + decode tests"
```

---

## Task 6: PlatesService

**Files:**
- Create: `Glutt/Services/Plates/PlatesService.swift`
- Test: `GluttTests/PlatesServiceTests.swift`

**Interfaces:**
- Consumes: `PlatesResponse` (Task 5), `Secrets.aiProxyBaseURL/aiProxyClientKey`.
- Produces:
  - `enum PlatesError: LocalizedError { case notConfigured, badResponse(String) }`
  - `struct PlatesService { typealias Transport = (URLRequest) async throws -> (Data, URLResponse); var transport; var baseURL; var clientKey; static let live; func daily() async throws -> PlatesResponse; func search(query: String, pageToken: String?) async throws -> PlatesResponse }`

- [ ] **Step 1: Write the failing test**

Create `GluttTests/PlatesServiceTests.swift`:

```swift
import XCTest
@testable import Glutt

final class PlatesServiceTests: XCTestCase {
    private func ok(_ json: String, url: URL) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func testDailyBuildsRequestAndDecodes() async throws {
        var captured: URLRequest?
        let service = PlatesService(
            transport: { req in
                captured = req
                return self.ok(#"{ "deckTitle": "Today's Plate", "recipes": [], "nextPageToken": null }"#, url: req.url!)
            },
            baseURL: "https://example.test/api",
            clientKey: "secret-key"
        )
        let resp = try await service.daily()
        XCTAssertEqual(resp.deckTitle, "Today's Plate")
        let url = try XCTUnwrap(captured?.url)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://example.test/api/plates/deck"))
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "x-glutt-proxy-key"), "secret-key")
    }

    func testSearchSendsQueryAndPageToken() async throws {
        var captured: URLRequest?
        let service = PlatesService(
            transport: { req in
                captured = req
                return self.ok(#"{ "recipes": [], "nextPageToken": "12" }"#, url: req.url!)
            },
            baseURL: "https://example.test/api",
            clientKey: "k"
        )
        let resp = try await service.search(query: "tofu bowl", pageToken: "12")
        XCTAssertEqual(resp.nextPageToken, "12")
        let comps = URLComponents(url: captured!.url!, resolvingAgainstBaseURL: false)!
        XCTAssertTrue(comps.path.hasSuffix("/plates/search"))
        XCTAssertEqual(comps.queryItems?.first { $0.name == "q" }?.value, "tofu bowl")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "pageToken" }?.value, "12")
    }

    func testNon2xxThrowsBadResponse() async {
        let service = PlatesService(
            transport: { req in
                ("boom".data(using: .utf8)!, HTTPURLResponse(url: req.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!)
            },
            baseURL: "https://example.test/api",
            clientKey: "k"
        )
        do { _ = try await service.daily(); XCTFail("expected throw") }
        catch let PlatesError.badResponse(detail) { XCTAssertTrue(detail.contains("502")) }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testEmptyBaseURLThrowsNotConfigured() async {
        let service = PlatesService(transport: { _ in (Data(), URLResponse()) }, baseURL: "", clientKey: "")
        do { _ = try await service.daily(); XCTFail("expected throw") }
        catch PlatesError.notConfigured {} catch { XCTFail("wrong error: \(error)") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `xcodegen generate`, then `test_sim`. Expected: FAIL — `PlatesService` undefined.

- [ ] **Step 3: Implement the service**

Create `Glutt/Services/Plates/PlatesService.swift`:

```swift
import Foundation

enum PlatesError: LocalizedError {
    case notConfigured
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "The recipe feed isn't available in this build."
        case .badResponse(let detail): "Couldn't load recipes: \(detail)"
        }
    }
}

/// Talks to the Glutt proxy's Plates endpoints. Mirrors `DiscoverService`'s
/// transport + auth, with an injectable `transport` so it is testable.
struct PlatesService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var baseURL: String = Secrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    var clientKey: String = Secrets.aiProxyClientKey.trimmingCharacters(in: .whitespacesAndNewlines)

    static let live = PlatesService()

    func daily() async throws -> PlatesResponse {
        try await get(path: "plates/deck", queryItems: [])
    }

    func search(query: String, pageToken: String?) async throws -> PlatesResponse {
        var items = [URLQueryItem(name: "q", value: query)]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await get(path: "plates/search", queryItems: items)
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> PlatesResponse {
        guard !baseURL.isEmpty else { throw PlatesError.notConfigured }
        guard var comps = URLComponents(string: "\(baseURL)/\(path)") else {
            throw PlatesError.badResponse("Bad URL")
        }
        comps.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = comps.url else { throw PlatesError.badResponse("Bad URL") }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"
        if !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        }

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PlatesError.badResponse("HTTP \(code)")
        }
        do {
            return try JSONDecoder().decode(PlatesResponse.self, from: data)
        } catch {
            throw PlatesError.badResponse("Unexpected response shape")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run `test_sim`. Expected: `PlatesServiceTests` passes.

- [ ] **Step 5: Commit**

```bash
git add Glutt/Services/Plates/PlatesService.swift GluttTests/PlatesServiceTests.swift
git commit -m "feat(plates): add PlatesService proxy client"
```

---

## Task 7: PlateCardMapper + PlatesSaver

**Files:**
- Create: `Glutt/Services/Plates/PlateCardMapper.swift`
- Create: `Glutt/Services/Plates/PlatesSaver.swift`
- Test: `GluttTests/PlatesSaverTests.swift`

**Interfaces:**
- Consumes: `PlateCard` (Task 5), `RecipeFactory.make` (Task 1), `DiscoverSaver.existingRecipe(forSourceURL:in:)`, `RecipeImageBackfill.ensure(for:in:fetch:)`.
- Produces:
  - `enum PlateCardMapper { static func draft(from card: PlateCard) -> ImportedRecipeDraft }`
  - `enum PlatesSaver { @MainActor static func save(card: PlateCard, into context: ModelContext, fetch: RecipeImageBackfill.Fetch = RecipeImageBackfill.defaultFetch) async throws -> Recipe }`

- [ ] **Step 1: Write the failing test**

Create `GluttTests/PlatesSaverTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PlatesSaverTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        RecipeImageBackfill.resetFailedURLsForTesting()
    }
    override func tearDownWithError() throws { container = nil; try super.tearDownWithError() }

    // A valid 1×1 PNG so ImagePrep can re-encode it during eager backfill.
    private let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMCAYAAALEj8AAAAAASUVORK5CYII="

    private func card(id: String = "spoonacular:1", url: String = "https://feast.test/r") -> PlateCard {
        let json = """
        { "id": "\(id)", "title": "Lemon Chicken", "imageURL": "https://img.test/1.jpg",
          "source": "spoonacular", "sourceURL": "\(url)", "creator": "Feast",
          "servings": 4, "cookMinutes": 30, "tags": ["dinner"], "dietFlags": [],
          "macros": { "calories": 620, "protein": 48, "carbs": 55, "fat": 18, "estimated": false },
          "ingredients": [ { "raw": "600 g chicken thighs", "name": "chicken", "quantity": 600, "unit": "g" } ],
          "steps": ["Season", "Sear 4 min"] }
        """
        return try! JSONDecoder().decode(PlateCard.self, from: Data(json.utf8))
    }

    func testSaveBuildsRecipeWithFullMacros() async throws {
        let context = container.mainContext
        let fetch: RecipeImageBackfill.Fetch = { _ in Data(base64Encoded: self.pngBase64)! }
        let recipe = try await PlatesSaver.save(card: card(), into: context, fetch: fetch)

        XCTAssertEqual(recipe.title, "Lemon Chicken")
        XCTAssertEqual(recipe.sourceURL, "https://feast.test/r")
        XCTAssertEqual(recipe.calories, 620)
        XCTAssertEqual(recipe.carbGrams, 55)
        XCTAssertEqual(recipe.fatGrams, 18)
        XCTAssertFalse(recipe.nutritionIsEstimated)
        XCTAssertEqual(recipe.ingredients.count, 1)
        XCTAssertEqual(recipe.steps.count, 2)
        XCTAssertNotNil(recipe.imageData, "eager backfill should cache the hero image")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Recipe>()).count, 1)
    }

    func testSaveDedupsBySourceURL() async throws {
        let context = container.mainContext
        let pre = Recipe(title: "Already", sourceURL: "https://feast.test/r", sourcePlatform: .website)
        context.insert(pre)
        try context.save()

        let recipe = try await PlatesSaver.save(card: card(), into: context, fetch: { _ in Data() })
        XCTAssertEqual(recipe.persistentModelID, pre.persistentModelID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Recipe>()).count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `xcodegen generate`, then `test_sim`. Expected: FAIL — `PlateCardMapper`/`PlatesSaver` undefined.

- [ ] **Step 3: Implement the mapper**

Create `Glutt/Services/Plates/PlateCardMapper.swift`:

```swift
import Foundation

/// Builds an `ImportedRecipeDraft` directly from a structured `PlateCard`,
/// skipping scraping and the macro-lossy AI cleanup path. Macros + the trusted
/// flag are written straight onto the draft so they survive to the saved Recipe.
enum PlateCardMapper {
    static func draft(from card: PlateCard) -> ImportedRecipeDraft {
        var draft = ImportedRecipeDraft()
        draft.title = card.title
        draft.summary = card.summary
        draft.imageURL = card.imageURL
        draft.creator = card.creator
        draft.sourceURL = card.sourceURL
        draft.platform = .website
        draft.servings = card.servings
        draft.prepMinutes = card.prepMinutes
        draft.cookMinutes = card.cookMinutes
        draft.ingredientLines = card.ingredients.map(\.raw).filter { !$0.isEmpty }
        draft.stepTexts = card.steps
        draft.tags = card.tags
        draft.calories = card.macros?.caloriesInt
        draft.proteinGrams = card.macros?.proteinInt
        draft.carbGrams = card.macros?.carbsInt
        draft.fatGrams = card.macros?.fatInt
        draft.nutritionIsEstimated = card.macros?.estimated ?? true
        return draft
    }
}
```

- [ ] **Step 4: Implement the saver**

Create `Glutt/Services/Plates/PlatesSaver.swift`:

```swift
import Foundation
import SwiftData

/// Saves a `PlateCard` into the library. Dedups by `sourceURL`, builds a Recipe
/// through the shared `RecipeFactory` chokepoint, and — unlike DiscoverSaver —
/// eagerly backfills the hero image so My Recipes shows it instantly/offline.
enum PlatesSaver {
    @MainActor
    static func save(
        card: PlateCard,
        into context: ModelContext,
        fetch: RecipeImageBackfill.Fetch = RecipeImageBackfill.defaultFetch
    ) async throws -> Recipe {
        if let sourceURL = card.sourceURL,
           let existing = DiscoverSaver.existingRecipe(forSourceURL: sourceURL, in: context) {
            return existing
        }
        let draft = PlateCardMapper.draft(from: card)
        let recipe = RecipeFactory.make(from: draft)
        context.insert(recipe)
        try context.save()
        await RecipeImageBackfill.ensure(for: recipe, in: context, fetch: fetch)
        return recipe
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run `test_sim`. Expected: `PlatesSaverTests` passes.

- [ ] **Step 6: Commit**

```bash
git add Glutt/Services/Plates/PlateCardMapper.swift Glutt/Services/Plates/PlatesSaver.swift GluttTests/PlatesSaverTests.swift
git commit -m "feat(plates): map + save PlateCards with full macros and eager image backfill"
```

---

## Task 8: Deck filter + seed deck

**Files:**
- Create: `Glutt/Services/Plates/PlatesDeckFilter.swift`
- Create: `Glutt/Services/Plates/PlatesSeedDeck.swift`
- Create: `Glutt/Resources/PlatesSeedDeck.json`
- Test: `GluttTests/PlatesDeckFilterTests.swift`, `GluttTests/PlatesSeedDeckTests.swift`

**Interfaces:**
- Consumes: `PlateCard`, `DietGuard.isAllowed(ingredientName:rules:allergies:)`, `IngredientCanonicalizer.canonicalize`.
- Produces:
  - `enum PlatesDeckFilter { static func filter(_ cards: [PlateCard], rules: [DietaryRule], allergies: [String], savedSourceURLs: Set<String>) -> [PlateCard] }`
  - `enum PlatesSeedDeck { static func decode(_ data: Data) -> PlatesResponse?; static func load(from bundle: Bundle = .main) -> PlatesResponse }`

- [ ] **Step 1: Write the failing tests**

Create `GluttTests/PlatesDeckFilterTests.swift`:

```swift
import XCTest
@testable import Glutt

final class PlatesDeckFilterTests: XCTestCase {
    private func card(_ id: String, url: String, ingredient: String) -> PlateCard {
        let json = """
        { "id": "\(id)", "title": "T", "source": "spoonacular", "sourceURL": "\(url)",
          "tags": [], "dietFlags": [],
          "ingredients": [ { "raw": "\(ingredient)", "name": "\(ingredient)" } ], "steps": ["s"] }
        """
        return try! JSONDecoder().decode(PlateCard.self, from: Data(json.utf8))
    }

    func testHardFiltersAllergyConflicts() {
        let cards = [card("1", url: "a", ingredient: "peanut butter"),
                     card("2", url: "b", ingredient: "chicken thighs")]
        let out = PlatesDeckFilter.filter(cards, rules: [], allergies: ["peanut"], savedSourceURLs: [])
        XCTAssertEqual(out.map(\.id), ["2"])
    }

    func testHardFiltersRuleConflicts() {
        let cards = [card("1", url: "a", ingredient: "pork belly"),
                     card("2", url: "b", ingredient: "chickpeas")]
        let out = PlatesDeckFilter.filter(cards, rules: [.halal], allergies: [], savedSourceURLs: [])
        XCTAssertEqual(out.map(\.id), ["2"])
    }

    func testDropsAlreadySaved() {
        let cards = [card("1", url: "https://x/a", ingredient: "rice"),
                     card("2", url: "https://x/b", ingredient: "rice")]
        let out = PlatesDeckFilter.filter(cards, rules: [], allergies: [], savedSourceURLs: ["https://x/a"])
        XCTAssertEqual(out.map(\.id), ["2"])
    }
}
```

Create `GluttTests/PlatesSeedDeckTests.swift`:

```swift
import XCTest
@testable import Glutt

final class PlatesSeedDeckTests: XCTestCase {
    func testDecodeParsesDeck() {
        let json = #"{ "deckTitle": "Seed", "recipes": [ { "id": "s:1", "title": "Seed Bowl", "source": "curated", "tags": [], "dietFlags": [], "ingredients": [], "steps": [] } ], "nextPageToken": null }"#
        let resp = PlatesSeedDeck.decode(Data(json.utf8))
        XCTAssertEqual(resp?.recipes.first?.id, "s:1")
    }

    func testDecodeReturnsNilOnGarbage() {
        XCTAssertNil(PlatesSeedDeck.decode(Data("not json".utf8)))
    }

    func testBundledSeedLoads() {
        // The app bundle ships PlatesSeedDeck.json with >= 1 recipe.
        let resp = PlatesSeedDeck.load()
        XCTAssertGreaterThanOrEqual(resp.recipes.count, 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run `xcodegen generate`, then `test_sim`. Expected: FAIL — types undefined.

- [ ] **Step 3: Implement the deck filter**

Create `Glutt/Services/Plates/PlatesDeckFilter.swift`:

```swift
import Foundation

/// Hard-filters a deck before it's shown: drops cards with any allergy/rule
/// conflict (reusing DietGuard's ingredient check) and cards the user already
/// saved (by sourceURL). Dislikes are NOT filtered — they surface as soft
/// warnings on the card back, never silently hidden.
enum PlatesDeckFilter {
    static func filter(
        _ cards: [PlateCard],
        rules: [DietaryRule],
        allergies: [String],
        savedSourceURLs: Set<String>
    ) -> [PlateCard] {
        cards.filter { card in
            if let url = card.sourceURL, savedSourceURLs.contains(url) { return false }
            return card.ingredients.allSatisfy { ing in
                let name = ing.name ?? ing.raw
                return DietGuard.isAllowed(ingredientName: name, rules: rules, allergies: allergies)
            }
        }
    }
}
```

- [ ] **Step 4: Implement the seed loader**

Create `Glutt/Services/Plates/PlatesSeedDeck.swift`:

```swift
import Foundation

/// Loads the bundled fallback deck so Plates works on first run, offline, or
/// before the backend is deployed.
enum PlatesSeedDeck {
    static func decode(_ data: Data) -> PlatesResponse? {
        try? JSONDecoder().decode(PlatesResponse.self, from: data)
    }

    static func load(from bundle: Bundle = .main) -> PlatesResponse {
        guard let url = bundle.url(forResource: "PlatesSeedDeck", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let resp = decode(data) else {
            return PlatesResponse(deckTitle: "Today's Plate", recipes: [], nextPageToken: nil)
        }
        return resp
    }
}
```

- [ ] **Step 5: Create the bundled seed JSON**

Create `Glutt/Resources/PlatesSeedDeck.json` (3 real, attribution-clean cards — expand later; keep macros complete so the bar renders):

```json
{
  "deckTitle": "Today's Plate",
  "recipes": [
    {
      "id": "curated:1",
      "title": "Sheet-Pan Harissa Chicken & Chickpeas",
      "imageURL": "https://images.unsplash.com/photo-1604908176997-125f25cc6f3d",
      "source": "curated",
      "sourceURL": "https://glutt.app/seed/harissa-chicken",
      "creator": "Glutt Kitchen",
      "license": "curated",
      "summary": "One pan, big flavor: harissa-roasted chicken thighs with crisp chickpeas.",
      "servings": 4,
      "prepMinutes": 10,
      "cookMinutes": 30,
      "difficulty": "beginner",
      "tags": ["high-protein", "dinner", "sheet-pan"],
      "dietFlags": ["gluten free", "dairy free"],
      "macros": { "calories": 540, "protein": 42, "carbs": 38, "fat": 22, "estimated": false },
      "ingredients": [
        { "raw": "8 chicken thighs", "name": "chicken thighs", "quantity": 8, "unit": "" },
        { "raw": "2 tbsp harissa paste", "name": "harissa", "quantity": 2, "unit": "tbsp" },
        { "raw": "1 can chickpeas, drained", "name": "chickpeas", "quantity": 1, "unit": "can" },
        { "raw": "2 tbsp olive oil", "name": "olive oil", "quantity": 2, "unit": "tbsp" }
      ],
      "steps": [
        "Heat oven to 220°C.",
        "Toss chicken and chickpeas with harissa and oil on a sheet pan.",
        "Roast 30 minutes until chicken is cooked and chickpeas crisp."
      ],
      "nutritionNote": null
    },
    {
      "id": "curated:2",
      "title": "Creamy Tomato White Bean Soup",
      "imageURL": "https://images.unsplash.com/photo-1547592180-85f173990554",
      "source": "curated",
      "sourceURL": "https://glutt.app/seed/tomato-white-bean-soup",
      "creator": "Glutt Kitchen",
      "license": "curated",
      "summary": "Velvety, weeknight-fast, and quietly high in fiber.",
      "servings": 4,
      "prepMinutes": 5,
      "cookMinutes": 20,
      "difficulty": "beginner",
      "tags": ["vegetarian", "dinner", "soup"],
      "dietFlags": ["vegetarian", "gluten free"],
      "macros": { "calories": 320, "protein": 14, "carbs": 44, "fat": 11, "estimated": false },
      "ingredients": [
        { "raw": "2 cans white beans, drained", "name": "white beans", "quantity": 2, "unit": "can" },
        { "raw": "1 can crushed tomatoes", "name": "crushed tomatoes", "quantity": 1, "unit": "can" },
        { "raw": "1 onion, diced", "name": "onion", "quantity": 1, "unit": "" },
        { "raw": "100 ml cream", "name": "cream", "quantity": 100, "unit": "ml" }
      ],
      "steps": [
        "Soften onion in a pot.",
        "Add tomatoes and beans; simmer 15 minutes.",
        "Blend smooth, stir in cream, season."
      ],
      "nutritionNote": null
    },
    {
      "id": "curated:3",
      "title": "Garlic Butter Shrimp Rice Bowl",
      "imageURL": "https://images.unsplash.com/photo-1512058564366-18510be2db19",
      "source": "curated",
      "sourceURL": "https://glutt.app/seed/garlic-shrimp-bowl",
      "creator": "Glutt Kitchen",
      "license": "curated",
      "summary": "15-minute garlicky shrimp over fluffy rice.",
      "servings": 2,
      "prepMinutes": 5,
      "cookMinutes": 10,
      "difficulty": "beginner",
      "tags": ["high-protein", "dinner", "quick"],
      "dietFlags": ["pescatarian"],
      "macros": { "calories": 480, "protein": 34, "carbs": 52, "fat": 14, "estimated": false },
      "ingredients": [
        { "raw": "300 g shrimp, peeled", "name": "shrimp", "quantity": 300, "unit": "g" },
        { "raw": "2 tbsp butter", "name": "butter", "quantity": 2, "unit": "tbsp" },
        { "raw": "3 cloves garlic, minced", "name": "garlic", "quantity": 3, "unit": "clove" },
        { "raw": "1.5 cups cooked rice", "name": "rice", "quantity": 1.5, "unit": "cup" }
      ],
      "steps": [
        "Melt butter, cook garlic 30 seconds.",
        "Add shrimp; cook 3–4 minutes until pink.",
        "Serve over rice with pan butter."
      ],
      "nutritionNote": null
    }
  ],
  "nextPageToken": null
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run `xcodegen generate`, then `test_sim`. Expected: `PlatesDeckFilterTests` and `PlatesSeedDeckTests` pass (the `testBundledSeedLoads` test confirms the JSON is bundled as a resource).

- [ ] **Step 7: Commit**

```bash
git add Glutt/Services/Plates/PlatesDeckFilter.swift Glutt/Services/Plates/PlatesSeedDeck.swift Glutt/Resources/PlatesSeedDeck.json GluttTests/PlatesDeckFilterTests.swift GluttTests/PlatesSeedDeckTests.swift
git commit -m "feat(plates): add deck diet-filter + bundled seed deck fallback"
```

---

## Task 9: PlatesFeedViewModel

**Files:**
- Create: `Glutt/Features/Plates/PlatesFeedViewModel.swift`
- Test: `GluttTests/PlatesFeedViewModelTests.swift`

**Interfaces:**
- Consumes: `PlatesService` (Task 6), `PlatesSaver` (Task 7), `PlatesDeckFilter` + `PlatesSeedDeck` (Task 8).
- Produces:
  - `@MainActor @Observable final class PlatesFeedViewModel` with: `enum Phase { idle, loading, loaded, empty, failed(String) }`; `struct Dependencies { daily; search; save; seed; cachedDeck; storeDeck; static let live }`; `private(set) var phase`, `recipes: [PlateCard]`, `index`, `savedIDs`, `skippedIDs`, `savingID`, `saveError`; `var deckTitle`; `var current: PlateCard?`; `func loadDaily(rules:allergies:savedSourceURLs:) async`; `func search(_:) async`; `func showNext() async`; `func save(_:into:) async`; `func skip(_:)`; `func clearSaveError()`.

- [ ] **Step 1: Write the failing test**

Create `GluttTests/PlatesFeedViewModelTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PlatesFeedViewModelTests: XCTestCase {
    private func card(_ id: String) -> PlateCard {
        let json = #"{ "id": "\#(id)", "title": "T-\#(id)", "source": "spoonacular", "sourceURL": "https://x/\#(id)", "tags": [], "dietFlags": [], "ingredients": [], "steps": [] }"#
        return try! JSONDecoder().decode(PlateCard.self, from: Data(json.utf8))
    }
    private func resp(_ ids: [String]) -> PlatesResponse {
        PlatesResponse(deckTitle: "Today's Plate", recipes: ids.map(card), nextPageToken: nil)
    }
    private func deps(
        daily: @escaping () async throws -> PlatesResponse,
        seed: @escaping () -> PlatesResponse = { PlatesResponse(deckTitle: nil, recipes: [], nextPageToken: nil) },
        cache: @escaping () -> PlatesResponse? = { nil }
    ) -> PlatesFeedViewModel.Dependencies {
        PlatesFeedViewModel.Dependencies(
            daily: daily,
            search: { _, _ in PlatesResponse(deckTitle: nil, recipes: [], nextPageToken: nil) },
            save: { c, ctx in let r = Recipe(title: c.title); ctx.insert(r); return r },
            seed: seed,
            cachedDeck: cache,
            storeDeck: { _ in }
        )
    }

    func testLoadDailyPopulatesAndFilters() async {
        let vm = PlatesFeedViewModel(deps: deps(daily: { self.resp(["a", "b"]) }))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: ["https://x/a"])
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.recipes.map(\.id), ["b"])  // "a" already saved → filtered
        XCTAssertEqual(vm.current?.id, "b")
    }

    func testLoadDailyFallsBackToSeedOnFailure() async {
        struct Boom: Error {}
        let vm = PlatesFeedViewModel(deps: deps(daily: { throw Boom() }, seed: { self.resp(["s1"]) }))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.recipes.map(\.id), ["s1"])
    }

    func testLoadDailyUsesCacheWhenPresent() async {
        var dailyCalls = 0
        let vm = PlatesFeedViewModel(deps: deps(
            daily: { dailyCalls += 1; return self.resp(["net"]) },
            cache: { self.resp(["cached"]) }
        ))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        XCTAssertEqual(vm.recipes.map(\.id), ["cached"])
        XCTAssertEqual(dailyCalls, 0, "cached deck must not hit the network")
    }

    func testSaveMarksAndAdvances() async throws {
        let container = try ModelContainer(for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self]),
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let vm = PlatesFeedViewModel(deps: deps(daily: { self.resp(["a", "b"]) }))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        await vm.save(vm.current!, into: container.mainContext)
        XCTAssertTrue(vm.savedIDs.contains("a"))
        XCTAssertEqual(vm.current?.id, "b")
    }

    func testSkipAdvancesAndRecords() async {
        let vm = PlatesFeedViewModel(deps: deps(daily: { self.resp(["a", "b"]) }))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: [])
        vm.skip(vm.current!)
        XCTAssertTrue(vm.skippedIDs.contains("a"))
        XCTAssertEqual(vm.current?.id, "b")
    }

    func testEmptyAfterFilterSetsEmpty() async {
        let vm = PlatesFeedViewModel(deps: deps(daily: { self.resp(["a"]) }))
        await vm.loadDaily(rules: [], allergies: [], savedSourceURLs: ["https://x/a"])
        XCTAssertEqual(vm.phase, .empty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `xcodegen generate`, then `test_sim`. Expected: FAIL — `PlatesFeedViewModel` undefined.

- [ ] **Step 3: Implement the ViewModel**

Create `Glutt/Features/Plates/PlatesFeedViewModel.swift`:

```swift
import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class PlatesFeedViewModel {
    enum Phase: Equatable { case idle, loading, loaded, empty, failed(String) }

    struct Dependencies {
        var daily: () async throws -> PlatesResponse
        var search: (_ query: String, _ pageToken: String?) async throws -> PlatesResponse
        var save: (_ card: PlateCard, _ context: ModelContext) async throws -> Recipe
        var seed: () -> PlatesResponse
        /// Today's cached deck, or nil if none/stale (keyed by local date in `.live`).
        var cachedDeck: () -> PlatesResponse?
        var storeDeck: (PlatesResponse) -> Void

        static let live = Dependencies(
            daily: { try await PlatesService.live.daily() },
            search: { try await PlatesService.live.search(query: $0, pageToken: $1) },
            save: { try await PlatesSaver.save(card: $0, into: $1) },
            seed: { PlatesSeedDeck.load() },
            cachedDeck: { PlatesDeckCache.today() },
            storeDeck: { PlatesDeckCache.store($0) }
        )
    }

    private(set) var phase: Phase = .idle
    private(set) var recipes: [PlateCard] = []
    private(set) var index = 0
    private(set) var savedIDs: Set<String> = []
    private(set) var skippedIDs: Set<String> = []
    private(set) var savingID: String?
    private(set) var saveError: String?
    var deckTitle: String?

    private var nextPageToken: String?
    private var query = ""
    private var isExplore = false
    private let deps: Dependencies

    init(deps: Dependencies = .live) { self.deps = deps }

    var current: PlateCard? { recipes.indices.contains(index) ? recipes[index] : nil }

    func loadDaily(rules: [DietaryRule], allergies: [String], savedSourceURLs: Set<String>) async {
        isExplore = false
        deckTitle = "Today's Plate"

        // 1. Today's cached deck (instant, offline-friendly).
        if let cached = deps.cachedDeck() {
            applyDeck(cached, rules: rules, allergies: allergies, savedSourceURLs: savedSourceURLs, store: false)
            return
        }

        // 2. Network deck → cache it.
        phase = .loading
        do {
            let page = try await deps.daily()
            applyDeck(page, rules: rules, allergies: allergies, savedSourceURLs: savedSourceURLs, store: true)
        } catch {
            // 3. Bundled seed fallback.
            let seed = deps.seed()
            applyDeck(seed, rules: rules, allergies: allergies, savedSourceURLs: savedSourceURLs, store: false)
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isExplore = true
        self.query = trimmed
        deckTitle = nil
        phase = .loading
        do {
            let page = try await deps.search(trimmed, nil)
            recipes = page.recipes
            index = 0
            nextPageToken = page.nextPageToken
            phase = page.recipes.isEmpty ? .empty : .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func showNext() async {
        guard !recipes.isEmpty else { return }
        if index < recipes.count - 1 { index += 1 }
        await prefetchIfNeeded()
    }

    func save(_ card: PlateCard, into context: ModelContext) async {
        saveError = nil
        savingID = card.id
        do {
            _ = try await deps.save(card, context)
            savedIDs.insert(card.id)
            savingID = nil
            await showNext()
        } catch {
            savingID = nil
            saveError = error.localizedDescription
        }
    }

    func skip(_ card: PlateCard) {
        skippedIDs.insert(card.id)
        if index < recipes.count - 1 { index += 1 }
    }

    func clearSaveError() { saveError = nil }

    private func applyDeck(
        _ page: PlatesResponse,
        rules: [DietaryRule],
        allergies: [String],
        savedSourceURLs: Set<String>,
        store: Bool
    ) {
        if store { deps.storeDeck(page) }
        deckTitle = page.deckTitle ?? deckTitle
        recipes = PlatesDeckFilter.filter(page.recipes, rules: rules, allergies: allergies, savedSourceURLs: savedSourceURLs)
        index = 0
        nextPageToken = nil  // daily deck never paginates
        phase = recipes.isEmpty ? .empty : .loaded
    }

    private func prefetchIfNeeded() async {
        guard isExplore, let token = nextPageToken, index >= recipes.count - 2 else { return }
        do {
            let page = try await deps.search(query, token)
            recipes.append(contentsOf: page.recipes)
            nextPageToken = page.nextPageToken
        } catch {
            nextPageToken = nil
        }
    }
}
```

- [ ] **Step 4: Add the local-date deck cache used by `.live`**

Append to `Glutt/Services/Plates/PlatesSeedDeck.swift` (same file, related responsibility) a small cache:

```swift

/// Persists the daily deck keyed by local calendar date, so reopening is
/// instant and the feed works briefly offline. Refreshes when the local day
/// rolls over (which is how "07:00 local" freshness is realized client-side:
/// the first open on a new local day fetches a fresh deck).
enum PlatesDeckCache {
    private static let dayKey = "plates.deck.day"
    private static let dataKey = "plates.deck.data"

    private static func todayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    static func today() -> PlatesResponse? {
        let d = UserDefaults.standard
        guard d.string(forKey: dayKey) == todayString(),
              let data = d.data(forKey: dataKey) else { return nil }
        return PlatesSeedDeck.decode(data)
    }

    static func store(_ response: PlatesResponse) {
        guard let data = try? JSONEncoder().encode(EncodablePlates(response)) else { return }
        let d = UserDefaults.standard
        d.set(todayString(), forKey: dayKey)
        d.set(data, forKey: dataKey)
    }
}
```

`PlatesResponse`/`PlateCard` are `Decodable` only, so add a minimal `Encodable` mirror for caching. Append to `PlateCard.swift`:

```swift

/// Encodable mirror used only to persist the daily deck cache. Kept separate so
/// the wire models stay decode-only and match the server contract exactly.
struct EncodablePlates: Encodable {
    let deckTitle: String?
    let recipes: [Card]
    let nextPageToken: String?

    struct Card: Encodable {
        let id, title, source: String
        let imageURL, sourceURL, creator, license, summary, difficulty, nutritionNote: String?
        let servings, prepMinutes, cookMinutes: Int?
        let tags, dietFlags, steps: [String]
        let macros: Macros?
        let ingredients: [Ingredient]
    }
    struct Macros: Encodable { let calories, protein, carbs, fat: Double?; let estimated: Bool }
    struct Ingredient: Encodable { let raw: String; let name: String?; let quantity: Double?; let unit: String? }

    init(_ r: PlatesResponse) {
        deckTitle = r.deckTitle
        nextPageToken = r.nextPageToken
        recipes = r.recipes.map { c in
            Card(id: c.id, title: c.title, source: c.source,
                 imageURL: c.imageURL, sourceURL: c.sourceURL, creator: c.creator,
                 license: c.license, summary: c.summary, difficulty: c.difficulty,
                 nutritionNote: c.nutritionNote,
                 servings: c.servings, prepMinutes: c.prepMinutes, cookMinutes: c.cookMinutes,
                 tags: c.tags, dietFlags: c.dietFlags, steps: c.steps,
                 macros: c.macros.map { Macros(calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat, estimated: $0.estimated) },
                 ingredients: c.ingredients.map { Ingredient(raw: $0.raw, name: $0.name, quantity: $0.quantity, unit: $0.unit) })
        }
    }
}
```

> The `EncodablePlates.Card` field names match `PlateCard`'s `CodingKeys`, so a stored deck round-trips back through `PlateCard`'s decoder unchanged.

- [ ] **Step 5: Run test to verify it passes**

Run `test_sim`. Expected: `PlatesFeedViewModelTests` passes; full suite green.

- [ ] **Step 6: Commit**

```bash
git add Glutt/Features/Plates/PlatesFeedViewModel.swift Glutt/Services/Plates/PlatesSeedDeck.swift Glutt/Services/Plates/PlateCard.swift GluttTests/PlatesFeedViewModelTests.swift
git commit -m "feat(plates): add PlatesFeedViewModel with deck cache + seed fallback"
```

---

## Task 10: FeedCardView (front + flip + back)

**Files:**
- Create: `Glutt/Features/Plates/FeedCardView.swift`

**Interfaces:**
- Consumes: `PlateCard`, `MacroStrip`, `RecipeImageView` (needs a `Recipe`; here we render the hero from `imageURL` via `AsyncImage` since the card isn't a Recipe), `StatPill`, `Chip`, `GluttStepper`, `Ph`, `Theme`, `Haptics`.
- Produces: `struct FeedCardView: View { let card: PlateCard; let isSaved: Bool; let isCookableNow: Bool; let onSave: () -> Void; let onSkip: () -> Void; @Binding var isFlipped: Bool; var reduceMotion: Bool }`

- [ ] **Step 1: Implement the card**

Create `Glutt/Features/Plates/FeedCardView.swift`:

```swift
import SwiftUI

/// One full-screen plate: hero photo front (title + stat strip + flip handle)
/// and a 3D-flip back (macros + servings + ingredients + steps + CTAs).
struct FeedCardView: View {
    let card: PlateCard
    let isSaved: Bool
    let isCookableNow: Bool
    let onSave: () -> Void
    let onSkip: () -> Void
    @Binding var isFlipped: Bool
    var reduceMotion: Bool = false

    @State private var displayServings: Int = 2

    private var scale: Double {
        guard let base = card.servings, base > 0 else { return 1 }
        return Double(displayServings) / Double(base)
    }

    var body: some View {
        ZStack {
            if reduceMotion {
                // Cross-fade instead of 3D rotation when Reduce Motion is on.
                if isFlipped { back } else { front }
            } else {
                front
                    .opacity(isFlipped ? 0 : 1)
                    .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                back
                    .opacity(isFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            }
        }
        .onAppear { displayServings = card.servings ?? 2 }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.8), value: isFlipped)
    }

    // MARK: Front

    private var front: some View {
        ZStack(alignment: .bottomLeading) {
            heroImage
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if isCookableNow {
                    HStack(spacing: 4) {
                        Ph.basket.fill.resizable().scaledToFit().frame(width: 13, height: 13)
                        Text("You can make this now")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.Colors.accent)
                    .clipShape(Capsule())
                }

                Text(card.title)
                    .font(.gluttLargeTitle)
                    .foregroundStyle(.white)
                    .lineLimit(3)

                if let creator = card.creator {
                    Text(creator)
                        .font(.gluttCaption)
                        .foregroundStyle(.white.opacity(0.85))
                }

                statStrip

                flipHandle
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, 80)  // clear the action bar
        }
        .contentShape(Rectangle())
        .onTapGesture { flip() }
    }

    private var heroImage: some View {
        GeometryReader { geo in
            AsyncImage(url: card.imageURL.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default:
                    Theme.Colors.accent.opacity(0.08)
                        .overlay(Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(Theme.Colors.accent.opacity(0.35)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private var statStrip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let cook = card.cookMinutes, cook > 0 {
                StatPill.time("\(cook) min")
            }
            if let cal = card.macros?.caloriesInt {
                StatPill(icon: Ph.flame.fill, text: "\(cal) cal",
                         foreground: Theme.Colors.tomato, background: Theme.Colors.tomatoTint)
            }
            if let protein = card.macros?.proteinInt {
                StatPill(icon: Ph.barbell.fill, text: "\(protein)g protein")
            }
        }
    }

    private var flipHandle: some View {
        HStack(spacing: 6) {
            Ph.bookOpen.fill.resizable().scaledToFit().frame(width: 16, height: 16)
            Text("Recipe").font(.gluttCaption.weight(.heavy))
            Ph.caretRight.bold.resizable().scaledToFit().frame(width: 11, height: 11)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .onTapGesture { flip() }
        .accessibilityLabel("Show recipe")
    }

    // MARK: Back

    private var back: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text(card.title).font(.gluttTitle).foregroundStyle(Theme.Colors.textPrimary)

                    if let m = card.macros {
                        MacroStrip(calories: m.caloriesInt, protein: m.proteinInt,
                                   carbs: m.carbsInt, fat: m.fatInt, isEstimated: m.estimated)
                    }

                    HStack {
                        Text("Servings").font(.gluttHeadline)
                        Spacer()
                        GluttStepper(value: $displayServings, in: 1...24, step: 1) { "\($0)" }
                    }

                    if !card.ingredients.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionLabel(text: "Ingredients")
                            ForEach(Array(card.ingredients.enumerated()), id: \.offset) { _, ing in
                                Text("• \(scaledLine(ing))")
                                    .font(.gluttBody)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                        }
                    }

                    if !card.steps.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionLabel(text: "Steps")
                            ForEach(Array(card.steps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                    Text("\(i + 1)")
                                        .font(.gluttCaption.weight(.heavy))
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Theme.Colors.accent)
                                        .clipShape(Circle())
                                    Text(step).font(.gluttBody).foregroundStyle(Theme.Colors.textPrimary)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }

            Button {
                Haptics.celebrate()
                onSave()
            } label: {
                Text(isSaved ? "Saved ✓" : "Save to cookbook").frame(maxWidth: .infinity)
            }
            .buttonStyle(.gluttPrimary)
            .disabled(isSaved)
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
        .padding(Theme.Spacing.sm)
    }

    private func scaledLine(_ ing: PlateIngredient) -> String {
        guard let qty = ing.quantity else { return ing.raw }
        let scaled = qty * scale
        let qtyText = scaled == scaled.rounded() ? String(Int(scaled)) : String(format: "%.1f", scaled)
        let unit = (ing.unit?.isEmpty == false) ? " \(ing.unit!)" : ""
        let name = ing.name ?? ing.raw
        return "\(qtyText)\(unit) \(name)"
    }

    private func flip() {
        if !reduceMotion { Haptics.impact(.medium) }
        isFlipped.toggle()
    }
}
```

> Note: ingredient scaling here is a lightweight string format (not the full `UnitConverter` pipeline, which operates on `RecipeIngredient`). This keeps the transient card free of SwiftData models; the full converter applies once the recipe is saved and viewed in `RecipeDetailView`.

- [ ] **Step 2: Build to verify**

Run `xcodegen generate`, then `build_sim`. Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Plates/FeedCardView.swift
git commit -m "feat(plates): add FeedCardView (hero front + 3D flip back)"
```

---

## Task 11: RecipeFeedView (pager + gestures)

**Files:**
- Create: `Glutt/Features/Plates/RecipeFeedView.swift`

**Interfaces:**
- Consumes: `PlatesFeedViewModel`, `FeedCardView`, `DeckEndCardView` (Task 12 — until then, a placeholder `EmptyView()` keeps this compiling; Task 12 swaps it in), `PantryMatcher`/`IngredientCanonicalizer` for "cookable now", `UserPrefs`, `Router`.
- Produces: `struct RecipeFeedView: View` (the full-screen feed presented by `RootView`).

> Build Task 12 before this in execution order if you want `DeckEndCardView` live; the plan lists the View here because it's the feed shell. To avoid a forward reference, this task uses a local end-state inline and Task 12 extracts/replaces it. (Simpler: implement Task 12 first, then this — see execution order note at the end.)

- [ ] **Step 1: Implement the feed shell**

Create `Glutt/Features/Plates/RecipeFeedView.swift`:

```swift
import SwiftUI
import SwiftData

/// The immersive Plates feed: vertical paging between full-screen cards, a 3D
/// flip to each card's recipe, and horizontal swipe-to-save / swipe-to-skip
/// with button equivalents. Presented as a fullScreenCover from RootView.
struct RecipeFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var recipes: [Recipe]
    @Query private var pantryItems: [PantryItem]

    @State private var model = PlatesFeedViewModel()
    @State private var flippedID: String?
    @State private var dragX: CGFloat = 0

    private var prefs: UserPrefs { UserPrefs.current(in: context) }

    var body: some View {
        ZStack {
            Theme.Colors.textPrimary.ignoresSafeArea()

            switch model.phase {
            case .idle, .loading:
                ProgressView().tint(.white)
            case .failed(let message):
                EmptyStateView(
                    icon: Ph.wifiSlash.regular, title: "Couldn't load Plates",
                    message: message, actionTitle: "Retry"
                ) { Task { await load() } }
            case .empty:
                deckEndCard
            case .loaded:
                pager
            }

            topBar
        }
        .task { await load() }
        .onAppear { router.floatingButtonSuppressors += 1 }
        .onDisappear { router.floatingButtonSuppressors -= 1 }
        .alert("Couldn't save", isPresented: Binding(
            get: { model.saveError != nil }, set: { if !$0 { model.clearSaveError() } }
        )) { Button("OK", role: .cancel) {} } message: { Text(model.saveError ?? "") }
    }

    private func load() async {
        await model.loadDaily(
            rules: prefs.dietaryRules,
            allergies: prefs.allergies,
            savedSourceURLs: Set(recipes.compactMap(\.sourceURL))
        )
    }

    // MARK: Pager

    private var pager: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.recipes.enumerated()), id: \.element.id) { _, card in
                        cardPage(card)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(card.id)
                    }
                    deckEndCard
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
        }
        .ignoresSafeArea()
    }

    private func cardPage(_ card: PlateCard) -> some View {
        let isFlipped = Binding(
            get: { flippedID == card.id },
            set: { flippedID = $0 ? card.id : nil }
        )
        return FeedCardView(
            card: card,
            isSaved: model.savedIDs.contains(card.id),
            isCookableNow: cookableNow(card),
            onSave: { Task { await model.save(card, into: context) } },
            onSkip: { model.skip(card) },
            isFlipped: isFlipped,
            reduceMotion: reduceMotion
        )
        .offset(x: flippedID == card.id ? 0 : dragX)
        .rotationEffect(.degrees(flippedID == card.id ? 0 : Double(dragX / 20)))
        .overlay(swipeStamp)
        .highPriorityGesture(flippedID == card.id ? nil : swipeGesture(card))
        .safeAreaInset(edge: .bottom) { actionBar(card) }
    }

    private func swipeGesture(_ card: PlateCard) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragX = value.translation.width
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 120
                if dragX > threshold {
                    commitSwipe(card, save: true)
                } else if dragX < -threshold {
                    commitSwipe(card, save: false)
                } else {
                    withAnimation(.spring) { dragX = 0 }
                }
            }
    }

    private func commitSwipe(_ card: PlateCard, save: Bool) {
        withAnimation(.spring) { dragX = save ? 600 : -600 }
        if save { Task { await model.save(card, into: context) } } else { model.skip(card) }
        dragX = 0
    }

    @ViewBuilder
    private var swipeStamp: some View {
        if dragX > 24 {
            stamp("SAVE", color: Theme.Colors.accent).opacity(Double(min(1, dragX / 120)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(40)
        } else if dragX < -24 {
            stamp("SKIP", color: Theme.Colors.tomato).opacity(Double(min(1, -dragX / 120)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(40)
        }
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color, lineWidth: 3))
            .rotationEffect(.degrees(-12))
    }

    // MARK: Action bar (button equivalents for the gestures)

    private func actionBar(_ card: PlateCard) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            circleAction(Ph.x.bold, tint: Theme.Colors.tomato) { model.skip(card) }
            Button {
                flippedID = (flippedID == card.id) ? nil : card.id
                Haptics.impact(.medium)
            } label: {
                HStack(spacing: 6) {
                    Ph.bookOpen.fill.resizable().scaledToFit().frame(width: 16, height: 16)
                    Text("Recipe").font(.gluttCaption.weight(.heavy))
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.ultraThinMaterial).clipShape(Capsule())
            }
            circleAction(Ph.heart.fill, tint: Theme.Colors.accent) { Task { await model.save(card, into: context) } }
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    private func circleAction(_ icon: Image, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.resizable().scaledToFit().frame(width: 22, height: 22)
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial).clipShape(Circle())
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Ph.x.bold.resizable().scaledToFit().frame(width: 16, height: 16)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(.ultraThinMaterial).clipShape(Circle())
                }
                Spacer()
                if model.phase == .loaded, !model.recipes.isEmpty {
                    Text("\(min(model.index + 1, model.recipes.count)) / \(model.recipes.count)")
                        .font(.gluttCaption.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial).clipShape(Capsule())
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            Spacer()
        }
    }

    private var deckEndCard: some View {
        DeckEndCardView(
            explored: model.recipes.count + model.skippedIDs.count,
            saved: model.savedIDs.count,
            onDone: { dismiss() }
        )
    }

    // MARK: Cookable-now

    private func cookableNow(_ card: PlateCard) -> Bool {
        let available = pantryItems.filter { $0.roughQuantity != .out }
        let required = card.ingredients.filter { ($0.name ?? $0.raw).isEmpty == false }
        guard !required.isEmpty else { return false }
        let missing = required.filter { ing in
            let canonical = IngredientCanonicalizer.canonicalize(ing.name ?? ing.raw)
            return !PantryMatcher.owns(ingredientNamed: canonical, available: available)
        }
        return missing.count <= 1
    }
}
```

> If `EmptyStateView`'s initializer differs from the call used here, adjust to match its real signature (search `EmptyStateView` in the codebase). It is referenced as the project's standard empty/error state.

- [ ] **Step 2: Build to verify**

Run `xcodegen generate`, then `build_sim`. Expected: build succeeds (requires Task 12's `DeckEndCardView`). If executing strictly in order, implement Task 12 first.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Plates/RecipeFeedView.swift
git commit -m "feat(plates): add RecipeFeedView pager + 2-axis gestures + button equivalents"
```

---

## Task 12: DeckEndCardView + streak store

**Files:**
- Create: `Glutt/Features/Plates/PlatesStreak.swift`
- Create: `Glutt/Features/Plates/DeckEndCardView.swift`
- Test: `GluttTests/PlatesStreakTests.swift`

**Interfaces:**
- Produces:
  - `enum PlatesStreak { static func recordOpen(today: Date, store: UserDefaults) -> Int; static var current: Int; static func addDiscovered(_:); static func addSaved(_:) }`
  - `struct DeckEndCardView: View { let explored: Int; let saved: Int; let onDone: () -> Void }`

- [ ] **Step 1: Write the failing test**

Create `GluttTests/PlatesStreakTests.swift`:

```swift
import XCTest
@testable import Glutt

final class PlatesStreakTests: XCTestCase {
    private func store() -> UserDefaults {
        let d = UserDefaults(suiteName: "plates.streak.test")!
        d.removePersistentDomain(forName: "plates.streak.test")
        return d
    }
    private func day(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.date(from: s)!
    }

    func testFirstOpenStartsAtOne() {
        XCTAssertEqual(PlatesStreak.recordOpen(today: day("2026-06-26"), store: store()), 1)
    }

    func testConsecutiveDaysIncrement() {
        let s = store()
        _ = PlatesStreak.recordOpen(today: day("2026-06-26"), store: s)
        XCTAssertEqual(PlatesStreak.recordOpen(today: day("2026-06-27"), store: s), 2)
    }

    func testSameDayIsIdempotent() {
        let s = store()
        _ = PlatesStreak.recordOpen(today: day("2026-06-26"), store: s)
        XCTAssertEqual(PlatesStreak.recordOpen(today: day("2026-06-26"), store: s), 1)
    }

    func testGapResetsToOne() {
        let s = store()
        _ = PlatesStreak.recordOpen(today: day("2026-06-26"), store: s)
        XCTAssertEqual(PlatesStreak.recordOpen(today: day("2026-06-29"), store: s), 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `xcodegen generate`, then `test_sim`. Expected: FAIL — `PlatesStreak` undefined.

- [ ] **Step 3: Implement the streak store**

Create `Glutt/Features/Plates/PlatesStreak.swift`:

```swift
import Foundation

/// Lightweight gamification counters in UserDefaults — no backend needed.
/// Streak = consecutive local days the user opened Plates.
enum PlatesStreak {
    private static let lastDayKey = "plates.streak.lastDay"
    private static let countKey = "plates.streak.count"
    private static let discoveredKey = "plates.discovered.total"
    private static let savedKey = "plates.saved.total"

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Records an open and returns the resulting streak length.
    @discardableResult
    static func recordOpen(today: Date = .now, store: UserDefaults = .standard) -> Int {
        let todayStr = dayString(today)
        let last = store.string(forKey: lastDayKey)
        if last == todayStr { return max(1, store.integer(forKey: countKey)) }

        let yesterday = dayString(Calendar.current.date(byAdding: .day, value: -1, to: today)!)
        let newCount = (last == yesterday) ? store.integer(forKey: countKey) + 1 : 1
        store.set(todayStr, forKey: lastDayKey)
        store.set(newCount, forKey: countKey)
        return newCount
    }

    static var current: Int { UserDefaults.standard.integer(forKey: countKey) }

    static func addDiscovered(_ n: Int, store: UserDefaults = .standard) {
        store.set(store.integer(forKey: discoveredKey) + n, forKey: discoveredKey)
    }
    static func addSaved(_ n: Int, store: UserDefaults = .standard) {
        store.set(store.integer(forKey: savedKey) + n, forKey: savedKey)
    }
    static var totalDiscovered: Int { UserDefaults.standard.integer(forKey: discoveredKey) }
    static var totalSaved: Int { UserDefaults.standard.integer(forKey: savedKey) }
}
```

- [ ] **Step 4: Implement the end card**

Create `Glutt/Features/Plates/DeckEndCardView.swift`:

```swift
import SwiftUI

/// The celebratory end of the daily deck: "that's today's plate", with a streak
/// and a come-back-tomorrow hook.
struct DeckEndCardView: View {
    let explored: Int
    let saved: Int
    var onDone: () -> Void

    @State private var streak = PlatesStreak.current

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Ph.forkKnife.fill.resizable().scaledToFit().frame(width: 56, height: 56)
                .foregroundStyle(.white)
            Text("That's today's plate")
                .font(.gluttLargeTitle).foregroundStyle(.white)
            Text("You explored \(explored) and saved \(saved).")
                .font(.gluttBody).foregroundStyle(.white.opacity(0.85))
            if streak > 1 {
                Text("🔥 \(streak)-day streak")
                    .font(.gluttHeadline).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial).clipShape(Capsule())
            }
            Text("Come back tomorrow for a fresh plate.")
                .font(.gluttCaption).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button { onDone() } label: { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(.gluttPrimary)
                .padding(.horizontal, Theme.Spacing.lg)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.textPrimary)
        .onAppear { streak = PlatesStreak.current }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run `test_sim`. Expected: `PlatesStreakTests` passes; `build_sim` succeeds (DeckEndCardView compiles, unblocking Task 11).

- [ ] **Step 6: Commit**

```bash
git add Glutt/Features/Plates/PlatesStreak.swift Glutt/Features/Plates/DeckEndCardView.swift GluttTests/PlatesStreakTests.swift
git commit -m "feat(plates): add deck end card + streak/discovery counters"
```

---

## Task 13: PlatesLauncherCard + TodayView integration

**Files:**
- Create: `Glutt/Features/Plates/PlatesLauncherCard.swift`
- Modify: `Glutt/Features/Today/TodayView.swift`

**Interfaces:**
- Consumes: `Router` (Task 14 adds `pendingPresentPlates`), `Theme`, `Ph`.
- Produces: `struct PlatesLauncherCard: View { var onOpen: () -> Void }`

- [ ] **Step 1: Implement the launcher card**

Create `Glutt/Features/Plates/PlatesLauncherCard.swift`:

```swift
import SwiftUI

/// The Today-tab entry into Plates: a hero "Today's Plate is ready" card.
struct PlatesLauncherCard: View {
    var onOpen: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.medium)
            onOpen()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.accent.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Ph.forkKnife.fill.resizable().scaledToFit().frame(width: 26, height: 26)
                        .foregroundStyle(Theme.Colors.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Plate is ready 🍳")
                        .font(.gluttHeadline).foregroundStyle(Theme.Colors.textPrimary)
                    Text("12 fresh recipes — swipe, flip, save")
                        .font(.gluttCaption).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Ph.caretRight.bold.resizable().scaledToFit().frame(width: 14, height: 14)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous)
                    .strokeBorder(Theme.Colors.accent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Insert into TodayView**

In `Glutt/Features/Today/TodayView.swift`, in `body`, immediately after `quickActionsRow` (line ~63), add:

```swift
                    PlatesLauncherCard { router.pendingPresentPlates = true }
```

- [ ] **Step 3: Build to verify**

Run `xcodegen generate`, then `build_sim`. Expected: build succeeds (requires Task 14's `router.pendingPresentPlates`). Implement Task 14 first if executing strictly in order, or temporarily wire `onOpen` to a local `@State` flag and replace in Task 14.

- [ ] **Step 4: Commit**

```bash
git add Glutt/Features/Plates/PlatesLauncherCard.swift Glutt/Features/Today/TodayView.swift
git commit -m "feat(plates): add Today-tab launcher card for the Plates feed"
```

---

## Task 14: Router + RootView + notification routing

**Files:**
- Modify: `Glutt/App/Router.swift`
- Modify: `Glutt/App/RootView.swift`
- Modify: `Glutt/App/GluttApp.swift`

**Interfaces:**
- Produces: `Router.pendingPresentPlates: Bool`; `glutt://plates` sets it; RootView presents `RecipeFeedView` via `fullScreenCover` bound to it; notification `destination == "plates"` sets it.

- [ ] **Step 1: Add the Router flag + deep link**

In `Glutt/App/Router.swift`, add a property near `demoCookOnLaunch`:

```swift
    /// Set by the Today launcher card, the glutt://plates deep link, or the
    /// daily "Today's Plate" notification. RootView presents the Plates feed
    /// (a fullScreenCover, not a tab) whenever this is true.
    var pendingPresentPlates = false
```

In `handle(url:)`, add a case before `default`:

```swift
        case "plates": pendingPresentPlates = true
```

- [ ] **Step 2: Present from RootView**

In `Glutt/App/RootView.swift`, add another `.fullScreenCover` after the Cook Mode one (before or after Onboarding):

```swift
        .fullScreenCover(isPresented: $router.pendingPresentPlates) {
            RecipeFeedView()
        }
```

- [ ] **Step 3: Route the notification**

In `Glutt/App/GluttApp.swift`, in `NotificationRoutingDelegate.userNotificationCenter(_:didReceive:)`, extend the destination check:

```swift
        let destination = response.notification.request.content.userInfo["destination"] as? String
        if destination == "plan" {
            router?.selectedTab = .plan
        } else if destination == "plates" {
            router?.selectedTab = .today
            router?.pendingPresentPlates = true
        }
```

(Replace the existing single `if` with this.)

- [ ] **Step 4: Build to verify**

Run `xcodegen generate`, then `build_sim`. Expected: build succeeds. Manual: in the simulator, open the app and run `xcrun simctl openurl booted glutt://plates` — the feed should present over Today.

- [ ] **Step 5: Commit**

```bash
git add Glutt/App/Router.swift Glutt/App/RootView.swift Glutt/App/GluttApp.swift
git commit -m "feat(plates): wire glutt://plates deep link + fullScreenCover presentation"
```

---

## Task 15: Daily 07:00 "Today's Plate" notification

**Files:**
- Modify: `Glutt/Services/ReminderScheduler.swift`
- Modify: `Glutt/App/RootView.swift` (schedule on launch)

**Interfaces:**
- Produces: `ReminderScheduler.schedulePlatesDailyReminder()` — a repeating 07:00-local notification with `userInfo["destination"] = "plates"`.

- [ ] **Step 1: Add the daily scheduler**

In `Glutt/Services/ReminderScheduler.swift`, add to the `ReminderScheduler` enum:

```swift
    /// A single repeating 07:00-local nudge that the daily deck is ready.
    /// Idempotent: re-scheduling replaces the one pending request.
    static func schedulePlatesDailyReminder() {
        let id = "plates-daily"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Today's Plate is ready 🍳"
        content.body = "12 fresh recipes to swipe through. Tap to explore."
        content.sound = .default
        content.userInfo = ["destination": "plates"]

        var components = DateComponents()
        components.hour = 7
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
```

- [ ] **Step 2: Schedule on launch (after permission)**

In `Glutt/App/RootView.swift`, in the existing `.task { await RecipeImageBackfill.sweep(in: context) }` area, add a sibling:

```swift
        .task {
            ReminderScheduler.requestPermissionIfNeeded()
            ReminderScheduler.schedulePlatesDailyReminder()
        }
```

- [ ] **Step 3: Build to verify**

Run `xcodegen generate`, then `build_sim`. Expected: build succeeds. Manual (optional): in the simulator, after launch, `xcrun simctl push` is not needed — verify the pending request exists by logging, or trust the repeating-trigger code (mirrors existing `add`).

- [ ] **Step 4: Commit**

```bash
git add Glutt/Services/ReminderScheduler.swift Glutt/App/RootView.swift
git commit -m "feat(plates): schedule the daily 07:00 Today's Plate notification"
```

---

## Task 16: Hook gamification counters + full verification

**Files:**
- Modify: `Glutt/Features/Plates/RecipeFeedView.swift`

**Interfaces:**
- Consumes: `PlatesStreak` (Task 12).

- [ ] **Step 1: Record streak + counters when the feed opens/loads**

In `RecipeFeedView.load()`, after the `await model.loadDaily(...)` call, add:

```swift
        PlatesStreak.recordOpen()
        PlatesStreak.addDiscovered(model.recipes.count)
```

And in `commitSwipe(_:save:)` and `actionBar`'s save action, after a successful save the ViewModel already tracks `savedIDs`; record the lifetime counter once per save by adding to the `onSave` closure in `cardPage`:

```swift
            onSave: { Task { await model.save(card, into: context); PlatesStreak.addSaved(1) } },
```

(Adjust the existing `onSave` closure to this.)

- [ ] **Step 2: Regenerate, build, and run the full suite**

Run:
- `xcodegen generate`
- `build_sim` (scheme `Glutt`) — expect success.
- `test_sim` (scheme `Glutt`) — expect ALL tests green: `RecipeFactoryMacroTests`, `MacroBreakdownTests`, `PlateCardDecodeTests`, `PlatesServiceTests`, `PlatesSaverTests`, `PlatesDeckFilterTests`, `PlatesFeedViewModelTests`, `PlatesSeedDeckTests`, `PlatesStreakTests`, plus all pre-existing tests.

- [ ] **Step 3: Simulator UI verification**

Boot a sim, `build_run_sim`. Then:
- On Today, confirm the "Today's Plate is ready" card appears after the quick actions.
- Tap it → the feed presents full-screen (no tab bar, no floating + button).
- Confirm a card shows the hero photo, title, stat strip; tap "Recipe" → it flips to the macro bar + ingredients + steps.
- Swipe right (save) / left (skip); confirm auto-advance and the SAVE/SKIP stamp.
- Reach the end → DeckEndCardView; tap Done → dismisses.
- Open a saved recipe in My Recipes → confirm `MacroStrip` shows and the hero image is cached (no flash).
- `xcrun simctl openurl booted glutt://plates` → feed presents over Today.

Capture a screenshot of the front and the flipped back via XcodeBuildMCP `screenshot`.

- [ ] **Step 4: Commit**

```bash
git add Glutt/Features/Plates/RecipeFeedView.swift
git commit -m "feat(plates): record streak + discovery/save counters"
```

---

## Execution order note

`RecipeFeedView` (Task 11) depends on `DeckEndCardView` (Task 12), and `PlatesLauncherCard`'s call site (Task 13) depends on `Router.pendingPresentPlates` (Task 14). When executing strictly task-by-task, use this order: **1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 12 → 10 → 11 → 14 → 13 → 15 → 16.** Each still ends with its own green test/build + commit.

## Self-review notes

- **Spec coverage:** macro chokepoint (T1), MacroStrip incl. detail screen (T2–T3), backend deck+search+health (T4), PlateCard contract (T5), service (T6), mapper+saver+eager backfill (T7), diet hard-filter + seed (T8), ViewModel + cache + seed fallback (T9), flip card (T10), pager+gestures+reduce-motion+buttons (T11), end card+streak (T12), launcher (T13), routing+deep link+notification presentation (T14–T15), counters + verification (T16). Deferred items (AI tail, personalized ranking, themed decks, carb/fat estimation, auto-collection) are intentionally absent per spec §1/§2.
- **Difficulty mapping:** the saved Recipe defaults to `.beginner` (the draft/factory chokepoint isn't widened for difficulty in v1); the feed front still shows the card's own difficulty. Accepted v1 simplification.
- **"Cookable now" / diet filter** reuse `PantryMatcher.owns` + `DietGuard.isAllowed` on canonicalized ingredient *names* (no transient Recipe construction).
- **EmptyStateView / nutritionLine** call sites must be matched to their real signatures during execution (noted inline).
