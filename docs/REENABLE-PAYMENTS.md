# Re-enabling Payments / Subscriptions in Glutt

**Status:** RE-ENABLING (in progress, 2026-07-11). The Paid Apps Agreement is
now **Active**, so payments are being switched back on. The in-app code seams
are already restored (both paywall hooks + Settings Restore) and the build
passes. Remaining blocker: (re)create the two subscription products in App Store
Connect under **new IDs** and wire them into Superwall paywall 234287.

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
   | `com.omarlahmimi.glutt.premium.yearly` | 1 year | $49.99 |
   | `com.omarlahmimi.glutt.premium.monthly` | 1 month | $7.99 |
   These IDs MUST match exactly what Superwall references (see below).

   > ⚠️ **The original `com.glutt.premium.*` products were DELETED in June 2026**
   > and Apple reserves deleted IAP product IDs, so (decided **2026-07-11**) we
   > recreate under a **new, bundle-matching namespace**
   > `com.omarlahmimi.glutt.premium.{yearly,monthly}`. After creating them in
   > App Store Connect, they must also appear in **Superwall's product catalog**
   > (auto-sync via the App Store Connect API-key integration, or add them
   > manually in the Superwall dashboard → Products) before paywall **234287**
   > can be re-pointed to them.
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
- ✅ **Products re-wired (2026-07-11):** paywall 234287 `primary` = yearly,
  `secondary` = monthly, both pointing at the new
  `com.omarlahmimi.glutt.premium.{yearly,monthly}` IDs. Reference names kept, so
  all `products.*` liquid bindings still resolve. Price fields on the plan cards
  are dynamic (`products.primary.price`, `.monthlyPrice`, `products.secondary.price`)
  → they show the real StoreKit price on device.
- ✅ **Terms/Privacy row added (2026-07-11):** a centered "Terms of Use · Privacy
  Policy" row was added to the footer, each opening glutt.org/terms & /privacy in
  an in-app browser (guideline 3.1.2). Restore is also covered in-app by Settings
  (3.1.1).
- ⚠️ **Superwall product-catalog metadata is a placeholder:** the two products
  were added to Superwall with `price = 0` and the monthly's period as `year`.
  Harmless on device (StoreKit overrides), but fix the editor/fallback by
  connecting the **App Store Connect API key** (Superwall → Settings → App Store
  Connect) so real prices/periods auto-sync, or set them manually in Settings →
  Products.
- ⏳ **PENDING PUBLISH:** the editor relay has **no publish tool**; the product
  re-wire + Terms/Privacy row are **drafts** until you hit **Publish** in the
  editor UI (or `POST /v2/paywalls/234287/publish`).

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

- [x] Paid Apps Agreement is **Active** (done 2026-07-11)
- [x] `com.omarlahmimi.glutt.premium.yearly` and `...monthly` exist and are "Ready to Submit" — 2026-07-11
- [x] New products added to Superwall's product catalog (manual; prices = $0 placeholder, monthly period=year — fix via ASC API-key sync)
- [ ] Privacy Policy URL + Terms/EULA link set in App Store Connect metadata
- [x] `OnboardingPaywallHook` restored (registers `onboarding_complete`) — 2026-07-11
- [x] `InventionPaywallHook` restored (registers `invent_recipe`, fail-closed gate) — 2026-07-11
- [x] Settings "Restore Purchases" button present (already on `main`)
- [x] Superwall paywall 234287 re-pointed to new product IDs + Terms/Privacy row added — 2026-07-11
- [ ] **Publish** paywall 234287 in the editor (draft until published)
- [x] Build number bumped (7 → 8), `xcodegen generate` run, build passes — 2026-07-11
- [x] Archived: `Glutt 8.xcarchive` (v1.0 build 8), signed, GluttShare embedded — 2026-07-11
- [x] Sim-tested: Terms/Privacy links open in-app browser (paywall published)
- [ ] Upload via Organizer → Distribute App → App Store Connect, then submit version with BOTH IAPs attached
- [ ] (Optional) Connect ASC API key in Superwall so catalog prices sync off the $0 placeholder
