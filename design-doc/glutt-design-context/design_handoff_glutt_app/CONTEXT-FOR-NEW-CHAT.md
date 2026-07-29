# Glutt — design context (paste this into a new chat)

## What Glutt is
A native iPhone app (SwiftUI + SwiftData, iOS 17+, light mode only, portrait only) for people who genuinely like to cook. It stitches recipe storage, meal planning, grocery lists, pantry/inventory, and AI cooking help into one calm loop: **What should I cook? → Do I have what I need? → How do I cook it properly? → What did I eat? → What next?**

The **shipped build is 3 tabs**, with **Recipes as the home screen** (an older six-tab "Today" home was cut). The three tabs are **Recipes · Discover · Kitchen**. AI never appears as a chatbot you must talk to; it lives behind concrete buttons (import a recipe, adapt to pantry, scan fridge, estimate macros, semantic search). Two flagship experiences: **Polly** (real-time voice + camera AI chef, full-screen) and **Cook Mode** (simpler guided one-step-at-a-time).

The real codebase is attached as a local folder named **`Glutt/`**. Orientation doc: `Glutt/docs/APP-OVERVIEW-FOR-DESIGN.md`. Design tokens: `Glutt/Glutt/DesignSystem/`. Real food photos: `Glutt/photos/`.

## Design language (this is the important part)
Warm, clean, food-forward, a modern cookbook crossed with a personal cooking assistant. Soft rounded cards, big food photos, friendly rounded type. **Light mode only.**

**Fonts** (committed): **Bricolage Grotesque** for display/headings (600/700, tight tracking -0.3 to -1px), **Nunito** for body/UI (400–800). Icons: **Material Symbols Rounded** (filled). NOTE: the real app currently ships SF Rounded; these designs deliberately moved to Bricolage + Nunito.

**Core colors**
- Background cream `#FAF3E7`; surfaces `#FFFDF7`, `#F4EDDC`, `#F1E9D6`; button text cream `#FBF5E9`
- Primary green `#2E5339` (hover `#356145`); green tint bg `#EAF1E7`; bright accent `#8FE3A3`
- Tomato/coral accents `#D9483B`, `#E1523D`
- Amber (pantry "need"/low) `#C28C21`, chip bg `#FCF0D6`
- Text: heading `#241E19`, base `#2A2420`, muted `#9A9082` / `#6E6456`
- **Dark tab bar** `#241F1A`, rounded top corners (30px), inactive icons `#928377`, active `#CFE6CC`/`#F4ECDF`

**Shape/shadow**: pills & buttons radius 100px; cards radius 22–26; icon squares 11–19. **All shadows are neutral/warm** `rgba(42,36,32,·)` (e.g. cards `0 8px 20px rgba(42,36,32,0.05)`, buttons `0 10px 24px rgba(42,36,32,0.14)`). **No colored (green/tomato-tinted) shadows anywhere** — the user explicitly does not want colored shadows on buttons.

**Copy rule (strict): NO dashes as punctuation.** No em dashes, en dashes, or spaced hyphens. Use commas, periods, or reword. Hyphenated compound words (gluten-free) are fine. Warm, friendly, never guilt-trippy tone. (Also in `CLAUDE.md`.)

## Recurring UI patterns to reuse
- **Pantry-match chip** on every recipe card: green `#EAF1E7`/`#2E5339` when you have everything ("You have it all" / "9/11 in pantry"), amber `#FCF0D6`/`#C28C21` when short ("8/12 · need 4").
- **Tag pill** top-left on photo + **favorite heart** top-right. NOTE: these are now **SOLID** (`#FFFDF7` cream), **not** frosted glass. The user disliked translucent/blurred backgrounds, so all on-photo pills/circles use solid fills.
- **Ingredient rows** (recipe detail + Kitchen inventory): a **flat colorful food-icon PNG** in a 46×46 rounded-13 tile (bg `#F4EDDC`, amber `#FCF0D6` when the item is missing), then name + a subtitle that carries the quantity/status ("1 lb · in your kitchen" / "1 cup · add to groceries"). Icons come from the **0xGF/food-icons** set (free for commercial use), baked into `assets/ing-*.png`. Do NOT go back to generic Material Symbol food glyphs — the user rejected those as "too generic."
- **Cook actions** (recipe detail, pinned above tab bar): one **simple solid-green pill** "Cook with Polly" (`graphic_eq` waveform icon + label), with a light secondary text line "Or cook step by step" beneath. Keep it simple; earlier busy versions (orb + subtitle + waveform) were rejected.
- **Section labels**: Nunito 800, 12px, letter-spacing 1.6px, uppercase, green `#2E5339`.
- **Search/ask pill**: cream, rounded 100px, search icon left + `auto_awesome` (green) right for semantic/AI search.
- Phones render inside an iOS device frame via `ios-frame.jsx` (`IOSDevice`, 402×874).

## What's already been designed (all live in this project, in `uploads/glutt-design-context/`)
1. **`Glutt Onboarding.dc.html`** + `Glutt Onboarding Board.dc.html` — full 11-screen first-run onboarding. Dev handoff in `design_handoff_onboarding_flow/`. (NOTE: still has the old green button shadows; not yet neutralized.)
2. **`Glutt Main Page.dc.html`** + `Glutt Main Page Board.dc.html` — reimagined Recipes home, two directions behind a `direction` prop. **User chose Direction B, "The Feed"** (a "ready to cook tonight" hero + big single-column cards). Direction A ("The Cookbook", 2-up grid) also exists. Solid pills + neutral shadows applied to both.
3. **`Glutt Screens.dc.html`** + `Glutt App Board.dc.html` — the Feed direction across the app, switched via the `screen` prop:
   - **Recipe detail** — hero, ingredients with food-icon tiles + pantry match, simplified "Cook with Polly" bar.
   - **Discover** — NOW the **"Recipe cards"** design (warm cream, a tactile deck of recipe cards you flip through, streak chip, tilted SAVE stamp, four consistent circular action buttons: undo · skip · save · recipe). The old dark swipe deck was replaced. The Deck/Videos toggle was parked behind the filter icon to declutter (not yet designed as its own view).
   - **Kitchen** — Ingredients/Tools/Groceries; inventory rows use the food-icon tiles with Full/Half/Low/Use-soon pills.
4. **`Glutt Home Flow Board.dc.html`** — the main working board (canvas, pan/zoom): Recipes home → Opening a recipe → Discover → Kitchen, side by side. This is the one to open to see the current app.
5. **`Glutt Discover Redesign.dc.html`** — the A/B exploration for Discover (A = immersive dark full-bleed, B = recipe cards). **B was chosen** and folded into `Glutt Screens.dc.html`; keep this file as the record.

## Assets added this session
Flat food-icon PNGs in `assets/`: `ing-chicken`, `ing-milk`, `ing-scallion`, `ing-rice`, `ing-honey`, `ing-flour`, `ing-spinach`, `ing-avocado`, `ing-beef`, `ing-olive-oil` (from 0xGF/food-icons; the full set has 135 across proteins/veg/fruit/dairy/grains/nuts/herbs/condiments if you need more).

## How these files are built (so the new chat matches)
- Every design is a **Design Component** (`Name.dc.html`) authored with `dc_write` / `dc_html_str_replace` / `dc_js_str_replace`. Template is inline-styled markup between `<x-dc>` tags; logic is `class Component extends DCLogic`. Board files mount screens with `<dc-import name="…">`; boards set `<meta name="design_doc_mode" content="canvas">` for pan/zoom.
- **Inline styles only**, no CSS classes (except `@font-face`/keyframes/resets and the `.ms` Material Symbols helper in `<helmet>`). Real photos in `assets/` (`food-*.png`), ingredient icons in `assets/ing-*.png`.
- Screens take a `board` boolean prop (true = bare frame for the board, false = centered on a desk background) plus an enum prop (`screen` or `direction`) to pick what to show.
- NOTE: this folder ships its own `support.js` (an older DC runtime the existing files were authored against) — keep editing against it; don't replace it.

## Still to design (candidates for the next chat)
Polly (live AI chef, full-screen) · Cook Mode (guided step-by-step) · Plan (weekly meal planner) · What-to-Cook assistant · Import review · Settings · Progress · a paywall. Also open: the Discover **Videos** view, and neutralizing the Onboarding button shadows for consistency.

## Good first message for the new chat
> "I'm designing Glutt, a warm cream + herb-green iOS cooking app. Design system: Bricolage Grotesque headings, Nunito body, cream `#FAF3E7`, green `#2E5339`, tomato `#D9483B`, dark rounded tab bar `#241F1A`, soft rounded cards, big food photos, light mode only. Strict rules: NO dashes in copy, NO colored shadows on buttons (neutral warm shadows only), on-photo pills are solid not frosted, and ingredient rows use the flat food-icon PNGs in `assets/ing-*.png` (not generic Material glyphs). The real codebase is in the local folder `Glutt/` (see `Glutt/docs/APP-OVERVIEW-FOR-DESIGN.md`). Onboarding, the Recipes home (Feed), Recipe detail, the Recipe-cards Discover, and Kitchen are already designed; open `Glutt Home Flow Board.dc.html` to see them. I want to design [NEXT THING]." Then attach the `Glutt/` folder and reference the existing `.dc.html` files.
