# Hard paywall + 7-day free trial

Status of the "Glutt is unusable without a subscription, with a free trial"
change. Shipped from `paywall-hard-gate-trial`, now on `main`.

**Current pricing (verified in the Superwall editor + App Store Connect product
data, 2026-08-18):**

| Product | ID | Price | Trial | ASC state |
|---|---|---|---|---|
| Annual, with trial (**paywall default**) | `com.omarlahmimi.glutt.premium.yearly.trial` | $44.99 / year | **7 days free** | APPROVED |
| Annual, charge now | `com.omarlahmimi.glutt.premium.yearly` | $44.99 / year | none | APPROVED |
| Monthly | `com.omarlahmimi.glutt.premium.monthly` | $14.99 / month | none | APPROVED |

Annual works out to $3.74/mo against $179.88/yr of monthly, which is the 75% the
paywall advertises. The badge computes that from both raw prices, so it follows a
price change on its own.

## The decisions (from the grilling session, 2026-07-17)

- **Hard paywall, B-strict, land-then-bounce.** After onboarding the user lands
  on the real tabs (the app "looks real"), but the **first touch bounces to the
  paywall**. Nothing is usable without an active subscription. There's an X on
  the paywall (so a broken IAP can never *fully* brick the app), but no free
  functionality behind it.
- **Runs every cold launch**, keyed to `Superwall.shared.subscriptionStatus`. A
  **lapsed / expired subscription re-locks** the app on the next launch.
- **Everyone is locked out** — no grandfather, no allowlist. Testers/reviewers
  sandbox-subscribe (free). Dev bypass flags for local builds.
- **Trial model changed after the fact.** The original plan was Model 1, a
  reverse-trial toggle: trial off by default, flip a switch to swap in the trial
  SKU. That toggle is **gone**. The paywall now makes the **trial SKU the default
  annual card**, so the trial is what a user gets unless they pick monthly.

## ✅ In code (`main`)

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
- **No prices in the app.** Nothing in `Glutt/` or `GluttShare/` hardcodes a
  price, a product id, or a trial length; it all arrives from Superwall and
  StoreKit. A price change needs no app release.
- **Covered:** 6 unit tests over the decision table
  (`GluttTests/SubscriptionGateTests.swift`).

## ✅ On the paywall (verified 2026-08-18)

Five-page flow. Pages 0 to 2 sell; the last page is the plan picker; a fixed
footer carries the CTA and the legal links.

- **Plan cards:** Annual (default, selected) and Monthly. Annual shows the
  monthly price struck through above the annual price.
- **Every price and trial length is a liquid binding.** Nothing is typed in:

  | Element | Binding |
  |---|---|
  | Annual price | `{{ products.primary.price }}/{{ products.primary.period }}` |
  | Annual per month | `{{ products.primary.monthlyPrice }}/mo` |
  | Strikethrough | `{{ products.secondary.yearlyPrice }}` |
  | Save badge | `products.primary.rawPrice ÷ 12` against `products.secondary.rawPrice` |
  | Monthly price | `{{ products.secondary.price }}/{{ products.secondary.period }}` |
  | Trial headings | `{{ products.primary.trialPeriodDays }}` |

- **CTA is conditional**, not a fixed string: with an introductory offer on the
  selected product it reads "Try {{ products.selected.trialPeriodDays }} days
  free"; otherwise "Continue". Selecting Monthly therefore reads "Continue"
  rather than the "Try 0 days free" a naive binding would produce.
- **No trial toggle.** The switch, its `state.isChecked` bindings, and the
  index-swapping click behavior described in the 2026-07 plan are no longer on
  the paywall.

This is paywall **249784 "Glutt Pro Trial Flow v1"**, which replaced 243875 on
2026-07-29 (243875 is left as a draft, as the rollback target). Identified from
its structure and typography rather than an id lookup, so confirm in the
dashboard before relying on it for a submission. Also not checked: whether the
current draft is published.

## Sequencing rules that still apply

Superwall paywalls are server-side: a reviewer's build fetches whatever is
**published** at review time. So a paywall change must be **published before
submission**, or the reviewer sees the previous published version. Worse: the
gate placement must resolve to a paywall at all, and an unresolved placement is a
**locked app with no paywall, which is an automatic rejection**. The reviewer
completes the purchase in the **sandbox**, so there is no dead button for them.

**Gate placement:** the gate reuses **`onboarding_complete`** (campaign 91288,
audience 153609, treatment variant → paywall 249784 since 2026-07-29), so no
campaign change is needed. A dedicated `premium_gate` placement is a future
analytics cleanup, not required to ship.

Review notes that worked: "Glutt requires a subscription; on the paywall tap the
Continue button and purchase with a Sandbox Apple ID (no charge). The annual plan
starts a 7-day free trial."

## After a price change (what to check)

1. Superwall editor: reopen the paywall and confirm the plan page renders the new
   numbers. The bindings update on their own; the point is to catch a stale
   *published* version.
2. **Publish** if the numbers only moved in the draft.
3. App Store Connect: the price change applies per territory and needs the
   existing-subscriber choice answered (keep them on the old price, or move them).
4. Nothing to rebuild in the app.

## Notes / edge cases

- **Trial eligibility:** StoreKit only grants the free trial to users who haven't
  used an intro offer in that subscription group. A returning user who already
  trialed will be charged immediately. StoreKit handles this automatically; a
  future polish is eligibility-aware copy on the paywall.
- **Two annual SKUs, same price.** `…premium.yearly` (no offer) exists alongside
  `…premium.yearly.trial` (7-day offer). Only the trial SKU is on the paywall
  today. Keep the plain one: it is what a trial-ineligible user should buy, and
  deleting an ASC product is not reversible.
- **Restore:** the paywall's Restore button + Settings → Restore both call
  `Superwall.shared.restorePurchases()`; a successful restore flips
  `subscriptionStatus` to `.active`, which unlocks the gate automatically.
- **Meta ads:** `StartTrial` fires on the trial purchase and `Subscribe` on a
  charge-now purchase, so a trial length change does not touch that wiring, but
  the value sent follows the price. See `docs/` Meta notes and
  `Glutt/Services/Analytics/MetaAds.swift`.
- **Simulator gotcha:** on the sim, Superwall's launch-time StoreKit check pops a
  "Sign in to Apple Account" dialog (no sandbox account). Harmless; doesn't happen
  on a device signed into a sandbox tester. It does obscure UI automation, so the
  locked overlay is verified via unit tests rather than a sim screenshot.
