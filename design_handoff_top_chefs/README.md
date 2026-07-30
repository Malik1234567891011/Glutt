# Handoff: Top Chefs on the Recipes home

## Overview

Adds a **Top Chefs** feature to Glutt. A horizontal rail of three chef portraits
sits on the Recipes home screen (the first tab, the app's home). Tapping a chef
pushes a chef page listing that chef's five most popular official recipes, using
the same recipe card the home feed already uses.

Chefs in scope, in rail order:

1. Gordon Ramsay
2. Nick DiGiovanni
3. Joshua Weissman

Content is free for all users. No lock or upsell state.

## About the design files

`Glutt Chef Feature Board.dc.html` is a **design reference created in HTML**. It
is a prototype of the intended look, not production code to copy. The task is to
recreate these two screens in the Glutt SwiftUI app using its existing
components, tokens and patterns (`Glutt/DesignSystem/`, `Glutt/Features/`).

The HTML was built by reading the real Swift source, so most of it maps one to
one onto components that already exist. Reuse them. Do not build new card types.

Open the board in a browser to see it. Every phone frame is a real 402 × 874
iPhone viewport and scrolls.

## Fidelity

**High fidelity.** Colors, type, spacing and radii are taken from
`Glutt/DesignSystem/Theme.swift` and `Typography.swift`. Recreate pixel for
pixel using the existing tokens, never raw hex.

## What to build, and what already exists

| Piece | Status |
|---|---|
| `Chef` model: name, portrait, credit line, ordered recipes | New |
| Chef rail in the Recipes feed | New |
| `ChefDetailView` | New |
| `FeedRecipeCard` | Exists, reuse unchanged |
| Stat pills, pantry match, `SectionLabel`, `GluttTabBar` | Exist, reuse unchanged |

## Board contents

Newest work is at the top of the board. Ids are visible badges on each frame.

| Id | What it is |
|---|---|
| **3a** | **Build this.** Recipes home with the chef rail |
| **3b** | **Build this.** Gordon Ramsay's chef page, all five recipes |
| 2a, 2b, 2c | Chef page alternatives. 2a was chosen and became 3b |
| 1a | The Recipes home as it ships today, unchanged, for reference |
| 1b, 1c, 1d | Entry point alternatives. 1b was chosen and became 3a |

Ignore 1b through 2c when implementing. They are kept for design history.

---

## Screen 1: Recipes home with the chef rail (3a)

**File to change:** `Glutt/Glutt/Features/Recipes/RecipesView.swift`

**Purpose:** surface three chefs without disturbing the existing feed.

### Layout

The chef rail is inserted into `feedContent`, between the hero card and the
`SectionLabel(text: listSectionTitle)` that heads the recipe list. Nothing else
on the screen changes. Current order becomes:

1. `header`
2. `searchPill`
3. `filterChips`
4. `heroCard`, "ready to cook tonight"
5. **chef rail, new**
6. `SectionLabel(text: listSectionTitle)`
7. `LazyVStack` of `FeedRecipeCard`

### The rail

- Section label: `SectionLabel(text: "Cook with the pros")`, so 12pt Nunito
  weight 800, uppercase, tracking 1.6, `Theme.Colors.accent`.
  Padding: 18 top, 20 horizontal, 10 bottom.
- Horizontal `ScrollView`, `showsIndicators: false`, `HStack(spacing: 16)`,
  horizontal padding 20, bottom padding 2.
- One item per chef, each a fixed 74pt wide `VStack(spacing: 7)`:
  - Portrait: 64 × 64 circle, `Circle().strokeBorder(Theme.Colors.card, lineWidth: 2.5)`
    on the outside, shadow `Theme.Colors.textPrimary.opacity(0.1)`, radius 13, y 5.
  - Name: `BrandFont.nunito(12, 800)`, `Theme.Colors.heading`, centered,
    line height 1.2, wraps to two lines.
- Whole item is the tap target. 74 × 92 clears the 44pt minimum.
- Tapping pushes `ChefDetailView` on the existing `navPath` `NavigationStack`.

### Cost, and a decision still open

The rail adds about 150pt. That pushes most of the first saved recipe card
behind the tab bar. If that turns out to hurt the feed, the rail moves above
the hero instead, directly under `filterChips`. Confirm with the designer
before changing the order.

### Portraits

The board uses striped placeholder circles with initials because no headshots
were licensed at design time. **Real portraits are required before ship.**
Square crops, face centered, minimum 192 × 192 for a 64pt circle at 3x. Until
they exist, keep the placeholder: `Theme.Colors.surface3` fill with the chef's
initials in `BrandFont.bricolage(20, 700)`, `Theme.Colors.muted`.

---

## Screen 2: Chef page (3b)

**New file:** `Glutt/Glutt/Features/Recipes/ChefDetailView.swift`

**Purpose:** pick one of a chef's five most popular recipes and cook it.

Pushed inside the Recipes tab, so `GluttTabBar` stays visible. Standard
`NavigationStack` push from the rail.

### Layout, top to bottom

**1. Top bar.** Padding 56 top, 20 horizontal, 8 bottom. Reuses the same 42 × 42
circle button as `RecipesView.circleButton`: `Theme.Colors.card` fill,
`Theme.Colors.textPrimary.opacity(0.07)` border at 1.5, shadow 0.05 / radius 10 / y 3.

- Left: back, `arrow_back`, 22pt, `#3A342C`
- Right: `HStack(spacing: 9)` of share, `ios_share` 21pt `#3A342C`, then
  favorite, `favorite` 21pt `Theme.Colors.tomato`

**2. Chef header.** `HStack(spacing: 14)`, padding 10 top, 20 horizontal.

- Portrait: 66 × 66 circle, 2.5 `Theme.Colors.card` border, shadow 0.12 / 13 / 5
- Right column:
  - "Official" pill: `Theme.Colors.greenTint` capsule, 3 vertical / 8 horizontal
    padding, `verified` glyph 13pt plus `BrandFont.nunito(11, 800)`, both
    `Theme.Colors.accent`. 4 bottom margin
  - Name: `BrandFont.bricolage(27, 700)`, `Theme.Colors.heading`,
    line height 1.05, tracking negative 0.6
  - Credit: `BrandFont.nunito(13, 700)`, `Theme.Colors.textSecondary`, 3 top
    margin. Gordon's reads "Michelin chef, London · 5 recipes"

**3. Section label.** `SectionLabel(text: "Most popular")`, padding 22 top,
20 horizontal, 12 bottom.

**4. Recipe list.** `LazyVStack(spacing: 16)`, horizontal padding 20, bottom
padding `GluttTabBar.reservedHeight + 44`.

Each row is **`FeedRecipeCard` unchanged**. The only difference from the home
feed is the tag pill: instead of `recipe.tags.first` it shows the rank.

- Rank 1: `local_fire_department` 14pt in `Theme.Colors.tomato`, then
  "Number 1" in `BrandFont.nunito(12, 800)` `Theme.Colors.heading`
- Ranks 2 to 5: same pill, text only, no glyph

Everything else on the card behaves as it does today, including pantry match,
so `PantryMatcher.match` must run on chef recipes too. That is the reason for
putting chef content in the library rather than in Discover.

### Content, Gordon Ramsay

| # | Title | Summary | Time | Difficulty | Rating | Pantry |
|---|---|---|---|---|---|---|
| 1 | Beef Wellington | Fillet in mushroom duxelles, wrapped in puff pastry | 2 hr 30 | Hard | 4.9 | 6/14 |
| 2 | Pan Seared Salmon | Crisp skin salmon, lemon butter, soft herbs | 18 min | Medium | 4.8 | have it all |
| 3 | Shepherd's Pie | Slow cooked lamb under a browned mash crust | 1 hr 10 | Medium | 4.7 | 9/13 |
| 4 | Spiced Lamb Flatbread | Kofta spiced lamb, yogurt, quick pickled onion | 40 min | Easy | 4.6 | 10/11 |
| 5 | Scrambled Eggs | Low and slow, folded off the heat with creme fraiche | 8 min | Easy | 4.9 | have it all |

Pantry figures are illustrative. In the app they come from `PantryMatcher`.
Nick DiGiovanni's and Joshua Weissman's five each are not written yet.

---

## Interactions

- Rail item tap: `Haptics.selection()`, push `ChefDetailView`
- Chef page back: standard `NavigationStack` pop
- Recipe card tap: push the existing `RecipeDetailView`, same as the feed
- Heart on a chef recipe: **open question.** If chef recipes are not in the
  user's library, favoriting has to either save a copy or be hidden. Resolve
  before building the card's heart on this screen
- Rail scrolls horizontally, no paging, no snap
- No loading or error states. Chef data is bundled, not fetched

## State

- `RecipesView`: no new state. Chefs come from a `@Query` or a bundled
  constant, and navigation reuses `navPath`
- `ChefDetailView`: takes a `Chef`, holds no state of its own

## Design tokens

All of these already exist in `Theme.swift`. Use the tokens, not the hexes.

| Role | Token | Hex |
|---|---|---|
| Background | `Theme.Colors.background` | `#FAF3E7` |
| Card | `Theme.Colors.card` | `#FFFDF7` |
| Secondary surface | `Theme.Colors.surface2` | `#F4EDDC` |
| Tertiary surface | `Theme.Colors.surface3` | `#F1E9D6` |
| Accent | `Theme.Colors.accent` | `#2E5339` |
| Green tint | `Theme.Colors.greenTint` | `#EAF1E7` |
| Tomato | `Theme.Colors.tomato` | `#D9483B` |
| Amber | `Theme.Colors.amber` | `#C28C21` |
| Amber chip | `Theme.Colors.amberChip` | `#FCF0D6` |
| Heading | `Theme.Colors.heading` | `#241E19` |
| Secondary text | `Theme.Colors.textSecondary` | `#6E6456` |
| Muted | `Theme.Colors.muted` | `#9A9082` |

Type: `BrandFont.bricolage` for display, `BrandFont.nunito` for UI. Sizes used
here are 27/700, 21/700, 20/700, 20/600, 13/700, 12/800, 11/800.

Spacing: 4 / 8 / 16 / 24 / 32, screen horizontal padding 20.

Radii: `Theme.Radius.cardLarge` 26 for cards, circles for portraits,
capsules for pills.

Icons: the board uses Material Symbols Rounded because that is what the app
uses. Glyph names referenced: `arrow_back`, `ios_share`, `favorite`, `verified`,
`local_fire_department`, `schedule`, `star`, `shopping_basket`, `check_circle`,
`menu_book`, `auto_awesome`, `skillet`, `search`, `auto_awesome`, `add`,
`settings`, `swap_vert`.

## Copy rules

**No dashes anywhere in UI copy.** No em dashes, en dashes, or spaced hyphens
as punctuation. Use commas, periods, or reword. Hyphenated compound words like
"gluten-free" are fine. This applies to every string in this feature.

## Assets

- `assets/food-*.png`: dish photography, copied from
  `design-doc/glutt-design-context/design_handoff_glutt_app/assets/` in the
  Glutt repo. Standing in for chef recipe photos, which do not exist yet
- Chef portraits: **not supplied.** See the portraits note above
- `ios-frame.jsx`, `support.js`: scaffolding for the HTML board only. Not part
  of the app

## Files in this bundle

- `Glutt Chef Feature Board.dc.html`: the design board, open in a browser
- `ios-frame.jsx`, `support.js`: needed for the board to render
- `assets/`: dish photos used by the board

## Source files the design was built from

- `Glutt/Glutt/App/RootView.swift`, three tab shell, Recipes first
- `Glutt/Glutt/Features/Recipes/RecipesView.swift`, the home screen
- `Glutt/Glutt/Features/Recipes/FeedRecipeCard.swift`, the recipe card
- `Glutt/Glutt/DesignSystem/Theme.swift`, tokens
- `Glutt/Glutt/DesignSystem/Typography.swift`, type ramp and `SectionLabel`
- `Glutt/Glutt/DesignSystem/Components/GluttTabBar.swift`, the dark bar

## Open questions for the designer

1. Real chef portraits, licensing and crops
2. What the heart does on a chef recipe
3. Whether the rail stays under the hero or moves above it
4. Nick DiGiovanni's and Joshua Weissman's five recipes each
