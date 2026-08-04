# Pre-push test script

Manual pass over everything that changed before the push to `main` and the App
Store submission after it.

Ordered by **risk**, not by feature. The first section is where a regression is
most likely to be hiding, because it's where existing behaviour was gated rather
than added to. If you only have ten minutes, do section 1 and section 6.

Legend: **[BLOCKER]** = do not push if this fails.

---

## 1. Existing chef clips still play — highest regression risk

Clip generation was switched off for imports, and that gate also covers playback.
The predicate is "is this a bundled chef dish", so if it's wrong in either
direction you either lose reviewed clips or leak clips onto imports.

- [x ] **[BLOCKER]** Cook a bundled Gordon Ramsay dish (Beef Wellington). Clips
  should still autoplay on the steps that have them, exactly as before.
- [ x] **[BLOCKER]** Cook the bundled scrambled-eggs dish (TikTok-sourced). Clips
  still play.
- [ x] Cook a Cotoa restaurant dish. No clips, no clip banner, no error — these
  never had clips.
- [ x] Cook a recipe you saved from Discover. No clips, and nothing that looks
  like a failure.

**What a failure looks like:** a chef recipe cooking with no video where you
remember video, or any recipe showing "Preparing technique clips…".

---

## 2. No clip machinery visible on imports

- [ ] **[BLOCKER]** Import a YouTube recipe. No "Preparing technique clips…"
  banner appears at any point, and none appears if you leave the detail screen
  open for a minute.
- [ ] **[BLOCKER]** Open a recipe you imported **before** today's build — one
  that used to show the clip banner. It must show **no** banner. Those recipes
  have `queued` saved in the database, and if the suppression missed them they'll
  spin forever with nothing left to drive them.
- [ ] Import a TikTok recipe. Same: no clip UI.

---

## 3. Import routing didn't break the platforms that already worked

Two new branches were inserted ahead of the existing ones in
`RecipeImportService.importFrom`, so the ordering is worth proving rather than
assuming.

- [ ] **[BLOCKER]** Paste a YouTube link. Title, creator, thumbnail, ingredients
  from the description — as before.
- [ ] **[BLOCKER]** Paste a TikTok link. Caption parsed into ingredients.
- [ ] **[BLOCKER]** Paste a normal recipe blog link (something with proper
  schema.org markup, e.g. Serious Eats or NYT Cooking). Full ingredients, steps,
  times, image.
- [ ] Paste a Reddit recipe post link.
- [ ] Import a screenshot of a recipe.
- [ ] Share a link in from Safari via the share sheet, then reopen the app. The
  recipe lands **with its image** — the share path now caches image bytes eagerly
  instead of waiting for a sweep.

---

## 4. Pinterest (new)

Pinterest's API is undocumented, so this is the feature most worth trying on
links you'd genuinely save rather than one happy-path pin.

- [ ] Paste a `pinterest.com/pin/<id>/` link for a recipe pin. Title, image,
  ingredients.
- [ ] **Share from the Pinterest app itself.** It usually produces a `pin.it`
  short link, which is the only path that exercises redirect resolution.
- [ ] A pin that **links out to a recipe blog**. This should follow the link and
  come back with the blog's proper ingredients and steps, which is better than
  the pin description — check you get real steps, not just an ingredient list.
- [ ] A native pin with the recipe in the description (no outbound link).
  Ingredients parse out of the description.
- [ ] **The title should be the pin's own title**, not a sentence of marketing
  copy lifted off the front of the description. This was a real bug in the first
  cut, so it's worth actually reading.
- [ ] Paste a **board** URL (`pinterest.com/someone/dinner-ideas/`). Expect the
  friendly "open a single pin" message, not a crash or a blank import.
- [ ] Paste a Pinterest **profile** URL. Same friendly failure.
- [ ] A video pin. It should at least come back with a title and image.

---

## 5. Instagram cover images (the original complaint)

- [ ] **[BLOCKER]** Share a recipe Reel from the Instagram app. The saved recipe
  has a cover image.
- [ ] Paste an Instagram post URL in-app. Cover image.
- [ ] On the import **review** screen, before you save — the image preview shows.
  That was a separate bug: the preview read only the URL, so a share that carried
  the picture as raw bytes reviewed as though it had none.
- [ ] Ingredients parse from the caption. The full caption is now read rather
  than the truncated `og:description`, so a Reel with a proper recipe in the
  caption should produce a real ingredient list.
- [ ] **Leave a freshly imported Instagram recipe for a day and reopen it.** The
  image must still be there. Instagram's image URLs are signed and expire, so
  this is the test that proves the bytes were saved rather than just the link.

---

## 6. Voice — the three fixes

- [ ] **[BLOCKER]** Cook any recipe to the last step, then finish it **by voice**
  ("I'm done", "mark that done"). The recap should open. This is the bug you
  reported before — the green button was fixed then, the voice path wasn't.
- [ ] Do the same with the green **Mark done / End recipe** button. Still opens
  the recap.
- [ ] While Chef is **mid-sentence**, hit mute. She should stop talking
  immediately. Try this with a **cloned voice** (Gordon) specifically — that's
  the case where nothing else would ever cut her off.
- [ ] Unmute. You should be back to dormant, waiting for "chef" — not open mic.
- [ ] **Background the app mid-cook** (swipe up, or lock the phone), wait a few
  seconds, come back. The pill should read "Say Chef to talk", not a stale
  "Listening". Your place in the recipe should be intact — it should not have
  ended the session.
- [ ] Pull down Notification Centre or Control Centre briefly. This should **not**
  drop you out of Listening — only real backgrounding does.

### Demo cue

- [ ] Run from the **`Glutt` scheme** (Debug) and say "serve". The shouted
  "YOU DONUT!" line fires. **Confirm this before you film.**
- [ ] It is inert on the `Glutt Beta` scheme, which is Release. That's deliberate
  — it's what stops it shipping — but it means Beta is the wrong scheme to film on.

---

## 7. Cooking Basics

- [ ] **[BLOCKER]** Recipes tab → **+** → "Cooking basics" → tap the fried-egg
  lesson. It should open the lesson. Previously **no** lesson row was tappable,
  not just this one.
- [ ] The sheet dismisses and the lesson opens in the Recipes tab, so **Back**
  returns you to your recipe list.
- [ ] Cook the egg lesson end to end.
- [ ] "Ask for a how-to" → type something ("grilled cheese") → the generated
  lesson opens. That path shared the closure that was changed, so it's worth
  re-checking.
- [ ] Reopen Cooking basics. The generated lesson is now listed, and tappable.

---

## 8. Discover

- [ ] **[BLOCKER]** Discover → **Videos**. The search field is at the top, and
  **Save** and **Show me next** are both visible without scrolling.
- [ ] Tap **Save**. It saves and moves on.
- [ ] Tap **Show me next**. Next clip loads.
- [ ] Type a dish into search and submit. Results change to that dish.
- [ ] Tap the **✕** in the search field. You go back to the suggested feed.
- [ ] Search something absurd ("xyzzy plutonium"). Friendly empty state, no spinner
  stuck forever.
- [ ] **Try it on a smaller phone** (iPhone 16e or an SE in the simulator). The
  player has a floor, so a small screen may scroll a little — check that it
  degrades sensibly rather than clipping the buttons off entirely.
- [ ] Toggle back to **Deck**. Swiping, saving and skipping all still work, and
  your place in the deck is where you left it.
- [ ] Toggle Deck → Videos → Deck a few times. No flicker, no duplicated cards.

---

## 9. Quick sanity sweep

- [ ] Fresh install (delete the app first). Onboarding, then the Recipes tab
  populates, restaurant and chef rails both render with images.
- [ ] Airplane mode: import fails with a readable message, Discover fails with a
  readable message, Cook Mode offers "Cook without Chef".
- [ ] Deny microphone permission, then open Cook Mode. Blocked cleanly with the
  "Cook without Chef" fallback.
- [ ] Cotoa restaurant page: logo, five dishes, all five with real photos.

---

## Known-and-accepted, don't file these

- Reconnect after a network drop doesn't re-arm the follow-up/idle timers, so a
  session can sit in Listening longer than it should after a hiccup. Parked until
  after the submission by decision.
- Wake suppression has a gap between the model committing a reply and the cloned
  voice starting to speak, where room echo could trip the bare "chef" wake.
- The overflow menu still shows the AEC/duplex debug toggles in production.
- Import clipping is off on purpose — it isn't broken, it's switched off behind
  `MediaClipConfig.generatesClipsForImports`.
