# PLAN.md — Cook4Me Build Plan

iOS-first native app (Swift / SwiftUI / Xcode). This document breaks down the entire build from empty repo to App Store launch, in the order that makes sense.

**Ordering logic:**

1. Foundation first (project, design system, data model) — everything depends on it.
2. Recipes are the root entity — nothing works without a recipe library.
3. Cook Mode next — it's the core promise and generates the data everything else uses.
4. Kitchen (pantry/groceries/leftovers) before Plan — "pantry-aware" is the differentiator and Plan needs grocery generation.
5. Plan + reminders after Kitchen — grocery lists come from plans, reminders come from plans.
6. **Today tab is built LAST of the main tabs** — it composes planned meals, pantry state, leftovers, and logging. Building it first means building it twice.
7. AI features layer on top of real data (semantic search, optimize, "what should I cook").
8. Tracking/Progress/Gym Mode is optional by design, so it ships last before polish.
9. Onboarding, notifications polish, TestFlight, App Store.

---

## Phase 0 — Foundation & Project Setup

### 0.1 Decisions (do these before writing code)
- [ ] Confirm tech stack: SwiftUI + SwiftData (or Core Data) for local persistence
- [ ] Decide local-first vs. cloud-first. Recommendation: **local-first with a thin backend** only for AI calls and recipe import scraping. Sync can come later.
- [ ] Pick backend for AI endpoints (recipe parsing, optimization, semantic search): small server (e.g. Vercel/Fly + Node or Python) or direct LLM API calls from the app with a proxy for key security
- [ ] Pick LLM provider(s) for: recipe extraction, substitutions, semantic search embeddings, food photo estimation
- [ ] Decide on auth: none for v1 (local-only) vs. Sign in with Apple (needed if any server-side per-user state). Recommendation: **Sign in with Apple from day one if a backend exists**, otherwise defer.
- [ ] Minimum iOS version target (recommend iOS 17+ for SwiftData and modern SwiftUI)
- [ ] App name check, bundle ID, Apple Developer account ready

### 0.2 Project scaffolding
- [ ] Create Xcode project, SwiftUI lifecycle, set deployment target
- [ ] Git repo, `.gitignore`, branch convention
- [ ] Folder structure: `Features/`, `Models/`, `Services/`, `DesignSystem/`, `Resources/`
- [ ] SwiftLint / SwiftFormat config
- [ ] Basic CI (build + test on push — Xcode Cloud or GitHub Actions)
- [ ] Set up schemes: Debug / Release / TestFlight
- [ ] Crash reporting + analytics decision (e.g. Sentry / TelemetryDeck — privacy-friendly)

### 0.3 Design system (build before any screens)
- [ ] Color palette: cream/off-white background, deep green or tomato red accent, black/brown text
- [ ] Typography scale (large readable cooking text sizes included)
- [ ] Spacing + corner radius tokens ("soft cards, rounded but not childish")
- [ ] Core components:
  - [ ] `RecipeCard` (image, title, source, time, difficulty, tags, ingredient-match indicator slot)
  - [ ] `MealCard` (planned meal w/ time + status)
  - [ ] Buttons (primary, secondary, destructive, pill/chip)
  - [ ] Filter chips
  - [ ] Section headers, empty states, loading states
  - [ ] Bottom sheet / action sheet style
  - [ ] Confidence indicator component (for import confidence, calorie ranges)
- [ ] App icon + brand pass (placeholder OK for now)
- [ ] Light mode first; dark mode deferred (food apps read better warm/bright)

### 0.4 App shell & navigation
- [ ] Bottom tab bar: Today / Recipes / Plan / Kitchen / Progress
- [ ] Center floating universal "+" action button overlaying the tab bar
- [ ] Universal action sheet (stub all 5 actions): Import recipe / Scan pantry / Log food / Add grocery item / Ask what to cook
- [ ] Placeholder screens for all 5 tabs so the shell is navigable end-to-end
- [ ] Deep link / share extension routing skeleton (needed later for "share from TikTok")

### 0.5 Core data model (get this right early — everything touches it)
- [ ] `Recipe`: title, image(s), source (creator, URL, platform, caption, import date), ingredients[], steps[], servings, prepTime, cookTime, difficulty, tags[], collections[], notes, versions[], confidence score, nutrition (optional), createdAt
- [ ] `Ingredient` (on recipe): name, quantity, unit, optionality, role (acid/fat/binder/protein/etc. — nullable, AI fills later)
- [ ] `Step`: text, duration (for timers), ingredientsUsed[]
- [ ] `PantryItem`: canonical ingredient name, category (produce/meat/dairy/pantry/frozen/spices), rough quantity (full/half/low/out), location (fridge/pantry/freezer), useSoonDate
- [ ] `GroceryItem`: name, quantity, category, sourceRecipes[], checked, optional flag, substitution hint
- [ ] `PlannedMeal`: date, mealType (breakfast/lunch/dinner/snack), optional exact time, recipe OR leftover OR freeform, status (planned/cooked/eaten/skipped/replaced)
- [ ] `Leftover`: source recipe/meal, servingsRemaining, cookedDate, frozen flag
- [ ] `FoodLog`: timestamp, source (cooked meal/leftover/restaurant/quick-add/photo), calories + macros with confidence range, photo, linked PlannedMeal (for planned-vs-actual)
- [ ] `UserPrefs`: dietary rules (halal, allergies, vegan…), disliked ingredients, gym mode on/off, calorie/protein goals, taste profile (grows over time)
- [ ] `CookSession`: recipe, date, servings made, notes, rating, feedback answers
- [ ] Ingredient name canonicalization strategy ("scallions" == "green onions") — define approach now, even if v1 is a simple synonym table
- [ ] Migrations strategy + seed/sample data for development

---

## Phase 1 — Recipes Tab: Library Core (manual first, import next)

### 1.1 Recipe CRUD
- [ ] Manual recipe creation form (title, ingredients, steps, times, servings, image)
- [ ] Recipe detail screen: hero image, meta row (time/difficulty/source), ingredients list, steps list, tags, notes
- [ ] Edit / delete recipe
- [ ] Ingredient scaling on detail view (2 → 4 → 6 servings, fractions handled sanely)
- [ ] Unit conversion toggle (cups↔grams, F↔C, tbsp↔ml)

### 1.2 Library organization
- [ ] Library grid/list of `RecipeCard`s
- [ ] Collections: create, rename, delete, add/remove recipes ("Ramadan meals", "date night")
- [ ] Custom tags: add/remove on recipe, tag management
- [ ] Filter chips: meal type, cuisine, time, protein, difficulty, source platform
- [ ] Sort: recently saved, recently cooked, A–Z, cook time
- [ ] Keyword search (plain text — semantic comes in Phase 6)
- [ ] "Recently saved" and "Cooked before" sections
- [ ] Empty states that teach (e.g. "Import your first recipe")

### 1.3 Recipe notes, ratings, versions
- [ ] Personal notes on recipe ("add more lemon", "too salty")
- [ ] Private rating (taste / effort / would-make-again)
- [ ] Recipe versioning: original preserved, "my version" editable, version switcher on detail screen
- [ ] Cooked-before history section on detail (populated by Cook Mode later)

---

## Phase 2 — Recipe Import (the #1 acquisition feature)

### 2.1 Import infrastructure
- [ ] Backend endpoint (or on-device pipeline) for URL → structured recipe
- [ ] Website import: fetch page, parse schema.org/JSON-LD recipe markup, fallback to LLM extraction from page text
- [ ] LLM extraction prompt + schema validation (title, ingredients w/ quantities, steps, times, servings, image URL)
- [ ] Import confidence scoring: per-field confidence, overall score, flag guessed quantities / unclear steps
- [ ] Original source preservation: creator, link, platform, caption, import date stored on recipe

### 2.2 Import entry points
- [ ] Paste-link flow from universal "+" button
- [ ] iOS Share Extension: share from Safari/TikTok/Instagram/YouTube directly into the app
- [ ] Screenshot/photo import: photo → OCR (Vision framework) → LLM structuring
- [ ] Clipboard detection ("Looks like you copied a recipe link — import it?")

### 2.3 Social/video import (hard, do after website import works)
- [ ] TikTok/Instagram/YouTube link handling: pull caption, description, thumbnail
- [ ] Video transcript extraction (audio → text) where feasible
- [ ] Combine caption + transcript + on-screen text into one LLM extraction pass
- [ ] Graceful degradation: if extraction is partial, save what we got with low confidence flags

### 2.4 Import Review screen (trust is the product)
- [ ] Preview card of extracted recipe
- [ ] Per-field uncertainty highlighting (missing quantities, ambiguous steps)
- [ ] Confidence score display
- [ ] Inline editing of any field before save
- [ ] "Clean up with AI" action (re-run extraction with user hints)
- [ ] Post-save prompts: Add to plan? / Add to collection? / Check my ingredients? (the last one activates after Phase 3)
- [ ] "Needs cleanup" section in Recipes tab for low-confidence imports

---

## Phase 3 — Cook Mode (the core promise)

### 3.1 Cook Mode screen
- [ ] Full-screen step-by-step view: one step at a time, big text
- [ ] Screen stays awake (`isIdleTimerDisabled`)
- [ ] Swipe / tap navigation between steps, progress indicator
- [ ] Ingredients-for-this-step shown inline on each step
- [ ] Full ingredient list accessible via pull-up sheet at any time
- [ ] Scaled quantities respected (if user scaled servings)

### 3.2 Timers
- [ ] Auto-detect durations in step text ("simmer 10 minutes" → timer chip)
- [ ] One-tap start timer per step
- [ ] Multiple concurrent timers with labels
- [ ] Live Activity / Dynamic Island timer support
- [ ] Local notification when a timer ends (works if app is backgrounded)

### 3.3 End-of-cooking flow (this generates the app's data)
- [ ] "How many servings did you make?"
- [ ] "How much did you eat?" → creates `FoodLog` entry
- [ ] "Save leftovers?" → creates `Leftover` with remaining servings
- [ ] Quick note + rating prompt (skippable, never naggy)
- [ ] Record `CookSession`, update cooked-before history and streaks
- [ ] After-cooking feedback (1–2 taps max: "Worth the effort?" "Make again?") feeding taste profile

### 3.4 Cook Mode extras (post-core, can slip to later phase)
- [ ] Voice control: "next step", "repeat", "start timer" (on-device speech recognition)
- [ ] "What does simmer mean?" — technique help sheet (static glossary first, AI later)

---

## Phase 4 — Kitchen Tab: Inventory, Groceries, Leftovers

### 4.1 Kitchen shell
- [ ] Segmented control: Inventory / Groceries / Leftovers

### 4.2 Inventory (manual first, camera scan later)
- [ ] Add item: name autocomplete from canonical ingredient list, category, rough quantity (full/half/almost empty), location
- [ ] Grouped list by category (Proteins, Produce, Dairy, Pantry, Frozen, Spices)
- [ ] Quick quantity adjust (tap to cycle full → half → low → out)
- [ ] "Use soon" flagging: manual flag + simple heuristics by category (e.g. fresh greens ~5 days)
- [ ] Use-soon section pinned at top
- [ ] Bulk add flow (type many items fast — comma separated or rapid-fire entry)
- [ ] Search inventory

### 4.3 Pantry-aware recipe matching (the differentiator — unlocks everything)
- [ ] Ingredient matcher: recipe ingredients vs. pantry items via canonical names + synonym table
- [ ] "You have 6/9 ingredients" indicator on every `RecipeCard`
- [ ] Recipe detail: have/missing breakdown with checkmarks
- [ ] "Add missing to groceries" one-tap action
- [ ] Shopping-before-cooking checklist (pre-cook screen: what's missing + possible swaps)

### 4.4 Groceries
- [ ] Manual add/edit/remove items
- [ ] Auto-categorize into Produce / Meat / Dairy / Pantry / Frozen / Spices
- [ ] Generate from recipe: missing ingredients → list
- [ ] Combine duplicates across recipes ("2 onions" + "1 onion" = "3 onions", unit-aware)
- [ ] Pantry-aware: items already in inventory removed or flagged
- [ ] Item detail: which recipe(s) need it, optional flag, substitution hint
- [ ] Check-off interaction with satisfying animation, checked items sink to bottom
- [ ] Store Mode: simplified big-tap shopping UI
- [ ] Post-shopping flow: "Add bought items to inventory?" one-tap confirm (closes the inventory loop)

### 4.5 Leftovers
- [ ] Leftover list: dish, servings remaining, cooked date, freshness hint
- [ ] Created automatically from Cook Mode end flow
- [ ] Manual leftover entry
- [ ] Actions per leftover: Add to plan / Log as eaten (decrements servings) / Freeze / Delete
- [ ] Frozen section
- [ ] Leftover staleness nudge ("Beef stew from Monday — use it soon")

### 4.6 Camera pantry scan (AI feature — after manual flows are solid)
- [ ] Camera capture flow from "+" button
- [ ] Photo → vision model → candidate ingredient list
- [ ] Confirmation flow: user swipes/taps to confirm or reject guesses (never auto-commit)
- [ ] Merge confirmed items into inventory (update quantities if item exists)
- [ ] Video scan (stretch: frame sampling → same pipeline)

---

## Phase 5 — Plan Tab: Meal Planning & Reminders

### 5.1 Week + day views
- [ ] Week view: stacked day sections with meal cards (NOT a dense calendar grid)
- [ ] Day detail view: meals with optional exact times, prep tasks, nutrition preview (if gym mode)
- [ ] Add recipe to a day/meal-type from Plan, from recipe detail, and from import flow
- [ ] Add leftovers to a slot (pulls from Leftovers)
- [ ] Add freeform meal ("eating out", "leftover pizza")
- [ ] Drag/move meals between days/slots
- [ ] Meal status: planned / cooked / eaten / skipped / replaced
- [ ] Week summary header: planned meals count, est. cooking time, grocery status, protein-on-track (gym mode only)

### 5.2 Grocery generation from plan
- [ ] "Generate grocery list" from selected days/whole week
- [ ] Reuses Phase 4 pipeline: dedupe, combine, pantry-aware filtering
- [ ] Re-generate handles already-checked items gracefully (no duplicates, no wiping progress)

### 5.3 Reminders & notifications
- [ ] Notification permission flow (asked in context, not at launch)
- [ ] Cooking start reminders: compute start time = meal time − (prep + cook + buffer)
- [ ] Prep-ahead reminders: thaw / marinate / soak detection (keyword heuristics first, AI later)
- [ ] Use-soon ingredient reminders (from inventory)
- [ ] Leftover reminders
- [ ] Notification settings screen (per-type toggles, quiet hours)
- [ ] All reminders deep-link to the relevant screen

### 5.4 Guided week planning (manual-first, AI-assisted later in Phase 6)
- [ ] "Plan my week" wizard: days? meals per day? meal prep or fresh? use leftovers?
- [ ] Draft week from saved recipes (simple heuristics: variety, pantry match, recently liked)
- [ ] Swap-a-card interaction to replace suggestions
- [ ] Confirm → meals planned + optional grocery generation in one flow

---

## Phase 6 — AI Layer (semantic search, optimize, assistant)

> Prereq: real recipe data, pantry data, and cook history exist. AI features now have substance to work with.

### 6.1 AI service foundation
- [ ] Backend proxy for LLM calls (API key security, rate limiting, cost logging)
- [ ] Embedding pipeline: generate embeddings on recipe save/import (title, ingredients, tags, notes, flavor descriptors)
- [ ] Local vector storage + similarity search (or server-side if backend-first)
- [ ] Prompt/response schema validation everywhere (no free-text parsing in app code)
- [ ] Offline/failure fallbacks for every AI feature (app must work without AI)

### 6.2 Semantic recipe search (killer feature #1)
- [ ] Natural-language search box behavior in Recipes tab ("that creamy lemon chicken thing")
- [ ] Hybrid search: keyword + embedding similarity, merged ranking
- [ ] Search by vague memory: flavor, texture, mood, "the beef thing from last month" (uses cook history dates)
- [ ] Results explain why they matched (chips: "creamy", "lemon", "cooked 3 weeks ago")

### 6.3 Optimize Recipe For What I Have (killer feature #2)
- [ ] Entry points: recipe detail, pre-cook checklist, Today card
- [ ] Input: recipe + pantry inventory + dietary rules → adapted recipe
- [ ] Smart substitutions with explanations (why the swap works, what changes)
- [ ] Do-not-substitute warnings for essential ingredients
- [ ] Cuisine-aware guardrails (no soy-sauce-in-carbonara nonsense)
- [ ] Output saved as a recipe **version** ("pantry version") — original untouched
- [ ] Side-by-side diff view: original vs. optimized

### 6.4 "What should I cook?" assistant (killer flow)
- [ ] Entry: Today tab button + universal "+" sheet
- [ ] Voice mode: open the app and just talk — "fuck I'm in a rush, what can I cook in 30 mins?",
      "craving something savory with chicken", "I want something really sweet" → speech-to-text →
      assistant parses constraints (time, mood, ingredient) → same recommendation cards
- [ ] Quick context capture: time available, hungry now/later, use what's home?, lazy/chef mode, gym goal (if enabled)
- [ ] Recommendation engine combines: pantry match, use-soon items, taste profile, recency, time constraint, dietary rules
- [ ] Returns 3–5 option cards: best match / fastest / high-protein / uses use-soon items / wildcard
- [ ] Each card: ingredient match ratio, missing items, est. start time
- [ ] Actions: Cook now / Add to plan / Optimize / Shuffle
- [ ] Use-what-I-have suggestions surface (pantry → recipes ranked by match %)
- [ ] Pantry cleanout mode (maximize use-soon ingredient usage)

### 6.5 Taste profile learning
- [ ] Signals: ratings, after-cooking feedback, repeats, skips, imports, search queries
- [ ] Stored taste profile (cuisines, flavors, protein preferences, effort tolerance)
- [ ] Profile feeds recommendation ranking
- [ ] User-visible & editable ("You seem to love: creamy, spicy, one-pan") — no black box

### 6.6 AI chat surfaces (contextual, not a giant chat tab)
- [ ] Chat with recipe library ("which recipes use chicken thighs and yogurt?")
- [ ] Chat with pantry ("what can I make with chicken, rice, spinach?")
- [ ] Keep as contextual sheets launched from relevant screens

---

## Phase 7 — Food Logging & Progress Tab

### 7.1 Food logging
- [x] Log flow from "+" button: photo / search / quick-add / leftovers / repeat frequent meal
- [x] Quick-add common foods (eggs, protein shake, coffee, rice bowl…)
- [x] Restaurant/fast-food logging (manual + restaurant toggle; "meal memory" via frequents)
- [x] Photo calorie estimation: photo → GPT-4o vision → estimate with **confidence range** ("likely 600–700 cal") + editable before logging
- [x] "Was this instead of a planned meal?" — replace planned meal (status → replaced) or log as extra
- [ ] Photo of leftovers → estimate servings remaining
- [x] Manual correction always available, never buried
- [x] Log leftovers as eaten (links to Leftover, decrements servings)
- [ ] Barcode scan → nutrition lookup (open food database) — post-beta
- [ ] Nutrition label scan (Vision OCR → macros) — post-beta
- [x] Every log updates Today timeline + Progress

### 7.2 Planned vs. actual (killer feature)
- [ ] Each PlannedMeal resolves to: eaten as planned / replaced (with what) / skipped / partial
- [ ] One-tap resolution from Today timeline
- [ ] Day reconciliation is calm and judgment-free (no red angry numbers)

### 7.3 Recipe nutrition
- [ ] Calculate calories/macros from recipe ingredients (nutrition DB lookup per ingredient + LLM fallback)
- [ ] Per-serving values, respects scaling
- [ ] Transparency: show which values are exact vs. estimated
- [ ] Shown on cards/detail only when gym mode (or light tracking) is on

### 7.4 Progress tab — cooking-only mode (default)
- [ ] Meals cooked this week
- [ ] Recipes tried (new vs. repeat)
- [ ] Cooking streak
- [ ] Eating-out frequency
- [ ] Leftovers used / food-waste insight
- [ ] Favorite meals (by rating + repeats)
- [ ] Weekly recap card (shareable later)

### 7.5 Progress tab — gym mode
- [ ] Gym mode toggle + goal setup (calories, protein; bulk/cut presets)
- [ ] Today: calories + protein vs. goal
- [ ] Planned vs. actual view
- [ ] Weekly consistency view
- [ ] Trends over time (simple charts, Swift Charts)
- [ ] No-shame design pass: calm copy, ranges not false precision, no guilt streak-breaking language

---

## Phase 8 — Today Tab (the command center — built last, composes everything)

### 8.1 Header & next meal
- [x] Greeting + date header
- [x] "Next up" meal card: recipe, meal time, computed start-cooking time
- [x] Missing-ingredients line with available swaps ("Missing: heavy cream · Swap: Greek yogurt + butter")
- [x] Card actions: Cook / Optimize / Add missing to list
- [x] Empty state: "Nothing planned — what should I cook?" → assistant

### 8.2 Timeline & smart cards
- [x] Today timeline: breakfast/lunch/dinner/snacks, planned vs. actually eaten, tap to resolve
- [x] Quick action row: Import / Scan / Log / Ask what to cook
- [x] Leftovers reminder card ("2 servings of beef stew left") — with one-tap "Eat one" logging
- [x] Use-soon alert card ("Spinach needs using") → opens assistant
- [x] Optional nutrition summary strip (gym mode only, hidden otherwise)
- [x] Smart card priority logic (use-soon first, then leftovers; max two cards)

### 8.3 Make it the launch screen
- [x] App opens to Today
- [x] Performance pass: Today must render instantly from local data (all local SwiftData queries, no async work)
- [ ] Widget (stretch): next meal + start time on home screen — deferred to post-MVP

---

## Phase 9 — Onboarding & First-Run Experience

- [x] Screen 1: "What do you want this app for?" (multi-select goals)
- [x] Screen 2: Food rules (halal, no pork, vegan, vegetarian, gluten-free, allergies, dislikes)
- [x] Screen 3: Nutrition tracking choice (no / light / gym mode)
- [x] Screen 4: Import your first recipe (paste link / share extension / starter pack)
- [x] Starter recipe pack for users with nothing to import (6 easy recipes)
- [x] Skip everything possible — learn from usage instead (Skip always visible, every screen optional)
- [x] Allergy safety: allergy warnings wired through recipes, suggestions, substitutions (DietGuard service)
- [x] Halal mode: filtering + substitution behavior wired through suggestions and optimize
- [x] Permission priming screens (notifications, camera) shown in context, not in onboarding (already the case: notifications prompt on first reminder, camera on first scan)

---

## Phase 10 — Quality, Beta & Launch

### 10.1 Hardening
- [ ] Empty/error/loading states audit on every screen
- [ ] Offline behavior audit (everything except AI works offline)
- [ ] AI failure fallbacks verified (timeouts, bad responses, no crash, helpful copy)
- [ ] Performance: large libraries (500+ recipes), image caching, list scrolling
- [ ] Accessibility: Dynamic Type (critical in Cook Mode), VoiceOver on main flows, contrast
- [ ] Data export / delete-my-data
- [ ] Unit tests: ingredient matching, grocery dedupe/combining, scaling math, start-time computation
- [ ] UI tests: import → save → plan → grocery → cook → log loop

### 10.2 Beta
- [ ] TestFlight internal build
- [ ] Feedback channel in-app (shake to report or simple form)
- [ ] External beta (10–50 real cooks)
- [ ] Instrument the core loop funnel: import → cook → log → return next day
- [ ] Two to three feedback/fix cycles; cut features that confuse rather than fix

### 10.3 App Store launch
- [ ] App Store Connect setup, privacy nutrition labels, data usage declarations
- [ ] Screenshots + preview video (show the loop: import → optimize → cook)
- [ ] App name / subtitle / keyword (ASO basics)
- [ ] Pricing decision: free vs. freemium (AI features as the paid layer is the natural split)
- [ ] Paywall implementation if freemium (StoreKit 2)
- [ ] Review prompt strategy (after a successful cook session, never during)
- [ ] Submit, respond to review, launch

---

## Post-MVP Backlog (explicitly NOT in v1)

Ordered roughly by value:

1. Video pantry scan (full video → inventory) — **photo version SHIPPED pre-beta**: one photo → GPT-4o vision lists candidates → user confirms/untoggles + sets rough amounts → inventory updates (merges with existing items); video stays post-MVP
2. Voice cooking assistant full conversational mode ("substitute cream?")
3. Trending recipe discovery + trend-pantry matching
4. Multi-recipe cooking schedule / smart prep sheet for menus
5. Meal-plan auto-balancer (calories/protein/budget across the week)
6. Budget mode (cost per serving, cheap alternatives)
7. ~~Leftover transformation ideas~~ → **SHIPPED pre-beta**: "Remix" button on every leftover; offline idea table + LLM personalization with pantry/rules; plan for tomorrow + add needs to grocery list
8. ~~Recipe health adjustment~~ → **SHIPPED pre-beta (small version)**: "Adjust with AI" on recipe detail — higher protein / lighter / cheaper / match my food rules; saves as a version with a change list
9. Freezer deep tracking, expiry intelligence
10. Collaborative household pantry + family meal planning
11. ~~Recipe sharing to friends~~ → **SHIPPED pre-beta (simple form)**: share button on recipe detail sends a clean cook-from-it text card (no accounts, no feed)
12. Social: meal posts, private friend groups, Strava-style feed
13. Creator/community published recipes
14. Occasion planning (dinner party, Ramadan iftar, meal-prep Sunday)
15. Apple Watch app (timers, grocery check-off)
16. iCloud sync / multi-device
17. Android
18. Instacart / local store integration: one tap sends the grocery list to a delivery service or
    pre-fills a cart at a store near the user (some apps already do this — big mental-load win)
19. Proper dark theme — app is deliberately light-only for now (locked via
    `UIUserInterfaceStyle: Light` in both app + share-extension Info.plists;
    a real dark palette needs its own design pass)

---

## Milestone Summary

| Milestone | Phases | What exists at the end |
|---|---|---|
| M1: Skeleton | 0 | Navigable app shell, design system, data model |
| M2: Recipe brain | 1–2 | Save, organize, and import recipes from links/screenshots with confidence review |
| M3: Actually cook | 3 | Cook Mode with timers; cooking generates logs + leftovers |
| M4: Real kitchen | 4 | Inventory, pantry-aware matching, smart grocery list, leftovers |
| M5: The week | 5 | Meal plan, grocery generation from plan, cooking/prep reminders |
| M6: It gets smart | 6 | Semantic search, optimize-for-what-I-have, "what should I cook" |
| M7: Close the loop | 7 | Food logging, planned vs. actual, Progress (both modes) |
| M8: Command center | 8 | Today tab composes everything; app opens to it |
| M9: Ready for humans | 9–10 | Onboarding, hardening, TestFlight, App Store |

**The core loop must work end-to-end by M5 even with zero AI:** import → plan → groceries → cook → leftovers. AI (M6) makes it magical; it must not be load-bearing.
