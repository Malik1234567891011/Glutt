# Go-live plan — App Store submission

Five pieces of work agreed before the push to `main` and the App Store review
that follows it. Ordered by risk to the submission, not by the order they were
asked for: item 1 is the one that changes what reviewers see.

Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.

---

## 1. Turn off clip generation for user imports

**Why first.** Import clipping doesn't work reliably yet and must not be in the
build that goes to review. The clips already generated for the bundled chef
recipes have been through review once and stay exactly as they are.

**Constraint from the brief:** hide it, don't delete it. Every line of the
pipeline stays in the tree so the work can continue behind the flag.

The pipeline has one chokepoint for *starting* work and one for *re-driving* it,
and both need the gate or opening a recipe re-queues the job the other one
refused:

- `MediaClipEnqueue.shouldEnqueue` (`Glutt/Services/CookClips/MediaClipEnqueue.swift:15`)
  — the only gate on creating a job. Called by `ensure`.
- `MediaClipEnqueue.refreshStatus` (same file, line 99) — calls `ensure` when the
  server has no record (line 114) and re-runs Gemini `analyze` on a cooldown
  (line 132). A read-only status poll is fine; these two re-drives are not.

Enqueue call sites, all of which go through `ensure`:

- `Glutt/Services/Import/ImportInboxDrainer.swift:29` — share-extension imports
- `Glutt/Features/Import/ImportReviewView.swift:316` — in-app import
- `Glutt/Services/Discover/DiscoverSaver.swift:39` — saving from Discover
- `Glutt/Features/Recipes/RecipeDetailView.swift:295` — the status poll

- [x] 1.1 Add a single `MediaClipConfig.generatesClipsForImports` flag, following
  the `ChefContent.isEnabled` convention (one `static let`, commented with what
  turning it back on requires).
- [x] 1.2 `shouldEnqueue` returns false when the flag is off.
- [x] 1.3 `refreshStatus` skips the `!status.found → ensure` re-drive and the
  `runAnalyze` retry when the flag is off, but still reads status so bundled
  chef recipes keep reporting `ready`.
- [x] 1.4 Hide the clip progress banner while the flag is off. **Recipes imported
  before this build already have `mediaStatus == "queued"` persisted**, so
  without this they'd show a spinner that can never finish.
- [x] 1.5 Confirm playback of existing chef clips is untouched — that path is
  `NativeClipService` fetching approved segments, not the ingest pipeline.
- [x] 1.6 Test: flag off ⇒ no enqueue for a YouTube import; flag off ⇒ a recipe
  with `mediaStatus == "queued"` shows no banner; flag on ⇒ old behaviour.

---

## 2. Instagram imports have no cover image

**What's actually wrong.** Instagram is the only social platform with no
dedicated importer — `SocialMediaImport.canHandle`
(`Glutt/Services/Import/SocialMediaImport.swift:29`) covers TikTok and YouTube
only, and the comment says Instagram "stays on the HTML-scrape + AI path". That
path reads `og:` tags in `RecipeHTMLParser.parseMetaFallback` (line 210).

Measured against a live public post, three things are true:

1. `og:image` **is** served to a phone user-agent, so the scrape isn't the whole
   story.
2. That URL is a **signed CDN URL that expires** — the one probed carried
   `oe=6A7737BE`, roughly nine days out. Store the URL and the image dies.
3. `og:description` is a **truncated** caption, so the recipe text is clipped
   even when it parses.

`RecipeImageBackfill` already exists to solve (2) by persisting bytes, and
in-app import calls it eagerly (`ImportReviewView.swift:315`) — but the
**share-extension path doesn't** (`ImportInboxDrainer.swift`), and sharing from
Instagram is the common flow. It waits for the next foreground sweep.

Better source, verified working without auth:
`https://www.instagram.com/p/<shortcode>/embed/captioned/` returns the media
JSON and the **full** caption. (`www.instagram.com/oembed` now answers with HTML,
not JSON — dead end.)

- [x] 2.1 New `InstagramImport` mirroring `SocialMediaImport`: shortcode out of
  `/p/`, `/reel/`, `/reels/`, `/tv/`; fetch the embed route; take image, full
  caption and author; parse the caption with `TextRecipeParser`.
- [x] 2.2 Route Instagram to it in `RecipeImportService.importFrom`, keeping the
  existing og: scrape as the fallback and `instagramBlocked` as the last resort.
- [x] 2.3 Cache image bytes eagerly in `ImportInboxDrainer` so shared imports
  don't depend on a later sweep landing inside the signing window.
- [x] 2.4 Tests: shortcode extraction across all four URL shapes; caption and
  image parsed out of a captured embed fixture.
- [x] 2.5 Show `draft.imageData` on the review screen. `previewCard` read only
  `imageURL`, so a share-sheet import carrying the picture as bytes — the
  Instagram reel case, and the one path that already worked — still reviewed as
  though it had no image.

---

## 3. Pinterest import

Probed live and confirmed working with no auth and no key: Pinterest's own web
resource API, `GET https://www.pinterest.com/resource/PinResource/get/`, with
`source_url`, a JSON `data` parameter and the single header
`x-pinterest-pws-handler: www/index.js`.

What a real food pin returns (measured, pin `364932376102173088`):

- `title` / `grid_title` — a clean recipe title
- `description` — **798 characters including a full ingredient list**, exactly
  what `TextRecipeParser` already eats
- `images` — every size up to `orig`, on `i.pinimg.com`
- `link` — the outbound URL to the original recipe site, `null` for pins native
  to Pinterest
- `story_pin_data` — Idea Pin pages, with a `recipe_data` slot in the schema

Plain HTML scraping is not an option: a pin page served to a phone user-agent is
a JS shell with an empty `<title>` and no `og:` tags at all.

This goes **client-side** in Swift along`SocialMediaImport`, not in the Vercel
proxy — the request should come from the user's phone IP. Pinterest rate-limits
and blocks datacenter ranges, and the proxy is one IP for every user.

- [x] 3.1 Add `pinterest` to `SourcePlatform`, with its label, and to
  `ImportedRecipeDraft.platform(for:)`. Find every switch over the enum
  (icons, attribution rows, share-extension copy) and handle the new case.
- [x] 3.2 New `PinterestImport`: pin id from `/pin/<id>/`, country domains
  (`pinterest.ca`, `br.pinterest.com`, …) and `pin.it` short links, which need
  a redirect followed first.
- [x] 3.3 Call `PinResource`, map the payload to `ImportedRecipeDraft`.
- [x] 3.4 **When the pin has an outbound `link`, follow it and run the existing
  website scraper** — a real recipe site gives JSON-LD with proper ingredients
  and steps, which beats any pin description. Fall back to the pin's own data
  when that fetch or parse fails.
- [x] 3.5 Register in `RecipeImportService.importFrom` and in the share
  extension's accepted-URL check.
- [x] 3.6 Tests: id extraction for every URL shape; payload → draft mapping from
  a captured fixture; outbound-link preference; graceful failure.
- [x] 3.7 Add `.pinterest` to `DraftCleanup.wouldImprove`. Pin descriptions are
  social captions — hashtags and emoji wrapped around an ingredient list — so
  they want the same unconditional LLM pass TikTok and Reddit already get.
  Reddit sets the precedent for doing this even though it can also follow an
  outbound link to structured data.

---

## 4. Cooking Basics lesson isn't tappable

Reported: the example egg lesson renders but doesn't respond. Root cause to be
confirmed against `CookingBasicsView` — candidates are a row that isn't a real
button, a lesson with no backing `Recipe` row to open, or the completion closure
`{ recipe in isShowingBasics = false; open(recipe) }` racing the sheet dismissal
in `RecipesView`.

- [x] 4.1 Confirm the root cause with evidence rather than guessing.
- [x] 4.2 Fix it, matching how the chef and restaurant pages open a recipe.
- [x] 4.3 Seeding turned out not to be the problem — the lessons were there and
  rendering, they just couldn't be pressed.

**Root cause, confirmed.** `CookingBasicsView` opened each lesson with
`NavigationLink(value: lesson)` (line 63 as it was), but the screen is presented
as a sheet wrapping its own bare `NavigationStack`
(`RecipesView.swift:230-234`), and the `navigationDestination(for: Recipe.self)`
that resolves a `Recipe` lives in the Recipes stack *outside* the sheet. A
`NavigationLink(value:)` whose type has no destination in its own stack renders
inert. So it wasn't the egg — **no** lesson in the list was tappable, including
any the user generated themselves.

The fix routes rows through the `onOpenLesson` closure the screen already had for
AI-generated how-tos, which dismisses the sheet and pushes on the Recipes stack.
The closure also lost its `= nil` default, so a future caller can't silently
recreate a screenful of dead rows.
- [x] 4.4 Test covering tap → detail.

---

## 5. Discover: search, and reachable Save / Show next

Two changes, both in the Videos feed.

- [x] 5.1 Search. `DiscoverFeedViewModel` already has a `search` path and
  `api/discover/search.js` already exists, so this is mostly UI: a field styled
  like the one in `RecipesView`, wired to the existing method, with the
  suggested feed as the empty state.
- [x] 5.2 Layout. Save and Show next currently sit below the fold. Shrink the
  player and lift the buttons so both are visible without scrolling, accounting
  for `GluttTabBar.reservedHeight`.
- [x] 5.3 Verify on a real device size in the simulator, not just in a preview.

---

**Measured cause of the layout bug.** The player was
`.aspectRatio(9.0/16.0, contentMode: .fit)` with no height ceiling. These are
vertical clips, so on a 430pt-wide phone that resolves to roughly 430×764pt —
taller than the screen on its own, before the title, the creator line and the
button row. Save and Show me next were never on screen. The player now takes a
`playerMaxHeight`, computed from the viewport minus the chrome that has to stay
visible with it, so it narrows instead of overflowing.

## Close-out

- [x] 6.1 Re-audit the voice stack for remaining bugs and report findings.

### Voice bugs found and fixed in this pass

- **Finishing the last step by voice never opened the recap.** The green button
  was fixed earlier; the `mark_step_done` tool was not. It reported `{"done":
  true}` to the model but nothing set `wantsEnd`, so saying you'd finished left
  the cook parked on a completed recipe unless the model happened to also call
  `end_session`. `PollyToolRegistry.markStepDone` now calls `onEndSession`, which
  was already wired.
- **Muting didn't stop her talking.** `toggleHardMute` closed the mic and stopped
  the wake word but never cancelled playback, so the mute button did nothing
  audible mid-sentence. Worse with a cloned voice, where the audio is ours and
  nothing else would ever cut it off. It now cancels playback.
- **Backgrounding left the session stale.** There was no `scenePhase` handling at
  all. The OS suspends capture for us — there's no `UIBackgroundModes` audio
  entitlement — but nothing stood the session down, so coming back found it
  nominally engaged with dead watchdogs and a pill still reading "Listening".
  Now stands down to dormant on `.background` only, and does not end the session,
  because glancing at a text message shouldn't lose your place.

### Voice issues found and deliberately NOT changed

- `DemoScript` is now **Debug-only** rather than a hand-flipped boolean, so it
  cannot reach the App Store by being forgotten. It had to be build-gated rather
  than trusted to a checklist: the trigger matches the on-device recognizer's
  partial transcripts, which run even while dormant, so a step reading "rest and
  serve" or a cook asking "when do I serve this?" would get shouted at — and the
  Realtime path deletes that turn without answering, so the question vanishes.

  **Film the demo from the `Glutt` scheme, not `Glutt Beta`.** `Glutt Beta` is
  Release on both build and run (`project.yml:218-227`), so the cue is inert
  there. Verified: a Release build compiles clean with the cue off.
- Reconnect doesn't re-arm the dormancy watcher or reset `watchdogStrikes`, so
  after a network hiccup the follow-up timeouts stop firing and the next silence
  escalates faster than it should. Real, but it needs a careful read of the
  reconnect ladder rather than a quick patch on the night of a submission.
- Wake suppression is tied to `isPollySpeaking`, leaving a gap between the model
  committing text and the cloned voice starting to play, where room echo could
  trip the bare "chef" wake.
- The overflow menu exposes AEC/duplex debug toggles in production builds.
- [x] 6.2 Full build, full test run (455 passing), simulator pass over the
  Discover layout and search field.
- [ ] 6.3 Hand back for review **before** the push to `main`.

### Verification notes

- 455 tests pass, including 27 new ones across the clip gate, Pinterest and
  Instagram.
- Discover Videos was confirmed by screenshot: search field at the top, player
  shrunk, both buttons visible above the tab bar without scrolling.
- The live probes behind the two new importers were run by hand before any Swift
  was written — Pinterest's `PinResource` returned a real food pin with an
  800-character ingredient list, and Instagram's embed route returned a full
  caption with a working image URL. The unit tests run against those captured
  payloads, trimmed, in `GluttTests/Fixtures/`.

### Still open

- Driving the Deck/Videos toggle with synthetic clicks didn't work, so the
  Videos surface was screenshotted by temporarily defaulting the mode (reverted).
  Worth a human glance at the toggle itself.
- Searching in the Videos feed was verified by code path, not by typing into the
  field: `discover/search` and `discover/suggested` share one authenticated
  helper in `DiscoverService`, and the suggested feed works, so search reaches a
  live endpoint. An unauthenticated probe returns 401, which is the endpoint
  behaving.

## Notes and risks

- **Pinterest and Instagram both depend on undocumented or embed-only
  endpoints.** They work today, measured, but they are not contracts. Both
  importers must fail soft — degrade to the generic scrape and never block the
  import — and both deserve a fixture-based test so a future break is
  diagnosable rather than mysterious.
- **Meta's oEmbed terms** forbid persisting metadata from that endpoint for
  anything but rendering an embed. The embed route used here is a different
  surface, and the app already scrapes `og:` tags, but storing an Instagram
  thumbnail as a recipe cover is worth a deliberate decision rather than a
  silent one.
