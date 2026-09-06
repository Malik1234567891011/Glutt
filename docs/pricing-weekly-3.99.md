# Switching the monthly plan to $3.99 weekly

Target: replace `com.omarlahmimi.glutt.premium.monthly` ($14.99/month) with a
new weekly product at **$3.99 USD per week**.

Written 2026-09-06. The state of the paywall described here comes from
`paywall-3.1.2-fix.md` (2026-08-17), which is the most recent record in the
repo. Verify the "before" column still matches before you start.

## The app needs no release

Checked, and this is the useful part: **nothing in the app names a product, a
price, or a billing period.**

- `grep` for product identifiers, prices and period words across `Glutt/`
  returns nothing. There is no `.storekit` file in the project.
- `SubscriptionGate.access` keys off `Superwall.shared.subscriptionStatus`
  `.isActive`, which is true for *any* live entitlement. It does not care which
  product produced it.
- The paywall itself is server-side in Superwall, rendered from campaign
  **91288** → paywall **249784**, reached through the `onboarding_complete`
  placement.
- `Glutt/Services/Analytics/PaywallEventBridge.swift` is the only file in the
  app that touches a product at all. It reads `product.productIdentifier`,
  `product.price` and `product.currencyCode` straight off Superwall's event and
  hands them to Meta. There is no switch on product ID and no price literal, so
  a weekly purchase reports itself correctly with no code change.

Re-verified 2026-09-06 in a second session, including the analytics bridge,
which the first pass had not checked. All of it holds.

So as long as the new weekly product is attached to the **same entitlement**,
the app unlocks for a weekly subscriber with no code change and no submission.
Everything below is App Store Connect and Superwall dashboard work.

## What the money actually does

Worth seeing before you commit to it.

| Plan | Price | Per year | Per month |
| --- | --- | --- | --- |
| Weekly (new) | $3.99 / week | **$207.48** | $17.29 |
| Monthly (being replaced) | $14.99 / month | $179.88 | $14.99 |
| Yearly trial (`primary`) | $44.99 / year | $44.99 | $3.75 |

Two consequences:

1. **This is a price rise, not a cut.** $3.99 a week is $17.29 a month, about
   15% more than the $14.99 it replaces. That is the normal reason to sell
   weekly, it reads cheaper, but it is a rise and the yearly plan is now 4.6×
   cheaper than the short plan rather than 4×.
2. **"Save 75%" on the yearly row becomes wrong.** $44.99 against $179.88 is
   exactly 75.0%, which confirms the existing claim was computed against the
   monthly row, the very row being replaced. Against $207.48 the yearly plan
   saves **78%**. If you keep a savings claim it has to say 78%, and it has to
   be computed against whichever plan you actually show beside it.

## 1. App Store Connect

1. App Store Connect → Glutt → **Subscriptions**.
2. Open the **same subscription group** the existing premium products live in.
   This matters: products in one group can be switched between by the customer
   and only one can be active at a time. A weekly product in a *new* group
   would let someone hold weekly and yearly at once.
3. **Create a subscription.**
   - Reference Name: `Glutt Premium Weekly`
   - Product ID: `com.omarlahmimi.glutt.premium.weekly`
     (matches the existing `...premium.<period>` convention)
   - Duration: **1 week**
4. Set the price: **$3.99 USD**, and let App Store Connect generate the other
   storefronts unless you want to price specific ones by hand.
5. Add the localisations Apple requires (display name and description) and a
   review screenshot, or the product stays in "Missing Metadata" and cannot be
   sold.
6. Introductory offer: **decide deliberately.** The product it replaces had
   none, and the 7 day free trial currently lives on the yearly `primary`
   product. If you add a trial here too, both need disclosing on the paywall.
7. Leave `...premium.monthly` alone for now. See "existing subscribers" below.

The product has to reach **Ready to Submit** before Superwall can import it.

## 2. Superwall: import the product

1. Superwall dashboard → the Glutt app → **Products**.
2. **Re-import from App Store Connect.** This cannot be done over the API:
   `PATCH /v2/products/{id}` accepts only `name`, `entitlements` and
   `metadata`, so the MCP cannot do it either.
3. Attach the new product to the **same entitlement** the existing premium
   products use. This is the step the app depends on. Get it wrong and a
   weekly subscriber pays and stays locked out, because `isActive` will be
   false.
4. While you are in there, re-import **all** the products, not just the new
   one. As of 2026-08-17 the catalog was stale in two ways: it recorded $99.99
   for both yearly SKUs that App Store Connect had already dropped to $44.99,
   and `run_doctor` reported three `ios.product_drift` errors where the stored
   period disagreed with ASC. If that was never fixed, a paywall using dynamic
   bindings will render prices that do not match what StoreKit charges.
5. Run `run_doctor` and confirm no `product_drift` remains, then confirm
   `list_products` reports `399` for the weekly product.

Note that `run_doctor` checks period but **not** price, so a clean doctor run
is not proof the prices are right. Read them.

## 3. Superwall: the paywall

Paywall **249784**, "Glutt Pro Trial Flow v1". The MCP has no `update_paywall`
and does not drive the visual editor, so this is dashboard work.

1. Swap the `secondary` product binding from `...premium.monthly` to
   `...premium.weekly`.
2. Update the plan rows. Prefer dynamic bindings over literals so other
   storefronts stay correct, but only once step 2 above is verified clean:

   ```
   Yearly · {{ products.primary.price }} per year · save 78%
   Weekly · {{ products.secondary.price }} per week
   ```

3. The billing disclosure under the CTA has to name the weekly cadence if
   weekly is what the button buys. Apple rejected this app twice under 3.1.2(c)
   for exactly this, so it must state price, period, auto-renewal and how to
   cancel, and it must be visible without scrolling.
4. Terms and Privacy links stay: `https://glutt.org/terms`,
   `https://glutt.org/privacy`.
5. **Publish a new version.** Superwall paywalls are versioned; editing without
   publishing changes nothing for users.

## 4. Existing monthly subscribers

Do not delete `...premium.monthly`, and you could not anyway once it has
subscribers. Removing it from the paywall only stops it being *offered*.

- Anyone already on monthly keeps billing at $14.99 and keeps their
  entitlement, so they keep working with no change.
- If you want it genuinely retired, mark it unavailable for new subscribers in
  App Store Connect. Existing subscriptions continue.
- If you ever raise a price on an existing product rather than replacing it,
  Apple makes you choose between preserving the old price for current
  subscribers or notifying them for consent. Replacing the product, which is
  what this is, avoids that entirely.

## 5. Before you submit

- Sandbox purchase of the weekly product, and confirm the app **unlocks**.
  That is the one thing that proves the entitlement mapping is right. Weekly
  subscriptions renew every 3 minutes in sandbox, so you can watch a renewal.
- Confirm the paywall renders $3.99 and the word "week", on a real device, at
  the top of the screen without scrolling.
- Screen record the purchase flow. Apple asked for one explicitly last time.
- In the review notes, say where price, period and trial terms now appear.
- Still open from the previous round, and not caused by this change: the
  **App Store Connect shared secret** is missing, so Superwall cannot verify
  receipts. Users and Access → Integrations → App-Specific Shared Secrets.

## Unrelated finding, left unfixed

`Glutt/Features/Paywall/SubscriptionGate.swift` lines 32 and 196 both name
paywall **243875** in their doc comments. 249784 replaced it on 2026-07-29 and
243875 is only the draft rollback target, so both comments are stale and
misleading to anyone reading the gate while doing this migration.

Not fixed, because this migration is meant to touch no app code. It is a
comment only change with no effect on behaviour, so it can ride along with any
later commit.

## Still unverified, and why

Three things need the live Superwall catalog and are **not** confirmed:

1. **Whether the August price drift was ever fixed.** Superwall recorded $99.99
   for both yearly SKUs while App Store Connect said $44.99, plus three
   `ios.product_drift` errors on period. `run_doctor` checks period but not
   price, so a clean doctor run is not proof. Read the prices.
2. **What paywall 249784 currently renders**, so weekly copy replaces the right
   text and the savings claim is corrected in the right place.
3. **Which entitlement the premium products map to.** This is the single
   setting that decides whether a weekly subscriber is actually unlocked.

**Blocker, 2026-09-06:** the Superwall MCP still cannot be used, but the cause
has moved. It is no longer `invalid_refresh_token`. The server now fails to
connect at all: `CONNECT_TIMEOUT, version negotiation probe timed out after
5000ms`.

That is an auth failure wearing a timeout's clothes. Probed directly, the
endpoint is healthy and fast:

```
$ curl -i https://superwall-mcp.superwall.com/mcp
HTTP/2 401
www-authenticate: Bearer realm="https://superwall-mcp.superwall.com", error="unauthorized"
{"error":"unauthorized","error_description":"Bearer token required"}
```

9ms to connect, 35ms to first byte. The host is up; there is simply no token.
There is no `superwall` entry in the login keychain and none in
`~/.claude/mcp-needs-auth-cache.json`, so the credential the previous session
created is gone rather than stale, and the client hangs on the auth probe
instead of reporting 401.

**Fix:** run `/mcp` → `superwall` → Authenticate, and complete the OAuth flow in
the browser. Then `mcp__superwall__whoami` before anything else.
