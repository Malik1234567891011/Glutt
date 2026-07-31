# Glutt — recipe import redesign (share extension)

Implement the redesigned import flow that appears when a user shares a video from
Instagram / TikTok to Glutt. Replaces the current grey `ProgressView` spinner.

Reference render: `reference-import-flow.png` (three states, left to right).
Interactive source of truth: open `design/Recipe Import Board.dc.html` in a browser
and scroll to the block labelled **2a** — every value below is lifted from it.

## Scope

Files to change:
- `GluttShare/ShareRootView.swift` — all three states below live here.
- `Glutt/Features/Import/ImportRecipeView.swift` — the in-app sheet's `.loading` and
  `.failed` cases should reuse the same two subviews.

Do **not** add a review/edit step. The user taps nothing during import. Parsing,
pantry matching and saving already happen without input; this is presentation only.

## Layout, shared by all three states

Sheet on `Theme.Colors.background` (`#FAF3E7`), top corners 26pt, over the dimmed
host app. Inside, top to bottom:

1. Grabber: 38 × 5pt, radius 100, `#D8CDBE`, 10pt from top, centred.
2. Header row, 16pt top / 20pt horizontal padding:
   - Left: uppercase label, Nunito 800, 12pt, tracking 1.6, `Theme.Colors.accent`.
   - Right: 30 × 30pt circle `#F1E9D6`, `xmark` glyph 18pt `#6E6456`.
3. Centre block, pinned 158pt from the sheet top, 24pt horizontal padding, centred:
   - The visual (see per-state below), 338 × 338pt.
   - Title, 24pt below it: Bricolage Grotesque 600, 21pt, tracking -0.4,
     line height 1.2, colour `#6E6456`, centred.
   - Sub-line, 7pt below: Nunito 600, 13.5pt, `#B0A697`.
4. Bottom actions where present: 20pt horizontal, 34pt bottom padding.

No progress bar. No percentage. No step counter. Nothing else on screen.

## State 1 — Importing

- Header label: **SAVING FROM INSTAGRAM** (substitute the real source name).
- Visual: the cooking loop animation, autoplaying and looping (see *Animation* below).
- Title: the dish name once known. Until then show two centred skeleton bars
  (`#EBE2D4`, 60% and 38% width, 11pt tall, radius 6) and crossfade to the real
  title over 200ms with a 6pt rise when it lands.
- Sub-line: the current pipeline stage, plain sentence case, no ellipsis:
  `Reading the recipe` → `Listening to the video` → `Building the recipe` →
  `Cleaning it up`. Crossfade between strings over 220ms. Any stage may be skipped,
  so any string must be able to follow any other.
- Pinned 42pt from the bottom, centred: `checkmark` 16pt + "You can close this,
  Glutt finishes it for you", Nunito 700 13pt, `#9A9082`. This is true — the import
  continues in the background via the existing import inbox. Do not show it if that
  is not wired up on the path you are implementing.

## State 2 — Done

Same layout, so the transition is in place and nothing reflows.

- Header label: **SAVED FROM INSTAGRAM**.
- Visual: the animation is replaced by the recipe photo — 214 × 214pt, radius 26,
  `.scaledToFill`, shadow `rgba(42,36,32,0.14)` radius 30 y 14. Behind it two
  offset cards, radius 30 `#F1E9D6` (inset -13 x, +11 top, -11 bottom) and radius 28
  `#F6EFE0` (inset -6 x, +5 top, -5 bottom), forming a small stack.
- Tick badge, bottom-trailing, offset (+14, +14): 52pt circle `Theme.Colors.accent`,
  `checkmark` 30pt `#FBF5E9`, shadow `rgba(42,36,32,0.2)` radius 22 y 10.
- **Float animation** on the stack, continuous while the state is visible:
  front photo + badge translate Y 0 → -9 → 0pt over 4.4s, ease in out, repeating.
  The two back cards translate Y 0 → -3 → 0 with scale 1 → 0.994 and opacity
  1 → 0.88, same duration, delayed 0.25s and 0.5s respectively. The lag is what
  makes it read as depth rather than a bounce — do not sync them.
- Title: dish name, same style as State 1.
- Sub-line becomes two lines, Nunito 600 15pt `#6E6456`, centred, line height 1.45:
  "In your recipes. 35 min, 4 servings, 8 of the 12 ingredients already in your
  kitchen." Numbers come from the saved draft and the pantry match.
- Actions: primary pill, full width, radius 100, `Theme.Colors.accent`, 16pt padding,
  Nunito 800 16pt `#FBF5E9`, shadow `rgba(42,36,32,0.14)` radius 24 y 10 — label
  **Back to Instagram** (host app name). Below it, 16pt gap, a text button
  **Open it in Glutt**, Nunito 800 15pt `Theme.Colors.accent`.

## State 3 — Failed

- Header label: **COULD NOT READ IT**, in `#C28C21`. Never red — tomato is reserved
  for destructive actions.
- Visual: recipe photo at 45% opacity, no card stack, no float. Amber badge in the
  tick's position: 52pt circle `#FCF0D6`, `exclamationmark` glyph 28pt `#C28C21`.
- Title: "No recipe in this one".
- Body: "Nothing was said out loud and the caption has no amounts. Keep the link and
  Glutt will ask you a couple of questions later." Only claim the parts that are
  true for the actual failure reason.
- Actions: primary **Keep the link anyway** (saves the URL as a stub recipe), text
  button **Try again**.

## Transitions

- Entry: sheet slides up (system). Contents fade in with an 8pt rise, 320ms ease out.
- Importing → Done: the animation crossfades to the photo over 260ms while the card
  stack scales in from 0.94; the tick badge then scales 0.6 → 1.08 → 1.0 over 320ms
  with a light spring and its checkmark strokes on over 180ms. This is the only
  energetic moment in the flow.
- The sub-line growing from one line to two animates its height over 260ms so the
  buttons do not jump.
- Importing → Failed: no shake, no red. Photo fades to 45%, badge fades in at 80%
  scale and settles, text crossfades. 300ms.
- Reduce Motion: skip the float and the badge spring; crossfade states over 200ms.
  The cooking loop should hold on its poster frame.

## Animation asset

`animation/cooking-loop.mp4` — 1080 × 1920, 12s, seamless loop.

**It must be cropped.** The source has a watermark at the top. Crop a 1000 × 1000
square at origin **x 40, y 380**, then render at 338 × 338pt. The clip's background
is already `#FAF3E7`, so it composites onto the sheet with no visible edge — do not
add a container, border or shadow around it.

Ask the motion designer for a Lottie export before shipping; a looping `AVPlayer` is
fine for a first pass but the MP4 is 12s of video for a decorative loop. If you keep
the video: `AVPlayerLooper`, muted, `.resizeAspectFill`, no controls, and make sure it
does not interrupt the host app's audio session (`.ambient`, `mixWithOthers`).

## Tokens used

Add any that are missing to `Theme.Colors` rather than inlining hex:

| Purpose | Hex |
|---|---|
| Background | `#FAF3E7` |
| Card surface | `#FFFDF7` |
| Warm tile | `#F4EDDC` |
| Deep warm tile | `#F1E9D6` |
| Stack mid | `#F6EFE0` |
| Skeleton / grabber | `#EBE2D4` / `#D8CDBE` |
| Accent (deep herb green) | `#2E5339` |
| Mint highlight | `#8FE3A3` |
| Amber warning | `#C28C21` on `#FCF0D6` |
| Heading | `#241E19` |
| Secondary text | `#6E6456` |
| Muted text | `#9A9082` |
| Extra-muted text | `#B0A697` |
| Cream on green | `#FBF5E9` |

Type: Bricolage Grotesque 600/700 for titles, Nunito 600/700/800 for everything else.
Both are already registered in `BrandFonts.swift`.

## Also in the design file, for context

The same board contains the current shipped flow recreated as **1a**, and three
fuller directions (**1b**, **1c**, **1d**) that were explored and set aside. Only
**2a** is being built. Ignore the rest unless asked.
