# Interactive Import Tutorial — Design Spec

**Date:** 2026-06-17
**Status:** Approved design; pending spec review
**Owner:** Omar
**Supersedes:** the scripted-simulation tutorial in `2026-06-16-onboarding-rebuild-design.md` (§ "Import tutorial").

## Summary

Rebuild the onboarding's import tutorial (`ImportTutorialScreen`) from an abstract,
auto-playing simulation into an **interactive, ReciMe-style guided walkthrough**. The
user is shown **real screenshots** of the share flow and must **tap the highlighted
spot** to advance — Share icon → "Share to…" → Glutt — training the exact muscle memory
of the real action. A **live pulsing ring** is layered on top of each screenshot to
show where to tap.

The tutorial still performs **no real import**; the end CTA hands off to the real
importer, exactly as today. `ImportTutorialScreen`'s public init is unchanged, so
`OnboardingFlow` needs no edits — this is a drop-in rewrite of one screen.

## Goals

- Replace the auto-advancing scripted tutorial with a **hands-on, tap-to-advance** flow.
- Use the **three real screenshots** the user provided as the frame backgrounds.
- Overlay a **blinking/pulsing animated mark** on top of each screenshot (no re-shooting,
  no clean-plate screenshots required).
- Never trap the user: strict tap-to-advance, but **idle auto-advance** + a persistent
  **Skip** guarantee forward progress.
- Note that import **works from other apps too** (TikTok, Pinterest, Safari…).

## Non-goals

- No real import inside the tutorial (unchanged from prior design).
- No re-screenshotting / no clean-plate assets — we animate **on top of** the screenshots
  as delivered, green "Tap here" pills and all.
- No multi-platform *interactive* flows — one concrete Instagram flow + a text note.
- No dark theme (app is light-locked).
- No changes to `OnboardingFlow`, gating, or the paywall hook.

## Frames & flow

An interactive 3-tap walkthrough, then the existing importing → success → CTA tail.

| Phase | Background | Pulsing hotspot — user taps | On tap → |
|---|---|---|---|
| `walkthrough[0]` | **Image #1** — recipe post | the **Send / share icon** (paper-plane, bottom row) | `walkthrough[1]` |
| `walkthrough[1]` | **Image #2** — Instagram share sheet | **"Share to…"** | `walkthrough[2]` |
| `walkthrough[2]` | **Image #3** — iOS share sheet | the **Glutt** icon | `importing` |
| `importing` | branded spinner (~1s) | — | `success` |
| `success` | "That's it — it's saved ✨" + saved-recipe card | — | `cta` |
| `cta` | **Import my first recipe** / **I'll explore on my own** | (existing handlers) | finish |

**Per-frame interaction rules:**

- **Tap inside the hotspot** → advance.
- **Tap elsewhere** → a stronger "nudge" pulse on the ring; **no** advance.
- **Idle ~4s** → auto-advance (safety net; timer resets on any tap).
- **Skip** pinned top-right throughout → `onFinish()`.

**Headline** tracks the phase, reusing existing copy:
`walkthrough[0]` → *"Found a recipe you love?"* · `walkthrough[1..2]` → *"Just tap Share → Glutt"* ·
`success`/`cta` → *"That's it — it's saved ✨"*.

**Cross-platform note:** a quiet caption beneath the frame — *"Also works with TikTok,
Pinterest, Safari & more."*

## The animated mark (layered on top of the screenshots)

Each screenshot ships **as-is**. On top of it we draw a native `CoachMark`:

- A **pulsing/blinking ring** — a soft "radar" ripple plus a gentle scale-pulse — centered
  on the target button.
- **Frames `walkthrough[1]` and `[2]`** already contain the user's green "Tap here 👇" pill
  in the image. The ring pulses on the button that pill points to, so the static label and
  the live pulse reinforce each other. We draw **only the ring** there.
- **Frame `walkthrough[0]`** (the clean recipe post) has no baked mark, so it gets the ring
  **plus** a small native "Tap here" pill (matching green styling) over the Send/share icon,
  for consistency.
- **Nudge:** a wrong tap triggers a one-shot, larger-amplitude pulse to redirect attention.

## Architecture

All under `Glutt/Features/Onboarding/`. `ImportTutorialScreen` is rewritten in place;
its init `(onImportNow:onFinish:)` is unchanged.

```
Onboarding/
  Screens/
    ImportTutorialScreen.swift   // REWRITE — hosts TutorialFlowModel, renders phases,
                                 //   keeps existing importing spinner / savedCard / CTA
  Support/
    TutorialFlowModel.swift      // NEW — pure @Observable state machine (no SwiftUI)
    WalkthroughFrame.swift       // NEW — screenshot + CoachMark + tap layer + idle timer
    CoachMark.swift              // NEW — pulsing ring (+ optional "Tap here" pill)
```

- **`TutorialFlowModel`** (`@Observable`, no SwiftUI import) — the testable core:
  - `phase: Phase` where `Phase = .walkthrough(Int) | .importing | .success | .cta`.
  - `steps: [TutorialStep]` (static config).
  - `tapHotspot()` → advance within walkthrough, then `importing → success → cta`.
  - `tapMiss()` → bumps a `nudgeToken` (view observes it to fire the nudge animation);
    does **not** advance.
  - `idleFired()` → same effect as `tapHotspot()` (auto-advance).
- **`TutorialStep`** value:
  ```
  TutorialStep {
    imageName: String
    headline: String
    hotspot: CGRect          // normalized 0–1, relative to the displayed screenshot
    pointer: Pointer         // .up | .down (label/finger orientation)
    showsLabel: Bool         // true only for frame 0 (others have a baked-in pill)
  }
  ```
- **`WalkthroughFrame`** — renders the screenshot **fit-to-width** (letterbox falls back to
  `GlowBackground`), converts the normalized `hotspot` into the displayed image's rect via
  `GeometryReader`, places the `CoachMark`, and hosts a full-frame tap layer that routes to
  `tapHotspot()` / `tapMiss()`. Owns the idle `Task` (resets on each tap, fires `idleFired()`
  after ~4s; cancels on disappear).
- **`CoachMark`** — the pulsing ring; optional "Tap here" pill + pointer when `showsLabel`.
  Drives a continuous pulse animation and a one-shot nudge keyed off `nudgeToken`.

**Reused unchanged:** `OnboardingFlow` (caller), `Theme`, `GlowBackground`, the existing
`importing` spinner, `savedCard`, and the two CTA buttons (`onImportNow` / `onFinish`).

## Assets

Three imagesets added to `Glutt/Resources/Assets.xcassets`, from the screenshots already
provided (`tutorial-1.png`, `tutorial-2.png`, `tutorial-3.png`) — **used as-is**:

| Asset | Source | Frame |
|---|---|---|
| `tutorialPost` | Image #1 (recipe post) | `walkthrough[0]` |
| `tutorialShareSheetApp` | Image #2 (Instagram share sheet) | `walkthrough[1]` |
| `tutorialShareSheetSystem` | Image #3 (iOS share sheet) | `walkthrough[2]` |

## Hotspot positioning & tuning

- Hotspots are **normalized `CGRect`s** relative to the screenshot, so they track the button
  on every device regardless of fit-to-width scaling.
- A `#if DEBUG` overlay in `WalkthroughFrame` prints the **normalized coordinates** of each
  tap to the console (and optionally draws a crosshair), so the exact button positions are
  dialed in quickly in the simulator — this is the "test where to circle the buttons" step.
- Initial coordinates are eyeballed from the screenshots, then corrected live in the sim.

## Error handling

- The walkthrough is deterministic and offline → no error states.
- Idle auto-advance + Skip guarantee the user can never get stuck on a frame.
- The optional real-import hand-off (`onImportNow` → `router.perform(.importRecipe)`) uses the
  existing importer, which already handles all `ImportError` cases — no new handling here.

## Testing

- **Unit (`GluttTests`)** against `TutorialFlowModel` (pure, no SwiftUI):
  - `tapHotspot()` advances `walkthrough[0] → [1] → [2] → importing → success → cta`.
  - `idleFired()` advances identically.
  - `tapMiss()` does **not** advance and increments `nudgeToken`.
  - From `.cta`, the two CTAs route to `onImportNow` / `onFinish` respectively.
- **Manual:** run with `-onboarding` (or the Glutt Beta scheme); tap through all three
  frames on device/simulator, verify each ring sits over the correct button, that wrong taps
  nudge, that idle auto-advances, and that Skip exits.

## Open items / future

- If frame 1's third-party post content (creator handle, like counts, Instagram chrome)
  becomes an App Store review concern, swap Image #1 for a generic/owned recipe post; frames
  2–3 are unaffected. (Flagged, not blocking.)
- Reduced-motion: optionally damp the pulse when `accessibilityReduceMotion` is on.
