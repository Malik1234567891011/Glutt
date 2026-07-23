# Plan: App redesign (1:1) + Polly wake-word feature

Branch: `redesign-app-and-polly-wakeword`. Design source: `design-doc/glutt-design-context/design_handoff_glutt_app/` (`Glutt Main Page.dc.html` = Feed home, `Glutt Screens.dc.html` = detail/Discover/Kitchen, `Glutt Polly.dc.html` = Live/Listening).

This is a large pass: an app-wide font migration, ~25 vendored icons, four screen rebuilds, a Polly UI overhaul, and a new on-device wake-word subsystem. Delivered on one branch in staged, build-and-test-green commits; the user reviews at the end.

## Locked decisions (from grilling)

1. **Scope** — Rebuild all four app screens (Recipes home, Recipe detail, Discover, Kitchen) + redesign Polly + build the wake-word feature.
2. **Fidelity** — Strict 1:1 to the mocks on the primary surface.
3. **Orphaned features** — Kept reachable *off* the mock surface (nothing built/saved is lost): Collections + Cooking Basics via the Recipes header/overflow; Discover Videos via a toggle; detail extras (Tools-you'll-need / Substitute / Macros / notes) via a `more_horiz` overflow on detail.
4. **Fonts** — Bricolage Grotesque (headings) + Nunito (body), **app-wide** (rewrite `Typography.swift`). Fonts are already bundled + registered in Info.plist (`UIAppFonts`).
5. **Icons** — Vendor the ~25 missing Material Symbols Rounded glyphs as SVG imagesets under `Glutt/Resources/Assets.xcassets/MaterialSymbols`, following the existing `MaterialSymbol.swift` (`MS` enum) pattern. True 1:1.
6. **Polly visual** — Full redesign to the mock: no orb; bottom step card; top bar `menu_book` / title+timer / `more_horiz`; centered state pill; big caption; call-style controls (mute · red `call_end` hang-up · camera). **Ending the call moves to the red `call_end` button.** Functional states (preflight, timers, reconnecting/failed/mic-denied) kept and restyled.
7. **Wake word** — Real on-device gate. Dormant (Live) = the Realtime mic is **muted** (Polly hears nothing). Saying "Polly" → Listening (unmute + gradient edge border + waveform pill + **live on-device transcription**) → she answers → ~6 s follow-up window (talk again without "Polly") → re-mute to dormant.
8. **Barge-in** — Interrupt her mid-answer by just speaking (raw, no "Polly"); the mic is already open during her turn.
9. **Mic button** — Master mute (incl. the wake word). Tapping the "Say Polly to talk" pill = manual force-listen fallback (for when the wake word mishears).
10. **Verification** — Wake-word *logic* is unit-tested (pure state machine + matcher, injected recognizer via the `Dependencies`-closure pattern); the four screens are checked on the simulator (screenshots); the **live wake word is device-tested by the user** (sim can't exercise on-device speech/mic, and a StoreKit/bundle-ID prompt blocks sim tap-through on this machine).

## Behavior defaults

- **Home hero** "Ready to cook tonight" = the recipe with the best pantry coverage (fully-stocked first), tie-broken by most recently saved. Its Cook button opens the recipe **detail** (not straight into Polly).
- **Home filter chips** map to existing logic: Ready now → pantry coverage · Under 30 min → time · High protein → protein sort · Recent → recently saved · All → none. The sort *menu* retires in favor of these chips.
- **Header stat** "132 saved · 18 cooked" → live counts (library size · cooks logged).
- **Search pill** → existing semantic search / AI-ranking, restyled as the pill.
- **Detail adapt row** — "Make it…" → existing adapt menu; "Use what I have" → adapt-to-pantry.
- **Ingredient tiles** (detail + Kitchen) use flat `ing-*.png` food icons (0xGF/food-icons, MIT). Import the 10 provided + a neutral fallback tile; keyword name→icon mapper.
- **Speech permission** — add `NSSpeechRecognitionUsageDescription`; prompt at Polly start. If on-device recognition is unavailable for the device/locale, degrade to "tap the pill to talk" with a subtle note.

## Stages / tasks

1. Design-system foundation (fonts, color tokens, vendored icons, ingredient icons + mapper, dark tab bar).
2. Recipes home (Feed).
3. Recipe detail.
4. Discover (recipe-cards deck).
5. Kitchen.
6. Polly session visual redesign.
7. Polly wake-word subsystem (on-device gate) + unit tests.
8. Regenerate, build green, tests, sim screenshots, checkpoint.

## Status — delivered (2026-07-20)

All eight stages landed on the branch, building green, full suite **309/309**.

- **Design system:** `Typography.swift` → Bricolage/Nunito app-wide (via `BrandFont`, Core Text variable axes); `Theme` palette to exact hexes; `Color(hex:)` moved to `Theme.swift` (shared with the share extension). 26 Material Symbols vendored under `Assets.xcassets/MaterialSymbols` (+ `MS` enum cases); `MaterialSymbolTests` confirms all glyph assets resolve. 10 `ing-*` food-icon imagesets + `IngredientTile`/`IngredientIcon` mapper. `GluttTabBar` → dark rounded MS bar.
- **Screens (sim-verified 1:1):** Recipes home (`RecipesView` Feed + `FeedRecipeCard`), Recipe detail (`RecipeDetailView`), Discover deck (`PlatesTabView` + `FeedCardView` cream cards, `DiscoverTabView` header + Videos toggle), Kitchen (`KitchenView` + `InventoryView`). Orphans kept reachable: Collections + Cooking Basics via the Recipes `+` menu (`CollectionsListSheet`); Discover Videos via the header toggle; detail extras via the detail `more_horiz` → "More details" sheet.
- **Polly:** `PollySessionView` rebuilt to the mock (no orb, bottom step card, call-style controls, red `call_end` hang-up, top bar menu_book/more_horiz, state pill, big caption, Listening edge border + waveform). Dead subviews (orb, status pill, step hero/card, question bubbles, control button) removed.
- **Wake word (device-tested by user):** `WakeWordListener` (on-device `SFSpeechRecognizer`, fed from `PollyAudioEngine.onBuffer` before the mute gate) + pure `WakeWordMatcher`. Controller gained `listeningMode` (dormant/listening), `liveTranscript`, `isHardMuted`, `wakeWordAvailable`, and the gate methods (`wakeUp`/`returnToDormant`/`toggleHardMute`/`forceListen`) + a `followUpWindowSeconds` dormancy timer (tuned to 3s after device testing). The "Listening" visual (edge glow, waveform, live transcript) shows only while *actively* waiting for the cook (`listeningMode == .listening && !isPollySpeaking && !isThinking`), not through her whole answer; a medium haptic + a one-shot full-screen `ListeningSweep` fire on wake. `NSSpeechRecognitionUsageDescription` added; Speech auth requested at session start; degrades to tap-the-pill if unavailable. Unit-tested: `WakeWordMatcherTests` (4) + 3 gate-transition tests in `PollySessionControllerTests`.
- **Testing hook:** `-openRecipe` launch arg (Router.`openFirstRecipeOnLaunch`) opens the first recipe's detail on launch, for screenshotting without UI tapping. Sim screenshots use `-seed -uiPreview` (+ `glutt://discover|kitchen` deep links).

**Needs device testing (sim can't):** the live Polly session + wake word — on-device Speech, mic/AEC, and a real Realtime connection. Verify: "Polly" wakes her, the Listening edge/waveform + live transcript appear, the ~6s follow-up window feels right, master-mute + tap-the-pill fallback work, and she no longer answers background chatter while dormant.

## Workflow notes

- XcodeGen project (`project.yml` is source of truth; `sources: - Glutt` is folder-based). Run `xcodegen generate` after adding/removing `.swift` files. New imagesets *inside* an existing `.xcassets` do **not** need regeneration.
- Share extension (`GluttShare`) compiles `Theme.swift`, `Typography.swift`, `Components/Buttons.swift` — keep them compiling for the extension (SwiftUI-only imports).
- Build/test via XcodeBuildMCP (`build_sim` / `test_sim`), scheme `Glutt`, sim `iPhone 17 Pro`.
- No dashes in UI copy (project rule). Neutral/warm shadows only. On-photo pills solid, not frosted.
