# Onboarding Paywall Integration — Design

**Date:** 2026-06-17
**Branch:** onboarding-rebuild
**Status:** Approach approved; pending spec review

## Summary

Show the Glutt Superwall paywall immediately after the onboarding import
tutorial, before the user lands in the main app. The paywall is a pure offer:
skipping (closing) it drops the user into the full, unlocked app. No feature
gating is introduced anywhere.

## Goals

- Present the Glutt paywall once, right after onboarding completes.
- Let the user skip into the full app (non-gated paywall).
- Already-subscribed users skip the paywall automatically.
- Never block onboarding completion, even if the paywall fails to load.

## Non-goals

- No feature/Pro gating anywhere in the app (separate future task).
- No restore-purchases UI, no settings paywall, no additional placements.
- No subscription-status checks beyond what Superwall handles internally.

## Current state (from codebase exploration)

- Onboarding is a 6-step enum flow (Welcome → Goals → Rules → Nutrition →
  Notifications → Import Tutorial) in
  `Glutt/Features/Onboarding/OnboardingFlow.swift`.
- After the tutorial, `finish(thenImport:)` calls
  `OnboardingPaywallHook.presentPostOnboarding { ... }` (currently a no-op)
  before `onFinish()` closes onboarding and the main `TabView` appears.
- `Glutt/Features/Onboarding/Support/OnboardingPaywallHook.swift` is the single,
  isolated integration point — already commented with the intended Superwall call.
- SuperwallKit is **not** a dependency; there is no `Superwall.configure(...)`
  call and no subscription/paywall/StoreKit/RevenueCat code anywhere.
- Project: SwiftUI + SwiftData, iOS 17.0, Swift 5.10, bundle id
  `com.omarlahmimi.glutt`, built via XcodeGen (`project.yml`).
- Superwall references: application id `47883`, paywall id `234287`,
  products `com.glutt.premium.yearly` ($39.99/yr) and
  `com.glutt.premium.monthly` ($7.99/mo).

## Architecture / changes

### 1. Add the SuperwallKit dependency

In `project.yml`:

```yaml
packages:
  SuperwallKit:
    url: https://github.com/superwall/Superwall-iOS
    from: "4.0.0"   # latest stable 4.x at implementation time
targets:
  Glutt:
    dependencies:
      - package: SuperwallKit
```

Then regenerate the project: `xcodegen generate`. The share-extension target
does **not** need SuperwallKit.

### 2. Configure Superwall at launch

In `Glutt/App/GluttApp.swift`, configure once at app init with the public key:

```swift
import SuperwallKit
// in GluttApp.init():
Superwall.configure(apiKey: "pk_xxx")
```

The `pk_` public key is a publishable key and is safe to embed in the app.
Stored as a constant for now; can move to a build config later.

### 3. Wire the onboarding hook

Replace the no-op body of
`OnboardingPaywallHook.presentPostOnboarding(completion:)`:

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

- `register` returns immediately. The feature block (`completion`) fires after
  the paywall is dismissed/skipped, immediately if the user is already
  subscribed, or if the paywall cannot present (fail-open).
- `completion()` is what advances onboarding into the main app (and triggers the
  demo recipe import if the user chose "Import my first recipe").

### 4. Superwall dashboard config (no code)

- A **campaign** with a placement/trigger named `onboarding_complete`, audience
  100%, that presents the Glutt paywall (`234287`).
- Paywall **feature gating = Non-Gated**, so closing the paywall fires the
  feature block (skip allowed).
- The paywall has a visible **close (✕)** control = the skip affordance.
  Optional: add a "Maybe later" text button in the paywall editor.

## Skip behavior

The paywall's close (✕) button is the skip. Because the campaign is non-gated,
closing the paywall fires the feature block → `completion()` → main app, fully
unlocked.

## Robustness / fail-open

Superwall executes the feature block whenever it cannot present a paywall
(no network, no matching campaign, user already subscribed). Therefore
onboarding always completes; the worst case is that the paywall simply does not
appear and the user proceeds into the app.

## Inputs required at implementation

- Superwall **public API key** (`pk_...`) — Dashboard → Settings → API Keys.
- `xcodegen` installed (or an alternative way to add the SPM package).
- A configured `onboarding_complete` campaign (can be verified/guided via the
  Superwall editor).

## Verification

- Build succeeds with SuperwallKit linked.
- Fresh install → complete onboarding → paywall appears after the import tutorial.
- Tap ✕ (skip) → lands in main app, everything accessible.
- "Import my first recipe" path → after the paywall dismisses, the demo recipe
  import still triggers.
- With an active subscription (sandbox) → paywall is skipped automatically.
- Airplane mode → onboarding still completes (fail-open).

## Risks / notes

- The placement name must match exactly between code (`onboarding_complete`) and
  the Superwall campaign.
- Products are "Ready to Submit"/sandbox; real purchases require sandbox testers
  or going live. Showing and skipping the paywall works regardless.
- If `xcodegen` regeneration conflicts with manual `.xcodeproj` edits, regenerate
  cleanly from `project.yml`.
