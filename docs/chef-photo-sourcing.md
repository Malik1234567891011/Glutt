# Chef feature: photo sourcing

Status as of 2026-07-30. The Top Chefs feature ships with placeholder art: chef
portraits are initials on a tinted circle, and the fifteen dishes reuse the
existing stock food photos in `Assets.xcassets`. This is what it takes to
replace them.

**Decided 2026-07-30:** Omar is sourcing the fifteen dish photos by hand
(option B below). The shopping list lives in
`design_handoff_top_chefs/dish-photos/README.md`. Chef portraits stay as initial
monograms until there is written permission, so the "Official" badge is not
making a claim nobody agreed to.

## What I tried without an API key, and why it failed

| Source | Key needed | Result |
|---|---|---|
| Openverse (Flickr CC) | no | Amateur snapshots. A billboard, a statue, a restaurant doorway. Unusable. |
| Wikimedia Commons | no | Legally clean, but restaurant table snapshots with Coke cans and receipts. Two or three usable out of thirty. |
| Foodiesfeed | no | Real food photography, free for commercial use, but a generic catalogue. No Beef Wellington, no birria, no katsu. Searching returns a burger for "beef wellington". |
| Unsplash internal search | blocked | Returns "Authorization required" now. The public API needs a free key. |

Conclusion: no keyless source can produce a coherent set of fifteen specific
dishes at the quality the app already ships.

## Option A, fastest: give me a free API key

Either one works, five minutes end to end, and then no further work from you.

**Pexels** (best fit for bundling into the asset catalog)
1. https://www.pexels.com/api/ → "Get Started" → sign in
2. Copy the API key
3. Paste it to me, or put it in `vercel-ai-proxy/.env.local` as `PEXELS_API_KEY=`

Pexels licenses allow downloading, modifying and shipping the photos inside an
app, with no attribution required.

**Unsplash** (matches how `CookingBasics` and the Plates seed deck already work)
1. https://unsplash.com/developers → "Register as a developer" → "New Application"
2. Copy the Access Key

Unsplash's API terms want the photos hotlinked from `images.unsplash.com`
rather than bundled. That is exactly what the app already does elsewhere, and
`RecipeImageBackfill` caches them locally on first view, so it works offline
after that.

## Option B: you grab the photos yourself

Fifteen files. Any stock site you like: Unsplash, Pexels, Freepik, or your own
camera. Spec:

- Landscape, at least 1600 pixels wide, JPEG or PNG
- The dish fills the frame, shot from above or at a 45 degree angle
- No text, no watermarks, no visible restaurant branding
- Name the file exactly as listed below and drop them all in
  `design_handoff_top_chefs/dish-photos/`. I will crop, downscale and wire them up.

| Filename | Search for |
|---|---|
| `beef-wellington.jpg` | beef wellington sliced |
| `pan-seared-salmon.jpg` | crispy skin salmon fillet pan |
| `shepherds-pie.jpg` | shepherds pie baking dish |
| `spiced-lamb-flatbread.jpg` | lamb flatbread yogurt |
| `scrambled-eggs.jpg` | creamy scrambled eggs toast |
| `steak-bites.jpg` | garlic butter steak bites skillet |
| `katsu-sandwich.jpg` | katsu sandwich milk bread |
| `truffle-mac.jpg` | baked macaroni and cheese skillet |
| `fried-rice.jpg` | chicken fried rice wok |
| `hot-honey-chicken.jpg` | crispy fried chicken honey glaze |
| `birria-tacos.jpg` | birria tacos consomme |
| `smash-burgers.jpg` | smash burger cheese lacy edges |
| `orange-chicken.jpg` | orange chicken glazed crispy |
| `chicken-shawarma.jpg` | chicken shawarma flatbread |
| `burrito-bowl.jpg` | burrito bowl rice beans chicken |

## Chef portraits are a separate problem

Two questions have to be answered, and only the second one is technical.

**1. Do you have the right to use their faces?** A photo of a public figure next
to an "Official" badge, on recipes we wrote, in a paid app, reads as an
endorsement. That is a right of publicity question, not a copyright one, and it
is the kind of thing App Review has pulled apps for. A CC licence on the
photograph does not grant it. Worth a decision before shipping, whatever the
photo source.

**2. What is actually available?**

| Chef | Wikimedia Commons | Notes |
|---|---|---|
| Gordon Ramsay | Yes, several CC BY 2.0 | Usable head and shoulders shots in chef whites |
| Nick DiGiovanni | Yes, CC BY 4.0 and CC BY-SA 4.0 | One is a clean straight to camera portrait |
| Joshua Weissman | None | Nothing licensed on Commons |

So a photo rail would be two real faces and one monogram, which looks broken.

Alternatives that carry no likeness risk:

- Keep the initials monograms (what ships today). Consistent, and honest.
- Commission or generate three illustrated chef avatars in the app's palette, so
  the rail reads as illustration rather than as a claim of endorsement.
- Get written permission or a licensed press kit from each chef's team, which is
  also what makes the "Official" badge true.

Portrait spec if you do supply photos: square, face centred, 512 x 512 or larger,
named `chef-gordon-ramsay.jpg`, `chef-nick-digiovanni.jpg`,
`chef-joshua-weissman.jpg` in `design_handoff_top_chefs/portraits/`. Wiring them
in is one line per chef (`portraitAsset:` in `Glutt/Models/Chefs.swift`).
