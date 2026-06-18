# Re-enabling Payments / Subscriptions in Glutt

**Status:** Payments are TEMPORARILY DISABLED. Glutt is shipping as a **free app
with no in-app purchases** while the Paid Apps Agreement is pending (waiting on a
**DUNS number** for the organization account, plus tax forms + banking).

This document is the single source of truth for switching subscriptions back on.
It is written so an AI agent or developer can follow it end-to-end.

---

## Background / why it was disabled

The June 2026 App Store submission (v1.0 build 2) was rejected partly because the
"Continue" purchase button did nothing — the StoreKit products could not load
because the **Paid Apps Agreement was not Active** (Apple won't serve IAP
products until it is). Rather than wait on the DUNS/tax/banking process, we are
launching free now and will add subscriptions in a later update.

The Superwall integration is intentionally kept in place (SDK dependency stays,
`Superwall.configure(...)` still runs in `Glutt/App/GluttApp.swift`). Only the
two paywall *presentation seams* and the Settings restore UI were neutralized, so
re-enabling is a small, well-contained change.

---

## Prerequisites in App Store Connect (do these FIRST — they are the real blocker)

1. **Paid Apps Agreement → Active.** App Store Connect → *Business / Agreements,
   Tax, and Banking*:
   - Obtain the **DUNS number** (organization accounts) if applicable.
   - Complete the **tax forms** (Canadian individual: typically a W-8BEN needing
     name, address, and SIN; a company/Delaware entity needs its own tax IDs).
   - Confirm **banking** is set up and not "Processing."
   - The agreement status must read **Active**, not "Pending User Info."
2. **Create the two auto-renewable subscriptions** in a Subscription Group
   (e.g. "Glutt Premium"), with localized display name + description, price, and
   a **review screenshot** so each reaches **"Ready to Submit":**
   | Product ID | Length | Price |
   | --- | --- | --- |
   | `com.glutt.premium.yearly` | 1 year | $39.99 |
   | `com.glutt.premium.monthly` | 1 month | $7.99 |
   These IDs MUST match exactly what Superwall references (see below).

   > ⚠️ **The original products were DELETED in June 2026** to ship the free
   > build (Apple kept reviewing them and rejecting because they were attached
   > to a free app). Apple generally does **not** allow reusing a deleted IAP's
   > product ID, so when recreating, expect to need **new IDs** (e.g.
   > `com.glutt.premium.yearly2` / `...monthly2`). If you change the IDs, also
   > update the product references on Superwall **paywall 234287** (and this
   > table) to match.
3. **Metadata:** Privacy Policy URL = `https://glutt.org/privacy`; add the Terms
   of Use (EULA) link `https://glutt.org/terms` to the App Description (or paste
   the EULA into the License Agreement field).
4. **Submit the IAPs together with the build** so they get reviewed.

> Until steps 1 & 2 are both done, the purchase button will not work — no code
> change can substitute for them.

---

## Superwall dashboard (already configured — verify only)

- Automatic mode (no PurchaseController). Org 23589 / project 24809 / app 47883.
- Placements `onboarding_complete` + `invent_recipe` → campaign "Glutt" (91288),
  audience "no active entitlements" → paywall **234287** ("Calorie Tracker
  template").
- Paywall 234287 has both products wired (yearly = primary, monthly = secondary)
  and a published footer with **Restore · Terms · Privacy** links.
- If you edit the paywall, **re-publish** it (`POST /v2/paywalls/234287/publish`).

---

## Code changes to revert (the actual re-enable)

### 1. `Glutt/Features/Onboarding/Support/OnboardingPaywallHook.swift`

Restore the body to present the post-onboarding paywall:

```swift
import SuperwallKit

enum OnboardingPaywallHook {
    static func presentPostOnboarding(completion: @escaping () -> Void) {
        Superwall.shared.register(placement: "onboarding_complete") {
            completion()
        }
    }
}
```

### 2. `Glutt/Features/Assistant/InventionPaywallHook.swift`

Restore the fail-closed Premium gate:

```swift
import SuperwallKit

enum InventionPaywallHook {
    static func presentBeforeInventing(completion: @escaping () -> Void) {
        Superwall.shared.register(placement: "invent_recipe") {
            // Fail-closed: only run the paid feature when actually entitled.
            guard Superwall.shared.subscriptionStatus.isActive else { return }
            completion()
        }
    }
}
```

### 3. `Glutt/Features/Settings/SettingsView.swift` — re-add the Restore button

Re-add the distinct "Restore Purchases" control (App Review guideline 3.1.1).
The exact, previously-shipped implementation is in git commit **`6533767`**
("feat: add Restore Purchases button in Settings"). To restore it:

```bash
git show 6533767:Glutt/Features/Settings/SettingsView.swift > Glutt/Features/Settings/SettingsView.swift
```

…then re-apply any unrelated Settings changes made since. That commit adds:
`import SuperwallKit`, `@State private var isRestoring/didRestorePurchases`, a
`subscriptionSection` with the Restore button, the success `.alert`, and a
`restorePurchases()` helper calling `Superwall.shared.restorePurchases()`.

---

## Build & ship

1. Bump the build number in `project.yml` (`CURRENT_PROJECT_VERSION`, both the
   `Glutt` and `GluttShare` targets) to the next unused value.
2. Regenerate the project: `xcodegen generate`.
3. Build to verify:
   `xcodebuild build -project Glutt.xcodeproj -scheme Glutt -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
4. Archive in Xcode (Release) and upload.
5. In sandbox, confirm: paywall shows after onboarding, Continue starts a real
   purchase, the invent feature is gated, and Restore works.

---

## Re-enable checklist

- [ ] Paid Apps Agreement is **Active** (DUNS + tax + banking done)
- [ ] `com.glutt.premium.yearly` and `com.glutt.premium.monthly` exist and are "Ready to Submit"
- [ ] Privacy Policy URL + Terms/EULA link set in App Store Connect metadata
- [ ] `OnboardingPaywallHook` restored (registers `onboarding_complete`)
- [ ] `InventionPaywallHook` restored (registers `invent_recipe`, fail-closed gate)
- [ ] Settings "Restore Purchases" button restored (from commit `6533767`)
- [ ] Superwall paywall 234287 published with products + Restore/Terms/Privacy
- [ ] Build number bumped, `xcodegen generate` run, build passes
- [ ] Sandbox-tested: purchase + gate + restore all work
