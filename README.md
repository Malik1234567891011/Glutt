# Glutt

A mobile-first cooking assistant. Import recipes from anywhere, know what's in your kitchen, plan your week, cook with guidance or live with Polly (a realtime voice + camera AI chef), and track what you actually ate — without the app forcing gym culture on you.

iOS-native: SwiftUI + SwiftData, iOS 17+.

## Project docs

| File | What it is |
|---|---|
| `docs/product.md` | Product vision, principles, MVP scope |
| `docs/structure.md` | App structure, screens, flows, design direction (source of truth for the current nav/tabs) |
| `docs/AI-PROXY-SETUP.md` | Vercel AI proxy: deploy, env vars, endpoints |
| `docs/REENABLE-PAYMENTS.md` | Subscriptions re-enablement status |

## Getting started

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open Glutt.xcodeproj
```

Build and run the `Glutt` scheme on an iOS 17+ simulator. Debug builds seed sample data so every screen has content.

## Architecture

- **Local-first**: all data lives on-device in SwiftData. A thin Vercel proxy (`vercel-ai-proxy/`, see `docs/AI-PROXY-SETUP.md`) handles AI calls and recipe import scraping — no accounts, no sync backend.
- **Structure**:
  - `Glutt/App` — entry point, root tab shell, deep-link router (`glutt://` scheme)
  - `Glutt/DesignSystem` — theme tokens + reusable components (warm, cream, deep-green)
  - `Glutt/Models` — SwiftData models: `Recipe`, `PantryItem`, `GroceryItem`, `PlannedMeal`, `Leftover`, `FoodLog`, `CookSession`, `UserPrefs`
  - `Glutt/Features` — one folder per tab: Today, Recipes, Polly (live cooking sessions), Plan, Kitchen, Progress, plus Capture (universal + button)
  - `Glutt/Services` — domain logic: ingredient canonicalization/pantry matching, AI (import cleanup, pantry chef, recipe adjust, Ask Glutt), recipe import pipeline, Polly session/memory
- **Tests**: `GluttTests` covers canonicalization, the data layer, and AI/LLM client behavior. CI runs build + tests on every push.

## Current status

Core loop is built and shipping: recipe import (link/screenshot/video), Cook Mode,
pantry-aware planning/groceries, food logging, and Polly — a realtime voice + camera
AI chef — live on the six-tab shell (Today, Recipes, Polly, Plan, Kitchen, Progress).
Onboarding, AI features (via the Vercel proxy), and subscriptions are all in active
iteration; see `docs/structure.md` for the current nav/screen contract and
`docs/REENABLE-PAYMENTS.md` for subscription status.
