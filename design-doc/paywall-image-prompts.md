# Glutt paywall — image slots and generation prompts

For Superwall paywall **249784** (draft), which replaces the live **243875**.

Six image slots remain filled with WalterPicks artwork. Each blue "blob" is baked
into its PNG, so replacing these six removes every remaining trace of the template.

| # | Slot | Node ID | On-screen caption |
|---|---|---|---|
| 1 | Page 0 hero | `node:YrIdHH6z228Bfi5p1BLip` | (headline: "Cook anything you actually want") |
| 2 | Slide 1 | `node:HnBcT8YGBI44XmGnzFyyv` | "Save any recipe in one tap" |
| 3 | Slide 2 | `node:VoDuNhjOxEg1LU3Kt7AIi` | "Cook hands-free with Polly" |
| 4 | Slide 3 | `node:Z6F4UtRXd5bm-Hbkjx48C` | "Know what is in your kitchen" |
| 5 | Slide 4 | `node:69Hxmwr8grBqwFIERcIPD` | "Macros from a single photo" |
| 6 | Slide 5 | `node:jS2RBZcd4T_MZK1l94Th8` | "Never wonder what to cook" |

## Read this before generating

Every one of these slots shows **app screenshots inside phone mockups**. No current
image model invents believable app UI from scratch: you get garbled pseudo-text that
looks nothing like Glutt, and shipping that on a purchase screen is an App Review risk.

So feed the generator **your real screenshots as input** and let it build only the
frame, the arrangement, and the background around them. That is what the
image-to-image prompts in the next section do. The single most important line in each
prompt is the instruction not to redraw the screenshot content, because models will
happily "improve" your UI into nonsense if you let them.

# Image-to-image prompts (attach your own screenshots)

## Prompt 0 — PRIMARY: reference layout + your screenshots

Use this when you attach the original template image as an inspiration/layout reference
alongside your screenshots. It is the best of the three approaches, because the
reference carries the exact composition and you only ask the model to swap content
and colour. The originals are saved in `design-doc/paywall-reference-images/`.

Attach the reference **first**, then your screenshots in left-to-right order.

```
You are given a layout reference image followed by one or more app screenshots.

REFERENCE (first image): use it ONLY for composition. Reproduce its phone count,
positions, rotations, 3D perspective, overlap order, relative scale, and drop
shadow placement as closely as you can. Reproduce the large organic blob shape
behind the phones at the same position, proportion and angle.

SCREENSHOTS (all remaining images): this is the new screen content. Place them
into the phone screens in the order given, left to right. Do NOT redraw, restyle,
regenerate, translate or alter anything inside them. Their text, icons, colours
and layout must survive exactly, sharp and fully legible. Crop only as needed to
fit the screen aspect ratio.

CHANGES from the reference:
- Remove every trace of the original app. None of its screens, colours, logos or
  text may survive anywhere in the output.
- Recolour the organic blob from blue to SHAPE_COLOR, keeping its exact shape,
  position and scale.
- Phone frames: slim matte black bezel, evenly rounded corners, Dynamic Island
  cutout, faint highlight along the edge of the glass. No glare, no reflection
  and no overlay across the screens.
- Shadows: soft, warm and neutral, rgba(42, 36, 32, 0.14), wide blur. Never
  coloured, never blue.

The background outside the blob and the phones must be fully TRANSPARENT.

No added text, no logos, no captions, no icons, no people.

Output PNG with alpha, at least 1600 px on the long edge.
```

Set `SHAPE_COLOR` per slot from the table further down. Transparent output matters:
the paywall page is already cream `#FAF3E7`, so an alpha PNG drops straight in and
the blob reads as a tint on the page rather than a pasted rectangle.

### What each reference actually contains

| Slot | Reference file | Composition |
|---|---|---|
| Hero | `01-hero.webp` | Two framed phones, tilted at opposing angles, front-right overlapping back-left |
| Save any recipe | `02-slide1-save-recipe.webp` | One framed phone lower left, plus two frameless screen cards fanned to the right |
| Polly | `03-slide2-polly.webp` | Two framed phones in 3D perspective, opposing angles, one high right, one low left |
| Your kitchen | `04-slide3-kitchen.webp` | Same file as the hero |
| Macros | `05-slide4-macros.webp` | Three framed phones in 3D perspective, stacked receding into depth |
| What to cook | `06-slide5-what-to-cook.webp` | A single phone in strong 3D perspective, rotated on its vertical axis |

Note the hero and "Your kitchen" ship the identical file. Either reuse one output for
both, or feed the hero reference twice with different screenshots so the two pages
don't look duplicated.

## Prompt 1 — no reference: Page 0 hero, two phones

```
Using the attached app screenshots exactly as provided, composite them into a
product mockup. Do NOT redraw, restyle, regenerate, translate, or alter anything
inside the screenshots. Every pixel of their content, text, icons and layout must
survive unchanged and stay perfectly sharp and legible.

Place each screenshot inside a realistic modern iPhone frame: slim matte black
bezel, evenly rounded corners, a Dynamic Island cutout at the top, a faint
highlight running along the edge of the glass. The screenshot fills the screen
area precisely, with no glare, no reflection, and no overlay across it.

Arrangement: two phones. The first sits slightly behind and to the left, rotated
about 8 degrees counter-clockwise. The second sits in front and to the right,
rotated about 8 degrees clockwise and positioned a little lower, overlapping the
first phone's lower right corner. Both float above the background with soft warm
neutral drop shadows falling down and to the right, rgba(42, 36, 32, 0.14), wide
soft blur, no coloured light anywhere.

Background: flat warm cream #FAF3E7. Behind the phone cluster, one large organic
hand-torn paper shape in soft sage #EAF1E7, irregular and asymmetric, extending
past the phones but never touching the edges of the frame.

No text, no logos, no captions, no icons, no people, no extra UI. Vertical
composition with generous empty cream space above the phones.

Output 1170 x 2080 px, PNG.
```

## Prompt 2 — no reference: carousel slides, three phones fanned

Run this once per slide with that slide's screenshots attached.

```
Using the attached app screenshots exactly as provided, composite them into a
product mockup. Do NOT redraw, restyle, regenerate, or alter anything inside the
screenshots. Their content, text, icons and layout must survive completely
unchanged and stay sharp and legible.

Place each screenshot inside a realistic modern iPhone frame: slim matte black
bezel, evenly rounded corners, Dynamic Island cutout, faint highlight along the
glass edge. Screens are clean, with no glare and no reflection.

Arrangement: three phones fanned like a spread hand of cards, overlapping left to
right. The left phone is rotated about 12 degrees counter-clockwise and sits
lowest. The centre phone is nearly upright, rotated about 3 degrees, and sits
highest and most forward. The right phone is rotated about 10 degrees clockwise
and sits slightly behind. Soft warm neutral shadows under each,
rgba(42, 36, 32, 0.12), wide blur, no coloured light.

Background: flat warm cream #FAF3E7 with one large organic hand-torn paper shape
in SAGE_OR_PEACH behind the cluster, irregular and asymmetric, bleeding past the
phones but not to the frame edges.

No text, no logos, no captions, no people. Vertical composition, even cream margin
around the whole cluster.

Output 1170 x 1462 px, PNG.
```

Replace `SAGE_OR_PEACH` per slide, alternating the way the app's own recipe cards
alternate their decorative tint panels:

| Slide | Shape colour |
|---|---|
| 1 Save any recipe | soft sage `#EAF1E7` |
| 2 Cook hands-free with Polly | soft peach `#F7E2D4` |
| 3 Know what is in your kitchen | soft sage `#EAF1E7` |
| 4 Macros from a single photo | soft peach `#F7E2D4` |
| 5 Never wonder what to cook | soft sage `#EAF1E7` |

## Capturing the screenshots to feed it

Shoot at a real device resolution so the generator has enough detail: iPhone 6.7 inch
is 1290 x 2796. Capture with the status bar clean, and prefer screens that read at a
glance, since these render small inside the paywall.

Suggested screen per slot:

| Slot | Screenshot to use |
|---|---|
| Hero | Recipes list, plus a recipe detail |
| Save any recipe | The share-sheet import, plus the imported recipe |
| Polly | The full-screen Polly session with captions |
| Your kitchen | Kitchen inventory with the pantry tiles |
| Macros | A recipe detail showing the nutrition banner |
| What to cook | Discover / Plates feed card |

## If the generator warps the screenshots anyway

Some models cannot resist re-rendering UI even when told not to. If that happens,
the fallback that always works is a dedicated mockup tool (Rotato, Angle, Shotsnapp,
or a Figma device-frame component): drop the screenshot into a device frame, export
with a transparent background, then place it on a plain cream canvas with the sage
or peach shape behind it.

## Brand constants — put these in every prompt

| Role | Hex |
|---|---|
| Cream background | `#FAF3E7` |
| Deep herb green | `#2E5339` |
| Tomato red | `#D9483B` |
| Amber | `#C28C21` |
| Warm near-black | `#241E19` |

Look: warm, natural daylight, real home kitchen, modern-cookbook editorial. **Not**
studio-sterile, not fine-dining, not moody, no blue or teal cast, no "AI gradient" glow.

## Global negative prompt (append to all)

```
no text, no lettering, no watermark, no logo, no user interface, no app screens,
no distorted fingers, no extra limbs, no faces, not dark, not moody,
no blue color cast, no teal-orange grade, no neon, no plastic CGI look,
no oversaturated HDR, no vignette, no restaurant plating, no tweezers
```

---

# Fallback: no phones at all, pure food photography

If the mockup route proves fiddly, these need no screenshots and suit a cooking app well.
Same slot order.

All shot warm and bright on cream `#FAF3E7`, natural daylight, real home cooking,
never studio-sterile or fine-dining. Append the global negative prompt to each.

1. **Hero** (9:16) — overhead cluster of five colourful home-cooked meal-prep bowls on
   pale cream linen, loose scallions and a halved lime scattered between them, a folded
   sage napkin and a worn wooden spoon, bright soft daylight from the top left, generous
   empty cream margin at the top for the headline.
2. **Save any recipe** (4:5) — an open, well-loved paper cookbook with a cracked spine
   beside three fanned handwritten recipe cards on pale oak, handwriting illegible and
   out of focus, a sprig of rosemary across one corner, soft morning light.
3. **Polly** (4:5) — over-the-shoulder view of someone cooking at a home stove, seen
   from behind so no face is visible, one hand tilting a cast-iron skillet of searing
   chicken thighs, the other holding wooden tongs, visible steam and a golden crust.
4. **Your kitchen** (4:5) — fridge and pantry contents laid out flat in a tidy even grid
   on cream: spinach, chicken breasts on parchment, milk, parmesan, a bowl of eggs, a jar
   of rice, olive oil, tomatoes on the vine, garlic, a lemon, scallions, honey.
5. **Macros** (4:5) — a single generous meal-prep bowl shot straight down on cream:
   crispy hot-honey chicken over white rice with cucumber, pickled red onion, sweetcorn,
   diced avocado and a small pot of herby yoghurt dressing.
6. **What to cook** (4:5) — a small home dining table set for three, seen from a standing
   three-quarter angle, a shared platter of roast chicken with lemon and herbs ringed by
   salad, roasted potatoes and a torn loaf, two people cropped at the shoulders so no
   faces show, warm evening light and one lit candle.

---

## Export settings

| Slot | Aspect | Export |
|---|---|---|
| Hero (1) | 9:16 | 1170 × 2080 px |
| Slides (2 to 6) | 4:5 | 1170 × 1462 px |

Generate at those sizes, then compress to WebP or JPEG under about 300 KB each
before uploading. Superwall auto-ingests remote URLs when you pass them to the
editor, so a public link is enough.

---

## Still outstanding on the paywall (not images)

- **Social proof on page 3 is set to visible `TODO` placeholders.** The template
  shipped with an invented testimonial ("HOOdyMelo", "WalterPicks has helped me…")
  and a "500K+ Users" figure. Both need real numbers and a real App Store review
  before publish. The app's existing "1M+ home cooks" and "4.9 stars" claims were
  already flagged internally as aspirational, so do not just copy those across.
- **Trial model decision** — see the conversation. Whichever product sits in the
  `primary` slot determines whether `hasIntroductoryOffer` is true, which drives
  the trial headline, the "No payment due now" line, and the "Try 3 days free" CTA.
