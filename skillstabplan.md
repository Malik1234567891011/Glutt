# Glutt Skills Tab — Product & Design Handoff

## Overview

Build a new **Skills** experience inside Glutt.

The purpose of Skills is to help users gradually become better cooks rather than only following recipes.

The core mental model is:

**A cooking skill map / progression world, not a library of tutorials.**

It should feel somewhat game-like and satisfying to progress through, but it should still feel like **Glutt**: warm, healthy, playful, approachable, modern, and useful.

Think more:

**Duolingo-style progression + cooking curriculum + Glutt**

and less:

* RPG skill tree
* Risk map
* dark video game interface
* dense dashboard
* online course catalog

Before implementing the visual design, inspect the existing Glutt codebase, design system, typography, spacing, components, colors, navigation patterns, cards, buttons, backgrounds, etc.

**The Skills tab should feel like it has always belonged inside Glutt.**

Do not blindly recreate any concept image.

---

# 1. Main product idea

Recipes currently help answer:

> "What do I do to cook this?"

Skills should help answer:

> "How do I actually get good at cooking?"

Instead of showing users a grid/list like:

* Knife Skills
* Eggs
* Steak
* Sauces
* Pasta

the main Skills screen should feel like an **explorable cooking journey**.

Different cooking disciplines appear as colorful areas / clusters / regions.

Inside each region are smaller individual skill nodes.

Example:

### Knife Skills

* Knife grip
* Claw grip
* Slice
* Rough chop
* Dice
* Mince
* Julienne
* Chiffonade
* Dice an onion
* Mince garlic
* Slice steak against the grain

### Heat & Pan Control

* Understand low / medium / high heat
* Preheat a pan
* Know when a pan is ready
* Sauté
* Sear
* Avoid overcrowding
* Cook with butter without burning it
* Deglaze
* Reduce

Users progress through these over time.

The important feeling should be:

> "There is a whole world of cooking knowledge here that I can slowly master."

---

# 2. Do NOT try to fit the entire map on one screen

This is important.

The generated concepts so far have made the experience feel cramped because they try to display every category simultaneously.

Instead, make the Skills screen **long and scrollable**.

Opening Skills should only reveal the beginning/current portion of the user's cooking journey.

As users scroll down they should naturally discover more categories and more advanced skills.

Something closer to:

```text
HEADER

Current skill / progress

        KNIFE SKILLS
      o       o
          o
      o       o

          v

      COOKING BASICS
       o     o
          o
       o     o

          v

     HEAT & PAN CONTROL
     o      o      o
        o       o

          v

           EGGS
        o      o
           o

          v

         MEAT
       o       o
          o
       o       o

          v

      SAUCES / FLAVOR
           ...

          v

      more advanced areas
```

It does **not** need to literally be one straight path.

Regions can overlap slightly, branch, shift left/right, and visually connect.

The point is that scrolling should feel like exploring further into someone's cooking education.

---

# 3. General visual direction

The experience should be significantly more playful than the dark concept.

Avoid:

* dark fantasy map aesthetic
* serious RPG interface
* tiny information everywhere
* hard borders around everything
* fitting 8 categories into one viewport
* overly complicated dashboards
* gold/black "premium game" styling
* making it look like Risk
* childish cartoon game UI

Instead lean toward:

* Glutt's existing light/warm visual language
* soft backgrounds
* rounded shapes
* friendly spacing
* healthy / food-oriented colors
* subtle illustrations
* organic shapes
* occasional playful motion
* lots of breathing room
* large tappable nodes
* simple labels

The screen should feel alive without feeling like a children's game.

---

# 4. Skill regions

Each major discipline should have its own recognizable visual identity.

For example:

* Knife Skills -> soft green
* Cooking Basics -> blue
* Heat & Pan Control -> warm orange
* Eggs -> yellow
* Meat -> warm red
* Seafood -> teal
* Sauces -> purple
* Flavor & Seasoning -> pink/red
* Baking & Dough -> tan/cream
* Cooking Intuition -> potentially Glutt green / special treatment

Do not treat these exact colors as mandatory.

Use Glutt's existing palette/design language where appropriate.

Each region could have a very soft organic background shape behind its nodes rather than a rigid rectangular card.

Example:

```text
        KNIFE SKILLS
        6 / 18 learned

     o Slice
           \
      o Dice -- o Mince
         \
         o Julienne

     o Dice an Onion
```

There can occasionally be small decorative food/utensil illustrations around the world, but keep them subtle.

Examples:

* chef knife
* onion
* skillet
* egg
* whisk
* salmon
* steak
* loaf of bread

They should add personality rather than take over the UI.

---

# 5. Map structure

Do not make the world feel like separate isolated cards stacked on top of each other.

There should be some sense that everything belongs to **one cooking map**.

Possible approaches:

* dotted paths between regions
* curved connecting paths
* subtle transition between region colors
* paths that branch
* one area's final skill leading into another area's first skill
* staggered node placement rather than perfect grids

For example:

Knife fundamentals could eventually connect to:

**Prep Chicken**

which visually leads toward:

**Meat**

Similarly:

**Deglaze a Pan**

could connect from:

**Heat & Pan Control**

into:

**Sauces**

That makes the curriculum itself feel intelligent.

---

# 6. Skill node types

A node represents one small learnable skill.

Keep individual skills narrow.

Bad:

> Learn Knife Skills

Good:

> Claw Grip

> Dice an Onion

> Mince Garlic

> Slice Against the Grain

> Know When Your Pan Is Hot

There should be a few visual states.

## Not started

Visible but neutral.

## Recommended / next

Highlighted slightly.

This should attract the user's eye without aggressively flashing.

## In progress

Visually show partial progress.

## Learned

Checkmark / completed state.

## Locked

Only use locking where it actually makes sense.

Avoid making most of the map inaccessible.

Users should still be able to explore.

## Challenge / mastery skill

A slightly larger/special node.

Examples:

**Prep an Entire Mirepoix**

**Cook the Perfect Steak**

**Make a Pan Sauce**

**Egg Mastery**

These combine several smaller skills.

---

# 7. Soft prerequisites, not aggressive locking

Do not make Skills feel like school.

If a user taps an advanced skill, we can say something like:

**Recommended first**

- Pan Heat
- Searing
- Deglazing

but still allow them to learn the skill.

People entering Glutt may already be competent cooks.

We should not make an experienced person complete:

> How to hold a knife

before learning:

> Hollandaise.

---

# 8. Top of Skills screen

The header should immediately communicate progression without becoming a dashboard.

Potential information:

**Skills**

Short supporting copy like:

> Become a better cook, one skill at a time.

Then lightweight progression.

Potential elements:

* current cooking level
* number of skills learned
* XP
* daily streak
* avatar

Do not necessarily show all four if it becomes cluttered.

Use judgment based on the existing Glutt UI.

---

# 9. Glutt bear / chef avatar

Use the existing Glutt bear identity somewhere in this experience.

The bear should become more of a character within Skills.

Potential treatment:

small circular avatar near the header:

**Bear, Level 8**

or appearing inside a progress card.

Eventually the bear could visually evolve / gain chef accessories as users progress, but that is not necessary for the initial implementation.

For now, simply make the mascot visible enough that the page feels uniquely Glutt.

If there is already an appropriate bear asset in the repository, reuse it.

Do not generate/recreate a random different bear.

---

# 10. Daily streak

Add a lightweight streak system.

Example:

**7 day streak**

A streak could increase when a user completes at least one skill in a day.

The purpose is simply to give someone a reason to keep learning.

Don't let streak mechanics dominate the interface.

Potential header:

```text
Skills

Bear Lv. 6               7
24 skills learned
```

or something more suited to the existing design system.

Persist streak data locally using whatever architecture is already appropriate in Glutt.

For MVP, streak logic can remain relatively simple.

---

# 11. "Continue Learning"

Near the beginning of the screen, give returning users a very obvious way to resume.

Example:

**Continue learning**

### Dice an Onion

Knife Skills, ~2 min

[Continue]

This should be lightweight.

A user should not be forced to manually find their previous node every time they reopen Skills.

If they have nothing in progress, this can instead say:

**Recommended next**

### Control Pan Heat

---

# 12. Learning a skill — MVP

This is important.

**Do NOT build animation/video lesson infrastructure yet.**

Eventually each skill will have custom visual animations demonstrating techniques.

Examples:

* animated knife showing a dice
* hand position for claw grip
* pan showing correct heat
* steak showing where to place a thermometer
* basting motion

Those are future work.

For the initial implementation, learning is primarily:

**written explanation + Polly**

---

# 13. Skill lesson experience

When the user taps a skill node, open a dedicated skill lesson screen or sheet depending on what best matches the existing Glutt architecture.

Example:

# Dice an Onion

**Knife Skills, Beginner**

Polly should explain the technique clearly and conversationally.

Potential structure:

### What you're learning

A one/two sentence explanation.

### How to do it

Concise steps.

Example:

1. Cut the onion in half through the root.
2. Peel the outer skin while keeping the root intact.
3. Make vertical cuts toward the root without cutting completely through it.
4. Rotate the onion.
5. Slice across your cuts to create an even dice.

### Things to watch for

* Keep fingertips behind your knuckles.
* Don't cut through the root too early.
* Try to keep the pieces roughly the same size.

### Why this matters

> Even pieces cook at roughly the same speed.

Then Polly is available underneath.

---

# 14. Polly inside Skills

Polly is a major part of the learning experience.

The idea should feel like:

> You're not reading a static cooking article. You have a chef teaching you.

While viewing a skill, there should be an obvious ability to ask Polly questions.

Example UI:

**Ask Polly about this skill**

Input:

> "Why do I keep the root attached?"

Polly already knows that the user is currently learning **Dice an Onion**, so the user should not need to repeat the context.

Examples:

> "Can I do this with a smaller knife?"

> "I don't understand step 3."

> "How big should the pieces be?"

> "Why does mine fall apart?"

> "Can you explain this more simply?"

Polly responds conversationally.

Use the existing Polly/chat infrastructure if practical rather than inventing an entirely separate AI system.

Pass the relevant skill context into Polly.

For the MVP, the lesson itself can be static/local content and Polly simply becomes the contextual instructor around it.

---

# 15. Skill completion

At the bottom of the lesson there should be something like:

**I've got it**

or:

**Mark as learned**

Upon completion:

* mark skill complete
* award XP
* potentially update streak
* update region progress
* animate completion lightly
* recommend next skill

Example:

> Skill learned
> **Dice an Onion**
> +20 XP

Then:

**Next: Mince Garlic**

[Continue]

Keep celebration tasteful and Glutt-like.

No giant arcade coin explosion.

---

# 16. Future-proof lessons for animation

Although lessons are text-first now, structure the feature so that visual learning content can easily be inserted later.

A Skill should conceptually support something like:

* title
* category
* description
* difficulty
* estimated duration
* text lesson
* steps
* tips
* prerequisite skill IDs
* XP reward
* visual/animation asset
* challenge type
* completion state

The animation/visual field can simply be nil/unused for now.

Do not over-engineer a huge content management system.

Just avoid coupling the UI so tightly to text that animation becomes painful later.

Eventually the lesson may look like:

```text
[ANIMATED DEMONSTRATION]

Dice an Onion

Polly:
"Start by keeping the root attached..."

[steps]

Ask Polly anything
```

---

# 17. Suggested launch categories

We do not need hundreds of skills immediately.

Build the architecture so it can support hundreds later, but populate enough content to make the map feel real.

Initial categories can include:

## Cooking Basics

Possible skills:

* Mise en Place
* Read a Recipe Before Starting
* Season as You Cook
* Taste as You Cook
* Understand a Simmer
* Understand a Boil
* Know When Food Is Done
* Use a Thermometer
* Rest Food After Cooking

---

## Knife Skills

* Hold a Chef's Knife
* Claw Grip
* Slice
* Rough Chop
* Dice
* Mince
* Julienne
* Chiffonade
* Dice an Onion
* Mince Garlic
* Chop Herbs
* Slice Steak Against the Grain

---

## Heat & Pan Control

* Understand Stove Heat
* Preheat a Pan
* Know When Your Pan Is Hot
* Add Oil Correctly
* Avoid Crowding a Pan
* Sauté
* Sear
* Cook With Butter
* Prevent Butter From Burning
* Deglaze
* Reduce

---

## Eggs

* Crack an Egg
* Scrambled Eggs
* Fried Egg
* Soft-Boiled Egg
* Hard-Boiled Egg
* Poached Egg
* Omelette
* Soft Scramble

---

## Meat

* Season Meat
* Dry Meat Before Searing
* Understand Internal Temperature
* Sear Meat
* Baste a Steak
* Rest Meat
* Slice Against the Grain
* Cook a Steak to Temperature
* Butterfly Chicken Breast

---

## Vegetables

Potentially add after initial implementation if the map becomes too large.

* Roast Vegetables
* Sauté Vegetables
* Blanch
* Char Vegetables
* Caramelize Onions
* Brown Mushrooms
* Roast Potatoes

---

## Seafood

* Fish Doneness
* Prevent Fish From Sticking
* Crispy-Skin Salmon
* Cook Shrimp
* Devein Shrimp
* Sear Scallops

---

## Sauces

* What Is Fond?
* Deglaze
* Reduce a Sauce
* Make a Pan Sauce
* Make a Vinaigrette
* Understand an Emulsion
* Thicken a Sauce
* Balance a Sauce

---

## Flavor & Seasoning

* Salt Properly
* Season in Layers
* Understand Acid
* Understand Fat
* Understand Umami
* Balance Salt / Fat / Acid
* Fix Bland Food
* Fix Oversalted Food
* Finish With Acid

---

## Baking & Dough

Could appear lower in the map / be more lightly populated initially.

* Measure Flour Properly
* Understand Yeast
* Knead Dough
* Proof Dough
* Understand Gluten
* Baking Soda vs Baking Powder

---

# 18. Cooking Intuition

Longer-term, one of the most important areas should be **Cooking Intuition**.

This represents the difference between someone who can follow recipes and someone who actually understands cooking.

Examples:

* Know Why Food Tastes Bland
* Know When Something Needs Acid
* Recover From Overcooking
* Make Ingredient Substitutions
* Time Multiple Components
* Cook Without a Recipe
* Adjust a Recipe for More Servings
* Build a Meal From What You Have

This could eventually be treated as a special central/mastery region.

It does not need to be deeply implemented in V1.

---

# 19. Challenges / mastery nodes

Some parts of the map should culminate in practical challenges.

Example Knife path:

```text
Knife Grip
   v
Claw Grip
   v
Slice
 /   \
Dice  Mince
  \   /
Dice an Onion
   v
* Prep a Mirepoix
```

Example steak path:

```text
Season Meat
   v
Pan Heat
   v
Searing
   v
Temperature
   v
Basting
   v
Resting
   v
* Cook a Great Steak
```

For V1, mastery challenges can still just be structured lessons/checklists rather than requiring camera verification.

Later Polly / camera understanding can make these much richer.

---

# 20. Relationship to recipes

The architecture should eventually allow skills to connect to recipes.

For example, while cooking a recipe:

> Baste the steak for 60 seconds.

"Baste" could eventually be tappable.

The user could quickly open:

**Basting — Skill**

learn it, ask Polly a question, and then return to cooking.

Similarly, a skill page could eventually display:

> Used in 14 recipes you've saved.

This does not need to be fully implemented unless it is very easy with the current recipe architecture.

Do not delay the Skills MVP for this.

But avoid making architectural decisions that would make this integration difficult later.

---

# 21. Progression philosophy

Progress should feel satisfying but not artificial.

Possible mechanics:

* XP for completing skills
* cooking level
* streak
* category completion percentage
* mastery challenges
* completed node styling

Do not add:

* coins
* currency
* loot
* battle passes
* complicated unlock systems
* competitive leaderboards

The game mechanic is:

> "I am visibly becoming a better cook."

That should be enough.

---

# 22. Levels

If adding levels, keep them simple.

Example:

**Lv. 8**

XP progresses toward the next level.

Don't worry about elaborate titles right now.

Potentially later:

* Beginner Cook
* Home Cook
* Confident Cook
* Skilled Cook
* Advanced Cook

But numeric level is enough for V1.

Choose reasonable XP values and centralize them so they can easily be changed later.

---

# 23. Content architecture

Avoid hardcoding the entire interface individually.

Skill/category content should ideally come from structured data.

Conceptually:

```text
SkillCategory
- id
- name
- description
- visualTheme
- order
- skills

Skill
- id
- categoryID
- title
- shortDescription
- difficulty
- estimatedMinutes
- XP
- prerequisiteIDs
- lesson
- tips
- order / mapPosition
- isChallenge
```

The exact Swift / SwiftData architecture should follow what already exists in Glutt.

Inspect the project and choose the most appropriate implementation rather than copying this literally.

The important thing is that adding:

> "Caramelize Onions"

later should be easy and should not require redesigning the screen.

---

# 24. Map positioning

The individual nodes will need some intentional positioning so the map feels organic rather than like a list.

However, do not build an overly complicated physics/map engine.

A pragmatic approach is fine.

Each skill/category can have predefined layout information or the UI can use a repeatable staggered layout.

Example:

```text
        o

   o         o

        o

      o    o
```

Paths can curve between them.

It should feel handcrafted but remain maintainable.

The scrolling experience is more important than arbitrary freeform panning.

**Prefer vertical scrolling over requiring the user to drag around a massive 2D canvas.**

This is still an iPhone app.

---

# 25. Performance

The map may eventually contain hundreds of nodes.

Be conscious of rendering performance.

Use lazy rendering / native scrolling patterns where appropriate.

Don't implement the initial version in a way that assumes there will only ever be 20 skills.

At the same time, do not prematurely over-engineer.

---

# 26. Bottom navigation

Integrate Skills naturally into Glutt's existing tab/navigation architecture.

Use the existing navigation style rather than implementing the navigation shown in generated mockups.

The user should feel like they moved into another Glutt tab, not opened another app.

---

# 27. Empty / first-time state

For first-time users, don't show a dead map with everything at 0%.

Give them a very clear starting point.

Potentially:

> **Start your cooking journey**

Polly/bear can say:

> "Let's start with a few fundamentals. You can explore anything you want along the way."

Then highlight one recommended beginner node.

Do not require a lengthy onboarding assessment for V1.

We can add skill assessment later.

---

# 28. Personality / copy

Copy should feel friendly and simple.

Avoid educational/corporate language such as:

> "Complete this module to demonstrate proficiency."

Prefer:

> "Learn this skill"

> "Give it a try"

> "Ask Polly"

> "You've got it"

> "Nice, you learned how to mince garlic."

Polly should sound like a helpful chef beside you rather than a textbook.

---

# 29. V1 scope

The first implementation should focus on getting the **core loop** right:

1. User opens Skills.
2. User sees their progress/streak and a playful scrolling cooking map.
3. User explores different skill regions.
4. User taps a skill.
5. Polly/text teaches the skill.
6. User can ask Polly questions about it.
7. User marks the skill learned.
8. XP/progress/streak updates.
9. Map visually updates.
10. Glutt suggests the next related skill.

That is the V1.

---

# 30. Explicitly NOT V1

Do not spend significant time building these yet:

* custom skill animations
* video lessons
* computer vision grading
* camera verification
* social leaderboards
* multiplayer
* elaborate achievements
* huge onboarding skill assessment
* dozens of badges
* skill marketplace/content CMS
* hundreds of lessons
* sophisticated adaptive-learning algorithm

Build the system so these can be added later, but don't let them delay the basic experience.

---

# 31. Future vision

Eventually I want someone to be able to open Glutt months later and see a map that genuinely represents what they have learned.

For example:

**Knife Skills**
17 / 22

**Heat Control**
14 / 20

**Sauces**
6 / 27

**Seafood**
3 / 18

And they can scroll much further down and see advanced things they still haven't learned.

That visual should create curiosity:

> "What the hell is an emulsion?"

> "I've never poached an egg."

> "I want to learn how to make a pan sauce."

The map itself should make people want to tap things.

---

# 32. Core design principle

This should **not** feel like we're building a bunch of cooking articles.

It should feel like Glutt is slowly teaching the user how to become a cook.

Recipes are things the user makes.

Skills are things the user keeps forever.

The emotional payoff is not:

> "I finished Lesson 23."

It is:

> **"I'm actually getting good at cooking."**

---

# Implementation instruction

Please first inspect the existing Glutt project and understand:

* current design system
* colors
* type styles
* component patterns
* navigation/tab structure
* Polly/chat architecture
* SwiftData/state architecture
* existing mascot/image assets

Then implement this feature in the way that feels most native to the existing application.

Treat this document primarily as the **product behavior, hierarchy, and desired feeling**, not a rigid pixel specification.

Where there is tension between a generated mockup and Glutt's existing design language, **follow Glutt's existing design language.**

The main things I care about preserving are:

1. **Scrollable cooking skill world**
2. **Color/category-based regions**
3. **Lots of small, specific skills**
4. **Visible progression**
5. **Playful/warm Glutt feeling**
6. **Bear/Glutt personality**
7. **Daily streak**
8. **Polly as the instructor**
9. **Text-based lessons for now**
10. **Ability to add animations later**
11. **Skills eventually connecting back into actual cooking/recipes**
12. **The feeling that the map can grow enormously over time**
