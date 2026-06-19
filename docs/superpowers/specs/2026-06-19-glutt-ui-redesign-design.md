# Glutt UI Redesign — Design Spec (Phase 1)

**Date:** 2026-06-19
**Branch:** `redesign`
**Source:** `design_handoff_glutt_redesign/` (README + `Glutt Redesign.dc.html` + photo assets)

## Overview

Adopt the handoff package as Glutt's **new design language** and apply it across the
whole app in phases. The handoff recolors a reference recipe app's shape language
(rounded cards, highlighted-word headline, food-photo tiles, pill stats, numbered
steps, grocery-style checklist) into Glutt's existing warm palette and Phosphor
icons. **Phase 1** (this spec) establishes the shared foundation and redesigns the
first-run + core recipe loop. Later phases reuse the foundation for the remaining
screens.

This is a **visual + structural restyle**, not a rewrite. We extend the existing
`Theme`, `Typography`, and `DesignSystem/Components/` rather than introducing a
parallel styling system, and we preserve all existing functionality (reorganized
where the new layout requires).

## Goals

- A cohesive, intentional new look driven by the handoff, on Glutt's warm palette.
- Phosphor icons (`PhosphorSwift`) as the app's icon set.
- Reusable design-system primitives so later phases are cheap restyles, not rebuilds.
- Zero feature loss: everything the current screens do still works after the restyle.

## Non-Goals (Phase 1)

- No monetization/paywall changes (the `redesign` branch keeps the free-launch state).
- No redesign yet of: Today, Plan, Kitchen sub-views (Inventory/Groceries/Leftovers/
  Store), Settings, Progress, Cook Mode, Import flow, What-to-Cook assistant. These
  get their own later specs that reuse this foundation.
- No bundled Nunito font (we use SF Rounded; revisit only if pixel-exact is wanted).

## Confirmed Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Redesign breadth | **Full app, phased.** Phase 1 = foundation + onboarding + browse + recipe detail. |
| 2 | Recipe Detail features | **Keep all, reorganize** into the new shell (overflow `⋯` / below-fold for extras). |
| 3 | Tab bar | **5 tabs kept** in the dark bar (Today/Recipes/Plan/Kitchen/Progress); **floating + stays** above it. |
| 4 | Onboarding | **Restyle the whole flow now** (Welcome → Goals → Rules → Nutrition → Notifications → Tutorial). |
| 5 | Browse categories | **Tag-driven** circular row (top tags + representative photos, reusing existing filter state). |
| 6 | Font | **SF Rounded** via existing `Font.glutt*` (no Nunito bundling). |
| 7 | Icons | **Add `PhosphorSwift` via SPM**, use `Ph.*`. SF Symbols remain as fallback only. |
| 8 | Favorite | **Add `isFavorite: Bool` to `Recipe`** for the detail heart. |

## Architecture

SwiftUI, SwiftData models, stock `NavigationStack`. The redesign touches the
presentation layer only. Two model-adjacent changes:
- `Recipe.isFavorite: Bool = false` (new SwiftData property; additive, no migration risk).
- Browse list/grid mode is view `@State`, not persisted (Phase 1).

### Dependency

Add Swift Package `https://github.com/phosphor-icons/swift` (product `PhosphorSwift`)
to the Xcode project. Icons used via `Ph.<name>.<weight>` (e.g.
`Ph.forkKnife.fill`, `Ph.clock.regular`). A thin wrapper is **not** required, but we
add a small `Glyph` helper only if call sites get noisy.

## Design Tokens (extend `Theme.swift`)

Keep all existing color constants as-is (README: match Glutt's tokens, not the mock's
slightly-brighter hexes). **Add:**

```
Radius.cardLarge: 26      // redesigned recipe/detail/section cards
Radius.photo:     18      // photo tiles inside cards
Colors.tomatoTint:  #F7DDD2   // difficulty pills, protein icon chips
Colors.sagePanel:   = successTint   // decorative card panel + produce chips (alias for clarity)
Colors.peachPanel:  #F7E2D4   // decorative card panel tint (rotating set)
```

`Colors.successTint` (sage), `Colors.warningTint` (amber), `Colors.warning` (amber
text) already exist and are reused for green/amber pills and chips.

**Typography additions** (in `Typography.swift`):
- `gluttSectionLabel` — 12pt, heavy, uppercase, +tracking, herb-green (FRESH/PANTRY,
  category labels).
- Reuse `gluttLargeTitle` (screen/detail titles), `gluttTitle` (card titles),
  `gluttBody`, `gluttCaption`. Heavier weights applied inline where the mock calls for
  900 (`.weight(.heavy)`).

## New / Updated Components (`DesignSystem/Components/`)

Each is small, single-purpose, independently previewable:

- **`StatPill`** — icon + text on a tinted capsule; tint variants green/amber/tomato.
  Powers rating (`star`/successTint), time (`clock`/warningTint), difficulty
  (`cell-signal-*`/tomatoTint). Radius 11, padding 7×12.
- **`IconChip`** — 36pt rounded-square (radius 11), section-tinted, Phosphor food glyph.
  Used in the Ingredients checklist (protein/produce/pantry tints).
- **`CategoryCircle`** — circular recipe-photo thumbnail + label; active state
  (66pt, 3px green ring, `sparkle` accent) vs inactive (50pt, 0.78 opacity).
- **`SegmentedTabs`** — two-segment control (Ingredients | Steps); track `#EBE2D4`,
  radius 14, active = green fill + cream text. Generic over a 2-case enum.
- **`PageDots`** — active = 24×8 herb-green bar, inactive = 8×8 `#D8CDBE` dots.
- **`HighlightHeadline`** — renders a headline as per-word tinted pills (green/amber/
  tomato/plain), 900 weight, pill radius 16. Used by onboarding.
- **`GluttTabBar`** — custom dark (`textPrimary`) full-width bar, rounded top (radius
  30), home-indicator padding; 5 Phosphor tabs; active = cream label + light-green
  glyph, inactive `#928377`. Backs the existing `Router.selectedTab` (no nav fork).

**Restyled existing components:**
- **`RecipeCard`** — warm-white card radius 26, padding 12; media block height 148,
  radius 18, panel-tint background (rotating sage/peach), photo positioned left at 63%
  width; tag pill top-right (Classic/`fork-knife`, Popular/`flame`); below: title
  (21/900), description, **StatPill row** (rating/time/difficulty). Keeps the optional
  `pantryMatch` slot (restyled as a StatPill or hidden when categories supply context).
- **`Chip` / `ChipRow`** — restyled to the new pill spec (used by filter/sort).
- **`Buttons`** — add a fully-rounded primary CTA variant (radius 30, flat, no glow)
  for onboarding "next", and the wide grocery button variant (radius 18).

## Screens (Phase 1)

### A. Tab bar (`App/RootView.swift`)
Replace the stock `TabView` chrome with `GluttTabBar` driven by `Router.selectedTab`.
5 tabs with Phosphor glyphs: Today `house`, Recipes `book-open` (fill when active),
Plan `calendar-blank`, Kitchen `cooking-pot`, Progress `chart-line-up`. The floating
**+** stays, repositioned to sit clear above the dark bar; existing
`floatingButtonSuppressors` behavior unchanged. Navigation, deep links, and capture
sheet are untouched — visual swap only.

### B. Onboarding (whole flow)
- **WelcomeScreen** — sage hero panel (radius 34) with a rotated white photo card,
  scattered decorative Phosphor accents, floating "Ready in 25 min" clock pill;
  `HighlightHeadline` ("Cook smarter not harder"); subtitle; footer with `PageDots`
  + green "next" CTA (`arrow-right`). CTA advances the existing flow.
- **Goals / Rules / Nutrition / Notifications / Tutorial** — restyle to the new
  language via `OnboardingScaffold`/`OnboardingFlow`: cream bg, pill/tinted section
  headers, `PageDots` progress (replacing the current capsule progress bar), green
  CTA. Underlying step logic, state, and the paywall hook at finish are unchanged.

### C. Browse (`Features/Recipes/RecipesView.swift` + `RecipeCard`)
- **Category row** — `CategoryCircle`s driven by the user's **top tags** (most
  frequent), each showing a representative recipe photo; tapping sets the existing
  `selectedFilter`. Graceful fallback when few/no tags (row hides or shows "All").
- **Count header** — "N recipes" (`gluttLargeTitle`) left; right = grid-toggle button
  (`squares-four`) + filter pill (`sliders-horizontal` + active-count) opening the
  existing sort/filter menu.
- **Grid toggle** — new `@State` list/grid mode; grid uses a 2-column
  `LazyVGrid` of restyled `RecipeCard`s. Search + collections row retained, restyled.

### D. Recipe Detail (`Features/Recipes/RecipeDetailView.swift`)
Treat the handoff's "Recipe detail" and "Ingredients" screens as **two tabs of one
view**.
- **Hero** — full-bleed photo (height ~352) with top scrim; translucent-white circle
  back (`caret-left`) and favorite (`heart` fill/tomato, toggles `Recipe.isFavorite`).
- **Content sheet** — overlaps hero bottom, radius 30 top, cream. Title
  ("Korean Beef Bowl, 520 Kcal" style — title + kcal inline), description.
- **`SegmentedTabs` (Ingredients | Steps):**
  - **Steps** — numbered 28pt green circles + step text; reuses `sortedSteps` and the
    existing timer-detection label.
  - **Ingredients** — grocery-style sectioned checklist: `gluttSectionLabel` sections
    (FRESH vs PANTRY). `RecipeIngredient` has no fresh/pantry field, so sectioning is
    **derived**: classify each ingredient's `canonicalName` into a category using the
    same canonical→`GroceryCategory` mapping groceries already use (produce/meat/dairy
    → FRESH; pantry/spices/frozen/other → PANTRY), defaulting to PANTRY when unknown.
    The same classification drives the `IconChip` glyph + tint (protein=tomato,
    produce=green, pantry=amber). Row = `IconChip` + name/qty + checkbox. **Checked =
    "in your kitchen"** (struck-through, "· in your kitchen"), seeded from
    `PantryMatcher`. **Servings stepper** scales displayed
    quantities (reuses existing `displayServings`/scale). Footer green button: `basket`
    + "Add N missing to groceries" (N = unchecked rows) → existing groceries flow.
- **Kept features, reorganized:**
  - **Cook Mode** stays the primary floating action (unchanged logic + PreCookChecklist).
  - Top-right **`⋯` overflow menu** + below-fold sections host: AI "Make it…" adjust,
    Add to plan, diet/allergy warnings, recipe versions, unit system, nutrition
    estimate, notes, star rating, cook history. Nothing removed — relocated.
  - Nutrition stays available (via overflow / below-fold), though it is **not** shown
    inline in the hero/tabs (mock removed the inline macro table).

## Data Flow

- **Pantry → Ingredients tab:** `PantryMatcher.match(recipe)` seeds each row's
  `haveIt`. Toggling a row updates strikethrough and the footer "missing" count
  (derived, not persisted). The footer button writes unchecked items to `GroceryItem`s
  via the existing groceries path.
- **Servings stepper:** drives `scale`, recomputing displayed quantities (existing
  logic in `RecipeDetailView`).
- **Favorite:** heart writes `Recipe.isFavorite` (SwiftData), reflected by fill state.
- **Categories:** derived at render time from the library's tag frequencies; tap sets
  `selectedFilter` (existing). No persistence.

## Testing

- **Build/compile:** project builds with the new SPM dependency on a clean checkout.
- **Snapshot/visual:** SwiftUI `#Preview`s for each new component (StatPill, IconChip,
  CategoryCircle, SegmentedTabs, PageDots, HighlightHeadline, GluttTabBar) in both
  states; restyled RecipeCard and the detail tabs.
- **Behavioral (manual + existing patterns):**
  - Ingredients checkbox toggles update missing-count and footer button.
  - "Add N to groceries" creates the expected `GroceryItem`s.
  - Favorite heart persists across relaunch.
  - Category tap filters the list; grid/list toggle preserves selection.
  - Onboarding still advances through all 6 steps and reaches the finish/paywall hook.
- **No-regression:** Cook Mode, versions, plan-add, diet warnings, notes, rating, and
  history remain reachable and functional from their new locations.

## Risks & Mitigations

- **Detail screen crowding** (keeping all features under a new minimal shell): mitigate
  with the `⋯` overflow + progressive disclosure; verify every relocated feature is
  reachable in ≤1 extra tap.
- **Tag-driven categories with sparse libraries:** fallback to hide the row or show a
  single "All"; never show an empty/broken row.
- **5 tabs in a bar styled for 4:** tighten spacing; verify labels (11pt) don't clip on
  small devices; floating + must clear the bar without overlapping tabs.
- **Phosphor weights/names:** confirm each `Ph.*` name/weight exists at integration;
  SF Symbol fallback table in the README covers any gap.

## Phase Plan

- **Phase 1 (this spec):** Foundation (tokens, Phosphor, shared components, tab bar) →
  Browse + Recipe Detail (core recipe loop) → Onboarding flow. Implement in that order
  so screens build on finished primitives.
- **Phase 2+ (separate specs):** Today, Plan, Kitchen sub-views, Settings, Progress,
  Cook Mode, Import flow, What-to-Cook assistant — each a restyle reusing this
  foundation.
