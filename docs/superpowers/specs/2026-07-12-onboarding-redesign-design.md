# Onboarding Rebuild — 1:1 from Design Handoff

**Date:** 2026-07-12
**Status:** Approved design, pending implementation plan
**Source of truth:** `design_handoff_onboarding_flow/` — read `Glutt Onboarding.dc.html` for exact values (colors, sizes, radii, shadows, copy, keyframes); `README.md` for the narrative spec. The HTML wins on any discrepancy.

## Goal

Delete the existing 6-step onboarding and rebuild it as a pixel-faithful 1:1 copy of the 11-screen design prototype, in SwiftUI, wired into the app's real integration points (UserPrefs, Superwall paywall, notification permission, demo recipe import).

## Decisions (settled during brainstorm)

1. **Approach:** clean-room rewrite of `Glutt/Features/Onboarding/`; only `Support/OnboardingPaywallHook.swift` survives. Onboarding-scoped design tokens — global `Theme`/`Typography` untouched.
2. **Screen 9 (notification permission):** keep the screen exactly as designed (mock iOS alert + green ring + bouncing arrow). Tapping "Allow Notifications" fires the **real** `UNUserNotificationCenter.requestAuthorization` — the real alert lands centered over the mock, so the arrow points at the real Allow button. Either OS answer advances to the tutorial. "Not now" skips. (User-selected option.)
3. **Fonts:** bundle Bricolage Grotesque + Nunito variable TTFs (Google Fonts, OFL; commit license files). Onboarding-only usage for now.
4. **Icons:** vendor the Material Symbols Rounded glyphs the design uses as template vector imagesets + an `MS` enum, mirroring the existing vendored-Phosphor pattern. Exact glyphs, not Phosphor approximations.
5. **Copy:** verbatim from the design, including "1M+ happy home cooks" and "4.9 ★ rated" (flagged as aspirational/misleading-risk; user kept them).
6. **No global Skip:** the old flow's top-bar Skip is gone; the design has none. Only "Skip tutorial" (screen 10) and "Maybe later"/"Not now" (screens 8/9) exist.
7. **Nutrition screen removed:** allergies/dislikes/nutritionMode are no longer captured at onboarding. `SettingsView` already edits all three; defaults remain (`nutritionMode = .cookingOnly`, empty lists).
8. **Finish behavior preserved:** both end CTAs run the Superwall `onboarding_complete` placement then dismiss; "Import my first recipe" additionally triggers the real import of the demo reel (`https://www.instagram.com/reel/DYxO-e7JPw3/` — the same hot-honey recipe the tutorial depicts) via `router.pendingImportURL` + `router.perform(.importRecipe)`.
9. **Haptics** (only deliberate addition beyond the mockup): light impact on taps, success notification on the saved-recipe phase — the app's existing `Haptics` convention.

## Architecture

```
Glutt/Features/Onboarding/
├── OnboardingFlow.swift            # coordinator: screen 0–10, chrome, transitions, finish
├── OnboardingState.swift           # @Observable selections + apply(to:)
├── Screens/
│   ├── WelcomeScreen.swift         # 0 — masonry grid + scrim + wordmark + Start
│   ├── IntroVideoScreen.swift      # 1 — H1 + looping glutt-intro.mp4
│   ├── QuestionsIntroScreen.swift  # 2 — centered H1 beat
│   ├── GoalsScreen.swift           # 3 — 6 checkbox rows, ≥1 gate
│   ├── RulesScreen.swift           # 4 — 9 gradient tiles, optional
│   ├── FourWeeksScreen.swift       # 5 — 3 benefit cards
│   ├── PollyHeroScreen.swift       # 6 — full-bleed video, glass chrome, caption pill
│   ├── AIFeaturesScreen.swift      # 7 — H1 + looping glutt-features.mp4
│   ├── NotificationsSoftAskScreen.swift   # 8 — 3 floating notif cards
│   ├── NotificationPermissionScreen.swift # 9 — mock alert + real prompt
│   └── ImportTutorialScreen.swift  # 10 — mini-phone, tutPhase 0–4
├── Support/
│   ├── OnboardingPaywallHook.swift # KEPT as-is
│   ├── OnboardingTheme.swift       # exact hex tokens from the design
│   ├── OnboardingFonts.swift       # Bricolage/Nunito helpers (wght axis, opsz = size)
│   ├── OnboardingComponents.swift  # primary/disabled/text-link buttons, chrome bar, headline+subhead
│   ├── LoopingVideoView.swift      # AVQueuePlayer + AVPlayerLooper, muted, aspect-fill, pauses off-screen
│   ├── MaterialSymbol.swift        # MS enum → template imagesets (Phosphor pattern)
│   ├── MiniPhoneFrame.swift        # 240×510 bezel; content on 390×830 canvas, scaleEffect 0.61538
│   ├── CoachMark.swift             # NEW: ripple ring + pulse + bobbing "Tap here 👇" bubble
│   └── TutorialFrames.swift        # SocialPost / AppShareSheet / SystemShareSheet / Importing / SavedRecipe
```

(Exact file grouping inside `Support/` may shift during implementation; the component boundaries above are the contract.)

### Deleted

- `Screens/`: WelcomeScreen, GoalsScreen, RulesScreen, NutritionScreen, NotificationPrimerScreen, ImportTutorialScreen (all replaced).
- `Support/`: TutorialFlowModel, OnboardingScaffold, WalkthroughFrame, CoachMark (old version).
- Assets: `tutorialPost`, `tutorialShareSheetApp`, `tutorialShareSheetSystem` imagesets (only the old tutorial used them).
- Tests: `GluttTests/TutorialFlowModelTests.swift`; `GluttTests/OnboardingStateTests.swift` rewritten (see Testing).

## Flow & state machine (mirrors the prototype's `Component` class)

- `screen: Int` 0–10, clamped. Start → 1; Continue → +1; back → −1. Entering screen 10 resets `tutPhase = 0` and cancels any import timer.
- Chrome (back circle + progress bar) on screens 1–5, 7, 8, 9 — cream variant (white 40pt back circle, track `rgba(42,36,32,0.09)`, fill `#3E7A50`). Screen 6 draws its own overlay variant (glass back `rgba(255,255,255,0.24)` + blur, track `rgba(255,255,255,0.32)`, fill `#7BD48F`). Screens 0 and 10 have no chrome.
- Progress fraction = `screen / 10`, fill width animates `.45s` `cubic-bezier(.4,0,.2,1)`.
- Back is always shown on chrome'd screens (the prototype's `showBackButton` prop is staging-only). Back from screen 1 returns to Welcome.
- Screen transition: incoming view fades in + slides up 12pt over ~0.45s ease; outgoing view swaps instantly (asymmetric — matches the prototype's remount behavior).
- Goals gate: Continue on screen 3 is the disabled gray pill (`#DED6C4` bg / `#A79D8B` text, non-interactive) until ≥1 goal selected.
- Notification branch: 8 —"Turn on notifications"→ 9; 8 —"Maybe later"→ 10; 9 —"Allow Notifications"→ real OS prompt → (any result) → 10; 9 —"Not now"→ 10. If permission was already determined, the request calls back immediately and we advance — no dead end.
- Tutorial: `tutPhase 0–4`. Phases 0–2 advance on any tap on the mini-phone. Entering phase 3 starts a 1800ms auto-advance to phase 4 (cancellable `Task`). If the view disappears or the app backgrounds during phase 3, the task is cancelled and re-armed on return (onAppear/scenePhase-active while `tutPhase == 3`), so the loader can never strand the user. Phases 0–2 show 3-dot progress + "Skip tutorial"; phase 4 shows the two finish CTAs.
- Finish: `state.apply(to: context)` → `OnboardingPaywallHook.presentPostOnboarding { onFinish(); [primary CTA also routes the demo import] }`.

## Data & persistence

`OnboardingState` (rewritten):

- `selectedGoals: Set<String>` over the design's 6 labels (order fixed):
  "Eat healthier without the fuss", "Stop wasting food", "Spend less on takeout", "Cook with what I already have", "Build a real cooking habit", "Cook for people I love".
- `selectedRules: Set<DietaryRule>` over the 9 tiles in design order: vegetarian, vegan, pescatarian, glutenFree, dairyFree, **nutFree (new case)**, halal, kosher, **keto (new case)**.
- `apply(to:)`: `prefs.goals = Array(selectedGoals)`, `prefs.dietaryRules = Array(selectedRules)`, `prefs.hasCompletedOnboarding = true`. Nothing else is written.

`DietaryRule` (`Glutt/Models/Enums.swift`) gains `nutFree` ("Nut-free") and `keto` ("Keto"). String-backed Codable — additive and data-safe; they appear automatically in Settings' rule list and in Polly's prompt context. `noPork` remains a case (Settings-only; no onboarding tile).

## Screens — build notes

Exact values (colors, paddings, radii, shadows, font sizes, copy) come from the handoff HTML; this section only records **platform mapping decisions**.

- **Layout mapping rule:** the design canvas is 390×874 with a ~54px fake status zone. Top paddings map to `(design value − 54)` below the safe-area top (e.g. chrome at design 60px → safeTop + 6; content at 104px → safeTop + 50). Bottom paddings 26–42px map from the safe-area bottom. Horizontal paddings are literal.
- **0 Welcome:** 3-column grid, `grid-auto-rows: 76pt`, gap 9, span pattern per the HTML (tiles 1 and 5 span 3 rows; the other nine span 2). Tiles use 11 of the existing recipe imagesets (beefWrapWithWedges, chickenRiceBowl, garlicButterSteakPotatoBowl, greekYogurtBowl, greenGoddessSteakPlate, hotHoneyChickenRice, koftaFlatbreadWrap, koreanBeefMealPrep, lemonDillSalmonBowl, pestoGnocchiMealPrep, steakFajitaSalad; tile↔photo assignment at implementation discretion — most appetizing shot in the span-3 hero tile). Grid bleeds past the fold; cream scrim gradient (62% height, stops per HTML) sits above it; bottom block: wordmark + red square, H1 34, social-proof pill, Start button.
- **1 Intro / 7 AI features:** same template; flex-fill rounded-28 video frame with top fade scrim; videos crop per the HTML transforms (intro: `translateY(-9%) scale(1.1)` top-anchored; features: `translateY(-8%) scale(1.08)`), implemented as an oversized aspect-fill layer inside a clipped container.
- **3 Goals:** rows are buttons (whole row toggles); 26pt rounded-9 checkbox, filled `#2E5339` + white check glyph when selected; 150ms selection transition.
- **4 Rules:** tiles `aspect-ratio 1/1.1`, radius 24; layered background = linear gradient per tile + top-left white radial sheen + bottom dark legibility gradient; 60pt glass icon square (`.ultraThinMaterial`-equivalent: white 0.22 + blur); selected = `translateY(-3)` + double ring (3pt cream, 6pt green via two strokes/shadows) + colored drop shadow + white check badge top-right; ~180ms transition.
- **5 Four weeks:** 3 cards; right icon = 62pt rounded-19 gradient square with inner top highlight + bottom shade (inner shadows approximated with overlay gradients) and a radial glow halo behind.
- **6 Polly:** top 66% full-bleed looping `glutt-intro.mp4` on near-black, multi-stop scrim to cream; caption pill at 18.5% from top (dark glass, blur 14, 32pt gradient avatar + `graphic_eq`); bottom-centered: leaf-flanked rating badge, H1 29, green mic pill, Continue.
- **8 Soft ask:** 3 notification cards, `gluttOrb` float 5/5.4/5.8s staggered 0/.55/1.05s; 40pt green-gradient app icon with `skillet` glyph.
- **9 Permission:** mock alert 272pt wide (SF system font — the one place we deliberately use the system font), green highlight ring over the Allow half, bouncing `arrow_upward` below at 75% x. CTA fires the real prompt (Decision 2); on grant also call `ReminderScheduler.schedulePlatesDailyReminder()`.
- **10 Tutorial:** headline/subhead swap per phase (fixed 64pt min header height to avoid jumps); mini-phone 240×510 radius 46 with 82×23 notch pill; content drawn on a 390×830 canvas scaled by 0.61538. On short devices, uniformly scale the whole phone block down to fit (GeometryReader), preserving proportions. Phase content per the HTML: social post (hot-honey photo, "thesapor" row, action rail with coached `send`, Georgia-italic caption), app share sheet (dimmed post, slide-up sheet, coached "Share to…"), system share sheet (link preview row, AirDrop/coached-Glutt/Messages/Mail, Copy/Reading List), importing loader (3 bouncing dots staggered .16s + sweeping bar 1.4s), saved recipe (hero + popping "Saved to your recipes" badge, title, meta row, ingredient checklist).

## Visual system & assets

- **`OnboardingTheme`**: static Colors from the design's hex values (cream `#FAF3E7`, surfaces `#FFFDF7`/`#F4EDDC`/`#F1E9D6`, green `#2E5339` (+`#356145`, `#244430`, `#3C6B4B`, `#3E7A50`, `#7BD48F`, `#8FE3A3`, `#6FB183`, `#4E7A5C`, tint `#EAF1E7`), coral `#D9483B`/`#E1523D`/`#F4906F`, ambers, text grays `#241E19`/`#2A2420`/`#3A342C`/`#9A9082`/`#8A8072`/`#6E6456`/`#B3A99A`, disabled `#A79D8B` on `#DED6C4`, cream text `#FBF5E9`, iOS-mock grays + `#0a84ff`), plus the 9 rule-tile gradient pairs + shadow colors.
- **Fonts**: `Glutt/Resources/Fonts/` gets `BricolageGrotesque[opsz,wdth,wght].ttf`, `Nunito[wght].ttf` (+ OFL.txt each), registered via `UIAppFonts` in `project.yml` (`xcodegen generate` after). `OnboardingFonts.bricolage(size:weight:)` / `.nunito(size:weight:)` build CTFont with the `wght` variation axis; Bricolage also pins `opsz` = point size (browser optical-sizing parity). Weights used: Bricolage 600/700; Nunito 600/700/800.
- **Icons**: `Assets.xcassets/MaterialSymbols/` template vector imagesets for the design's glyphs — check, chevron_left, eco, spa, set_meal, grain, icecream, no_meals, mosque, synagogue, egg, local_fire_department, kitchen, graphic_eq, mic, skillet, favorite, mode_comment, send, bookmark, search, add_circle, ios_share, link, chat, wifi_tethering, chat_bubble, mail, content_copy, chrome_reader_mode, schedule, restaurant, check_circle, arrow_upward (filled variants where the design sets `FILL 1`). `MS` enum mirrors `Ph`. Sourced from google/material-design-icons (Apache 2.0; note license).
- **Video**: `Glutt/Resources/Videos/glutt-intro.mp4` + `glutt-features.mp4` copied from the handoff (XcodeGen bundles them automatically as folder resources). `LoopingVideoView`: `AVQueuePlayer` + `AVPlayerLooper`, `isMuted`, `.resizeAspectFill`, plays on appear (audio-session-safe: playback does not interrupt others — configure `.ambient`/mixWithOthers so onboarding never kills the user's music), pauses on disappear.
- **Photos**: `hot-honey.png` downscaled (sips, longest side ≤1500px) → `tutorialHotHoney` imageset.

## Integration changes outside `Features/Onboarding/`

1. **`RootView.swift`**: the launch `.task` stops blind-requesting permission. It becomes `.task(id: needsOnboarding)`, runs only when `needsOnboarding == false` (still skipped under `-uiPreview`), reads `UNUserNotificationCenter.notificationSettings()`, and calls `schedulePlatesDailyReminder()` **only if** status is `.authorized`/`.provisional`. It never calls `requestAuthorization` — the OS prompt is requested exactly once, on screen 9 (or later by feature code like `TimerManager` that already requests per-use). This keeps "Maybe later" meaning *not now*: no prompt before screen 9, and none ambushing the user right after onboarding dismisses. `ReminderScheduler.requestPermissionIfNeeded()` loses its RootView call site (screen 9 calls `requestAuthorization` with `[.alert, .sound, .badge]` directly, matching the old primer's options).
2. **`Glutt/Models/Enums.swift`**: add `DietaryRule.nutFree`, `.keto`.
3. **`project.yml`**: `UIAppFonts` entries for the two TTFs; regenerate project. No new packages or targets.
4. Unchanged: `OnboardingPaywallHook` (Superwall placement `onboarding_complete`), `Router` import routing, `-onboarding` force flag, share extension, seeding (`SeedData` sets `hasCompletedOnboarding = true`).

## Animations & accessibility

- Keyframes reproduced: `gluttFade` (screen enter), `gluttSheet` slide-up (`.4s cubic-bezier(.2,.9,.3,1)`), `gluttPop` badge overshoot (`.5s cubic-bezier(.2,.9,.3,1.3)`), `gluttOrb` float, coach `gluttCoachRipple` 1.4s + `gluttPulse` 1s + `gluttCoachBob` 1s, loader `gluttBounce` 1s staggered + `gluttBar` 1.4s sweep, progress `.45s cubic-bezier(.4,0,.2,1)`.
- `accessibilityReduceMotion`: infinite loops (orb, coach, arrow, loader) render static; screen transitions become plain fades. Videos still play (muted, decorative) — acceptable; revisit if flagged.
- Fixed font sizes (no Dynamic Type) inside onboarding, matching the design. All tappables get accessibility labels; the mini-phone advances via tap gesture with an `.accessibilityAction` equivalent.

## Error handling

- Video asset missing/failed → the frame keeps its cream `#F4EDDC` background; no crash, no spinner.
- Import auto-advance `Task` cancelled on disappear/backgrounding and re-armed on return while in phase 3 (see Flow); entering screen 10 fresh always resets to phase 0 (prototype behavior).
- `requestAuthorization` callback hops to the main actor and always advances (grant, deny, or already-determined).
- Font registration failure → system font fallback + `assertionFailure` in debug builds.

## Testing & verification

- **Unit (GluttTests):**
  - `OnboardingStateTests` (rewritten): goal/rule toggling, goals-gate (`canContinueFromGoals`), `apply(to:)` writes goals/rules/flag and nothing else, new enum cases round-trip.
  - New flow-logic tests on extracted pure logic: screen clamping, chrome-visibility set {1–5,7,8,9}, progress fractions, notification branch targets, tutorial phase machine (tap advance stops at 3, timer → 4, skip semantics) with injectable clock.
- **Build/run:** XcodeBuildMCP (`session_show_defaults` first), `Glutt` scheme, iPhone simulator.
- **Visual pass:** launch with `-onboarding`, screenshot all 11 screens + 5 tutorial phases; side-by-side against the HTML prototype (open `Glutt Onboarding.dc.html` in Chrome, drive `startScreen`/`startPhase` props). Iterate until matching. Follow `docs/superpowers/verify-screenshots/` workflow.
- **Behavioral pass:** real permission alert appears over the mock (sim), goals gate blocks, back/skip routes, finish → paywall placement fires (Superwall sandbox) → "Import my first recipe" lands on Recipes tab with importer pre-filled with the demo reel URL.

## Risks / notes

- **Social-proof copy is aspirational** ("1M+", "4.9 ★") — kept 1:1 per user decision; App Review risk acknowledged. One-line change if it ever needs softening.
- Bricolage/Nunito rendering will differ sub-pixel from Chrome (CoreText vs Skia) — expected; match metrics, not rasterization.
- The two handoff mp4s are the design's placeholder media; swap-in of final production video is a drop-in replacement later.
- Onboarding typography now deliberately diverges from the app's SF Rounded; adopting Bricolage/Nunito app-wide is explicitly out of scope here.
