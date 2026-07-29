# Handoff: Glutt, the app (daily loop + Cook with Polly)

## Overview
Glutt is a warm, food-forward iPhone app (SwiftUI + SwiftData, iOS 17+, **light mode only, portrait only**) for people who genuinely like to cook. It stitches recipe storage, meal planning, grocery lists, pantry inventory, and AI cooking help into one calm loop: **What should I cook? → Do I have what I need? → How do I cook it properly?**

This handoff covers the **shipped daily loop** (3 tabs: Recipes · Discover · Kitchen, with Recipes as home) plus the full-screen **Cook with Polly** voice + camera session that a recipe opens into. The single design board that shows all of it is `Glutt All Screens Board.dc.html`.

## About the design files
The files in this bundle are **design references created in HTML** (Design Components, `*.dc.html`) — prototypes showing intended look and behavior, **not production code to copy directly**. The task is to **recreate these designs in the Glutt codebase's existing SwiftUI environment**, using its established patterns and the design tokens in `Glutt/Glutt/DesignSystem/` (`Theme.swift`, etc.).

To open a prototype locally, open the `.dc.html` file in a browser — `support.js` (the runtime) and `ios-frame.jsx` (the iPhone frame) are included alongside them. Each screen renders inside a 402×874 iOS device frame.

> Note: the HTML mocks deliberately use **Bricolage Grotesque + Nunito**, while the real app currently ships **SF Rounded**. Match the design intent (tight display headings, friendly rounded body); use the team's decision on whether to adopt the new fonts or keep SF Rounded.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, radii, and interactions. Recreate pixel-accurately using the codebase's components and the `Theme` tokens below. Exact hex values are given throughout.

## Strict project rules (carry into `CLAUDE.md`)
1. **NO dashes in UI copy.** No em dashes (—), en dashes (–), or spaced hyphens ( - ) as punctuation. Use commas, periods, or reword. Hyphenated compound words ("gluten-free") are fine.
2. **NO colored shadows.** All shadows are neutral/warm `rgba(42,36,32,·)`. No green- or tomato-tinted shadows on buttons or cards.
3. **On-photo pills/circles are SOLID** (`#FFFDF7` cream), never frosted/translucent/blurred. The user rejected glass effects.
4. **Ingredient rows use the flat food-icon PNGs** in `assets/ing-*.png` (46×46 rounded-13 tile), never generic Material Symbol food glyphs.
5. Tone: warm, friendly, never guilt-trippy.

## Screens / views
The board shows six phones in one "Daily loop" section. Order = the loop, ending in the live cooking session.

### 1. Recipes (home) — "The Feed"
- **Purpose:** the home tab; what to cook tonight.
- **Layout:** single scrolling column. Header ("Your recipes", stat line "132 saved · 18 cooked", settings + add buttons), a "ready to cook tonight" hero, then big single-column recipe cards.
- **Components:** recipe cards with a top-left solid tag pill + top-right favorite heart, title, meta, and a **pantry-match chip** (green `#EAF1E7`/`#2E5339` "You have it all" or "9/11 in pantry"; amber `#FCF0D6`/`#C28C21` when short, "8/12 · need 4"). Source: `Glutt Main Page.dc.html`, `direction="B"`.
- Direction A ("The Cookbook", 2-up grid) also exists in that file but **B was chosen.**

### 2. Recipe detail
- **Purpose:** decide to cook, check pantry, launch cooking.
- **Layout:** hero photo, title/meta, ingredients list, pinned cook action above the tab bar.
- **Components:** **ingredient rows** = flat food-icon PNG in a 46×46 rounded-13 tile (bg `#F4EDDC`, amber `#FCF0D6` when missing) + name + subtitle carrying quantity/status ("1 lb · in your kitchen" / "1 cup · add to groceries"). Pinned **"Cook with Polly"** pill: solid green, `graphic_eq` icon + label, with a light secondary line "Or cook step by step" beneath. Keep it simple. Source: `Glutt Screens.dc.html`, `screen="Recipe detail"`.

### 3. Discover — "Recipe cards"
- **Purpose:** find something new.
- **Layout:** warm cream screen, a tactile deck of recipe cards you flip through.
- **Components:** streak chip, tilted "SAVE" stamp, four consistent circular action buttons (undo · skip · save · recipe). Source: `Glutt Screens.dc.html`, `screen="Discover"`.

### 4. Kitchen
- **Purpose:** manage what you own.
- **Layout:** segmented control Ingredients / Tools / Groceries; search pill; grouped inventory rows.
- **Components:** inventory rows reuse the food-icon tiles + status pills (Full / Half left / Low / Use soon). Source: `Glutt Screens.dc.html`, `screen="Kitchen"`.

### 5. Cook with Polly — Live session  *(new)*
- **Purpose:** the flagship real-time voice + camera AI chef. Full screen, hands-free, launched from Recipe detail. Recreated from the real `Glutt/Glutt/Features/Polly/PollySessionView.swift`.
- **Layout:** full-bleed **camera feed** with a top→bottom dark scrim. Content in a z-stack: top bar, a centered state pill, a spoken caption near the bottom, then a bottom cluster (step card + controls). No large center orb (removed as redundant).
- **Components (exact values):**
  - **Top bar** (`padding:56px 18px 0`, space-between): left 42×42 circle `#241F1A`, border `rgba(244,236,223,0.16)`, `menu_book` icon 21px `#F4ECDF`; center recipe title (Nunito 800, 14px, `#FBF5E9`) + elapsed timer under it (Nunito 700, 12px, `rgba(251,245,233,0.72)`, tabular-nums); right identical circle with `more_horiz`.
  - **State pill** (Live): dark chip `rgba(36,31,26,0.62)`, border `rgba(244,236,223,0.14)`, radius 100px, `graphic_eq` 15px `#8FE3A3` + "Say “Polly” to talk" (Nunito 700, 12.5px, `rgba(244,236,223,0.85)`).
  - **Spoken caption:** centered, max-width 330px, Nunito 600, 15px, line-height 1.36, `rgba(244,236,223,0.94)`.
  - **Step card:** `#FFFDF7`, radius 22, padding 16, shadow `0 12px 32px rgba(42,36,32,0.3)`. Top = 6-segment progress bar (4px tall, radius 2; done = `#2E5339`, remaining = `#E4DAC6`). Row: "STEP 3 OF 6" (Nunito 800, 11.5px, tracking 1.5px, uppercase, `#2E5339`) + right "Up next, glaze" (Nunito 700, 11.5px, `#9A9082`). Title "Sear the chicken" (Bricolage Grotesque 600, 22px, tracking -0.4px, `#241E19`). Body (Nunito 600, 13.5px, line-height 1.42, `#6E6456`). Amber timer pill `#C28C21`, `timer` icon + "Start 3:00 timer" (Nunito 800, 13px, `#FBF5E9`), radius 100px.
  - **Controls** (centered, gap 20px): mute 52×52 circle `#241F1A` (`mic`), **hang-up 64×64 circle `#D9483B`** with `call_end` 29px `#FBF5E9` and shadow `0 10px 24px rgba(42,36,32,0.28)`, camera 52×52 circle `#241F1A` (`videocam` 22px `#8FE3A3`). This is a call metaphor: red hang-up ends the session.
- Source: `Glutt Polly.dc.html`, `state="Live"`.

### 6. Cook with Polly — You said "Polly" (Listening)  *(new)*
- **Purpose:** the wake-word moment. Polly only responds when you say "Polly" (like Siri); the screen shows it is listening. Same session as #5, one moment later.
- **What changes vs. Live:**
  - **Edge border:** a crisp **solid color** border (NOT a soft glow — the user explicitly wanted less glow, more straight color) drawn as a `linear-gradient(135deg, #8FE3A3 0%, #2E5339 36%, #C28C21 70%, #E1523D 100%)` clipped to a 6px inset border via mask-composite, radius 44px, with a subtle opacity pulse (`0.88 ↔ 1`, 2.4s). This reads as "the phone is listening to you."
  - **State pill (Listening):** **solid green** `#2E5339` chip (opaque, not translucent), radius 100px, containing a 4-bar animated waveform (`#8FE3A3`, 3px wide, staggered scaleY 0.9s) + "Listening" (Nunito 800, 13px, `#DFF3DC`).
  - **Speech line:** shows the user's live transcription instead of Polly's caption — "“Polly, is the chicken cooked through yet…”" (Nunito 700, 18px, `#FBF5E9`, trailing ellipsis at 0.5 opacity).
  - Step card and controls are unchanged.
- Source: `Glutt Polly.dc.html`, `state="Listening"`.

## Interactions & behavior
- **Wake word:** Polly is ambient during a session; saying "Polly" transitions Live → Listening (edge border animates in, state pill swaps to the waveform, caption becomes live transcription). After the question resolves it returns to Live. Model these as one session view with a listening state, matching `PollySessionView.swift`.
- **Hang up:** the red `call_end` button ends the session and returns to Recipe detail.
- **Timers:** "Start 3:00 timer" starts a per-step countdown; multiple can run.
- **Edge-border pulse:** opacity `0.88 ↔ 1` over 2.4s ease-in-out, infinite. **Waveform bars:** scaleY `0.3 ↔ 1`, 0.9s ease-in-out, staggered 0.15s.
- **Pantry chips:** green when you have everything, amber when short (see rule in Recurring patterns).

## State management
- **Polly session:** `mode` (live | listening), `elapsed` timer, current `stepIndex` (of total), array of running `timers`, `isMuted`, `isCameraOn`, live `transcript` string, latest Polly `caption`.
- **Home / Discover / Kitchen:** saved recipes, pantry inventory (drives match chips), discover deck index + saved/skipped, kitchen segment (Ingredients/Tools/Groceries).

## Design tokens (from `Glutt/Glutt/DesignSystem/Theme.swift`)
**Colors**
- Background cream `#FAF3E7`; surfaces `#FFFDF7`, `#F4EDDC`, `#F1E9D6`; button/CTA text cream `#FBF5E9` / `#F4ECDF`
- Primary green `#2E5339` (hover `#356145`); green tint `#EAF1E7`; bright accent `#8FE3A3`; active tab glyph `#CFE6CC`
- Tomato `#D9483B` / `#E1523D`; tomato tint `#F7DDD2`
- Amber (need/low/use-soon) `#C28C21`; amber chip bg `#FCF0D6`
- Text: heading `#241E19`, base `#2A2420`, muted `#6E6456` / `#9A9082`
- Border `#E1D7CA`; dark tab bar `#241F1A`, inactive icons `#928377`
**Spacing:** 4 · 8 · 16 · 24 · 32
**Radius:** chip 8, button 12, pill/icon-square 11, segment 14, card 16, photo 18, sheet 24, cardLarge 26, tab-bar-top 30, pills/buttons 100, tag 13
**Type:** Bricolage Grotesque (600/700, tracking -0.3 to -1px) for display; Nunito (400–800) for body/UI; Material Symbols Rounded (filled) for icons
**Shadows (neutral only):** cards `0 8px 20px rgba(42,36,32,0.05)`; buttons `0 10px 24px rgba(42,36,32,0.14)`; board frames `0 30px 70px rgba(42,36,32,0.16)`

## Assets
In `assets/`:
- **Food photos:** `food-*.png` (e.g. `food-hot-honey-rice.png`, used as the Polly camera feed).
- **Ingredient icons:** `ing-*.png` (chicken, milk, scallion, rice, honey, flour, spinach, avocado, beef, olive-oil) — from the 0xGF/food-icons set (free for commercial use). Full set has ~135 more if needed.
- The real codebase also has photos in `Glutt/photos/`.

## Files in this bundle
- `Glutt All Screens Board.dc.html` — the board showing all six phones (open this first).
- `Glutt Polly.dc.html` — Cook with Polly, `state` prop = `Live` | `Listening` (new work).
- `Glutt Main Page.dc.html` — Recipes home, `direction` prop = `A` | `B` (B chosen).
- `Glutt Screens.dc.html` — Recipe detail / Discover / Kitchen, `screen` prop.
- `support.js`, `ios-frame.jsx` — runtime + iPhone frame so the `.dc.html` files open in a browser.
- `assets/` — food photos + ingredient icons.
- `CONTEXT-FOR-NEW-CHAT.md`, `PROJECT-RULES.md` — fuller design language + copy rules.

## Where the real code lives
`Glutt/` (local repo). Orientation: `Glutt/docs/APP-OVERVIEW-FOR-DESIGN.md`. Tokens: `Glutt/Glutt/DesignSystem/`. Polly source: `Glutt/Glutt/Features/Polly/PollySessionView.swift` + `PollySessionSubviews.swift`.
