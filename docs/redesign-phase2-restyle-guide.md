# Glutt Redesign — Phase 2 Restyle Guide (shared)

Applies the Phase-1 design language to the rest of the app, screen by screen. Most Phase 2
screens already use `Theme`/`Font.glutt*`/button styles, so a restyle is mostly: **Phosphor
icons + haptics + card/panel refinement — with ZERO feature loss.**

## The golden rule
**Restyle is visual + haptic only. Never remove a button, action, navigation path, data
write, conditional, or feature.** (Phase-1 reviews repeatedly caught dropped features in
rewrites.) If a section is hard to restyle, keep its behavior and restyle conservatively.

## Build / tooling
- Build: `xcodebuild build -scheme Glutt -destination 'id=1EEC6A07-E689-4149-ABC7-FF36F702BBF6' 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED| error:" | tail -8`. Only on a DerivedData permission error, re-run with the sandbox disabled.
- New files → `ruby Scripts/xcp_add.rb <relpath> Glutt` and commit the pbxproj change.
- Editor "No such module 'PhosphorSwift'/'UIKit'" notes are stale-index noise; the build is truth.

## Icons — Phosphor
- Add `import PhosphorSwift` to any file using icons.
- Replace EVERY `Image(systemName:)` / `Label(_, systemImage:)` with `Ph.<name>.<weight>` (`.regular`/`.bold`/`.fill`), `.resizable().scaledToFit().frame(...)`, tinted with `.foregroundStyle(...)`.
- `Ph.<name>.<weight>` returns an `Image` (already resizable); assets are template-rendered so `.foregroundStyle`/`.foregroundColor` tints them.
- **Verify each case name** against the installed package before relying on it:
  `grep -oE "case [a-zA-Z]+" "$(echo ~/Library/Developer/Xcode/DerivedData/Glutt-*/SourcePackages/checkouts/swift/Sources/PhosphorSwift/Icons.swift)" | sort -u` — if a guessed name is absent, pick the nearest real Phosphor case; only fall back to the SF Symbol if there is genuinely no equivalent.
- Common mappings (verify names): `gearshape→gearSix`, `chevron.left/right/down/up→caretLeft/Right/Down/Up`, `xmark→x`, `checkmark→check`, `circle→circle`, `checkmark.circle.fill→checkCircle(.fill)`, `plus→plus`, `plus.circle.fill→plusCircle(.fill)`, `minus→minus`, `fork.knife→forkKnife`, `frying.pan→cookingPot`, `timer→timer`, `clock→clock`, `sparkles→sparkle`, `leaf→leaf`, `flame→flame`, `star/star.fill→star(.fill)`, `basket→basket`, `cart→shoppingCart`, `trash→trash`, `pencil→pencil`, `square.and.arrow.up→export`, `magnifyingglass→magnifyingGlass`, `calendar→calendarBlank`, `camera→camera`, `link→link`, `bell→bell`, `house→house`, `chart.bar→chartBar`.

## Haptics (device-only; no-ops in Simulator)
`Haptics` is in the same module — no import needed. Add a call at the START of the relevant action closure:
- `Haptics.selection()` — changing tab / segment / filter / picker / category selection.
- `Haptics.impact(.medium)` — primary CTAs (Cook, Continue, Save, Add, Import, primary confirm).
- `Haptics.impact(.light)` — secondary taps, checkbox/toggle flips, stepper +/-, list-row taps, expand/collapse.
- `Haptics.notify(.success)` — a thing completed: added to groceries, marked eaten, logged, saved, finished cooking, plan created.
- `Haptics.notify(.warning)` — surfacing a blocker (diet/allergy conflict shown, "missing ingredients").
- `Haptics.notify(.error)` — failures; also fine just before a destructive `confirmationDialog`.
Don't over-fire: one cue per user action. For `.onChange`-driven selection (e.g. a Picker bound to state), put `Haptics.selection()` in an `.onChange` so it fires once per change.

## Visual language (apply where it improves hierarchy — don't force it)
- Background `Theme.Colors.background` (cream). Cards `Theme.Colors.card`.
- **Feature/hero cards**: `Theme.Radius.cardLarge` (26), soft shadow, optional panel-tint accent area (`sagePanel`/`peachPanel`/`successTint`/`warningTint`/`tomatoTint`).
- **List rows / small cards**: keep `cardStyle()` / `Theme.Radius.card`.
- **Stat rows**: foundation `StatPill` (`.rating/.time/.difficulty` or custom icon+tint).
- **Category/identity glyphs**: foundation `IconChip` (36pt tinted rounded square).
- **Uppercase section headers**: foundation `SectionLabel`.
- **Segmented switches**: foundation `SegmentedTabs` (`titles:[String], selection:Binding<Int>`).
- **Primary CTA**: green accent — `.gluttPrimary`, or a capsule (`Theme.Colors.accent` fill + `creamText` text) for the redesigned look. Secondary: `.gluttPill`/`.gluttPillFilled`.
- Keep diet/allergy/safety warnings VISIBLE and legible — never hide them.

## Per-screen workflow
1. Read the target file fully.
2. Apply: Phosphor icons (verified) + haptics at actions + card/panel refinement, preserving every feature.
3. Build → BUILD SUCCEEDED, no new warnings.
4. Commit `feat(redesign): restyle <screen> (Phosphor + haptics + new look)`.
5. Controller screenshots the screen (launch `-tab <name> -seed`, or the screen's entry) and reviews.
