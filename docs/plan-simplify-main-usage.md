# Plan — Simplify the main app usage (2026-07-14)

> **Status: ✅ IMPLEMENTED (2026-07-14).** All 9 phases done; app builds clean and the
> full test suite passes (290 tests, 0 failing). Verified in the simulator: 3-tab nav,
> Discover `Deck│Videos` toggle, Kitchen Tools checklist.
>
> **Deviations / scoping decisions made during build:**
> - **Discover › Videos** shows *suggested* clips (by taste tags); an in-tab video search
>   field was deferred (fast-follow). The deck keeps its position when you switch modes.
> - **"Missing gear" badge** ships on **recipe detail + Polly awareness**. Deck/Discover
>   *card* badges were deferred — the server feed's cards lack full step text for reliable
>   tool detection. Detection is keyword-based (`KitchenToolCatalog.requiredTools`).
> - **SwiftData migration:** left as-is (no auto-wipe) to avoid ever nuking a user's saved
>   recipes on an unrelated error. Existing dev/beta installs with old-schema stores need a
>   reinstall once; fresh installs are unaffected. (Considered a delete-and-retry fallback,
>   decided against it for recipe safety.)
> - **Onboarding:** only real dead reference found + fixed (FourWeeksScreen card 2, which
>   pitched "your plan"). The onboarding intro/features **videos** (`glutt-features.mp4`
>   etc.) may still show old UI — that's for the later frontend redesign.
> - **Tests:** deleted dead test classes (WeekPlanner/ProgressStats/TodayPlanner/Leftover);
>   aligned stale `OnboardingFlowModelTests` to your in-flight 10-screen flow; updated the
>   nav test to 3 tabs; added `KitchenToolCatalogTests`.

Goal: strip Glutt down to only the features that matter, before the later
frontend redesign. Fewer tabs, no floating capture button, one unified Discover,
a leaner Polly, and a Kitchen that finally tracks **tools** as well as ingredients.

> Supersedes the navigation contract in `docs/structure.md` and `docs/product.md`
> (six tabs, Today-as-home, central floating +). Those describe the pre-simplification app.

This pass is **feature pruning + the new Tools build**. The full visual redesign
(and full onboarding redesign) come later and are **out of scope** here.

---

## Locked decisions

1. **Bottom nav → 3 tabs:** `Recipes · Discover · Kitchen`. Recipes is home. No floating **+**.
2. **Discover unified:** the Discover tab gets a `Deck │ Videos` toggle — the photo swipe-deck (Plates) + the relocated YouTube video feed. Recipes loses its embedded Discover segment → Recipes is purely "My Recipes."
3. **"Invent a dish" cut** entirely (Assistant / WhatToCook + its paywall hook).
4. **Floating + button removed;** its 5 actions redistributed:
   - Import recipe → **Recipes** header button (share-extension import untouched)
   - Scan pantry → **Kitchen** header button
   - Log food → **removed** (intake tracking)
   - Add grocery item → **Groceries** segment
   - Invent a dish → **removed**
5. **Kitchen → `Ingredients · Tools · Groceries`.** Leftovers segment removed (+ its AI "remix").
6. **Tools (new build):** preset equipment checklist + custom entries, **AI-connected** — Polly reads your gear mid-cook; Discover/recipes show a soft "needs an air fryer" **badge** (not a hard filter that hides recipes).
7. **Polly controls trimmed:** control row 6 → 2 (**Mic · Camera on/off**). Top-left **✕** ends the session (the duplicate red End is removed). **Start timer** stays contextual. The copy-debug-log button moves **behind a long-press** (kept, not deleted — it's the triage tool).
8. **Cooking:** one **Cook with Polly** CTA on recipe detail. Classic Cook Mode survives as the auto-fallback (mic denied / AI down) + a small "cook without Polly" link.
9. **Macros:** per-dish only, as recipe info on recipe detail + Discover cards. No daily totals, no logging, no goals.
10. **Settings:** gear in the **Recipes** header (it was orphaned by the Progress removal).

### Also locked (housekeeping)
- **Full delete** of removed features' code **and** their SwiftData models. Old meal-plan / eaten-log / leftover data is discarded.
- Polly's exit dialog **"Finish & log" → "Finish"** (no more intake logging). Same for Cook Mode's finish.
- **Keep** the Discover browsing **streak** and **Recipe Collections**.
- Clean up dead deep links / launch args (`glutt://today|plan|progress`, `-demoWizard`, `-ask`). Keep `-demoCook`.
- **Onboarding:** *light cleanup only* — strip screens/copy that pitch removed features (Today / Progress / Plan / tracking / Invent-a-dish). Full onboarding redesign deferred.

---

## Target app

**Bottom nav — 3 tabs, no floating +**

| Tab | Holds | Header actions |
|---|---|---|
| **Recipes** (home) | Saved library — search, filters, Collections | **Import** · **Settings ⚙** |
| **Discover** | `Deck │ Videos` toggle — swipe-deck + relocated video feed | — |
| **Kitchen** | `Ingredients │ Tools │ Groceries` | **Scan pantry** |

**Polly session:** top-left **✕** · `● step / Start timer` · row = **🎙 Mic** + **📷 Camera**. Long-press = debug log.

---

## Build order (checklist)

### Phase 1 — Nav skeleton
- [ ] `AppTab` (`Glutt/App/Router.swift`) → `recipes, discover, kitchen`; default `selectedTab = .recipes`
- [ ] `RootView.tabContent` (`Glutt/App/RootView.swift`) → 3 cases; remove `captureButton` + `isCaptureSheetPresented` / `CaptureActionSheet` presentation
- [ ] `GluttTabBar` glyphs (`Glutt/DesignSystem/Components/GluttTabBar.swift`) → 3 tabs
- [ ] Router deep links + launch args: drop `today/plan/progress/plates`, `-demoWizard`, `-ask`, `askWhatToCook`; keep `recipes/discover/kitchen/import/recipe`, `-demoCook`, `-tab`, `-importURL`
- [ ] Delete `CaptureAction` enum + `Router.perform(_:)` + `Glutt/Features/Capture/`

### Phase 2 — Delete removed features + data models
- [ ] Delete views: `Features/Today/`, `Features/Progress/`, `Features/Plan/`, `Features/Assistant/`, `Features/Log/`, `Features/Polly/PollyTabView.swift` (orphaned)
- [ ] Delete leftover code: `Features/Kitchen/LeftoversView.swift`, `Features/Kitchen/LeftoverRemixSheet.swift`, `Services/AI/LeftoverRemix.swift`
- [ ] Delete/verify SwiftData models: meal-plan, eaten-food log, `Leftover` (`Models/Kitchen.swift`), progress/macro-tracking models. Sweep `Glutt/Models/`.
- [ ] Update the `ModelContainer` schema list in `Glutt/App/GluttApp.swift` (lines ~55–84) to drop deleted `@Model` types
- [ ] Confirm `Services/Polly/CookPlanCompiler.swift` is **Polly-internal** (recipe → cook steps), NOT the Plan tab — keep it

### Phase 3 — Discover unification
- [ ] Discover tab view = `Deck │ Videos` toggle; Deck = existing `PlatesTabView` content, Videos = `Features/Discover/DiscoverView.swift`
- [ ] Remove the `My Recipes | Discover` segment from `Features/Recipes/RecipesView.swift` (~L119–129) and the "Find it in Discover" handoff (~L269–281)
- [ ] Re-point `glutt://plates` and `glutt://discover` at the Discover tab

### Phase 4 — Kitchen + Tools
- [ ] `KitchenView` segments → `Ingredients · Tools · Groceries` (drop Leftovers)
- [ ] Move "Scan pantry" to Kitchen header; "Add grocery item" into Groceries
- [ ] New `KitchenTool` `@Model` (name, category, `isOwned`, custom flag) in `Glutt/Models/`
- [ ] New Tools segment view: preset checklist (oven, stovetop, air fryer, microwave, blender, cast iron, slow cooker, stand mixer, …) + custom add
- [ ] Register `KitchenTool` in the `ModelContainer`

### Phase 5 — Tools AI wiring
- [ ] Polly reads the owned-tools list as session context (hook: the existing `equipment` memory category in `Models/Polly.swift`)
- [ ] Recipes/Discover cards show a soft **"needs <tool>"** badge when a recipe requires gear not owned (badge, not a filter). Requires recipe→required-tools data; derive/AI-tag as needed.

### Phase 6 — Polly controls
- [ ] `PollySessionView` control row → **Mic + Camera** only; remove Show-Polly, eye-watch, flip, duplicate red End
- [ ] Move copy-debug-log from a visible top-bar button to a **long-press** gesture
- [ ] Exit dialog **"Finish & log" → "Finish"**; stop writing an eaten-food log (also in Cook's `CookFinishView`)

### Phase 7 — Recipes header + cook CTA
- [ ] Recipes header = **Import** + **Settings ⚙**
- [ ] Recipe detail → single **Cook with Polly** CTA; classic Cook Mode = auto-fallback + small "cook without Polly" link

### Phase 8 — Onboarding light cleanup
- [ ] Remove/soften onboarding screens + copy referencing removed features (tracking, progress, planning, Invent-a-dish). No redesign.

### Phase 9 — Build + verify
- [ ] `xcodegen generate` if `project.yml` changes; build via XcodeBuildMCP
- [ ] Verify in simulator: 3 tabs, no +, Discover toggle, Kitchen Tools, lean Polly, single cook CTA, Settings reachable

---

## Dependencies / gotchas
- **Settings** currently launches from `ProgressTabView` → must be re-homed (Recipes gear) *before/at* Progress deletion or it's unreachable.
- **`CookPlanCompiler`** (Polly's step compiler) is easy to confuse with the Plan tab — it stays.
- **Polly equipment memory** (`Models/Polly.swift` `case equipment`) already exists as the natural hook for the new Tools list.
- **"Missing gear" badge** needs a recipe→required-tools signal that may not exist yet — scope it as part of Phase 5 (derive from ingredients/instructions or AI-tag on import).
- SwiftData model deletions change the schema — this is a **destructive migration** for any existing tracking/plan/leftover data (acceptable: those features are going).

## Out of scope (later)
- Full visual redesign of the app.
- Full onboarding redesign (only dead-reference cleanup now).
- Blending video into the swipe-deck (we chose the `Deck │ Videos` toggle, not a merged deck).
