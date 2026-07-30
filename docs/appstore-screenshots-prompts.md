# Glutt — App Store screenshot set (Gemini prompt kit)

6 panels. Story arc: **what it is → why you'd start → the magic → the habit → the payoff.**

Brand tokens pulled from `Glutt/DesignSystem/Theme.swift`:
cream `#FAF3E7` · card `#FFFDF7` · herb green `#2E5339` · mint `#8FE3A3` · honey `#FCF0D6` ·
amber `#C28C21` · tomato `#D9483B` · peach `#F7E2D4` · near-black `#241E19`
Fonts: **Bricolage Grotesque** (display) / **Nunito** (UI).

---

## 0. How this is actually built — hybrid, not all-Gemini

Two attempts at letting Gemini render whole panels proved it cannot be trusted with the things that
must be exact. Given layout instructions to follow, it re-imagines everything else: filter chips came
back reading "Filters / Boont / Recups", the search placeholder became a generic "Search", the cream
background went white, the Cook button and tab bar vanished, `2 of 15` silently became `3 of 15`, and
the locked mascot was redrawn as a different parrot entirely.

So the split is:

| Job | Tool | Why |
|---|---|---|
| Photoreal food cut-outs | Gemini (Nano Banana Pro) | What it's genuinely great at |
| Mascot character art | Gemini, generated **once** per pose, then frozen as a PNG | Identity must not drift |
| Real app UI, headline type, layout | `compose.py` (Pillow) | Must be pixel-exact and repeatable |

Headlines are set in the **real `BricolageGrotesque-Variable.ttf`** from `Glutt/Resources/Fonts`, at
weight 800 / width 82 — that condensed extra-bold is the poster look in the references, and no
image model can match a real font file.

**The toolchain** (session scratchpad, copy it somewhere permanent if you want to keep it):
- `gen.py` — prompt file + reference images → PNG via Gemini, with retry on 429/503
- `compose.py` — panel config → finished 1320×2868 PNG. Chroma-keys food props, flood-keys the
  mascot off white, draws the bezel, insets the real screenshot, sets type with variable-axis control
- `panels.py` — one dict per panel: background, blob, phone position, props, mascot, headline
- Output size is **1320×2868** (iPhone 6.9", what App Store Connect wants) — no padding step needed

**Food props must be generated on pure magenta `#FF00FF`**, never white — plates and cream sauces
are unkeyable against white. `key_magenta()` handles the cutout and de-fringes the edges.

**Model note:** image generation requires **billing enabled** on the key's Cloud project. Free tier
reports `limit: 0` for every image model (Nano Banana Pro, Nano Banana 2, 2.5 Flash Image) while text
models keep working — which makes it look like a broken key when it isn't.

---

## STEP 1 — The mascot: a brown bear, generated once and frozen

The mascot is a **brown bear cook**, not a parrot — the brand already has a bear. Two existing assets
define him:
- `Glutt/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` — a flat deep-green bear-and-pot
  mark (lid, side handles, steam). Source of the **flat geometric construction, the cream muzzle
  patch, and the nose-above-curved-smile**.
- `Glutt/Resources/Assets.xcassets/gluttBear.imageset/gluttBear.png` — a painterly brown bear with
  its tongue out. Source of the **brown fur and the hungry personality**.

He is deliberately **brown, not green**: a green bear vanishes on the green panels (2, 4, 6), and
flat vector reads better than painterly fur at store-gallery thumbnail size. The short deep-green
`#2E5339` bib apron carries the brand colour instead, and reads instantly as "cook".

Locked poses, in `~/Desktop/glutt-appstore/mascot/`:

| File | Pose | Used by |
|---|---|---|
| `bear-wave.png` | waving, wooden spoon in the lowered paw | panels 1, 6 |
| `bear-speak.png` | paw raised mid-explanation, mouth open | panel 3 |
| `bear-peek.png` | peeking over a horizontal edge, paws on top | panel 4 |
| `bear-basket.png` | holding a veg basket with both paws | panels 2, 5 |

**How to add a new pose — this method matters.** Do NOT ask for a multi-pose character sheet in one
image. Tried twice: the model fixed one face out of four and then ignored every instruction to
propagate it, returning a near-identical image. Instead:

1. Render ONE canonical pose and iterate until it's right (`prompts/bear-wave.txt`, then
   `bear-wave2.txt` for surgical fixes).
2. For each further pose, attach that canonical PNG as the single reference and describe only the new
   pose, restating the face rules verbatim (`prompts/bear-speak.txt` etc.).

Single-subject edits hold identity; multi-subject grids do not.

**Two face rules must be restated in every pose prompt**, because they are the reliable failure modes:
- The two eye whites must stay SEPARATE with a band of fur between them. Left unstated, they merge
  into one cream mask spanning the face and the character reads as an owl in goggles.
- The nose sits BELOW the eye line and must not overlap either eye.

Also restate "do not lengthen the apron" — unconstrained, it grows into a long green dress that
swallows the silhouette.

---

## The set as shipped — 5 panels

All 1320×2868, in `~/Desktop/glutt-appstore/panels/`. Story arc:
**what it is → the differentiator → the habit → the everyday problem → the payoff.**

| # | Headline | Background | Screenshot | Mascot pose | Floating props |
|---|---|---|---|---|---|
| 1 | Glutt / **Cook what you save** | cream + peach blob | Recipes (13 saved · 3 cooked) | sitting, waving, spoon | pasta "40 min", chicken "Ready now" |
| 2 | **Talk to Polly while you cook** | honey + peach blob | Polly live cook (dark) | sitting, mid-speech | shrimp skillet; bubbles "Flip it now", "How much salt?" |
| 3 | **Swipe to find tonight's dinner** | herb green | Discover (Turkey Pot Pie) | peeking over the hill | salmon "45 min" |
| 4 | **Use what you already have** | cream + sage blob | Kitchen (pantry states) | sitting with veg basket | onion "Add to list", garlic "In your kitchen" |
| 5 | **Macros, no math** | herb green | Recipe detail | sitting right, waving | grilled chicken + magnified macro card |

Panel 2 of the original six — **"Paste a link. Get a recipe."** — was cut. It needs a screenshot
of the import flow that cannot be captured in the simulator: allrecipes, budgetbytes and
minimalistbaker all fail the fetch with "Couldn't load that page" (they block the simulator's
request), and Wikibooks fetches but has no schema.org Recipe markup so extraction returns
"Needs review" with empty ingredients. The fallback — tapping "+" to shoot the add-recipe sheet —
needs a UI-automation `tap`, which is not among the XcodeBuildMCP workflows enabled here.
**To add it later:** capture the "+" add sheet (or a resolved import) on device, then add a `p6`
dict to `panels.py` — green background, `bear-basket` scene band, headline "Paste a link." /
"Get a recipe.", and no third-party logos in the art (App Store rules).

---

## The scene band — what fixed the "pasted sticker" problem

A mascot dropped into a corner reads as fake, however good the character is: no ground under it,
no interaction, dead space around it. The fix is to let Gemini compose **the whole bottom third as
one scene** — hill, mascot, scattered props, shrubs, steam, floating leaves — on a magenta
background, then key it and composite it **in front of** the phone so the phone rises out of the
hill instead of floating above empty background.

Every panel shares the same soft sage `#E3EEDC` hill, which is what makes five separate posters
read as one continuous world.

Two implementation details that matter:
- `compose.py` samples the median colour of the band's bottom row and fills from there to the
  canvas edge, so the hill continues seamlessly however the band is positioned.
- Constrain the mascot hard in the prompt — "entirely within the LEFT 20% of the image width,
  no more than 42% of the image height". Unconstrained, he lands centre-frame and covers the
  phone's UI text.

---

## Screenshot capture — use the simulator, not a device

`-seed` seeds demo recipes AND bypasses the paywall; add `-uiPreview` to skip
`Superwall.configure`, which is what stops the StoreKit "Sign in to Apple Account" dialog
appearing over the UI. Full launch-arg hooks live in `Glutt/App/Router.swift`:

    -seed -uiPreview -tab recipes|discover|kitchen
    -seed -uiPreview -openRecipe        # pushes the first recipe's detail
    -seed -uiPreview -demoCook          # step-by-step cook mode
    -seed -uiPreview -importURL <url>   # import flow

Seeded data beats hand-made device state: 13 saved / 3 cooked, varied dishes, plausible macros.

Capture full-resolution with `xcrun simctl io <udid> screenshot --type=png` — XcodeBuildMCP's
`screenshot` downsamples to 368×800, too small to composite.

**Crop the status bar, don't fake one.** `crop_status` is a fraction of screenshot height, and it
must be measured per device, not guessed — on the iPhone 17 Pro capture the Dynamic Island block
runs y=42→152 of 2622, so 0.047 left a visible black notch and 0.062 is correct. The Max-sized
device screenshots need ~0.058.

---

## Still worth fixing

- **The macros on panel 5 don't sum.** `380 CAL` with `28g protein · 37g carbs · 1g fat` computes to
  ~269 cal, and 1g fat alongside granola is implausible. It is magnified as that panel's hero card,
  so it is the most scrutinised number in the set. Shoot a recipe with cleaner nutrition.
- **The bear is a promise the app does not yet keep.** He is on all five panels but appears nowhere
  in the product. Cheapest fix: his face as Polly's avatar on the live-cook screen.
- The bear's paw slightly overlaps the "Recipes" tab label on panels 1 and 4.
