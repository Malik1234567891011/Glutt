# Glutt

A mobile-first cooking assistant. Import recipes from anywhere, know what's in your kitchen, plan your week, cook with guidance, and track what you actually ate — without the app forcing gym culture on you.

iOS-native: SwiftUI + SwiftData, iOS 17+.

## Project docs

| File | What it is |
|---|---|
| `product.md` | Product vision, principles, MVP scope |
| `ideas.md` | Full feature inventory with priorities |
| `structure.md` | App structure, screens, flows, design direction |
| `plan.md` | Phase-by-phase build plan (start here) |

## Getting started

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open Glutt.xcodeproj
```

Build and run the `Glutt` scheme on an iOS 17+ simulator. Debug builds seed sample data so every screen has content.

## Architecture

- **Local-first**: all data lives on-device in SwiftData. A thin backend comes later (Phase 6) only for AI calls and recipe import scraping.
- **Structure**:
  - `Glutt/App` — entry point, root tab shell, deep-link router (`glutt://` scheme)
  - `Glutt/DesignSystem` — theme tokens + reusable components (warm, cream, deep-green)
  - `Glutt/Models` — SwiftData models: `Recipe`, `PantryItem`, `GroceryItem`, `PlannedMeal`, `Leftover`, `FoodLog`, `CookSession`, `UserPrefs`
  - `Glutt/Features` — one folder per tab: Today, Recipes, Plan, Kitchen, Progress, plus Capture (universal + button)
  - `Glutt/Services` — domain logic (ingredient canonicalization for pantry matching)
- **Tests**: `GluttTests` covers canonicalization and the data layer. CI runs build + tests on every push.

## Current status

Phase 0 complete: project scaffolding, design system, full data model, navigable 5-tab shell with universal action button. See `plan.md` for what's next (Phase 1: recipe library CRUD).
