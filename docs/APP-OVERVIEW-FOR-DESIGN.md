# Glutt — App Overview for the Design Team

*A one-document orientation to what Glutt is, who it's for, every screen it contains, and the visual system it's built on. Read this before touching any screen.*

---

## 1. What Glutt is, in one paragraph

Glutt is a **native iOS cooking assistant** (iPhone only, portrait only, iOS 17+). It's built to answer one loop for people who genuinely like to cook: *What should I cook? → Do I have what I need? → How do I cook it properly? → What did I eat? → What should I cook next?* It combines the useful parts of five app categories — recipe storage, meal planner, grocery list, pantry tracker, and a light nutrition log — into a single calm cooking flow, plus two AI-driven experiences: a **swipeable recipe discovery feed** and **Polly**, a real-time voice-and-camera AI chef that talks you through cooking hands-free.

It is deliberately **not**: a recipe database, a Pinterest clone, a calorie-tracker-first fitness app, or a chatbot where everything is a text prompt. Nutrition/fitness tracking is optional and off by default.

---

## 2. Who it's for

Someone who enjoys cooking, saves recipes from Instagram / TikTok / websites, wants to cook more consistently, and wants an app that understands their **actual kitchen** rather than just storing recipes. They may care about meal planning, groceries, protein, leftovers, or pantry use — but the app must never force gym culture on them.

---

## 3. Product principles (these drive design decisions)

- Cooking **flow** matters more than content volume.
- Reduce thinking **before, during, and after** cooking.
- Mobile-first — the user is likely standing in a kitchen, possibly with wet hands.
- Keep the interface simple even though the app is powerful underneath.
- AI shows up as **useful actions**, not decoration or mandatory chat.
- The app adapts to what the user has, likes, and has cooked before.
- Nutrition is **optional**, never forced.
- Warm, clean, practical, food-focused. **No** generic AI gradients, **no** cartoon-chef mascots (Polly is the one sanctioned exception), **no** dark dashboards, **no** stat overload on the home screen.

---

## 4. Visual identity (the current design system)

Glutt already ships a coherent, intentional design language. **Extend it — don't replace it.** It lives in code at `Glutt/DesignSystem/` (`Theme.swift`, `Typography.swift`, and `Components/`). A recent 9-screen restyle sharpened it toward a "modern cookbook" look (rounded photo cards, pill stats, a dark bottom tab bar). Full spec: `design_handoff_glutt_redesign/README.md`.

**The app is light-mode only.** Dark theme is explicitly backlog — do not design dark variants yet.

### Color tokens (source of truth = `Theme.Colors`)

| Role | Hex (approx) | Token |
|---|---|---|
| App background (cream) | `#F6F0E6` | `background` |
| Card surface (white) | `#FFFFFF` | `card` |
| Primary — herb green | `#265935` | `accent` |
| Secondary — tomato red | `#D9472B` | `tomato` |
| Text primary (warm near-black) | `#261F1A` | `textPrimary` |
| Text secondary (warm gray) | `#66594F` | `textSecondary` |
| Hairline border | `#E0D6C9` | `border` |
| Success / "you have it" tint (sage) | `#E4EFDD` | `successTint` |
| Warning tint (amber) | `#FCF0D6` | `warningTint` |
| Warning text (amber) | `#C28C21` | `warning` |
| Soft tomato tint | `#F7DDD2` | `tomatoTint` |
| Peach decorative panel | `#F7E2D4` | `peachPanel` |
| Cream text on dark/green fills | `#F4ECDF` | `creamText` |
| Segmented-control track | `#EBE2D4` | `segmentTrack` |

Semantic use of accents: **green = you have it / positive / primary action**, **amber = use-soon / time / caution**, **tomato = protein / difficulty / destructive / appetite highlight**.

### Type

**SF Rounded** throughout (`Font.system(design: .rounded)`), heavy weights for titles. Named styles: `gluttLargeTitle`, `gluttTitle`, `gluttHeadline`, `gluttBody`, `gluttCaption`, `gluttCookStep` (28pt, for cook mode), `gluttSectionLabel` (12pt heavy, uppercase, letter-spaced, herb-green — used for FRESH / PANTRY / category headers).

### Shape & spacing

- Radii: chips `8`, standard card `16`, **large photo cards `26`**, nested photo tiles `18`, stat pills / icon chips `11`, segmented track `14`, sheets `24`, dark tab bar top corners `30`.
- Spacing scale: `4 / 8 / 16 / 24 / 32`. Screen horizontal padding ~22–26.
- Soft, low shadows (6–10% black). Cards visibly lift off the cream background.

### Icons

**Phosphor Icons** (a vendored ~80-icon subset, referenced as `Ph.<name>` with `.regular` / `.bold` / `.fill` weights). If you need a new glyph, it must be added to the vendored set — the full 9,000-icon package caused build problems and was removed.

### Signature components (reusable, already built)

Dark bottom tab bar · stat/info pill (three tints) · segmented control · restyled recipe card (photo over tint panel + tag pill) · selectable chip · icon chip (category-tinted rounded square) · page dots · streak/stat pills · empty-state view.

---

## 5. Navigation model

A **6-tab bottom bar** (dark `#241F1A`, full-width, flush to the bottom, 30pt top corners) plus a **floating universal "+" capture button** hovering above the bar.

### The six tabs

| # | Tab | What it is |
|---|---|---|
| 1 | **Today** | Home / daily command center |
| 2 | **Recipes** | The saved recipe library |
| 3 | **Discover** | Full-screen swipeable recipe feed ("Plates") |
| 4 | **Plan** | The weekly meal planner |
| 5 | **Kitchen** | Real-world pantry / groceries / leftovers |
| 6 | **Progress** | Optional tracking layer |

> Note: an older product doc lists "Polly" as a center tab. In the **shipping build** the six tabs are the ones above; **Polly is launched full-screen** (from recipe/cook entry points), not a tab. Discover currently hosts the "Plates" swipe feed.

### The floating "+" capture button (universal action)

One quiet green circle above the tab bar opens a sheet with **five capture actions** — so the app doesn't need extra tabs:

1. **Import recipe** (paste/share a link)
2. **Scan pantry or fridge** (camera)
3. **Log food** (what you ate)
4. **Add grocery item**
5. **Ask what to cook** (opens the assistant)

*(The button hides itself on the Discover tab, which has its own save/skip bar.)*

---

## 6. Every screen / surface, tab by tab

### Tab 1 — Today (`Features/Today/`)
The home screen and daily command center. Contains:
- **Greeting + date** header, Settings gear top-right.
- **"Next up" hero card** — the next planned meal: food photo, "NEXT UP · DINNER" label, title, timing meta ("start by…", total time), missing-ingredient warning strip, and a big green **Cook** button.
- **Quick actions row** — Import · Scan · Log · Ask (tinted circular icon buttons).
- **Nutrition gauges** — *only* if the user turned on tracking (progress rings for calories/protein).
- **Smart cards** (max two) — context nudges like "Use these soon" (peach) and "Leftovers waiting" (sage).
- A **Plates launcher card** linking to Discover.
- First-run **getting-started** guidance when the app is empty.

### Tab 2 — Recipes (`Features/Recipes/`)
The user's saved recipe memory. Includes:
- **Browse list/grid** with a category row and sort/filter, recipe cards (photo, title, source, time, difficulty, "you have the ingredients" signal, optional macros).
- **Recipe detail** — hero photo, favorite heart, segmented **Ingredients / Steps** tabs, numbered steps, servings context.
- **Ingredients checklist** — grocery-style sectioned list (FRESH / PANTRY), tick off what you own, servings stepper rescales quantities, "Add N missing to groceries" footer.
- **Recipe editor** (create/edit), **collections/detail**, a **"discover more like this"** inline video row (`DiscoverView` — YouTube/web recipe videos surfaced from the user's taste tags).
- **AI recipe tools** (see §7): **Adjust recipe**, **Optimize for what I have**, **pre-cook checklist**, semantic search ("that creamy chicken dish").

### Tab 3 — Discover / "Plates" (`Features/Plates/`)
A **full-screen, endless, TikTok-style recipe feed**. Vertical paging browses cards; **tap flips** a card to its recipe; **swipe right saves / swipe left skips** (with button equivalents in a bottom action bar). New pages stream in so it never dead-ends. Shows macro strips, a daily **streak**, and a deck-end card. Diet rules and allergies filter the deck; already-saved recipes are excluded.

### Tab 4 — Plan (`Features/Plan/`)
Weekly meal planning without becoming a heavy calendar.
- **Week summary card** — meals planned, cooking time, items to buy, "you already have 82% of this week's ingredients," leftovers ready, and **generate grocery list from plan**.
- **Day sections** — per-day meal cards, prep/thaw tasks (amber), empty "+ add a meal" slots.
- **"Plan my week" wizard** (`WeekPlannerWizard`) — guided auto-planning.
- **Add-meal sheet.**

### Tab 5 — Kitchen (`Features/Kitchen/`)
The real-world kitchen layer, as a **segmented three-view shell**:
- **Inventory** — fridge/pantry/freezer items with rough quantities (Full / Half left / Almost empty / Out), "use soon" badges, category sections, search. Includes a **camera pantry scan** (AI reads items from a photo).
- **Groceries** — auto-built from recipes/plans, grouped by category, de-duplicated, items you already own removed; manual editing. Has a **Store Mode** for shopping.
- **Leftovers** — track cooked servings, add to a future meal, log as eaten, freeze/reuse, and an AI **"leftover remix"** sheet.

### Tab 6 — Progress (`Features/Progress/`)
Optional, **never guilt-based**. If tracking is off: meals cooked, recipes tried, cooking streak, eating-out frequency, leftovers used, waste reduced, favorite meals. If **Gym Mode** is on: daily calories, protein, planned-vs-actual, weekly consistency.

### Cross-cutting full-screen experiences (not tabs)

- **Onboarding** (`Features/Onboarding/`) — first-run flow: Welcome → Goals → Nutrition preference → Dietary rules → an **interactive import tutorial** (coach marks that walk you through sharing a recipe from another app) → notification primer. Paywall hooks live here.
- **Cook Mode** (`Features/Cook/`) — full-screen, step-by-step guided cooking: progress bar, one big step at a time, per-step ingredients, inline **timers**, screen stays awake, then a **finish** flow (rate, save leftovers, log it).
- **Polly — live AI chef** (`Features/Polly/` + `Services/Polly/`) — the flagship experience. A **full-bleed camera preview** behind a **voice-first overlay**: an animated orb, rolling captions, the current step, live timers, and minimal controls. You **talk to Polly hands-free** while cooking — ask questions, get guidance, and Polly can "watch the pan" via the camera. Screen stays awake and audio keeps playing when the phone locks. Launched full-screen from a recipe.
- **What to Cook assistant** (`Features/Assistant/WhatToCookView`) — a modal: a free-text "just tell me" field, time + mood chips, and AI recommendation cards ("BEST MATCH", "ready now" vs "N items missing", reason chips, open/add-to-plan).
- **Import review** (`Features/Import/`) — after importing a link, a review screen to confirm/clean the parsed recipe before saving.
- **Settings** (`Features/Settings/`) — preferences, nutrition mode, dietary rules, etc.

---

## 7. Where the AI shows up (as actions, not chat)

Glutt leans on AI heavily, but always behind a concrete button. Notable AI-powered actions:

- **Recipe import & parsing** — turn a website/Instagram/TikTok/YouTube link (or screenshot via OCR) into a structured recipe.
- **Optimize recipe for what I have** — adapt a recipe to the user's pantry without ruining it.
- **Adjust recipe** — change servings, swap ingredients, dietary tweaks.
- **Pantry scan** — read fridge/pantry items from a photo.
- **Meal photo estimator** — estimate a logged meal's macros from a photo.
- **What to cook / pantry chef** — recommend meals from what's on hand + taste profile.
- **Leftover remix** — turn leftovers into a new dish.
- **Semantic recipe search** — find by vague memory / flavor / mood.
- **Polly** — real-time conversational voice + vision cooking guidance.
- **Taste profile** — the app learns preferences over time to personalize Discover and recommendations.

---

## 8. The core product loop (design everything to serve this)

1. Save or import a recipe →
2. Find or choose what to cook →
3. Check what ingredients are available →
4. Add missing items to groceries →
5. Cook with guidance (Cook Mode or Polly) →
6. Log what was actually eaten →
7. Save notes, leftovers, feedback →
8. Use all of that to recommend better meals next time.

---

## 9. Platform & technical context designers should know

- **Native iOS, SwiftUI + SwiftData, iOS 17+.** iPhone only, **portrait only**, **light mode only**.
- **Local-first** — data lives on-device; a thin backend (a Vercel proxy) handles AI calls, recipe scraping, and Polly's realtime voice session.
- **Share extension** ("GluttShare") — users import recipes by hitting Share in Instagram/TikTok/Safari and picking Glutt; the recipe lands in the app.
- **Permissions used:** camera (pantry scan, meal photos, Polly's vision), microphone (Polly), notifications (cook-start / prep / daily reminders).
- **Monetization:** paywalls via **Superwall** at onboarding, Polly, and "invent a recipe" hooks. *(Payments are temporarily disabled in the current build pending an App Store agreement — see `docs/REENABLE-PAYMENTS.md`. Paywall screens still exist and are designed surfaces.)*
- **Deep links:** `glutt://` scheme.

---

## 10. Where to find things

| You want… | Look at |
|---|---|
| Product vision & principles | `product.md` |
| Screens, flows, design direction (detailed) | `structure.md` |
| The most recent onboarding design handoff | `design_handoff_onboarding_flow/README.md` + the `Glutt Onboarding.dc.html` reference |
| Live design tokens | `Glutt/DesignSystem/Theme.swift`, `Typography.swift` |
| Reusable components | `Glutt/DesignSystem/Components/` |
| Each screen's code | `Glutt/Features/<TabName>/` |
| The app's own food photography | `Glutt/photos/` and the Xcode asset catalog |

---

*Design north star: it should feel like a **modern cookbook plus a personal cooking assistant** — warm, clean, premium, food-forward, big photos, soft cards, minimal clutter, and calm enough to trust while your hands are covered in flour.*
