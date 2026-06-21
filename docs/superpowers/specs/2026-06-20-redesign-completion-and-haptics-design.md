# Design: Finish the Glutt redesign + complete haptics

**Date:** 2026-06-20
**Status:** Approved (design); pending spec review
**Source of visual truth:** `design_handoff_glutt_redesign/README.md` (+ `Glutt Redesign.dc.html`)

## Context

A visual redesign of Glutt's nine core screens is **~75% complete**. This spec covers finishing the remaining seven screens and making haptic feedback complete and consistent across the app.

### Already done (do not redo)
- **Design-system foundation:** `StatPill`, `IconChip`, `SegmentedTabs`, `CategoryCircle`, `HighlightHeadline`, `PageDots`, the dark `GluttTabBar`.
- **`Theme` tokens are complete** — every redesign token already exists (`Radius.cardLarge` 26, `Radius.photo` 18, `Radius.pill` 11, `Radius.segment` 14, `Radius.tabBarTop` 30, `Radius.tag` 13; colors `tomatoTint`, `peachPanel`, `sagePanel`, `creamText`, `segmentTrack`, `dotInactive`, `mutedLabel`, `tabInactive`, `activeTabGlyph`). **No token work required.**
- **Browse + `RecipeCard`** — fully restyled.
- **Recipe detail — Steps tab** — done.
- **Onboarding** — ~90% (one polish item remains).
- **`Haptics` enum** — `selection()` / `impact(_:)` / `notify(_:)`; centralized in 5 shared components (`SegmentedTabs`, `Chip`/`ChipRow`, `GluttTabBar`, `CategoryCircle`, `OptionRow`); outcome buzzes exist for grocery/timer/cook-finish.

### Decisions (locked)
1. **Scope:** finish everything — all 7 remaining screens + complete haptics.
2. **Haptic depth:** complete + signature cooking moments.
3. **Fidelity:** match the handoff visuals; preserve current behavior where it's a genuine improvement.
4. **Verification:** I verify build + visuals on the iOS Simulator; the user feels haptics on a physical device (UIKit feedback generators are no-ops on the Simulator).

### Non-goals
- No new `Theme` tokens (already complete).
- No state / `@Query` / navigation / routing changes — this is a restyle. Preserve every binding, `@Query`, sheet/`fullScreenCover`, router action, and helper (`TodayPlanner`, `PantryMatcher`, `MealRecommender`, `TimerManager`, etc.).
- No re-work of already-done screens (Browse, RecipeCard, Steps tab, tab bar).
- Do not bundle Nunito; keep SF Rounded via `Font.glutt*`.
- The macros/nutrition table stays removed on Recipe detail (intentional, per handoff).

---

## Part A — Haptics architecture

Goal: coverage becomes complete and consistent by **centralizing**, not by sprinkling more call-site calls. Keep the `Haptics` enum and its taxonomy.

### A1. Centralize impact in the button styles
Fire the haptic inside the four `ButtonStyle`s in `Glutt/DesignSystem/Components/Buttons.swift` via `.onChange(of: configuration.isPressed)` (fire when it transitions to `true`):
- `PrimaryButtonStyle`, `FilledPillButtonStyle` → `Haptics.impact(.medium)`
- `SecondaryButtonStyle`, `PillButtonStyle` → `Haptics.impact(.light)`

Implementation note: a `ButtonStyle` body can't hold `@State`; use a tiny private wrapper view (`@State private var wasPressed`) inside `makeBody` to detect the false→true edge and call the haptic once per press.

**Then audit and remove redundant call-site `Haptics.impact(...)`** on any button already using these styles, so nothing double-buzzes. **Keep** call-site `Haptics.notify(...)` (outcomes are semantically separate) and keep call-site impacts only on controls that are *not* one of these four styles.

Rejected alternatives: (B) add missing call-site calls only — stays inconsistent, every future button must remember; (C) migrate to iOS 17 `.sensoryFeedback` and retire the enum — needless churn vs. the established pattern.

### A2. Wrapper components for system controls (can't fire haptics natively)
- **`GluttStepper`** (new, in `Glutt/DesignSystem/Components/`): minus / value / plus row; `Haptics.selection()` per tick; styled as the handoff's pill stepper (does double duty as a visual fix). Replace the system `Stepper` in: Ingredients servings control (Recipe detail), `ImportReviewView`, `CookFinishView`.
- **`.gluttHapticToggle()`** view modifier (or `GluttToggle` wrapper): fire `Haptics.selection()` on value change. Apply to: Inventory "assumed staples" toggle, Settings toggles, Plan toggles.

### A3. Fill scattered gaps (one-liners)
- `RecipesView` — recipe-card tap → `selection()`; grid/list toggle → `selection()`; filter/sort menu → `selection()` / `impact(.light)`.
- `CookModeView` — active-timer dismiss (✕) → `impact(.light)`.
- `RecipeDetailView` — overflow (…) menu → `impact(.light)`.
- Kitchen/Inventory — search-field clear → `impact(.light)`.

### A4. Signature cooking moments
- **Ingredient check-off** (Ingredients tab): `impact(.light)` on check; `selection()` on uncheck.
- **"Add N missing to groceries"**: `notify(.success)`.
- **Cook Mode "Finish cooking"**: short celebratory sequence — `impact(.medium)` then `notify(.success)`.
- **Timer hits zero** — already notifies; keep.

### A5. Taxonomy comment
Add a short guideline block to `Haptics.swift`:
- `selection` → navigation / value change (tabs, segments, pickers, steppers, card taps)
- `impact(.light)` → secondary taps, toggles, dismissals
- `impact(.medium)` → primary commit (CTAs)
- `notify(.success/.warning/.error)` → outcomes

---

## Part B — Screen restyles

Each touches only its own feature file. Match the handoff section for the screen; use `Theme` tokens and `Font.glutt*`; preserve all existing state/logic. Build + screenshot-verify each against the handoff before moving on.

### B1. Today — `Features/Today/TodayView.swift` (M)
- Quick-action items → 46px `successTint` circles with herb-green glyph.
- Nutrition gauges card → `Radius.cardLarge` (26) to match the next-up hero scale.
- Next-up hero meta row → `StatPill`s (time / start-by / total) instead of plain text.
- Smart-card tints: "Use these soon" peach/tomato; "Leftovers waiting" sage/green.
- Keep `TodayPlanner`, getting-started, leftovers logic, all `@Query`s, sheets, and the missing-ingredients warning strip.

### B2. Plan — `Features/Plan/PlanView.swift` (S)
- Week-summary card → `Radius` 24; meal rows → compact `Radius` 17.
- Today's date pill → filled herb-green + white (not `accent.opacity`).
- "Generate grocery list from plan" → outlined herb-green (radius 13).
- Keep `weekDays`, `weekMeals`, `pantryCoverage`, prep-task detection, wizard, grocery generation.

### B3. Kitchen + Inventory — `Features/Kitchen/KitchenView.swift`, `InventoryView.swift` (M)
- Header buttons → 38px outlined circle (camera) + 38px filled herb-green circle (plus/add).
- Inventory rows → section-tinted 36px `IconChip` before the name (produce→green, protein→tomato, dairy→amber per `IngredientCategoryStyle`).
- **Use-soon: render inline** — a "Use soon" badge (peach bg / tomato text, radius 9) on the right of the row for `useSoonDate` items. **Keep the existing use-soon detection logic;** only change where/how it's surfaced (the current separate section may be folded into inline badges — preserve the underlying matching).
- Section labels → UPPERCASE, herb-green, letter-spacing ~0.12em.
- 1px hairline dividers between rows.

### B4. Recipe detail — Ingredients tab — `Features/Recipes/RecipeDetailView.swift` (M)
- Recipe context card (warm-white, radius 20): 50px thumbnail + title (16/900) + "N ingredients" (13/700) + **`GluttStepper`** servings pill on the right.
- Section labels UPPERCASE FRESH / PANTRY (herb-green, letter-spaced).
- Footer: cream gradient fade → full-width herb-green button (radius 18) with basket icon + "Add N missing to groceries" (N = unchecked count).
- Wire A4 ingredient check-off + add-to-groceries haptics here.
- Treat Ingredients/Steps as two tabs of the same detail view (no new navigation). Keep `PantryMatcher` seeding, servings scaling, derived missing count.

### B5. What to Cook — `Features/Assistant/WhatToCookView.swift` (M)
- Recommendation card: right-aligned status — `check-circle` "Ready now" (accent) or "N items missing" (warning).
- Reason chips → accent/amber tinted pills (by reason type).
- "Just tell me" card input → inset cream pill (`#F4ECDD`) with `paper-plane-tilt` send.
- Keep ask/invent/recommend logic, chips, `MealRecommender` results; presented as a sheet.

### B6. Cook Mode — `Features/Cook/CookModeView.swift` (S)
- Top bar → 40px outlined circles (✕ left, ingredients/list right, accent).
- "FOR THIS STEP" label → 12/800 uppercase, herb-green.
- Icon weights per handoff (close bold, etc.).
- Wire A4 finish-cooking signature haptic + A3 timer-dismiss haptic.
- Keep `TabView` paging, `TimerManager`, idle-timer, per-step ingredient heuristic, finish flow.

### B7. Onboarding — `Features/Onboarding/Screens/WelcomeScreen.swift` (S)
- Hero card → static −3° rotation (replace the animated oscillation).

---

## Part C — Execution & verification

### Sequencing
1. **Foundation (serial — shared files):** Part A (A1 button centralization + call-site dedupe, A2 `GluttStepper` + toggle modifier, A5 taxonomy). Build to confirm green.
2. **Screens (parallel — independent feature files):** B1–B7, each embedding its own signature haptics from A3/A4. Fan out one agent per screen.
3. **Verify pass:** XcodeBuildMCP build + simulator screenshot per screen, compared to the handoff frame. User feels haptics on a device.

### Build/verify tooling
- Use XcodeBuildMCP (`session_show_defaults` first, then `build_run_sim`, `screenshot`) per CLAUDE.md. Scheme `Glutt`. Tests via `test_sim` if touched.

### Risks & care-points
- **Double-buzz** after A1 — the dedupe of call-site impacts is the critical step; grep `Haptics.impact` after centralizing and confirm each remaining one is on a non-style control.
- **Kitchen use-soon restructure** — must not break pantry-matching / `useSoonDate` logic; visual change only.
- **`RecipeDetailView` size** — Ingredients-tab refactor is layout-only; keep `PantryMatcher`/servings bindings intact.
- **Git hygiene** — `main` is the default branch; create a feature branch before committing implementation.

### Definition of done
- All 9 screens match the handoff (7 newly finished + 2 already done) under simulator screenshot review.
- Haptics: buttons buzz app-wide via styles; steppers/toggles via wrappers; all A3 gaps filled; A4 signature moments fire; no double-buzz.
- App builds clean on the simulator; existing tests pass.
