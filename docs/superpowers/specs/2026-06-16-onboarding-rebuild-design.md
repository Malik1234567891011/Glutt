# Onboarding Rebuild — Design Spec

**Date:** 2026-06-16
**Status:** Approved flow & approach; pending spec review
**Owner:** Omar

## Summary

Rebuild Glutt's first-run onboarding into a polished, conversion-style flow modeled
on the **structure and polish of the RIZZ app**, with an **interactive import tutorial
modeled on ReciMe**, rendered entirely in **Glutt's existing warm cream/green brand**
(no dark theme — the app is deliberately light-locked).

This is a UX-pattern adaptation, not a visual clone: we borrow common onboarding
*patterns* (welcome hero, progress chrome, full-width option rows, a coached import
walkthrough, a post-onboarding paywall placement) and express them in Glutt's own
design tokens and original copy.

## Goals

- Replace the single 470-line `OnboardingView.swift` with a decomposed, testable flow.
- Keep Glutt's genuinely valuable steps (goals, food rules + allergies, nutrition mode).
- Add a branded **welcome hero**, a **notification-permission primer**, and a
  **scripted import tutorial** that teaches Glutt's best feature (share-from-anywhere).
- End onboarding at a single, clearly-named **Superwall placement hook** (call site only).
- Preserve existing integration points: `UserPrefs.hasCompletedOnboarding` gating, the
  `-onboarding` force flag, the "Glutt Beta" scheme, and `Router.perform(.importRecipe)`.

## Non-goals

- **No paywall UI and no StoreKit/Superwall SDK work** — only a stub call site that
  currently completes immediately. Paywall is a later, separate task (Superwall).
- No accounts/auth (Glutt has none).
- No dark theme (app is `UIUserInterfaceStyle: Light`, by design).
- No social-proof screen and no "how did you hear about us?" survey (cut by decision).
- The tutorial performs **no real import**; only the optional end-of-tutorial hand-off
  routes into the real importer.

## Flow

Seven steps. Top chrome = progress indicator + Back; Skip remains available
(every step is skippable — the app learns from usage either way, as today).

| # | Screen | Origin | Behavior |
|---|--------|--------|----------|
| 1 | **Welcome hero** | RIZZ structure | Full-bleed cream screen, ambient `GlowBackground`, animated hero, bold original headline, one primary "Get started" CTA. No login link. |
| 2 | **Goals** | keep, ReciMe-style rows | Existing multi-select (`UserPrefs.goals`), restyled from wrapping chips to full-width emoji `OptionRow`s. |
| 3 | **Food rules + allergies** | keep | `DietaryRule` multi-select + allergies + dislikes text fields. Restyled. Allergies still get the "hard warning, always" framing. |
| 4 | **Nutrition mode** | keep | Single-select `NutritionMode` (cookingOnly / lightTracking / gymMode) as selectable cards. |
| 5 | **Notification primer** | RIZZ/ReciMe | Soft pre-prompt ("want a dinnertime nudge?") → triggers the real iOS permission dialog via `UNUserNotificationCenter`. "Not now" skips. Feeds existing `NotificationRoutingDelegate`. |
| 6 | **Import tutorial** ⭐ | ReciMe | Scripted, animated simulation (see below). Ends with "Import my first recipe" (→ real importer) or "I'll explore on my own". |
| 7 | **Finish → Superwall hook** | — | Writes `UserPrefs`, sets `hasCompletedOnboarding = true`, calls the paywall-placement stub, then completes. |

## Import tutorial (scripted simulation)

A self-contained, deterministic animation — never network-dependent, never fails
mid-demo. Phase state machine in `ImportTutorialScreen`:

```
intro → showPost → coachTapShare → shareSheetMock → importing → success → cta
```

- **showPost** — a mock social post card (generic "video recipe" styling, original art —
  not a real platform's chrome) with a visible Share affordance.
- **coachTapShare** — animated pointer / pulse on the Share button ("Tap here" coach mark).
- **shareSheetMock** — a simulated iOS share sheet (`ShareSheetMock`) with Glutt present;
  Glutt's row pulses. This is a *visual mock*, distinct from the real `ShareSheetSetupView`.
- **importing** — branded "Importing…" modal with Glutt's glyph.
- **success** — "✨ Saved to your recipes!" revealing a **pre-baked sample recipe card**
  (sourced from `StarterRecipes`, no network).
- **cta** — two buttons:
  - "Import my first recipe" → `finish()` then `router.perform(.importRecipe)`
    (reuses the existing real flow at `Router.swift:146`).
  - "I'll explore on my own" → `finish()`.

Advancement uses `withAnimation` + an async sequence (`Task` + `Task.sleep`); users can
also tap to advance. No real `RecipeImportService` call anywhere in the tutorial.

## Architecture (Approach B — decomposed)

All under `Glutt/Features/Onboarding/`, replacing the current `OnboardingView.swift`.

```
Onboarding/
  OnboardingFlow.swift          // coordinator: hosts OnboardingState, progress chrome,
                                //   bottom CTA, finish(), Superwall hook call site
  OnboardingState.swift         // plain Observable model: selections + finish-mapping.
                                //   Pure, unit-testable (no SwiftUI).
  Screens/
    WelcomeScreen.swift
    GoalsScreen.swift
    RulesScreen.swift
    NutritionScreen.swift
    NotificationPrimerScreen.swift
    ImportTutorialScreen.swift
  Support/
    OnboardingScaffold.swift    // shared title/subtitle + scroll layout (replaces stepLayout)
    ShareSheetMock.swift        // simulated share sheet for the tutorial
    OnboardingPaywallHook.swift // stub: presentPostOnboarding(completion:) → completion() now;
                                //   documented Superwall placement integration point
```

**New design-system components** (`Glutt/DesignSystem/Components/`):

- `GlowBackground.swift` — ambient radial-glow / soft animated blobs behind the welcome
  hero (and tutorial success), in Glutt's palette (green/tomato tints on cream).
- `OptionRow.swift` — full-width selectable row: leading emoji or SF Symbol, label,
  trailing check. Used by Goals (multi) and Nutrition (single). Replaces the chip grid for
  these screens. `FlowLayout`/`SelectableChips` (currently private in OnboardingView) move
  to a shared file if still needed elsewhere, otherwise are retired with the old file.

**Reused as-is:** `Theme` tokens, `Typography` (`.gluttLargeTitle` etc.), button styles
(`.gluttPrimary`, `.gluttPill`), `UserPrefs`, `StarterRecipes`, `Router`, `ShareSheetSetupView`.

## Data flow & integration

- **State:** `OnboardingFlow` owns an `OnboardingState` (Observable): `selectedGoals`,
  `selectedRules`, `allergyText`, `dislikeText`, `nutritionMode`, plus current `step`.
- **Finish:** `OnboardingState.apply(to:)` maps state → `UserPrefs.current(in: context)`
  exactly as the current `finish()` does (goals, dietaryRules, allergies, dislikes,
  nutritionMode, `hasCompletedOnboarding = true`). Keeping this in `OnboardingState`
  makes it unit-testable without the view.
- **Gating:** unchanged — `RootView` shows onboarding while `!hasCompletedOnboarding`;
  `-onboarding` launch flag (`Router.forceOnboarding`) and the "Glutt Beta" scheme still
  replay it from zero.
- **Paywall placement:** `OnboardingFlow.finish()` → `OnboardingPaywallHook.presentPostOnboarding { onFinish() }`.
  Stub calls the closure immediately today. Later: register a Superwall placement
  (e.g. `Superwall.shared.register(placement: "onboarding_complete")`) at this one site.
- **Notifications:** primer calls `UNUserNotificationCenter.current().requestAuthorization`;
  result is not gated on — either choice advances. Routing already exists.

## Error handling

- Tutorial is deterministic → no error states inside it.
- Notification primer: if the user has already granted/denied at the OS level, the iOS
  call is a no-op; the screen advances regardless. No custom error UI.
- The optional real-import hand-off uses the existing `ImportRecipeView` Phase machine,
  which already handles all `ImportError` cases — no new error handling needed.

## Testing

- **Unit (`GluttTests`):**
  - `OnboardingState.apply(to:)` writes every field correctly and sets `hasCompletedOnboarding`.
  - Goal/rule toggle logic (insert/remove).
  - Tutorial phase machine advances `intro → … → cta` and the two CTAs call the right paths.
- **Manual:** run the **Glutt Beta** scheme (Release, no seed data) and/or pass
  `-onboarding` to replay first-run; walk all seven screens on device.

## Open items / future

- Superwall SDK + a real placement at the hook site (separate task).
- Optional: A/B the welcome hero copy once analytics exist.
- Decide later whether `StarterRecipes` "start with our picks" (today's step 4 option)
  resurfaces elsewhere, since the new tutorial replaces that screen.
