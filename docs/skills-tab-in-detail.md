# The Skills tab, in detail

Everything the Skills tab is and does, written so somebody who has never seen
it could picture the screen and describe how it behaves. Describes what is
built today, not what is planned.

Glutt is a native iOS cooking app (SwiftUI + SwiftData). Skills is the fourth
of its four tabs: **Recipes · Discover · Kitchen · Skills**.

Two versions of this tab exist on two branches, and they differ in one
important way, covered at the end. Unless stated otherwise, everything here is
true of both.

---

## What it is for

Recipes tell you what to do. Skills teach you to cook — the technique
underneath the recipes. It is a structured course, not an article library: the
skills have prerequisites, the map opens up as you learn, and a chef can watch
you attempt one and tell you what to fix.

The design intent, written into the code, is that it should feel like **a place
you travel through** rather than a list of modules or a dashboard.

---

## The screen: one long scrolling map

The whole tab is a single vertical scroll. There is no grid, no category
picker, no tab bar within the tab.

### The header

Small, three lines, deliberately kept short so the map is not pushed below the
fold:

- An uppercase amber eyebrow: **BECOME A BETTER COOK**
- A large heading in the display face: **Skills**
- Top right, an amber pill with a flame icon: **"3 days"** — the cooking streak
- Below that, one quiet line of progress, not a card:
  `Level 4 · 12 skills` on the left, `40 XP to 5` on the right, with a thin
  progress bar underneath in the accent colour

That line used to be a white card with the mascot inside it. It was cut down
because it pushed the map below the fold and turned the character into a
profile photo.

### First run

A cook who has learned nothing gets a small "start here" prompt above the map,
because a map at 0% with nothing pointed at reads as dead.

### The map itself

Below the header, the map runs continuously for the whole length of the tab.

**No containers.** An earlier version drew each category as a big rounded
rectangle, and by the third one the feature read as a vertical pile of modules.
So the rectangles are gone: a cream canvas runs the entire length, and each
region only *tints the air* around it, fading back to cream before the next
begins.

**Regions** are the nine areas of the world, in this order:

| Region | Colour | Skills | Watchable |
|---|---|---|---|
| Cooking Basics | sky | 9 | 2 |
| Knife Skills | herb green | 12 | 12 |
| Heat & Pan Control | ember | 11 | 8 |
| Eggs | amber | 8 | 7 |
| Meat | peach | 8 | 7 |
| Sauces | plum | 6 | 5 |
| Mother Sauces | peach | 8 | 8 |
| Flavor & Seasoning | amber | 7 | 0 |
| Cooking Intuition | sky | 6 | 0 |

About **75 skills**, of which roughly **49 can be visually checked**. Each
region has a header with its name, a one-line blurb ("Most cooking problems are
a pan that was too cool or too crowded") and a learned-count like `4 / 11`.

**The path.** Skills are laid out down the screen on a winding trail, one per
row, each row 112pt tall — generous on purpose, because the map is meant to be
travelled rather than surveyed. Each skill sits in a left, centre or right
column so the route weaves rather than running straight down.

The trail is drawn in **two passes**: a faint dotted line for the whole route,
and a solid line in the region's own colour drawn only as far as you have
actually got. The journey colours itself in behind you.

**Nodes.** Every skill is a circle carrying its own icon (an egg, a knife, a
flame). They differ by state in *size, fill, ring and weight*, not only colour:

- **Not started** — plain card-coloured circle, thin grey border, muted icon, 62pt
- **In progress** — card fill, coloured ring in the region's tint, coloured icon
- **Learned** — filled solid in the region's colour, no border
- **Recommended** — the loudest object on screen: 78pt instead of 62, filled and
  saturated, a cream ring, a soft coloured halo 26pt wider than the node, a
  heavier drop shadow, and the word **NEXT** under its label
- **Coming soon** — greyed and faded, still tappable but with nothing to read

**Mastery challenges** get a different silhouette rather than just a bigger
circle: a rounded square rotated 45° into a diamond, 84pt (92 when
recommended), so a milestone is recognisable while scrolling past at speed.

Under each node is its short name in two lines at most.

**The bear.** Polly, the Glutt character, stands beside whichever skill is
recommended — an 84pt illustration placed on the opposite side of the node from
the map's centre so he never covers the path or the label. When the
recommendation moves he **walks** to the new node with a spring animation
rather than blinking out of one and into the other.

Tapping any node opens its lesson. The tap has haptics — medium for the
recommended node, light for the rest.

---

## The lesson screen

Pushed over the map. Text-first and sectioned, so it reads as a chef talking
you through it rather than a wall.

- **Heading** — the skill title in the display face, with its one-line
  description underneath
- **A demonstration video** where the skill has one, sitting above the text
- **Summary** — what this is and why it is worth knowing
- **Steps** — numbered, one action each
- **Watch for** — the common mistakes
- **Why it matters** — the reasoning, which is the part that turns a rule into
  something you can adapt

If the skill has unmet prerequisites, they are named. If it is mapped but not
yet written, it says so plainly rather than showing an empty lesson.

**The check block** sits in a green-tinted card near the bottom with a primary
button reading **"Try it and show her"**, or **"Show her again"** if you have
already passed.

**Ask Polly** lives inline at the bottom of the lesson — a single question box,
deliberately not a second chat screen behind a button, because a sheet on top of
a sheet for one question makes a small thing feel like an errand.

The footer carries the completion state: **"You've learned this one"** once
passed, or an **"I've got it"** button to mark it yourself.

---

## Being watched: how a check actually works

This is the part that separates Skills from a written guide.

### Photo mode (both branches)

You take two or three photos with your phone and send them. The screen is one
page, not a wizard — "here is what I am looking for, here are your slots, send
when ready" — because a cook doing this has a knife in one hand and every extra
tap is taken with the wrong hand.

The flow: **Show Chef** → *Check yourself first* (what she is looking for) →
photo slots you fill from camera or library → **Having a look** / "She is
reading them now" → the verdict, with **Done** or **Try it again**.

### What happens to the pictures

1. **Hand detection.** Apple's Vision framework finds the hands and crops to
   each one separately. The landmark-confidence threshold is deliberately low
   (0.15), because a hand holding a knife has its fingers *covered by the
   knife* and therefore scores low — at the default it systematically discarded
   the hand holding the tool and cropped the empty one.
2. **Marking.** Numbered magenta rings are drawn on each fingertip (1 thumb
   through 5 little), so questions can refer to a ring rather than asking the
   model to reason spatially about fingers.
3. **Quality gate.** Crops that come out too blurry or blown out are dropped
   rather than sent.
4. **The read.** The wide shot goes with the close-ups, so the reader can work
   out what is actually in the scene and which hand holds the tool, and is asked
   to name which picture the tool is in. If none of them show it, that is a
   valid answer and the check stops there.
5. **Narrow questions.** Rather than "which grip is this", it is asked closed
   per-picture questions — "is the pixel under ring 4 steel or handle" — with
   **cannotTell** as a first-class answer. The single deciding question goes out
   as its own small request, because inside the full rubric prompt it gets
   drowned. These same questions are what the Cook Rating counts.

### What she is allowed to say

Every verdict is gated in code, not left to the model:

- **A correction** must be one of the authored ones, and it must be supported by
  what the pictures actually showed. She cannot say "your thumb is on the
  handle" if her own reading of the pictures puts it on the blade.
- **A pass** is treated as a claim and checked the same way. It is not enough
  for her to say "ready".
- **Danger** (fingers wrapped around the blade) outranks everything, including
  her own confident pass.
- **Uncertain readings ask you** rather than asserting: *"Your thumb and index
  finger are exactly right. I could not see the rest clearly, so tell me: are
  your bottom fingers around the handle, or on the blade itself?"* — then she
  believes your answer.

The words a cook hears are always authored in the app, never generated. The
model reports what it saw; the app decides what that means and what to say.

### Not everything is graded

Two whole regions — **Flavor & Seasoning** and **Cooking Intuition** — have no
visual checks at all, on purpose. You cannot photograph "tasting as you go".
Those are knowledge rather than technique, and they say so rather than pretending
to grade you.

---

## Progress

There are two numbers, and they deliberately measure different things.

### Level and XP: what you have learned

- **XP per skill:** 20 beginner, 30 intermediate, 40 advanced, +35 for a mastery
  challenge. Awarded as a snapshot at the time, so retuning the values later
  never rewrites history.
- **Levels** with a rising cost per level, shown in the header line.
- **A daily streak**, in the amber pill.
- **Attempts are recorded**, so a lesson knows how many times you have tried.
- Only progress is stored. The catalog itself is static Swift, not a database.
- The recommendation follows the most recently opened skill, staying in the
  region you are working in rather than sending you elsewhere with one node
  left.

Reading a lesson and pressing "I've got it" moves this and nothing else.

### Cook Rating: what you can actually do

A quiet row under the header, reading `Cook Rating … Unranked ›`, opening a
sheet. Not a card, not a second XP bar.

**Unranked is a real state.** There is no invented starting number. Under the
row sits the way out of it: `3 verified checks to place`. Below eight pieces of
evidence the rating is shown but marked *provisional*, because three narrow
observations is not a picture of somebody's cooking.

**Only being watched moves it.** Every verified check writes one piece of
evidence: which skill, which region, how it went, and what it was worth. A
mastery trial is worth five ordinary beginner checks. The same check passed a
second time is worth half, a third time a quarter, so twenty photographs of one
easy grip is worth slightly less than two.

**The score is counted, not judged.** No model is ever asked how good the
cooking was. Each check asks two or three narrow authored questions with known
right answers, and the score is how many were right out of how many could be
seen. So `2 of 3` is a claim anybody can check by looking at the same
photograph. 48 of the 49 watchable checks are authored this way.

Two rules decide what gets a question at all. It has to be something a
photograph can settle, so nothing about grip pressure or how sharp the knife
is. And it has to be something the cook was told to aim at, so a yolk's
looseness, a butter stage and an omelette's colour are asked but never scored:
those are the cook's choice, and marking somebody wrong for hitting what they
aimed at is worse than not scoring them.

**Uncertainty costs nothing, ever.** An unusable picture, a part nobody could
see, or an inconclusive check writes no row at all. Not a zero, nothing. A
criterion that could not be seen is in neither total. And a check where only
one criterion could be read produces no score either, because one criterion is
a pass or a fail rather than a score, and calling it one would be harsher than
having asked nothing.

**Ranks** are kitchen brigade titles rather than invented tiers, numbered
downward within a rank the way a kitchen does it: Prep Cook III through I, Line
Cook III through I, Chef de Partie, Sous Chef, Head Chef.

**Regions get their own standard** out of 100 in the sheet, weighted toward
recent work so a cook who was poor in January and good in March reads as good.
Flavour & Seasoning and Cooking Intuition read **Not scored** rather than a
dash, because you cannot photograph tasting as you go and a dash reads as
missing data.

---

## The one difference between the two branches

**The glasses branch** additionally has a **live voice lesson**. Chef teaches
out loud through Meta Ray-Ban camera glasses: she opens by naming the skill,
tells you that you can say "Chef" at any point, and offers you the video or an
explanation. She talks over the clip rather than playing it in silence. When you
are ready she tells you how to hold things so she can see and asks you to say
"Chef, take a look". She watches, answers, fills the wait with a fact about why
the technique is shaped as it is, and congratulates you properly when you pass.

**The Apple-ready branch** has none of that, and it is not a degraded version —
it is photo mode only, deliberately. Photo mode is genuinely better at some
things: a phone can photograph both faces of a knife blade, which a camera on
your face can never see at once.

Everything else in this document — the map, the nodes, the lesson, the catalog,
the checking pipeline, the gates, the progress — is identical on both.
