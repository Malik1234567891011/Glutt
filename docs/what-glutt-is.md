# Glutt — everything the app actually does

A complete description of the shipping product, written to be handed to a person
or pasted into an AI with no other context. Everything below is what is built and
working in the app today, not what is planned. Where something well known is
missing or half-built, it says so, because a description that quietly omits the
gaps is useless to anyone trying to reason about the product.

Meta Ray-Ban glasses support exists in the codebase and is deliberately left out
of this document.

---

## What it is, in one paragraph

Glutt is a native iOS cooking app for people who already like cooking and are
tired of recipe apps that are really just storage. It does four things: it keeps
the recipes you actually collect (including the ones you find on social media),
it helps you decide what to cook from what is genuinely in your kitchen, it
stands next to you and talks you through the cook out loud, and it teaches you
technique as a structured course rather than a pile of articles. It is built
around a live voice chef called Chef (internally Polly) who can see, hear and
talk during a cook and during a lesson.

**Platform:** native iOS, SwiftUI + SwiftData, iOS 17+. Local-first: your
recipes, kitchen and progress live on the device. AI, recipe import and media go
through a hosted proxy. Optional account sync via Supabase.

**Business model:** hard paywall. There is no free tier. Without an active
subscription the app opens onto the real tabs so it looks like itself, and every
touch bounces you to the paywall. Subscriptions are handled by Superwall over
StoreKit, re-checked on every cold launch, so a lapsed subscription re-locks the
app.

**Accounts:** Sign in with Apple, or Continue with Google.

---

## The four tabs

The app has exactly four tabs: **Recipes, Discover, Kitchen, Skills.**

(An older product document describes six tabs including Today, Plan and
Progress. Those do not exist. Where their ideas survived, they live inside the
four tabs above.)

---

## 1. Recipes — your library and everything you do to a recipe

### Getting recipes in

- **Paste a link.** Websites, Instagram, TikTok, YouTube, Reddit, Pinterest.
  Each has its own extraction path rather than one generic scraper.
- **Screenshot import.** OCR a picture of a recipe, including the screenshots
  people take of TikTok captions.
- **iOS share sheet.** Share a link from any app straight into Glutt. The
  extension runs the whole import inside the share sheet, then either closes and
  leaves you where you were or opens Glutt on the finished recipe.
- **Write one manually.**
- **AI cleanup pass.** Imported drafts go through a model that fixes mangled OCR
  lines, pulls the actual recipe out of a chatty caption, and fills in missing
  structure. Strictly additive: if it fails, the original draft is kept.
- **Review before saving.** Nothing is saved silently. You see the draft with
  confidence flagged, problems highlighted, and every field editable.

### Living with the library

- Search, including **semantic search** — find "that creamy lemon chicken thing"
  without remembering its name. Hybrid: keyword matching plus on-device word
  embeddings, fully offline. When AI is configured it additionally re-ranks the
  results and writes a one-line headline.
- **Collections** you create and browse.
- **Versions.** Any change saves as a version; the original is never overwritten.
- Cooked-before history, tags, difficulty, time, servings with rescaling.
- **Tools you'll need** on each recipe, checked against the equipment you own.

### Things you can do to a recipe

- **Ask Polly** — a text conversation about the dish before you cook it. Ask
  anything; answers are just answers and nothing touches your library unless you
  say so.
- **Make it with what I have** — adapts the recipe to your actual pantry, showing
  every proposed swap with the reason it works and warning you when something is
  essential. Saves as a separate version.
- **One-tap adjustments** — higher protein, lighter, cheaper, or match my food
  rules. Saves as a version.
- **Substitutions** — when an ingredient breaks your dietary rules or allergies, a
  banner offers a recommended swap plus alternatives, each itself re-checked for
  compliance. Tapping one rewrites that ingredient and clears the warning.
- **Plan a week of dinners** — five dinners generated *as a set*, not five
  separate recipes. The point is overlap: they share a core of ingredients so one
  shop covers all five. Saving drops five ordinary recipes into your library in a
  collection and pushes one merged list into Groceries.

### Bundled content

- **Cooking Basics** — evergreen technique lessons ("how to fry an egg") that sit
  above your personal library. They are real recipes underneath, so Cook Mode and
  Chef work on them unchanged.
- **Request a how-to** — ask for anything ("how to cook rice", "grilled cheese")
  and it is generated as a proper chef-beside-you lesson rather than a thin
  recipe card.
- **Chef pages** — Gordon Ramsay, Nick DiGiovanni, Joshua Weissman, Nicky's
  Kitchen Sanctuary, Preppy Kitchen, each with their signature dishes.
- **Restaurant pages** — dishes inspired by real restaurants.

---

## 2. Discover — finding something new

Two surfaces behind one toggle:

- **Videos** (the default) — a feed of recipe videos.
- **Images** — "Plates", a full-screen tactile swipe deck of photo recipes.
  Vertical paging browses, a tap flips a card to its recipe, swipe right saves and
  left skips, with buttons for both. New pages stream in as you approach the end
  so it never dead-ends.

Both carry a streak chip. Saving from here drops the recipe into your library.

---

## 3. Kitchen — the real-world layer

- **Inventory.** What is actually in your fridge, pantry and freezer. Deliberately
  fast rather than precise: tap an item to cycle its rough quantity (full, half,
  low, out), swipe to remove. Use-soon items are flagged.
- **Pantry scan.** Photo, or just say or type what you have. AI proposes
  candidates, you confirm before anything is added. Nothing is auto-committed, so
  a wrong guess costs one untoggle.
- **Groceries.** A shopping list grouped by aisle, with checked items sinking to
  the bottom. Duplicates are combined. Finishing a shop offers to move everything
  you bought into your inventory.
- **Store mode.** A stripped-down in-store view: big rows, giant tap targets,
  nothing but the list, screen stays awake.
- **Invent a dish.** Builds an original recipe around what you actually have on
  hand. Not a search against saved recipes: a new dish. The result flows through
  the normal review-and-save path and is labelled as Glutt-invented.
- **Tools.** A checklist of the equipment you own. Recipes use it to flag missing
  gear, and Chef uses it so she never tells you to use a pan you do not have.

---

## 4. Skills — learning to cook, as a course

A single continuous scrolling map rather than a grid of categories, deliberately
built to feel like a place rather than a list of modules.

**Nine regions, roughly 75 skills:** Cooking Basics, Knife Skills, Eggs, Heat &
Pan Control, Meat, Sauces, Mother Sauces, Flavour & Seasoning, Cooking Intuition.

Skills have prerequisites, so the map opens up as you learn. Each has a lesson
written as structured text — summary, steps, what to watch for, and why it
matters — plus XP and progress tracking.

**Around 49 of them can be watched and checked**, which is the part that makes
this different from reading an article. The rest are knowledge rather than
technique (you cannot photograph "tasting as you go"), and those are explicitly
not graded — you are told you can ask questions instead.

### How a checked lesson runs

Chef teaches by voice. She opens by naming the skill, telling you that you can
say "Chef" at any moment, and asking whether you want to watch the short
demonstration clip or have her explain it. If you take the clip she talks over it
rather than playing it in silence. When you are ready she tells you exactly how
to hold things so she can see, and asks you to say "Chef, take a look".

She then looks and gives you one thing at a time. She can:

- tell you what is right before what is wrong,
- stop the lesson if she sees something dangerous,
- ask you to confirm something she cannot see clearly, rather than guessing,
- refuse to answer when the picture genuinely does not support one.

Passing a skill is called out properly and recorded.

**Two ways to be seen:** wearing camera glasses, or **photo mode** — you take a
couple of pictures with your phone and send them. Photo mode is a genuinely
different lesson, not a degraded one; a phone can photograph both faces of a
knife blade, which a camera on your face never can.

---

## Cooking: the two modes

### Cook Mode

Full-screen, step by step. Big text, screen stays awake, per-step ingredients,
built-in timers, swipe or tap to move. Before it starts, if you are missing
ingredients you get a checklist showing what is missing, what can be swapped from
your pantry, and the choice to shop, swap, or cook anyway.

### Cook with Chef — the live voice cook

The headline feature. A real-time voice session where Chef talks you through the
cook, listens, and answers.

- **Pre-cook briefing.** A short rundown of the dish and the beats before you
  start.
- **Wake word.** Say "Chef" to talk. The microphone is otherwise closed, and
  saying her name over her stops her mid-sentence.
- **She can see.** Point a camera at the pan and ask "does this look right" and
  she looks at it before answering.
- **What she can do mid-cook, on her own initiative:** start, check and cancel
  timers; move between steps and mark them done; read out the current step; adjust
  servings; check your pantry; find substitutes; read nutrition; play the
  technique clip for a step; remember a fact you tell her; and record a "Polly
  Save" when she catches something.

### After the cook

- **Rate it and leave a note**, recorded as cook history.
- **Cook recap card** — plate photo, soft scores, the Polly Saves from the
  session, and a shareable card. Framed as a cooking *run*, not an AI judging your
  food.

---

## The things that quietly run underneath

- **Diet guard.** Allergies and dietary rules are hard blocks, everywhere:
  recipes, suggestions and substitutions are all checked. Dislikes are soft —
  surfaced but never silently hidden, because you may be cooking for someone else.
- **Taste profile.** Learns what you actually like from your ratings, repeats and
  saves. Not a black box: it is visible and editable in Settings.
- **Nutrition, optional.** Three modes — just cooking, light tracking, or gym
  mode. Off by default. Calories and protein appear on recipes and cards only if
  you turn them on, with daily goals if you want them.
- **Onboarding.** Ten screens, including the dietary rules and a tutorial for the
  share-sheet import.
- **Settings.** Dietary rules, allergies, disliked ingredients, the editable taste
  profile, nutrition mode, and AI configuration.
- **Discord.** A launch invitation to the community server.

---

## What is deliberately not there

Named because their absence is often surprising:

- **No Today, Plan or Progress tab.** Meal planning exists only as the "week of
  dinners" generator inside Recipes. There is no calendar, no meal-time scheduling
  and no cooking-start reminders.
- **No leftovers tracking at all.** Not modelled, not built.
- **No food logging.** The photo-to-calories estimator exists in the codebase but
  is not wired to any screen, so there is no "what did I actually eat" loop and no
  planned-versus-actual comparison.
- **No social features.** No following, no comments, no feed of other people.
- **No free tier.**

---

## Shape of the thing, for anyone reasoning about it

The product loop it is actually built around is narrower than a general cooking
app: **collect recipes → decide using what you really have → cook with someone
talking you through it → get better at cooking.** The parts that serve that loop
are deep (import, pantry-aware adaptation, the live voice cook, the skills
course). The parts that serve tracking and scheduling are either shallow or
absent on purpose.

The strongest, most distinctive things in it are the **live voice cook** and the
**skills course with visual checking**. Almost everything else in the app exists
in some form elsewhere; those two do not.
