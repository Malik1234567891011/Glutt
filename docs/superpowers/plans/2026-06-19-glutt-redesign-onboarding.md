# Glutt Redesign — Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Restyle the first-run flow to the new design language — a Welcome hero (sage panel, rotated food-photo card, decorative Phosphor accents, "Ready in 25 min" pill, `HighlightHeadline` "Cook smarter not harder", `PageDots`, green "next" CTA) and new flow chrome (`PageDots` progress + green capsule CTA) that carries the look through all six steps — without changing any onboarding logic (state, navigation, skip, finish/paywall hook).

**Architecture:** Two files. `WelcomeScreen.swift` is rewritten to the hero design (consuming foundation `HighlightHeadline`, `PageDots`). `OnboardingFlow.swift` swaps its capsule progress bar for `PageDots` and restyles the footer CTA. The step screens (`GoalsScreen`, `RulesScreen`, `NutritionScreen`, etc.) keep their content and inherit the new chrome + cream background — no per-screen rewrites in this plan.

**Tech Stack:** SwiftUI, PhosphorSwift 2.1.0, scheme `Glutt`. Foundation components `HighlightHeadline`/`HeadlineWord` and `PageDots` already exist.

## Global Constraints

- **Build:** `xcodebuild build -scheme Glutt -destination 'id=1EEC6A07-E689-4149-ABC7-FF36F702BBF6' 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED| error:" | tail -8` → `** BUILD SUCCEEDED **`. Only on a DerivedData permission error re-run with sandbox disabled.
- **No new files** (both files exist; no registration). Use `Theme.*`, `Font.glutt*`, foundation components. Phosphor names usable: `plus`, `sparkle`, `clock`, `arrowRight`.
- **Preserve all logic:** `OnboardingFlow`'s `Step` enum, `advance()`, `goBack()`, `backTarget`, `finish(thenImport:)`, `OnboardingState`, the skip button, and the paywall hook stay byte-for-byte. `WelcomeScreen`'s single `onStart` callback stays.
- **Bundled hero photo:** asset `"pestoGnocchiMealPrep"` (confirmed in `Glutt/Resources/Assets.xcassets`).
- **Commits:** conventional; end body with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## File Structure

- Modify (rewrite body): `Glutt/Features/Onboarding/Screens/WelcomeScreen.swift`.
- Modify: `Glutt/Features/Onboarding/OnboardingFlow.swift` — progress → `PageDots`, footer CTA restyle.

---

### Task 1: Redesign WelcomeScreen

**Files:** Modify `Glutt/Features/Onboarding/Screens/WelcomeScreen.swift`

**Interfaces:** Keeps `WelcomeScreen(onStart: () -> Void)`. Consumes `HighlightHeadline`/`HeadlineWord`, `PageDots`, `Theme.Colors.sagePanel/creamText`, Phosphor.

- [ ] **Step 1:** Replace the entire file with:
```swift
import SwiftUI
import PhosphorSwift

/// First onboarding screen: a food-photo hero on a sage panel + the highlighted
/// headline and a single "next" CTA.
struct WelcomeScreen: View {
    let onStart: () -> Void
    @State private var float = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            heroPanel
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HighlightHeadline(words: [
                    HeadlineWord(text: "Cook", style: .green),
                    HeadlineWord(text: "smarter", style: .amber),
                    HeadlineWord(text: "not", style: .plain),
                    HeadlineWord(text: "harder", style: .tomato),
                ])
                Text("Save recipes from anywhere, cook what you already have, and waste less — all in one place.")
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
            footer
        }
        .padding(.top, Theme.Spacing.lg)
        .background(Theme.Colors.background)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { float = true }
        }
    }

    private var heroPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Theme.Colors.sagePanel)
            // scattered decorative accents
            Ph.plus.bold.resizable().scaledToFit().frame(width: 22, height: 22)
                .foregroundColor(Theme.Colors.tomato).offset(x: -118, y: -118)
            Ph.sparkle.fill.resizable().scaledToFit().frame(width: 26, height: 26)
                .foregroundColor(Theme.Colors.warning).offset(x: 122, y: -92)
            Ph.plus.bold.resizable().scaledToFit().frame(width: 14, height: 14)
                .foregroundColor(Theme.Colors.accent).offset(x: 118, y: 120)
            Circle().fill(Theme.Colors.tomato).frame(width: 10, height: 10).offset(x: -120, y: 104)
            // the photo card
            Image("pestoGnocchiMealPrep")
                .resizable().scaledToFill()
                .frame(width: 200, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Theme.Colors.textPrimary.opacity(0.18), radius: 18, y: 10)
                .rotationEffect(.degrees(float ? -3 : -1))
            // floating "ready" pill
            HStack(spacing: 6) {
                Ph.clock.regular.resizable().scaledToFit().frame(width: 13, height: 13)
                Text("Ready in 25 min").font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.Colors.card, in: Capsule())
            .shadow(color: Theme.Colors.textPrimary.opacity(0.1), radius: 8, y: 3)
            .offset(y: 150)
        }
        .frame(height: 366)
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                PageDots(count: 6, index: 0)
                Spacer()
                Button(action: onStart) {
                    HStack(spacing: 8) {
                        Text("next").font(.system(size: 16, weight: .bold, design: .rounded))
                        Ph.arrowRight.bold.resizable().scaledToFit().frame(width: 16, height: 16)
                    }
                    .foregroundStyle(Theme.Colors.creamText)
                    .padding(.horizontal, 26).padding(.vertical, 15)
                    .background(Theme.Colors.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if let privacyURL = URL(string: "https://glutt.org/privacy") {
                Link("Privacy Policy", destination: privacyURL)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
    }
}

#Preview {
    WelcomeScreen(onStart: {})
}
```
- [ ] **Step 2:** Build → `** BUILD SUCCEEDED **`. (If `"pestoGnocchiMealPrep"` doesn't render, pick another confirmed asset from `Glutt/Resources/Assets.xcassets` such as `greekYogurtBowl` or `garlicButterSteakPotatoBowl`.)
- [ ] **Step 3:** Commit: `git commit -am "feat(redesign): Welcome hero — sage panel, photo card, highlighted headline, next CTA"`.

---

### Task 2: Restyle OnboardingFlow chrome (PageDots + green CTA)

**Files:** Modify `Glutt/Features/Onboarding/OnboardingFlow.swift`

**Interfaces:** Consumes `PageDots`, Phosphor. ALL navigation/finish logic unchanged.

- [ ] **Step 1:** Add `import PhosphorSwift` after the existing imports (the file currently imports `SwiftData` + `SwiftUI`).

- [ ] **Step 2:** Replace the `topBar` computed property so the capsule progress bar becomes `PageDots` centered between Back and Skip:
```swift
    private var topBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            if backTarget != nil {
                Button { goBack() } label: {
                    Image(systemName: "chevron.left").font(.headline)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            PageDots(count: Step.allCases.count, index: step.rawValue)
            Spacer()
            Button("Skip") { finish(thenImport: false) }
                .font(.gluttCaption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
    }
```

- [ ] **Step 3:** DELETE the now-unused `progressBar` and `progressFraction` computed properties (lines ~76-94). They have no other callers after Step 2.

- [ ] **Step 4:** Replace `standardFooter` so "Continue" becomes the green capsule CTA matching Welcome:
```swift
    private var standardFooter: some View {
        Button { advance() } label: {
            HStack(spacing: 8) {
                Text("Continue").font(.system(size: 16, weight: .bold, design: .rounded))
                Ph.arrowRight.bold.resizable().scaledToFit().frame(width: 16, height: 16)
            }
            .foregroundStyle(Theme.Colors.creamText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.Colors.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.md)
    }
```

- [ ] **Step 5:** Build → `** BUILD SUCCEEDED **`. Confirm no leftover references to `progressBar`/`progressFraction`.
- [ ] **Step 6:** Commit: `git commit -am "feat(redesign): onboarding chrome — PageDots progress + green capsule CTA"`.

---

## Self-Review

**Spec coverage:** Welcome sage hero panel + rotated photo card + decorative accents + "Ready in 25 min" pill + `HighlightHeadline` + subtitle + `PageDots` + "next" CTA (Task 1) ✓; new look carried through the flow via `PageDots` progress + green capsule CTA on the cream background (Task 2) ✓; the standard footer steps (goals/rules/nutrition) get the new CTA; notifications/tutorial own their buttons (unchanged) ✓.

**Placeholders:** none. **Logic preserved:** `Step`, `advance`, `goBack`, `backTarget`, `finish`, skip, paywall hook untouched; `WelcomeScreen(onStart:)` signature unchanged (so `OnboardingFlow`'s `WelcomeScreen { advance() }` call still compiles).

**Risks:**
- Decorative-accent `.offset` positions are approximate — verify on the screenshot they sit inside the panel and don't clip; nudge if needed.
- The hero photo card `.frame(width:200,height:250)` on the 366-tall panel + the `offset(y:150)` pill must not overflow the panel bottom — verify in screenshot.
- `PageDots(count: 6, index: step.rawValue)` shows all 6 steps including welcome/tutorial; that's intended (continuous progress). Verify dots advance as steps change.
