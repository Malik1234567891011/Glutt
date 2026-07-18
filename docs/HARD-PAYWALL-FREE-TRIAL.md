# Hard paywall + 3-day free trial

Status of the "Glutt is unusable without a subscription, with a 3-day free trial"
change. Branch: `paywall-hard-gate-trial`.

## The decisions (from the grilling session, 2026-07-17)

- **Hard paywall, B-strict, land-then-bounce.** After onboarding the user lands
  on the real tabs (the app "looks real"), but the **first touch bounces to the
  paywall**. Nothing is usable without an active subscription. There's an X on
  the paywall (so a broken IAP can never *fully* brick the app), but no free
  functionality behind it.
- **Runs every cold launch**, keyed to `Superwall.shared.subscriptionStatus`. A
  **lapsed / expired subscription re-locks** the app on the next launch.
- **Plans:** annual ($49.99) + monthly ($7.99) — both already approved. No weekly.
- **Trial = Model 1 (reverse-trial funnel).** Toggle **OFF (default)** → existing
  annual, charged now, no trial. Toggle **ON** → a **new annual SKU** carrying a
  3-day free-trial intro offer. Monthly is the faded secondary.
- **Everyone is locked out** — no grandfather, no allowlist. Testers/reviewers
  sandbox-subscribe (free). Dev bypass flags for local builds.

## ✅ Done in code (this branch)

- **`SubscriptionGate`** (`Glutt/Features/Paywall/SubscriptionGate.swift`) — the
  single app-wide gate. `access` = `.resolving` / `.locked` / `.unlocked`, keyed
  to `Superwall.shared.subscriptionStatus`, observed live via Combine. Fails
  **closed**: only a genuine entitlement (or a dev bypass) unlocks.
- **`RootView`** wraps the app: `.resolving` shows a neutral cream splash;
  `.locked` overlays a transparent full-screen catcher that swallows every touch
  and re-presents the paywall (`PaywallGateOverlay`); `.unlocked` is the full app.
- **Centralized:** the old per-feature hooks are retired — `OnboardingPaywallHook`
  and `PollyPaywallHook` deleted (invention hook was already gone). Onboarding now
  lands straight into the app; the gate does all enforcement.
- **Dev bypass** (`SubscriptionGate.bypassEnabled`): `-uiPreview`, `-seed` (the
  demo scheme), or `-unlockPremium` (DEBUG only). None survive a TestFlight/App
  Store upload, so they can never unlock a shipped build.
- **Verified:** clean build; unlocked path renders the full app; 6 unit tests
  cover the decision table (`GluttTests/SubscriptionGateTests.swift`).

## ✅ Done in Superwall (paywall 243875) — draft, NOT yet published

Discovery: the paywall's annual card **already** had the trial-selection logic
wired (conditional click-behavior: `if state.isChecked && products.hasIntroductoryOffer
→ set-product-index 2, else index 0`). Only the toggle UI + the index-2 product had
been removed. So the rebuild was a re-add, verified in both states via screenshots:

- **Toggle row re-added** ("Not sure yet? Enable free trial." + iOS switch), placed
  above the plan cards. Nodes: row `node:2Zv43Gkvfe05jP6hEVE03`, track
  `node:tDmlqHlZIouGjkZYKswZf`, knob `node:1mzeHAK_x_tbP0flqRrvL`. Bound to
  `state.isChecked` (default **false** = Model 1 reverse-trial default).
- **Switch appearance** bound to `isChecked`: track bg `#2e5339`↔`#d8d2c4`, knob
  slides via `paddingLeft` `23px`↔`2px`.
- **Toggle click behavior** (conditional): flips `isChecked` AND sets product index
  (enable → index 2 trial, disable → index 0 yearly). CTA buys `by-selected`.
- **Trial-aware copy** bound to `isChecked`:
  - CTA `node:RYpzLKOq0Um85KZK8e_L1`: "Continue" ↔ "Start my 3-day free trial".
  - Disclosure `node:vHfxx6HVO9JrAMFsQ7l6b`: "Cancel anytime · Protected by the App
    Store" ↔ "3-day free trial, then $49.99/year. Auto-renews unless cancelled. Cancel anytime."

- **Trial product added at index 2** ✅ — `a2 | trial | com.omarlahmimi.glutt.premium.yearly.trial`
  (trialDays=3, $49.99/yr). Adding it did not spawn a stray third card (verified).

The paywall **draft is complete**. Everything below is the go-live sequence.

## ⏳ Remaining — publish + ship (do in this order)

**Why not publish the paywall right now:** the trial SKU is still **"Ready to Submit"**
(not approved). Apple requires the *first* auto-renewable sub to be **submitted with an
app version** before it's purchasable. If we published the toggle paywall to production
today, current users at `onboarding_complete` could flip the toggle and hit a **dead
"Start free trial"** (product not purchasable) — the exact 2.1 bug from June. So hold
publish until the trial is approved *with the app build*.

Also: the hard gate lives in app code (branch `paywall-hard-gate-trial`), so **nothing
goes live until that build ships anyway.**

Go-live order:
1. Merge/commit `paywall-hard-gate-trial`, bump build, `xcodegen generate`, archive.
2. **Submit to App Review with the trial IAP attached** (`…premium.yearly.trial`) plus
   the existing IAPs → this gets the trial **approved**.
3. On approval: **publish paywall 243875** (its editor draft already has the toggle) and
   **wire the `premium_gate` placement** → campaign 91288 → 243875 (a ~2-min REST/editor
   step; the gate fails closed if unwired, so the app just stays locked until then).
4. Release → hard gate + 3-day trial live together.

Note: dynamic `{{ products.* }}` price bindings left as static literals for now
($49.99 / $0.96/week / $7.99) — the annual price is unchanged by the trial, and the trial
terms are shown in the disclosure. Revisit if going multi-currency.

## 🔴 YOUR App Store Connect to-do (go-live blockers — only you can do these)

1. **Create one new auto-renewable subscription product:**
   - Suggested ID: **`com.omarlahmimi.glutt.premium.yearly.trial`**
     (the Superwall wiring will reference this exact ID — tell me if you pick a
     different one).
   - **Same price as the existing annual: $49.99 / year.**
   - **Same subscription group** as `com.omarlahmimi.glutt.premium.yearly`.
2. **Add a 3-day Free introductory offer** to that new product
   (Product → Subscription → Introductory Offer → type **Free**, duration **3 days**).
   - Leave the *existing* `…premium.yearly` **without** an intro offer — that's the
     "toggle OFF, charge now" product.
3. **Confirm a sandbox purchase completes** for BOTH annual products
   (charge-now and trial) before we flip the gate live.

## Go-live sequence (so we never ship a brick)

1. ✅ Code gate built + verified (behind dev bypass; `main` stays safe).
2. ⏳ Superwall paywall rebuilt (toggle + dynamic prices + disclosure + `premium_gate`).
3. 🔴 You: create the trial SKU + 3-day intro offer in ASC; confirm sandbox purchases.
4. Ship the build; the gate is live. Testers/reviewers sandbox-subscribe (free).

## Notes / edge cases

- **Trial eligibility:** StoreKit only grants the free trial to users who haven't
  used an intro offer in that subscription group. A returning user who already
  trialed will be charged immediately. StoreKit handles this automatically; a
  future polish is eligibility-aware copy on the paywall.
- **Restore:** the paywall's Restore button + Settings → Restore both call
  `Superwall.shared.restorePurchases()`; a successful restore flips
  `subscriptionStatus` to `.active`, which unlocks the gate automatically.
- **Simulator gotcha:** on the sim, Superwall's launch-time StoreKit check pops a
  "Sign in to Apple Account" dialog (no sandbox account). Harmless; doesn't happen
  on a device signed into a sandbox tester. It does obscure UI automation, so the
  locked overlay is verified via unit tests rather than a sim screenshot.
