# Handoff: Glutt Onboarding Flow

## Overview
An 11-screen first-run onboarding for **Glutt**, a home-cooking app. It welcomes the user, learns their cooking goals and dietary rules, sells the core value (hands-free AI cooking guide "Polly", auto grocery lists, less waste), asks for notification permission, and ends with an interactive tutorial that teaches the app's key mechanic: **importing a recipe from a social post via the OS share sheet**.

The flow runs inside an iPhone frame. Design width is a 390pt phone screen (rendered in an iOS device bezel at 402×874).

## About the Design Files
The files in this bundle are **design references created in HTML** — a working prototype showing the intended look, motion, and behavior. They are **not** production code to copy directly. Your task is to **recreate these designs in the target codebase's existing environment** (React Native, SwiftUI, Flutter, etc.) using its established components, navigation, and styling patterns. If no app environment exists yet, pick the framework most appropriate for the product (this is a native-feeling iOS mobile app) and implement there.

The `.dc.html` file uses a small custom runtime (`support.js`) and a template dialect (`<sc-if>`, `<sc-for>`, `{{ }}` holes). Read it for structure, exact values, and logic — do not port the runtime itself.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, radii, shadows, copy, and interactions are all specified below and in the source. Recreate the UI pixel-accurately using the codebase's own component library. The one exception is the iOS system notification permission dialog on screen 9, which is a **visual mock** of the native OS alert — in production you trigger the real OS permission prompt instead of rendering this.

## Screens / Views

The whole flow is one component driven by a `screen` integer (0–10). A top progress bar + optional back button (the "chrome") appears on screens 1–5, 7, 8, 9.

### 0 — Welcome
- **Purpose:** First impression; single "Start" CTA.
- **Layout:** Full-bleed 3-column masonry grid of recipe photos (11 tiles, varying row-spans of 2–3, `grid-auto-rows:76px`, gap 9px, top padding 54px). A cream gradient scrim rises from the bottom 62% (`linear-gradient(to top,#FAF3E7 46%, …0% top)`). Bottom-anchored content block (padding 26/28/40px).
- **Components:** Wordmark "Glutt" (Bricolage 700, 22px, #241E19) + 10×10px red square (#D9483B, radius 3). H1 "Cook anything you actually want" (Bricolage 600, 34px/1.08, -1px, max-width 320, `text-wrap:balance`). Social-proof pill: "1M+" (Bricolage 700, 14px, #2E5339) + "happy home cooks" (Nunito 700, 13.5px, #4E7A5C) on #EAF1E7, radius 100px, padding 8/14. Primary button "Start".
- **Note:** The 11 grid tiles are user-fillable image placeholders in the prototype. In production these are real recipe thumbnails from the catalog. Placeholders name intended dishes (Creamy Tomato Rigatoni, Green Goddess Bowl, Shakshuka, Avocado Toast, Thai Green Curry, Herb Roast Chicken, Caesar Salad, Carnitas Tacos, Miso Ramen, Buttermilk Pancakes, Miso-Glazed Salmon).

### 1 — Intro
- **Purpose:** One-line pitch over a looping video.
- **Layout:** Top-padded column (104/24/42). Centered H1 "Glutt is a whole new way to cook at home" (Bricolage 600, 28px/1.2, max-width 310). Flex-fill rounded video frame (radius 28, bg #F4EDDC, `margin:22px 0`) with a top fade scrim. Bottom "Continue" button.
- **Video:** `glutt-intro.mp4`, autoplay loop muted playsinline, `object-fit:cover`, nudged `translateY(-9%) scale(1.1)`.

### 2 — Questions intro
- **Purpose:** Transition beat before the questions.
- **Layout:** Centered H1 "Let's tune Glutt to how you actually cook" (Bricolage 600, 29px/1.22, max-width 290). Bottom "Continue".

### 3 — Goals (multi-select)
- **Purpose:** Capture motivations; **≥1 required** to proceed.
- **Layout:** H1 "Why do you want to cook more at home?" (26px) + subhead "Pick anything that sounds like you" (Nunito 600, 14.5px, #9A9082). Scrollable column of 6 selectable rows (gap 11).
- **Row component:** flex space-between, padding 18, radius 20. Unselected: bg #FFFDF7, 1.5px border rgba(42,36,32,0.06). Selected: bg #EAF1E7, 1.5px border #2E5339. Right-side checkbox 26×26, radius 9; selected = filled #2E5339 with white `check` glyph; else transparent with 2px border rgba(42,36,32,0.2). Label Nunito 700, 15.5px, #3A342C. 150ms transition.
- **Options:** Eat healthier without the fuss · Stop wasting food · Spend less on takeout · Cook with what I already have · Build a real cooking habit · Cook for people I love.
- **CTA state:** Enabled green "Continue" when ≥1 selected; otherwise a disabled pill (bg #DED6C4, text #A79D8B, `cursor:not-allowed`).

### 4 — Food rules (multi-select grid)
- **Purpose:** Dietary restrictions; optional.
- **Layout:** H1 "Any food rules?" (27px) + subhead "Tap all that apply". 3-column grid, gap 12, of 9 gradient tiles.
- **Tile component:** `aspect-ratio:1/1.1`, radius 24, centered column (icon square + label), gradient background per tile with a soft top-left white radial sheen overlay, plus an inner dark bottom gradient for text legibility. Icon in a 60×60 glass square (rgba(255,255,255,0.22), `backdrop-filter:blur(6px)`, radius 19) with a 33px white filled Material Symbol. Label Bricolage 600, 15px, white, text-shadow. **Selected:** lifts `translateY(-3px)` and gets a double ring `0 0 0 3px #FAF3E7, 0 0 0 6px #2E5339` + colored drop shadow, and a white 24px check badge top-right (green check).
- **Tiles (label · icon · gradient · shadow color):**
  - Vegetarian · eco · `155deg,#7FB56A,#3F7A3A` · rgba(63,122,58,.45)
  - Vegan · spa · `#6CC99A,#2C8A5E` · rgba(44,138,94,.45)
  - Pescatarian · set_meal · `#6BB6C4,#2E7385` · rgba(46,115,133,.45)
  - Gluten-free · grain · `#E8C06A,#C08A2E` · rgba(192,138,46,.45)
  - Dairy-free · icecream · `#F0B98A,#D9884E` · rgba(217,136,78,.45)
  - Nut-free · no_meals · `#E0906E,#B85436` · rgba(184,84,54,.45)
  - Halal · mosque · `#5FA377,#2E5339` · rgba(46,83,57,.5)
  - Kosher · synagogue · `#9088CC,#574C9E` · rgba(87,76,158,.45)
  - Keto · egg · `#E28AA0,#BC4E6E` · rgba(188,78,110,.45)
- **CTA:** "Continue" always enabled (rules are optional).

### 5 — "Here's where you'll be in 4 weeks"
- **Purpose:** Aspirational value payoff.
- **Layout:** H1 (27px, max-width 290). Vertically-centered stack of 3 benefit cards (gap 14).
- **Card component:** flex row, padding 18/20, radius 24, bg rgba(255,253,247,0.72), 1px border rgba(42,36,32,0.05), shadow `0 8px 22px rgba(42,36,32,0.05)`. Left: title (Bricolage 600, 18px, #241E19) + description (Nunito 600, 13.5px, #9A9082). Right: 62×62 rounded-square (radius 19) glossy gradient icon with a soft radial glow halo behind it and a 30px white filled Material Symbol.
  - Cook with confidence — "Hands-free guided recipes that actually work" — icon `local_fire_department`, coral gradient `155deg,#F4906F,#D9483B`, glow rgba(225,82,61,.55)
  - A kitchen that runs itself — "Grocery lists build themselves from your plan" — icon `kitchen`, green `#6FB183,#2E5339`, glow rgba(46,83,57,.5)
  - Less waste, less takeout — "Use what you have before it goes off" — icon `eco`, amber `#F3C877,#D99A3C`, glow rgba(217,154,60,.55)
- **CTA:** "Continue".

### 6 — Polly (voice AI hero)
- **Purpose:** Introduce the hands-free voice+camera cooking guide.
- **Layout:** Top 66% is a full-bleed looping video (`glutt-intro.mp4`, `object-position:center 34%`) on a dark base, with a multi-stop scrim fading to #FAF3E7 at the bottom. Chrome (back + progress) overlaid in white/glass on the video; progress fill is #7BD48F here. A floating voice-caption pill sits at 18.5% from top: dark glass (rgba(20,15,10,0.44), blur 14), 32px green gradient avatar with `graphic_eq` glyph + line "Sear it 2 more minutes, I'll tell you when to flip." (Nunito 600, 13px, white). Bottom content is centered: a "4.9 ★ rated / Loved by 1M+ home cooks" badge flanked by two rotated `eco` leaves; H1 "Polly guides you through recipes, completely hands-free" (Bricolage 600, 29px/1.13); a green "Real-time voice + camera" pill with `mic` glyph; then "Continue".

### 7 — AI features
- **Purpose:** Show AI surfacing contextually while cooking.
- **Layout:** Same template as screen 1/Intro. H1 "AI shows up right where you cook" (27px) + subhead "Smart help, right where you're cooking". Rounded video frame with `glutt-features.mp4`. "Continue".

### 8 — Notifications (soft ask)
- **Purpose:** Show the *value* of notifications before the OS prompt.
- **Layout:** H1 "Turn on gentle nudges" (27px) + subhead "Cook on rhythm, never nagging". Centered stack of 3 realistic notification cards (max-width 344, gap 12), each gently floating (`gluttOrb` 5–5.8s, staggered).
- **Notification card:** flex row, radius 22, bg rgba(255,253,247,0.95), 1px border, shadow `0 12px 30px rgba(42,36,32,0.1)`, padding 13/15. 40×40 green gradient app icon (radius 11, `skillet` glyph). Header row: "GLUTT" (Nunito 800, 11px, letter-spacing .7, #9A9082) + timestamp (#B3A99A). Title (Bricolage 600, 14.5px) + body (Nunito 600, 12.5px, #8A8072):
  - "Tonight's dinner is 20 minutes away" / "You've got everything for Creamy Tomato Rigatoni." — *now*
  - "Plan this week in 2 minutes" / "Pick a few meals and Glutt builds your list." — *8:00 AM*
  - "Use it before it turns" / "Your spinach and mushrooms expire Sunday." — *Sun*
- **CTAs:** Primary "Turn on notifications" → screen 9. Text link "Maybe later" (Nunito 700, 15px, #9A9082) → skips to tutorial (screen 10).

### 9 — Notification permission (OS prompt mock)
- **Purpose:** Point the user at the native "Allow" button.
- **Layout:** Centered mock of the iOS system alert (272px, radius 14, bg rgba(249,249,250,0.97), shadow `0 24px 60px rgba(42,36,32,0.28)`): title "&quot;Glutt&quot; Would Like to Send You Notifications" (SF Pro / -apple-system 600, 16px, #1c1c1e), body "Just gentle reminders to cook. No spam, ever." Two-button row (44px, top border, "Don't Allow" / "Allow" in #0a84ff, Allow is 600) with a green highlight ring drawn over the Allow half, plus a bouncing `arrow_upward` (green) pointing at it. Bottom app CTA "Allow Notifications" → screen 10; text link "Not now" → screen 10.
- **Production:** Replace the mock alert with the real OS permission request; the on-screen highlight/arrow is only a teaching aid.

### 10 — Import tutorial (multi-phase)
- **Purpose:** Teach the core import gesture, then reward with the saved recipe. This screen shows a **mini phone-within-the-phone** (240×510, radius 46, black bezel with notch) demonstrating the OS share flow. Headline + subhead above it change per phase; below is either a 3-dot progress + "Skip tutorial" (walkthrough phases) or the final CTAs.
- **Phases (`tutPhase` 0→4):**
  - **0 — the post.** Headline "Found a recipe you love?" / "Tap the share button on the post." A full social-video post (photo `hot-honey.png`, creator "thesapor", like/comment counts, italic caption "Crispy hot honey chicken bites 🍯🔥 · with cheesy ramen · 12 min · #weeknight"). A **coach mark** highlights the share (`send`) icon: pulsing/rippling red ring + a bobbing "Tap here 👇" bubble (#E1523D). Tap anywhere advances.
  - **1 — app share menu.** Headline "Open the share menu" / "Tap your app's Share option." Dimmed post + a slide-up sheet (`gluttSheet`) of share circles; the "Share to…" option is coached.
  - **2 — system share sheet.** Headline "Pick Glutt" / "Choose Glutt from the share sheet." iOS-style share sheet with a link preview row (recipe title + "thesapor.com"), the AirDrop/Messages/Mail row, and a coached **Glutt** target (green `skillet` icon). A copy/reading-list list below.
  - **3 — importing (loader).** Headline "Pulling out the recipe…" / "Reading ingredients, steps & macros." Cream screen with 3 bouncing green dots (`gluttBounce`, staggered .16s) over an indeterminate sweeping progress bar (`gluttBar`). Auto-advances to phase 4 after **1800ms**.
  - **4 — saved recipe.** Headline "That's it, it's saved!" / "Glutt captured the full recipe for you." The imported recipe detail: hero photo with a popping "Saved to your recipes" green badge (`gluttPop`), title "Crispy hot honey chicken bites", meta row (12 min · 540 cal · Serves 4), and an INGREDIENTS checklist (3 packs Otoki Cheesy Ramen; 1 lb chicken breast; 1 cup buttermilk; Mozzarella + heavy cream; Hot honey glaze; "+ 4 more ingredients").
- **Bottom CTAs (phase 4):** Primary "Import my first recipe" + secondary "I'll explore on my own" — both finish onboarding (return to screen 0 in the prototype; in production this routes into the app home / first real import).

## Interactions & Behavior
- **Linear advance:** Start (0→1) and every "Continue" advances `screen` by 1; the back button decrements. `screen` is clamped 0–10.
- **Goals gate:** "Continue" on screen 3 is only active when ≥1 goal is selected; disabled state is a non-interactive gray pill.
- **Notification branch:** screen 8 "Turn on notifications" → 9; "Maybe later" → 10. Screen 9 "Allow"/"Not now" → 10. (Entering screen 10 resets `tutPhase` to 0.)
- **Tutorial taps:** In phases 0–2 a tap anywhere on the mini-phone calls advance (`tutPhase+1`). Phase 3 is entered on the tap out of phase 2 and **auto-advances** to phase 4 after 1800ms (clear the timer if the user leaves the screen). "Skip tutorial" jumps to finish.
- **Finish:** Both end CTAs reset to `screen 0, tutPhase 0`. Wire these to your real post-onboarding destination.
- **Videos:** autoplay, loop, muted, playsinline; a mount effect calls `.play()` and swallows rejections (autoplay-block safe).

### Animations & transitions (all defined as keyframes)
- `gluttFade` — screen/element enter: opacity 0 + translateY(12px) → none. ~0.45–0.5s ease. Used on every screen root.
- `gluttSheet` — share sheet slide-up: translateY(100%)→0, 0.4s `cubic-bezier(.2,.9,.3,1)`.
- `gluttPop` — "Saved" badge: scale .7→1.06→1 with fade, 0.5s `cubic-bezier(.2,.9,.3,1.3)`.
- `gluttOrb` — gentle float (translateY 0↔-6px), 5–5.8s, used on notification cards (staggered) and the pointer arrow (1.5s).
- Coach mark = `gluttCoachRipple` (ring scale 1→2.3, fade out, 1.4s) + `gluttPulse` (scale .95↔1.09, 1s) + `gluttCoachBob` (bubble bob, 1s).
- Loader = `gluttBounce` (dots, 1s, staggered .16s/.32s) + `gluttBar` (bar sweep translateX -130%→330%, 1.4s).
- Progress bar fill width transitions `.45s cubic-bezier(.4,0,.2,1)`.
- Selection state changes on goal rows / rule tiles transition ~150–180ms.

## State Management
- `screen: int (0–10)` — current step.
- `tutPhase: int (0–4)` — tutorial sub-step (only meaningful on screen 10).
- `goals: boolean[6]` — multi-select for screen 3.
- `rules: boolean[9]` — multi-select for screen 4.
- One transient timer (`_impT`) drives the 1800ms importing→saved auto-advance; clear it on unmount / leaving screen 10.
- **Props (for staging/preview only):** `showBackButton: boolean` (default true) toggles the chrome back button; `startScreen: enum` jumps to a given screen by name for review. These are prototype conveniences, not production inputs.
- **Data to persist in production:** the selected goals and dietary rules (send to profile/preferences), and notification-permission result. No other data fetching in this flow beyond loading the welcome grid's recipe thumbnails.

## Design Tokens

**Colors**
- Background cream: `#FAF3E7`; surfaces `#FFFDF7`, `#F4EDDC`, `#F1E9D6`; button text cream `#FBF5E9`
- Primary green: `#2E5339`; hover `#356145`; link hover `#3d6d4b`; darker `#244430`, `#3C6B4B`; progress fill `#3E7A50` (dark-bg variant `#7BD48F`); accents `#8FE3A3`, `#6FB183`, `#4E7A5C`; green tint bg `#EAF1E7`
- Coral/red: `#D9483B`, `#E1523D`, gradient partner `#F4906F`
- Amber: `#D99A3C`, `#F3C877`, `#E8C06A`, `#C08A2E`
- Text: heading `#241E19`; base `#2A2420`; list `#3A342C`; muted `#9A9082`, `#8A8072`, `#6E6456`, `#B3A99A`; disabled text `#A79D8B` on disabled bg `#DED6C4`
- iOS system mock: `#1c1c1e`, `#6b6b70`, tint `#0a84ff`, sheet grays `#ECEBED` / `#F9F9FA`
- (9 dietary-tile gradients + shadow colors are listed per-tile under screen 4.)

**Typography**
- Display / headings: **Bricolage Grotesque** (400–700; used at 600/700), tight tracking (-.3 to -1px on large sizes).
- Body / UI: **Nunito** (400–800).
- Icons: **Material Symbols Rounded** (variable `FILL`, `wght`).
- Social-post caption: **Georgia** italic.
- OS mock text: **-apple-system / SF Pro**.
- Key sizes: welcome H1 34; screen H1s 25–29; benefit/notif titles 14.5–18; body/subhead 12.5–14.5; buttons 18–19; small labels/badges 11–13.5.

**Spacing** — screen padding commonly `104px 24px 42px` (top-heavy for chrome); tighter variants 96–98px top on grid screens, 80px on tutorial. Card padding 13–20px. Gaps 9–16px.

**Radius** — pill/button/progress `100px`; video frames `28`; cards & rule tiles `24`; notif cards `22`; welcome grid & goal rows `20`; icon squares `19`; app icons `11`; iOS alert `14`; checkbox `9`; device bezel `46`.

**Shadow** — buttons `0 10px 24px rgba(46,83,57,0.3)` (welcome/Polly go to `0 12px 28px …`); soft cards `0 8px 22px rgba(42,36,32,0.05)`; notif `0 12px 30px rgba(42,36,32,0.1)`; device `0 26px 56px rgba(42,36,32,0.3)`; OS alert `0 24px 60px rgba(42,36,32,0.28)`.

## Assets
In `assets/` (all referenced by the design):
- `hot-honey.png` — recipe photo used throughout the tutorial post, share previews, and the saved recipe card.
- `glutt-intro.mp4` — looping hero video (screens 1 Intro and 6 Polly).
- `glutt-features.mp4` — looping video (screen 7 AI features).

Replace with your own production media. The 11 welcome-grid tiles are placeholders for real recipe thumbnails (dish names listed under screen 0). Icons are Material Symbols Rounded — map each named glyph to your icon system.

## Files
- `Glutt Onboarding.dc.html` — the complete design (all 11 screens + tutorial). Template markup at top, logic class (`Component`) at the bottom `<script>`. **Read this for exact values.**
- `ios-frame.jsx` — the iPhone bezel wrapper the flow renders inside (reference only; use your platform's real device / safe-area).
- `image-slot.js` — the fillable image placeholder used on the welcome grid (reference only).
- `support.js` — the prototype runtime. **Do not port**; it only exists to run the HTML reference.
- `assets/` — the media listed above.
