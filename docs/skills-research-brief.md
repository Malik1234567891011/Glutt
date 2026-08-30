# Glutt Skills: what we need from a cooking instructor

## Why this document exists

We are building a cooking teacher that **watches you through smart glasses**,
tells you the one thing you are doing wrong, watches you fix it, and only then
counts the skill as learned. One skill works end to end today: **Hold a Chef's
Knife**. It is convincing, and building it taught us exactly what we cannot
write ourselves.

We can write plausible cooking prose all day. What we cannot do is know, with
authority:

- which differences are **mistakes** and which are just how people cook
- which error **actually costs the dish**, when three are true at once
- what an instructor can genuinely **see** versus what they have to ask about
- what would make a real teacher **stop a student mid-task**

Get those wrong and the app becomes a pedant that fails people for having small
hands. That is the whole risk, and it is what this brief is for.

**Bias every answer toward permissiveness.** A false correction costs more trust
than ten missed ones. If you are unsure whether something is a mistake, it is a
variation.

---

## The two gaps

**1. 35 skills are mapped but unwritten.** They appear on the map with real
titles and open to "coming soon". Listed in full in Appendix A.

**2. 31 of the 32 written skills cannot be watched.** They are good reading and
nothing more. The written lesson is the cheap half; the rubric that lets Chef
judge it is the half we need you for.

Both matter. If you have to choose, **rubrics for skills that already have
lessons are worth more than lessons for skills that have none** — they turn
existing content into the thing that makes this app different.

---

## What Chef can actually perceive

Scope your answers to this. It is narrower than a person standing next to
someone, and wider in one surprising way.

**Sight.** First-person camera on the cook's glasses, pointed wherever they are
looking. About 7 frames a second, roughly 500x900. We take several frames a
second or two apart, usually while the hand is turning, and judge them together.

Reliable: hand and finger positions, tool shape and size, colour (this is a big
one: roux, sear, caramelisation, egg set), gross texture, how food is arranged
on a board, what is in a pan, relative sizes and distances.

**Hearing.** The microphone is open the whole time. We are not yet using audio
for assessment and we would like to. Sizzle, crackle, the pitch change when
water hits a pan, the sound of a knife through a carrot: **tell us where sound
is a better signal than sight**, because that is a differentiator nobody else
has and we would build for it.

**Not available.** Temperature, taste, smell, weight, grip pressure, force, and
anything behind an oven door or under a lid. We ask about these out loud instead
("does that feel tense or comfortable?"), so tell us **which question to ask**
where the eyes cannot go.

**One hard geometric limit, which shaped everything.** You cannot see both faces
of a knife at once, so a still photograph can never show a whole pinch grip.
This is why we read across movement rather than a held pose. Expect the same
problem elsewhere and flag it: **for each skill, is there a view that shows what
matters, and what movement brings it into shot?**

---

## What we need per skill

For every skill you cover, we need two blocks. The first is teaching. The second
is judgement, and it is the one that cannot be faked.

### Block 1: the lesson

Short. This is read on a phone by someone holding a knife.

| Field | What it is | Length |
|---|---|---|
| `summary` | What they are learning and why it is worth two minutes | 1–2 sentences |
| `steps` | How to do it. **Only the thing itself** | 2–4 steps |
| `watchFors` | What tends to go wrong | 2–3 |
| `whyItMatters` | The line that turns a rule into understanding | 1 sentence |

On `steps`: our knife grip lesson had four, and two of them were the rocking cut,
which is a different skill. **If a step is not part of the thing named in the
title, it belongs to another skill.** Say so and we will move it.

### Block 2: the visual rubric — the important one

This is what stops the app being a pose classifier.

**`targetTechnique`** — what good looks like, as an observer would describe it.
Physical and visible, not felt.

**`acceptableVariations`** — *the most valuable list in this document.* Every
difference that is NOT a mistake: professional variation, body size, equipment
geometry, handedness, regional or school difference, personal comfort. Our knife
grip has seven, including "exactly where along the blade the pinch sits" and
"knives with no bolster". Each one is a correction that will never be wrongly
given.

Please be generous here and specific about *why* the variation is fine, so we
can have Chef say it: "some cooks pinch a little forward onto the blade and some
stay right at the heel, both are fine if the hand is controlling the blade."

**`rankedMistakes`** — habits worth correcting, **in priority order**, because
Chef gives exactly one correction at a time and needs to know which one costs
the most. For each:

- **key** — a short name we use in code (`handleGrip`, `pointerGrip`)
- **observation** — what an observer sees, so the vision model can name it
- **correction** — *the one sentence Chef says.* Physical, specific, no preamble.
  This is the sentence the whole feature is judged on, so please write it as you
  would say it out loud. "Curl it down onto the side of the blade instead,
  opposite your thumb" is right. "Remember to use a proper grip" is useless.
- **rationale** — why it matters, offered only if they ask
- **contextual?** — is this wrong *in general*, or only wrong *for what we are
  teaching here*? A finger along the spine is a real grip for delicate slicing.
  Chef says "not for this one" rather than "wrong", and that distinction is a lot
  of why she sounds like a teacher.
- **what must be visible** to claim it — if the thumb is hidden, Chef must not
  say anything about the thumb

**`safetySignals`** — what stops the lesson immediately. Only things you would be
confident about **from a photograph**, not things you would infer. And please
mark anything you would NOT actually stop a student for, because we would rather
under-alarm than cry wolf.

**`notVisuallyAssessable`** — what a photo cannot establish for this skill, and
**the question to ask instead**.

**`equipment`** — which tools this technique is written for, which need different
handling, and what changes with each. Carbon vs stainless, non-stick vs cast
iron, gas vs induction vs electric, Japanese vs Western knives, a cheap thin pan.

**`parts`** — the technique broken into 3–5 components a cook can check on their
own body or their own pan, all visible at once. For the grip: hand forward on the
blade / thumb on the flat / index curled on the far side / three fingers round
the handle. Not steps, parts.

**`framing`** — what Chef should say to get the thing into view, and what
movement shows it. Ours is "rest the blade on your board, look down at your hand,
and turn it slowly, like you are showing me both sides."

---

## Assessing the result, not just the technique

For many skills the **outcome** is far more visible than the motion. Nobody can
watch a dice reliably at 7fps, but a board of finished cubes is trivially
readable: size spread, squareness, consistency.

For each skill, tell us **which is the better thing to look at**, and if it is
the result, what good and bad look like. Include the numbers a professional
would use, and the tolerance a home cook should actually be held to. Those are
different and we want both.

---

## Priorities

**First, rubrics for skills that already have lessons.** Highest value per hour:
the words exist, the judgement does not.

1. **Knife Skills** (11 more) — claw grip especially. It is the safety one, it is
   the natural next lesson, and knuckles and fingertips are very visible.
2. **Heat & Pan Control** (11) — colour and sound are the whole game here, so it
   may be the most watchable category we have. Fond, sear, butter browning,
   crowding, oil shimmer.
3. **Cooking Basics** (9) — several are judgement rather than technique, so tell
   us honestly which are not watchable at all.

**Second, the unwritten categories**, in this order: Eggs, Meat, Sauces, Flavor,
Intuition. Eggs first because it is cheap to practise and heavily visual;
Intuition last because we suspect much of it cannot be watched and would like
your view on that.

**Third, Mother Sauces**, below.

---

## Mother Sauces

A new category, not yet designed. We want your view on the shape as well as the
content.

**Which sauces, and is the classical five still the right teaching frame?**
Béchamel, velouté, espagnole, hollandaise, tomate is Escoffier's canon. We have
read that some schools drop espagnole for demi-glace, treat mayonnaise as a cold
mother, or teach beurre blanc as more useful to a home cook than any of them.
**We would rather teach what a working instructor teaches in 2026 than what a
1903 book says**, so tell us what you would actually build a course on, and what
you would cut.

**What comes before them.** We suspect roux is a skill, emulsion is a skill, and
reduction is a skill, and that the sauces are challenges built on those. Is that
the right decomposition, or does it break something?

**Per sauce we need:** ratios by weight and volume with tolerances; the order
operations must happen in and which are genuinely order-dependent; how you know
it is done **by eye** (this is the good part: roux colour, nappe, the coating of
a spoon, the break of a hollandaise); how it fails, what the failure looks like,
and whether it can be rescued; how it is held, and how it behaves reheated.

**Where the camera should be genuinely strong.** Roux colour is a continuous
visible scale from white through blond to brown, which is close to ideal for us.
Please tell us how you would describe each stage in words a beginner can match to
what they see, and how fast the window is.

**The honest question:** is a mother sauce something a person can learn from a
teacher who cannot taste it? If half of it is taste and texture in the mouth,
say so, and tell us what the visible half is worth on its own.

---

## Cross-cutting questions

1. **Ordering.** We have prerequisites, and we invented them. Where is our order
   wrong, and where does teaching one thing before another actually hurt?
2. **Mastery.** We currently count a skill learned when Chef watches it done once.
   How many correct repetitions before a real instructor considers it habit, and
   does that number differ by skill?
3. **The one-correction rule.** We deliberately give a single correction at a
   time. Is that how you teach, and are there techniques where two must be fixed
   together because fixing one alone makes it worse?
4. **What beginners actually do wrong**, as opposed to what books say they do. If
   there is a mistake you correct constantly that no textbook lists, that is the
   most valuable thing you can tell us.
5. **What cannot be taught this way at all.** We would rather leave a skill off
   the map than teach it badly through a camera. Which ones need a person in the
   room, and why?
6. **Where instructors genuinely disagree**, so we do not present one school as
   settled fact.

---

## Answer format, and what not to send

Please answer **per skill**, in the two blocks above. Prose is fine, structure
matters more than polish; we transcribe it into code.

**Please do not send:** history, etymology, nutrition, general encyclopedia
content, or long explanations of things a cookbook covers. We can generate all of
that and none of it makes Chef better.

**Do send** the things that only come from having taught: the corrections you
repeat, the variations you have learned to leave alone, the moment you stop a
student, and the thing you can tell at a glance from across a kitchen.

**Sourcing.** Where a claim is contested, say so and give both positions. Where
it comes from your own teaching rather than a source, say that too: we would
rather have "this is what I correct constantly" than a citation, and we would
like to know which one we are getting.

---

## Appendix A: the 35 unwritten skills

**Eggs** — crack an egg · scrambled · fried · soft-boiled · hard-boiled ·
poached · omelette · egg mastery (challenge)

**Meat** — season meat · dry before searing · internal temperature · sear ·
baste a steak · rest meat · butterfly a chicken breast · cook a great steak
(challenge)

**Sauces** — what is fond · pan sauce · vinaigrette · understand an emulsion ·
thicken a sauce · balance a sauce

**Flavor & Seasoning** — salt properly · understand acid · understand fat ·
understand umami · fix bland food · fix oversalted food · finish with acid

**Cooking Intuition** — know why food tastes bland · make substitutions ·
recover from overcooking · time multiple components · scale a recipe · cook
without a recipe

## Appendix B: the 32 written skills needing rubrics

**Knife Skills** — grip *(done, use as the worked example)* · claw grip · slice ·
rough chop · dice · mince · julienne · dice an onion · mince garlic · chop herbs ·
slice against the grain · mirepoix (challenge)

**Heat & Pan Control** — stove levels · preheat · pan ready · oil · crowding ·
sauté · sear · butter · deglaze · reduce · pan sauce (challenge)

**Cooking Basics** — read a recipe · mise en place · season as you go · taste as
you go · simmer vs boil · doneness · thermometer · rest food · cook without a
timer (challenge)

## Appendix C: the worked example

`Glutt/Models/Skills/SkillVisualCheck+KnifeGrip.swift` in this repo is a complete
rubric for one skill: target technique, seven acceptable variations, five ranked
mistakes with their exact spoken corrections, safety signals, supported and
unsupported equipment, and what cannot be seen. **Anything in that shape, for
another skill, is immediately usable.** It is worth reading before answering.
