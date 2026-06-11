# PRODUCT.md

## Product Vision

Build a mobile-first cooking assistant for people who love cooking but feel let down by current apps.

Most cooking apps are either recipe storage apps, meal planners, calorie trackers, grocery lists, or social recipe feeds. This app should combine the useful parts of those categories into one simple cooking flow.

The goal is not to overwhelm the user with features. The goal is to help them answer:

* What should I cook?
* Do I have what I need?
* How do I cook it properly?
* How can I adapt it to what I actually have?
* What did I eat?
* What worked, and what should I cook next?

## Core User

Someone who enjoys cooking, saves recipes from social media or websites, wants to cook more consistently, and wants an app that understands their real kitchen instead of just storing recipes.

They may care about meal planning, groceries, calories, protein, leftovers, or using pantry ingredients, but the app should not force every user into fitness tracking.

## Core Promise

Help the user decide what to cook, cook it properly, adapt recipes to real life, remember what worked, and improve their cooking over time.

## The App Is Not

* Not just a recipe database.
* Not just a meal planner.
* Not a Pinterest clone.
* Not a calorie tracker first.
* Not a social media recipe app first.
* Not a cluttered dashboard with too many tabs.
* Not an AI gimmick where everything requires chat.

## Product Principles

* Cooking flow matters more than content volume.
* The app should reduce thinking before, during, and after cooking.
* Mobile-first, because the user is likely in the kitchen.
* Keep the interface simple even if the app is powerful underneath.
* AI should appear through useful actions, not as random decoration.
* The app should adapt to what the user has, likes, and previously cooked.
* Nutrition tracking should be optional, not forced.
* The app should feel warm, clean, practical, and food-focused.

## Core Navigation

Use a simple bottom navigation with a maximum of five main tabs:

1. **Today**
2. **Recipes**
3. **Plan**
4. **Kitchen**
5. **Progress**

There should also be one main universal action button for adding/importing/scanning/logging.

## Main Tabs

### 1. Today

The home screen and daily command center.

Shows:

* Next planned meal.
* When to start cooking.
* Missing ingredients.
* Possible substitutions.
* Today’s meal timeline.
* Leftovers reminders.
* Optional nutrition summary if Gym Mode is enabled.

Primary actions:

* Cook now.
* Optimize recipe for what I have.
* Log food.
* Ask what to cook.
* Add meal to plan.

### 2. Recipes

The user’s saved recipe memory.

Supports:

* Imported recipes from websites/social links.
* Saved recipes.
* Collections.
* Tags.
* Search.
* Semantic search, such as “that creamy chicken dish.”
* Recipe notes.
* Recipe versions.
* Cooked-before history.

Recipe cards should show:

* Image.
* Title.
* Source/creator.
* Time.
* Difficulty.
* Tags.
* Whether the user has the needed ingredients.
* Optional calories/protein if enabled.

### 3. Plan

Meal planning without becoming a complicated calendar.

Supports:

* Planning meals by day.
* Planning meals by meal type.
* Optional exact meal times.
* Cooking start reminders.
* Prep-ahead reminders.
* Weekly meal view.
* Grocery list generation from planned meals.
* Leftovers scheduling.

The Plan tab should feel simple and guided.

### 4. Kitchen

The real-world kitchen layer.

Contains:

* Inventory.
* Groceries.
* Leftovers.

Inventory:

* Fridge/pantry items.
* Rough quantities like full, half left, almost empty.
* Camera or video scan in future.
* Use-soon items.

Groceries:

* Grocery list from recipes and meal plans.
* Items grouped by category.
* Duplicate ingredients combined.
* Items removed or flagged if already in inventory.
* Manual editing.

Leftovers:

* Tracks cooked servings.
* Lets user add leftovers to a future meal.
* Lets user log leftovers as eaten.
* Lets user freeze or reuse leftovers.

### 5. Progress

Optional tracking layer.

If the user enables Gym Mode:

* Daily calories.
* Protein.
* Planned vs actual eaten.
* Weekly consistency.
* Progress over time.

If the user does not enable Gym Mode:

* Meals cooked.
* Recipes tried.
* Cooking streak.
* Eating out frequency.
* Leftovers used.
* Food waste reduction.
* Favorite meals.

Progress should never feel guilt-heavy or shame-based.

## Universal Action Button

A central action button should open a simple menu:

* Import recipe.
* Scan pantry/fridge.
* Log food.
* Add grocery item.
* Ask what to cook.

This avoids adding too many tabs.

## Core MVP Features

The first version should focus on the core cooking loop.

Must include:

* Recipe import from links.
* Saved recipe library.
* Recipe search.
* Meal planning.
* Grocery list from recipes or plan.
* Basic pantry/inventory.
* Pantry-aware grocery list.
* “Optimize recipe for what I have.”
* Cook mode.
* Basic actual-eaten logging.
* Leftovers tracking.
* Optional nutrition/gym mode basics.

Avoid building social features in the first version.

## Killer Features

The app should eventually be known for:

1. **Semantic Recipe Memory**

   * Find recipes by vague memory, flavor, ingredients, or mood.

2. **Optimize Recipe For What I Have**

   * Adapt a recipe based on the user’s pantry without ruining the dish.

3. **Pantry-Aware Cooking**

   * Suggest meals based on what the user already owns.

4. **Planned vs Actual Eating**

   * Connect meal planning with what the user actually ate.

5. **Leftovers Tracking**

   * Track cooked servings and help reuse them intelligently.

6. **Cooking Start Reminders**

   * Remind the user when to thaw, prep, marinate, or start cooking.

## Design Direction

The app should feel like a modern cookbook plus a personal cooking assistant.

Visual style:

* Warm.
* Clean.
* Premium.
* Food-focused.
* Mobile-first.
* Large food images.
* Soft cards.
* Minimal clutter.
* Clear action buttons.

Avoid:

* Generic AI gradients.
* Cartoon chef mascots.
* Overly dark dashboards.
* Fitness-app-first design.
* Too many tabs.
* Too many stats on the home screen.

## Main Product Loop

The app should be designed around this loop:

1. Save or import a recipe.
2. Find or choose what to cook.
3. Check what ingredients are available.
4. Add missing items to groceries.
5. Cook with guidance.
6. Log what was actually eaten.
7. Save notes, leftovers, and feedback.
8. Use that information to recommend better meals later.

Every feature should support this loop.

## Success Criteria

The app is successful if users feel:

* They know what to cook.
* They waste less time deciding.
* They use more of what they already have.
* They cook more consistently.
* They can find saved recipes easily.
* They trust the app while cooking.
* The app improves as it learns their taste.
* The app feels simple even though it is powerful.
