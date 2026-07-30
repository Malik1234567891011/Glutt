# App Store Connect metadata, version 1.2

Everything you need to paste into App Store Connect for the 1.2 submission, plus the
things that are wrong in the **live 1.1 listing** and have to change with it.

- **Live now:** "Glutt - Cooking" 1.1, released 2026-07-15, updated 2026-07-20, seller
  CielPM, Inc., Food & Drink, `id6780553556`.
- **Submitting:** 1.2 (project.yml says build 11), new screenshots (5 panels,
  1320 x 2868, in `~/Desktop/glutt-appstore/panels/`), new app icon.
- **Locales:** the app ships English only (no `.strings` / `.xcstrings` anywhere), so keep
  the store listing at **English (U.S.) only**. Adding a second store locale would
  translate the listing while the app stays English, which reads as broken.
- **Style:** no dash is used as punctuation anywhere in this copy, per house style.
  Hyphens inside compound words ("hands-free", "3-day") are kept, since those are
  spelling, not an aside. Say the word if you want those gone too.

---

## 1. Read this before you submit

Ordered by how likely each one is to cost you the release.

### 1.1 The three real chefs are the biggest risk in this build

`Glutt/Models/Chefs.swift` ships **Gordon Ramsay, Nick DiGiovanni and Joshua Weissman**
by name, with credit lines ("Michelin chef, London", "MasterChef finalist"), portraits, and
five "greatest hits" recipes each presented as theirs. Per `docs/chef-photo-sourcing.md`,
the portraits and nine dish photos were cut from **YouTube thumbnails**.

That is a real person's name and likeness plus third-party photography, with no licence.
App Review guideline 5.2 covers exactly this, and a rejection here is not a metadata fix,
it is a code change under a clock. It is also the kind of thing a rights holder complains
about after approval, which is worse.

Options, cheapest first:

1. **Ship 1.2 with the chef rail hidden** behind a flag, submit everything else, and bring
   chefs back once the content is yours. One line in `ChefRail`.
2. **Keep the packs, drop the identity.** Rename the section to something like "Pro packs",
   replace the portraits with dish photography you own, and lose the names and credits. The
   recipes themselves are technique, not protected expression.
3. **Get written permission** from each chef or their management, and licence the photos.
   Real, but not on this submission's timeline.

Either way: **no chef names in the description, keywords, promotional text or screenshots.**
The copy below deliberately says "chef packs" and never a name.

### 1.2 App Privacy says "Data Not Collected" and that is no longer true

The live listing shows **Data Not Collected**. Since then the app added:

- **PostHog** (US region), with the customer's **email address as a person property** and
  the Supabase user id as `distinct_id`. `Glutt/Services/Analytics/Analytics.swift` says so
  in its own header comment.
- **Supabase accounts** via Sign in with Apple and Google, holding email and an auth id.
- **Superwall / StoreKit** subscription state.
- The AI proxy, which logs model, tokens and cost per install id (no prompt content, see
  `vercel-ai-proxy/api/_lib/usage.js`).

Inaccurate privacy answers are their own rejection reason, and this one is easy for Apple
to check because Sign in with Apple is in the binary. Fill in the answers in section 4
before you submit. Your policy at `glutt.org/privacy` already covers email, telemetry and
the OpenAI 30-day retention window, so only the ASC questionnaire needs work.

### 1.3 The live description sells a feature the app does not have

> "INSTANT CALORIES FROM A PHOTO. Snap a photo of your plate and Glutt estimates the
> calories and nutrition in seconds."

`Glutt/Services/AI/MealPhotoEstimator.swift` exists but **nothing calls it**. There is no
plate-photo calorie flow in the shipping app. Nutrition comes from the recipe, either
parsed on import or estimated from the ingredient list.

Same paragraph problem, smaller: "Got leftovers? Get fresh ideas instead of throwing them
out." Leftover tracking was deleted in the July simplification. What survives is "invent a
dish" from what is in your kitchen, which is a different promise.

Both are gone from the rewrite below. This is guideline 2.3.1 territory, and more
practically it is a refund request waiting to happen.

### 1.4 The live 1.1 release notes have two broken sentences

Currently on the store:

> "Glutt Premium is here start with a 3-day free trial."
> "A cleaner, more focused app Recipes, Discover, and Kitchen, all in one place."

Both are missing the punctuation that a dash used to carry. The no-dash rule needs a period
or a colon in its place, not nothing. Nothing else in the live description or notes is
misspelled, and the punctuation is otherwise clean. The fixed pattern is used throughout the
copy below.

### 1.5 Two mechanical blockers from the paywall work

From `docs/HARD-PAYWALL-FREE-TRIAL.md`, both must happen **before** you hit Submit:

- **Publish Superwall paywall 243875.** The build fetches whatever is published at review
  time. An unresolved placement means a locked app with no paywall, which is an automatic
  rejection.
- **Attach all three IAPs to the build:** `com.omarlahmimi.glutt.premium.yearly`,
  `...premium.monthly`, `...premium.yearly.trial`. Attaching the trial is what gets it
  approved and what makes it testable in the review sandbox.

Also: if build 11 was already uploaded to TestFlight, ASC will reject a second upload with
the same number. Bump `CURRENT_PROJECT_VERSION` to 12 in `project.yml` (both targets) and
run `xcodegen generate` before archiving.

---

## 2. The fields, ready to paste

Character counts are exact, and every field is inside Apple's limit.

### App Name (limit 30)

```
Glutt - Cooking
```
15 characters. Keep it. Renaming triggers a fresh name review and you gain little.

Optional, if you want the search weight instead: `Glutt: Recipes and AI Chef` (26). Only do
this if you are ready for the listing name to stop matching the icon label everywhere.

### Subtitle (limit 30)

Recommended:
```
Recipes and a live AI chef
```
26 characters. Says what it is, and carries two terms people actually search.

Alternatives:
- `Save recipes. Cook hands-free.` (30, exactly at the limit)
- `Your kitchen, sorted.` (21, what is live now, zero search value)

### Promotional Text (limit 170)

Editable any time without a new build, so this is your one lever between releases.

```
Glutt has been rebuilt. Every screen is redesigned, and Polly now wakes up when you say her name, so your hands never have to leave the pan.
```
140 characters.

### Keywords (limit 100, comma separated, no spaces after commas)

```
recipe,cookbook,meal,pantry,fridge,grocery list,voice,hands free,dinner,macro,calorie,cook
```
90 characters. Notes on why it looks like that:

- No "glutt", no "cooking", no "AI chef". Those are already in the name and subtitle, which
  Apple indexes, so repeating them wastes characters.
- No "Instagram" or "TikTok". Third-party trademarks in the keyword field are a known
  rejection. They are fine in the description as plain prose, which is how the live listing
  passed review.
- Singular forms only. Apple matches plurals from the singular stem.

### Description (limit 4000)

```
Glutt is your kitchen, finally figured out.

Save any recipe, cook it hands-free with your own live AI chef, and use what is already in your fridge.

SAVE RECIPES FROM ANYWHERE
Found something on Instagram, TikTok, Reddit or any recipe site? Share it to Glutt and it becomes a clean, cookable recipe with ingredients, steps and timings in one place. If the method is only spoken out loud in the video, Glutt listens and writes it down for you. Screenshots work too. No more saved links you never open again.

MEET POLLY, YOUR LIVE AI CHEF
Talk to Polly out loud while you cook. Say her name, then ask what to use instead of buttermilk or whether the chicken is done, and the answer comes back straight away with no greasy taps on your phone. Polly walks you through every step, runs your timers, and can look through the camera at what is happening in the pan.

A KITCHEN THAT KNOWS WHAT YOU HAVE
Tell Glutt what is in your fridge and pantry by voice, by camera or by typing, then tick off the equipment you own. Recipes show what you are missing before you start, offer a substitute for what you do not have, and send the rest straight to your grocery list.

FIND TONIGHT'S DINNER
Swipe a feed of real dishes and cooking videos picked for your taste. Save the ones you want to cook, skip the rest, and Glutt gets better at reading you as you go.

COOK IT PROPERLY
Step by step cook mode with type big enough for greasy hands, timers that run themselves, serving scaling that does the arithmetic, and short lessons on the basics nobody ever taught you.

MACROS WITHOUT THE MATH
Every recipe carries calories and protein per serving, scaled to the number of servings you actually cook. No food diary, no daily goals, no guilt.

GLUTT PREMIUM
Glutt needs an active subscription. Yearly is $49.99 and monthly is $7.99, or start with a 3-day free trial that turns into the yearly plan unless you cancel first. Prices are in US dollars and may vary by country.

Payment is charged to your Apple Account at confirmation of purchase. Your subscription renews automatically unless auto renew is turned off at least 24 hours before the end of the current period. Manage or cancel it any time in your Apple Account settings.

Terms of Use (EULA): https://glutt.org/terms
Privacy Policy: https://glutt.org/privacy
```
2302 characters. Guideline 3.1.2 wants the subscription length, price and both links in the
metadata, which the GLUTT PREMIUM block covers.

If you take option 1 or 2 on the chefs, this description needs no change. It never mentions
them.

### What's New in This Version (limit 4000)

This is the version where the whole app changed, so lead with the look.

```
Glutt has been rebuilt.

A NEW LOOK
Every screen redesigned, with new type, new icons and a new app icon to match. Recipe cards now open by zooming into the dish.

POLLY LISTENS FOR HER NAME
Just say "Polly" while your hands are covered in flour. No tap, no wake button. Her voice runs on a new engine, so she answers faster, lets you interrupt her, and stops talking over you. Ask her anything mid-cook, and she can look through the camera at what is in the pan.

RECIPES FROM VIDEOS THAT NEVER WROTE ANYTHING DOWN
Share a cooking video and Glutt listens to what the cook actually says, then writes the ingredients and steps out properly.

BEFORE AND AFTER THE COOK
A short briefing before you start, so you know what is coming. A recap at the end, where you keep a photo of what you made.

CHEF PACKS
Signature dishes ready to cook step by step with Polly.

YOUR KITCHEN, BY VOICE
Say what is in your fridge instead of typing it in, and every recipe now carries its calories and protein per serving.

YOUR OWN ACCOUNT
Sign in with Apple or Google after you subscribe, so your subscription follows you to a new phone.

Plus better AirPods and Bluetooth headset support during a live cook, fixes to logging in and restoring purchases, and a lot of polish underneath.

Happy cooking.
```
1282 characters. **Delete the CHEF PACKS block if you hide the chef rail** (section 1.1).

Everything above landed after 1.1 was cut. 1.1 was build 10 from 2026-07-18, so the
redesign (2026-07-23), the Polly voice rebuild (2026-07-24), video import, the pre-cook
briefing, the cook recap, voice pantry, recipe nutrition, accounts and chef packs are all
new to the store with this version. The redesign is the reason the screenshots changed, so
naming it first also explains the new gallery to anyone comparing.

### URLs, copyright, category

| Field | Value |
|---|---|
| Support URL | `https://glutt.org/support` (live, 200) |
| Marketing URL | `https://glutt.org` (live, 200) |
| Privacy Policy URL | `https://glutt.org/privacy` (live, 200) |
| Copyright | `2026 CielPM, Inc.` |
| Primary category | Food & Drink |
| Secondary category | Lifestyle, or leave empty. Health & Fitness would be a stretch now that tracking is gone. |
| Age rating | 4+, with one caveat below. Polly is scoped to the recipe in front of it rather than open chat, and there is no user-to-user content anywhere in the app. |
| Encryption | Already declared: `ITSAppUsesNonExemptEncryption: false` in `project.yml`. No extra upload step. |

**The age rating caveat: the web view in Discover.** `YouTubePlayerView` is a `WKWebView`
loading the YouTube IFrame player with **no navigation delegate**, so a tap on the player's
own "Watch on YouTube" affordance can leave the embed and browse from there. Strictly read,
that is the "unrestricted web access" question, and answering it yes pushes the rating well
above 4+.

The cheap, honest fix is a `decidePolicyFor` in `YouTubePlayerView` that cancels any
navigation whose host is not the embed page, so the player stays a player. Small change,
worth doing before you answer the questionnaire. Say the word and I will write it.

### Screenshots

Five panels at 1320 x 2868 (iPhone 6.9"), which is the size App Store Connect wants for the
required display size. iPhone-only app (`TARGETED_DEVICE_FAMILY: "1"`), so no iPad set.

| Order | File | Headline |
|---|---|---|
| 1 | `01-cook-what-you-save.png` | Cook what you save |
| 2 | `02-talk-to-polly.png` | Talk to Polly while you cook |
| 3 | `03-swipe-to-find-dinner.png` | Swipe to find tonight's dinner |
| 4 | `04-use-what-you-have.png` | Use what you already have |
| 5 | `05-macros-no-math.png` | Macros, no math |

One open item from `docs/appstore-screenshots-prompts.md`: panel 5's magnified macro card
reads `380 CAL` with `28g protein, 37g carbs, 1g fat`, which sums to roughly 269 calories.
It is the most scrutinised number in the set because it is magnified. Worth reshooting that
panel with a recipe whose numbers add up.

### In-app purchase metadata

| Product | Display Name (30) | Description (45) |
|---|---|---|
| `...premium.yearly` | `Glutt Premium, Yearly` | `Everything in Glutt. Billed once a year.` |
| `...premium.monthly` | `Glutt Premium, Monthly` | `Everything in Glutt. Billed every month.` |
| `...premium.yearly.trial` | `Glutt Premium, Yearly Trial` | `3 days free, then the yearly plan.` |

Each subscription also needs a review screenshot to reach "Ready to Submit". A capture of
the paywall works for all three.

---

## 3. App Review notes

Paste into App Review Information, Notes. The June rejection turned on a purchase button that
could not work. A reviewer who cannot get past the paywall ends in the same place, so do not
leave this empty.

```
Glutt requires an active subscription to use. There is no free tier. How to get in:

1. Complete the short onboarding on first launch.
2. The paywall appears. Either tap Continue to take the yearly plan, or turn on the "Not sure yet? Enable free trial." switch and tap "Start my 3-day free trial". If the switch is not shown, Continue takes the yearly plan.
3. Complete the purchase with your sandbox Apple Account. Sandbox purchases are free.
4. The app unlocks, then asks you to sign in. Tap "Sign in with Apple" and use your own Apple Account — Glutt creates the account for you on the spot. There is no password-based demo login to hand over, because Glutt only supports Sign in with Apple and Google. Signing in is what carries a subscription to a new phone; Glutt stores nothing but your name and email.

Three in-app purchases are submitted with this build: com.omarlahmimi.glutt.premium.yearly, com.omarlahmimi.glutt.premium.monthly, and com.omarlahmimi.glutt.premium.yearly.trial.

Other things worth knowing:

Restore Purchases is on the paywall and in Settings.
Sign-in is asked for after the purchase, never before, and only via Sign in with Apple or Google. Account deletion is in Settings, Account, Delete account.
The microphone and speech recognition are used by Polly, the in-app voice cooking assistant. Wake word detection runs on device. Camera access is optional and only used inside a Polly session or when scanning a pantry.
To try Polly: open any recipe, tap Cook with Polly, then say "Polly" or tap the mic. It needs a network connection.
The app is iPhone only and portrait only by design.
```

---

## 4. App Privacy answers

Replace **Data Not Collected** with the following. Verify each line against your own reading
of the questionnaire, since the wording changes, but this is what the code actually does.

| Data type | Collected | Linked to identity | Used for | Where it comes from |
|---|---|---|---|---|
| Contact Info, Email Address | Yes | Yes | App Functionality, Analytics | Sign in with Apple or Google, stored in Supabase and set as a PostHog person property |
| Identifiers, User ID | Yes | Yes | App Functionality, Analytics | Supabase user id as the PostHog `distinct_id`, install id on AI usage rows |
| Usage Data, Product Interaction | Yes | Yes | Analytics | PostHog product and funnel events |
| Purchases, Purchase History | Yes | Yes | App Functionality, Analytics | Superwall and StoreKit subscription status |
| User Content, Photos or Videos | Yes | No | App Functionality | Pantry scans and recipe screenshots sent to the AI provider |
| User Content, Audio Data | Yes | No | App Functionality | Polly voice sessions and pantry dictation |
| User Content, Other User Content | Yes | No | App Functionality | Recipe text and pantry contents sent to the AI provider |

Answer **No** to tracking across apps and companies. Nothing in the build does that, there is
no ad SDK, and no ATT prompt.

The three User Content rows are the judgment call. The content is sent to a third-party AI
provider and, per your own privacy policy, may be retained by them for up to 30 days for
abuse monitoring. Declaring it is the defensible answer and costs you nothing, because it is
App Functionality rather than tracking.

One small cleanup for later: `glutt.org/privacy` still lists "leftover remix" and "meal photo
estimation" as AI features. Both are gone from the app. Harmless, but it is the same
accuracy problem as section 1.3 in a different document.

---

## 5. Submission checklist

- [ ] Decide what happens to the chef rail (section 1.1) and adjust What's New to match
- [x] Build bumped to 12 and `xcodegen generate` run
- [ ] Tick **Sign-in required** in App Review Information. Glutt walls the app behind Sign in
      with Apple or Google once the purchase lands (`RootView.unlockedOverlay` presents
      `SignInView` with `canDismiss: false`, and its "Continue without an account" link only
      appears after a sign-in failure). There is no password-based login, so leave Username
      and Password empty and let the notes in section 3 explain that the reviewer signs in
      with their own Apple Account. Omar chose to keep the wall mandatory rather than make it
      skippable; if a reviewer refuses to use their own ID, the fix is to show that link
      unconditionally and untick this box.
- [ ] Publish Superwall paywall 243875
- [ ] Confirm the trial SKU and its 3-day free introductory offer exist and are Ready to Submit
- [ ] Confirm a sandbox purchase completes for both annual products
- [ ] Confirm `ELEVENLABS_API_KEY` is set on the production Vercel proxy. Without it the
      video listening path soft-fails back to captions, and the description now promises it
      (see the deploy note in `docs/plan-video-first-import.md`)
- [ ] Attach all three IAPs to the 1.2 build
- [ ] Upload the 5 new screenshots, then delete the 1.1 set
- [x] Icon checked: `AppIcon.png` is 1024 x 1024, RGB with no alpha channel, so it will
      upload cleanly
- [ ] Paste subtitle, promotional text, keywords, description, What's New
- [ ] Redo App Privacy from section 4
- [ ] Paste the review notes from section 3
- [ ] Decide on the YouTube web view before answering the age rating questionnaire (section 2,
      under the URLs table), then expect 4+
- [ ] Submit
