# Fixing the 3.1.2(c) rejections on paywall 249784

Submission `94b8ca7b-893d-4554-ac99-7079bec53619`, rejected 2026-08-17. Two of
the three rejection items are about the paywall, and the paywall is server-side
in Superwall, so none of this is a code change.

## What is live right now

`onboarding_complete` → campaign **91288** → audience "no active entitlements" →
100% → paywall **249784** "Glutt Pro Trial Flow v1", version 14, published
2026-08-13.

The published screen, in full: a back chevron, "Glutt PRO", the headline "Cook
anything you actually want", two phone mockups, "✓ No commitment, cancel
anytime", and a green **"Try 7 days free"** button.

That is everything. There is no price, no subscription length, no statement that
the trial converts to a paid subscription, and no Terms or Privacy links. Apple
wrote it up twice and was right both times.

## The prices

Malik and Omar switched to **$14.99 monthly / $44.99 yearly** on 2026-08-18.
Omar has already changed them in App Store Connect, on **both** yearly SKUs:
`...premium.yearly` and `...premium.yearly.trial` (confirmed 2026-08-18). That
matters because the paywall sells the trial SKU and the plain yearly is the
fallback, so a price change to only one of them would show two different prices
depending on which product a cook was served.

| Reference | Product | Real price (ASC) | Superwall still says | Period | Trial |
| --- | --- | --- | --- | --- | --- |
| `primary` | `com.omarlahmimi.glutt.premium.yearly.trial` | **$44.99** | $99.99 | year | **7 days** |
| `secondary` | `com.omarlahmimi.glutt.premium.monthly` | **$14.99** | $14.99 | month | none |
| (not on paywall) | `com.omarlahmimi.glutt.premium.yearly` | **$44.99** | $99.99 | year | none |

$44.99/year is **$3.75 per month**. Against $14.99 monthly ($179.88 a year) the
annual plan saves **75%**.

> Ignore the prices in `HARD-PAYWALL-FREE-TRIAL.md` and `REENABLE-PAYMENTS.md`
> ($49.99 / $7.99). They are two price changes out of date.

## Fix 1: re-import the products FIRST, and this is now urgent

Superwall's catalog is **stale in two different ways**, and one of them is new:

1. **Price.** Superwall records $99.99 for both yearly products (last updated
   2026-08-13). App Store Connect now says $44.99.
2. **Period.** `run_doctor` reports three `ios.product_drift` errors: all three
   products record `month`/`year` where ASC says `ONE_MONTH`/`ONE_YEAR`.
   Superwall's own wording is that "paywall period substitutions will render the
   wrong cadence to users".

The price drift is the dangerous one. If the paywall is fixed the *correct* way,
with dynamic bindings like `{{ products.primary.price }}`, it would today render
**$99.99 while StoreKit charges $44.99** — a paywall overstating the price by
more than double. That is a guaranteed rejection and a worse one than the
current two.

Note that `run_doctor` does **not** check price, only period, so it gives false
comfort here. It passed the products as "ready for sale" while their prices were
stale.

Re-import all three products from App Store Connect, then re-run the doctor and
confirm both the period errors are gone and `list_products` reports 4499.

This cannot be done over the API: `PATCH /v2/products/{id}` accepts only `name`,
`entitlements` and `metadata`. It is a dashboard re-import.

## Fix 2: the paywall copy

Add to paywall 249784. Prefer dynamic bindings (`products.primary.price`,
`.periodly`, `.trialPeriodDays`) over literals **once the drift above is fixed**,
so other storefronts and any future price change stay correct.

**Primary CTA**

    Start my 7 day free trial

**Directly beneath the CTA, always visible without scrolling**

    7 days free, then $44.99 per year. Auto-renews unless cancelled at least
    24 hours before the end of the period. Cancel anytime in Settings.

**Plan rows** (the monthly product is configured on this paywall but never
shown, so today there is no plan choice at all; either surface it or drop it)

    Yearly · $44.99 per year · $3.75 per month · save 75%
    Monthly · $14.99 per month

**Footer, both as working links**

    Terms of Use      https://glutt.org/terms
    Privacy Policy    https://glutt.org/privacy

Keep "No commitment, cancel anytime" if you like, but it must not be the only
thing said about billing. On its own, above an undisclosed auto-renewing trial,
it is the specific thing Apple called misleading.

## Fix 3: App Store Connect metadata

Apple's message also requires functional links in the metadata, not only in the
app. Confirm the Privacy Policy URL field is set and the EULA/Terms link is in
the App Description or the EULA field. `REENABLE-PAYMENTS.md` still lists this
as unchecked.

The app itself already satisfies the in-app links: Settings has Privacy Policy
and Terms of Service rows pointing at `glutt.org/privacy` and `glutt.org/terms`.

## Also worth fixing, not blocking

- **App Store Connect shared secret is missing** (doctor, p0). Superwall cannot
  verify receipts without it. Revenue tracking still works via the ASC API key
  and Server Notifications, so this is not why anything was rejected, but it is
  a real gap. Set it under Users and Access → Integrations → App-Specific Shared
  Secrets.
- **Campaign 101739 and paywall 255591** were created for the freemium
  per-feature placements and are now orphaned, since that work was reverted.
  Worth archiving so nobody wires a future build into them by accident.

## Who has to do what

The Superwall MCP can read all of this but **cannot edit paywall content** —
there is no `update_paywall`, and the docs confirm it does not drive the visual
editor. So Fix 1 and Fix 2 are dashboard work for Malik or his friend, and
Fix 3 is App Store Connect.

After the paywall is republished, the review notes for the resubmission should
say where the price and trial terms now appear, and include a screen recording
of the purchase flow — Apple asked for one explicitly.
