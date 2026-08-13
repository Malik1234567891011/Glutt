# Free tier test script

Manual pass over the freemium change, before this branch (`feat/free-tier`)
merges anywhere.

Ordered by **risk**, not by feature. Section 1 is where a regression is most
likely to hide, because that is where a paying customer can be harmed. Sections
2 and 3 are where the money is. If you only have ten minutes, do 1 and 2.

Legend: **[BLOCKER]** = do not merge if this fails.

**Setup.** On a phone, launch from the tooling with `GLUTT_FREE_TIER=1` and
`GLUTT_REAL_GATES=1`. Both latch, so you can then kill the app and open it from
the icon and stay on the free tier with a live paywall. `GLUTT_PRO_TIER=1` puts
you back. Launch **arguments** containing the letter "l" cannot be used on a
device: `devicectl` splits them into single letters and fails on `-l`. On the
simulator the arguments `-freeTier` / `-proTier` / `-realGates` / `-relaxGates`
all work normally.

---

## 1. A subscriber must lose nothing — highest regression risk

Every one of these worked before the free tier existed. The gate is new code
between the user and features they have paid for.

- [ ] **[BLOCKER]** With `GLUTT_PRO_TIER=1`, open a recipe. There is **no crown
  anywhere** on the screen, and Cook with Chef, Or cook step by step, Ask Polly
  and Add missing to groceries all do exactly what they used to.
- [ ] **[BLOCKER]** The `…` menu shows Units as a working picker, and Edit, Save
  as version, Add to collection and Share all work, with no crowns.
- [ ] **[BLOCKER]** The Kitchen tab is fully usable: all three segments with no
  crowns on them, the add menu, photo scan, voice dictation, and Invent a dish
  all the way through to a generated recipe.
- [ ] **[BLOCKER]** Discover swipes without any counter appearing, past ten.
- [ ] The sign-in screen still appears for an entitled user who is signed out.
  This is Pro-only by design; a free user must never be asked to sign in.

**What a failure looks like:** a crown on a paying customer's screen, or a
control that opens the paywall for someone who already bought it.

---

## 2. The free tier gives away exactly the four things it should

- [ ] **[BLOCKER]** Import a recipe from a link. It works, with no crown and no
  limit. Import several.
- [ ] **[BLOCKER]** Import from the iOS share sheet, from Instagram or a browser.
  Works. The share extension is deliberately untouched by any of this.
- [ ] **[BLOCKER]** Open any saved recipe. The photo, title, time, difficulty,
  the **macros banner** and the **ingredients list** are all fully readable.
- [ ] **[BLOCKER]** Switch to the **Steps** tab. The written steps are fully
  readable. Only the guided cook is Pro, not the recipe text.
- [ ] Change the servings stepper. The ingredient amounts and macros rescale.
- [ ] Discover deals cards and you can swipe ten of them.
- [ ] Create a recipe manually. Works, no crown.
- [ ] **[BLOCKER]** Open the Kitchen tab. It opens. The Ingredients segment shows
  your real inventory, you can search it, and **Add manually** adds an
  ingredient with no crown and no paywall.
- [ ] Search your kitchen, and search your recipes from the Recipes tab. Both
  free, including pressing Return on a recipe search: the AI re-ranking is
  **not** gated. Nothing about finding your own things costs money.

**What a failure looks like:** anything in this list wearing a crown. This is the
product we are giving away; if it is gated, the free tier has no reason to exist.

---

## 3. Every crown opens the paywall

Tap each one. The paywall must appear each time. A crown that does nothing is
worse than no crown.

Recipe detail:

- [ ] **[BLOCKER]** Cook with Chef
- [ ] **[BLOCKER]** Or cook step by step
- [ ] **[BLOCKER]** Ask Polly
- [ ] Add missing to groceries
- [ ] Use what I have (only appears when the AI proxy is unconfigured)
- [ ] Substitute, on a recipe that conflicts with your diet rules
- [ ] `…` menu: More details, Units, Edit, Save as version, Add to collection,
  Share. **Delete is deliberately free** and must still work.

Recipes tab:

- [ ] **[BLOCKER]** + menu: Plan a week of dinners
- [ ] + menu: Cooking basics, Browse collections, New collection
- [ ] Type a search and press Return. Plain results still appear; the paywall
  opens instead of the AI re-ranking.

Discover:

- [ ] **[BLOCKER]** The Videos toggle
- [ ] **[BLOCKER]** The eleventh swipe, and the See plans button on the cover

Kitchen. The tab itself opens for everyone, so these are the individual gates:

- [ ] **[BLOCKER]** Add menu: Scan with a photo, Choose a photo, Tell us what
  you have. **Add manually right below them must stay free.**
- [ ] **[BLOCKER]** The Tools segment. It selects and shows the tool list
  blurred behind See plans, rather than refusing the tap.
- [ ] **[BLOCKER]** The Groceries segment, same treatment, plus its crowned +.
- [ ] **[BLOCKER]** Invent a dish. The row is crowned but **opens**: you can read
  the pitch, pick a meal type, type a hint. The wall is on **Make something new**
  and nowhere earlier.

**What a failure looks like:** a tap that does nothing at all. If that happens on
*every* crown at once rather than one, suspect the `isPresenting` flag rather
than the gate: it is shared by every crown in the app, and there is an 8 second
watchdog for exactly that.

---

## 4. The swipe meter

- [ ] **[BLOCKER]** Swipe exactly ten cards. The tenth is allowed; the eleventh
  is not.
- [ ] **There is no counter anywhere.** Nothing on the deck says how many swipes
  are left. It runs silently and the wall is the first and only mention of a
  limit, the way Tinder does it. A visible tally makes people ration the feed.
- [ ] The weekday in the cover copy is the coming week boundary.
- [ ] **[BLOCKER]** Spend all ten, then press **undo**. You get a swipe back and
  the deck reopens. Undo must never cost you the card *and* the swipe.
- [ ] Subscribe (or `GLUTT_PRO_TIER=1`), swipe twenty, then go back to free. Your
  ten are still there: a subscriber's swipes are never counted against the free
  allowance.
- [ ] Kill and relaunch the app. The count survives.

---

## 5. Paywall behaviour

- [ ] **[BLOCKER]** On a **fresh install**, finish onboarding. The paywall
  appears once. Close it and you land in a working free app, not on a cover.
- [ ] **[BLOCKER]** Kill and relaunch several times. The paywall does **not**
  reappear on launch. It is once ever, not once per launch. Upgrading is prompted
  by the crowns from then on.
- [ ] Settings → Restore Purchases still works.
- [ ] **[BLOCKER, device only]** Buy with a sandbox Apple ID. Every crown
  disappears without a relaunch, and the Kitchen tab uncovers.
- [ ] Cancel the sandbox subscription and relaunch. The crowns come back.

---

## 6. What only a device can tell you

The simulator cannot load StoreKit products, so it pops a "Sign in to Apple
Account" dialog and paywall presentations there may report an error even when the
wiring is correct. Purchase, restore, and the unlock-on-purchase transition are
device-only checks.

---

## Known and deliberate

- **Deleting a recipe is free.** Nobody should have to subscribe to clean up
  their own library.
- **Reading versions of a recipe is free**, though creating one is Pro. Reading
  is reading.
- **The swipe counter is local.** Deleting the app resets it. It is a nudge, not
  a security boundary; the expensive features are gated on entitlement instead.
- **Unlimited free imports cost real money** (an LLM cleanup pass per import, plus
  transcription on video imports). That is a deliberate subsidy, chosen to beat
  ReciMe on the acquisition hook.
- **All gates currently register the `onboarding_complete` placement**, which is
  the one already published. Per-feature placements exist in `PremiumFeature` but
  are switched off until campaign 91288 carries them, because an unpublished
  placement presents nothing and turns every crown into a dead tap.
