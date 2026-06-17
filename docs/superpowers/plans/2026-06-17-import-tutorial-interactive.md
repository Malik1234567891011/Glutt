# Interactive Import Tutorial Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the onboarding import tutorial into an interactive, ReciMe-style walkthrough where the user taps a highlighted spot on real share-flow screenshots (Share → "Share to…" → Glutt) to advance, with a live pulsing coach mark layered on top.

**Architecture:** A pure `@Observable` state machine (`TutorialFlowModel`) drives a rewritten `ImportTutorialScreen`. Each walkthrough step renders a screenshot via `WalkthroughFrame`, which maps a normalized hotspot to a tappable region and overlays a pulsing `CoachMark`. Tapping the hotspot advances; a miss nudges; ~4s idle auto-advances. After the 3 taps, the existing importing → success → CTA tail runs (no real import).

**Tech Stack:** SwiftUI, Observation (`@Observable`), XCTest, XcodeGen.

## Global Constraints

- Deployment target **iOS 17**, **Swift 5.10**. `@Observable` / `@State` reference-model pattern is available and preferred.
- **Light theme only** — use existing `Theme` tokens and button styles (`.gluttPrimary`, `.gluttSecondary`); introduce no new colors.
- `ImportTutorialScreen`'s init **must stay** `init(onImportNow: @escaping () -> Void, onFinish: @escaping () -> Void)` — `OnboardingFlow.swift:44` depends on it. Do not change the call site.
- The tutorial performs **NO real import**. Only the end CTA `onImportNow` hands off to the real importer (handled by the existing caller).
- **XcodeGen:** after creating or deleting any file under `Glutt/` or `GluttTests/`, run `xcodegen generate`. `Glutt.xcodeproj/project.pbxproj` **is tracked** — commit it with the change. (Adding imagesets *inside* the already-referenced `Assets.xcassets` does **not** need regeneration.)
- Tests use **XCTest** with `@testable import Glutt`.
- Build: `xcodebuild build -project Glutt.xcodeproj -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO`
- Known tradeoff: `tutorial-2.png` / `tutorial-3.png` are ~338px-wide composites; upscaled full-width they look soft. Accepted for now (can be re-exported higher-res later). Do not block on it.

---

### Task 1: TutorialFlowModel (pure state machine) + tests

The testable core. No SwiftUI. Also removes the obsolete `TutorialPhase` enum's test (the enum itself is removed in Task 5).

**Files:**
- Create: `Glutt/Features/Onboarding/Support/TutorialFlowModel.swift`
- Create (test): `GluttTests/TutorialFlowModelTests.swift`
- Delete: `GluttTests/TutorialPhaseTests.swift` (tests the `TutorialPhase` enum being retired)

**Interfaces:**
- Produces (consumed by Tasks 3 & 5):
  - `struct TutorialStep: Identifiable` with `let id: Int`, `imageName: String`, `headline: String`, `hotspot: CGRect` (normalized 0…1, origin top-left), `pointer: TutorialStep.Pointer` (`.up | .down`), `showsLabel: Bool`.
  - `final class TutorialFlowModel` (`@Observable`) exposing: `enum Phase: Equatable { case walkthrough(Int), importing, success, cta }`, `let steps: [TutorialStep]`, `private(set) var phase: Phase`, `private(set) var nudgeToken: Int`, `var currentStep: TutorialStep?`, `var headline: String`, and methods `tapHotspot()`, `idleFired()`, `tapMiss()`.
  - `static let TutorialFlowModel.defaultSteps: [TutorialStep]`.

- [ ] **Step 1: Write the failing test**

Create `GluttTests/TutorialFlowModelTests.swift`:

```swift
import XCTest
@testable import Glutt

final class TutorialFlowModelTests: XCTestCase {

    func testStartsAtFirstWalkthroughStep() {
        let m = TutorialFlowModel()
        XCTAssertEqual(m.phase, .walkthrough(0))
        XCTAssertEqual(m.currentStep?.id, 0)
        XCTAssertEqual(m.steps.count, 3)
    }

    func testTapHotspotAdvancesThroughEveryPhase() {
        let m = TutorialFlowModel()
        m.tapHotspot(); XCTAssertEqual(m.phase, .walkthrough(1))
        m.tapHotspot(); XCTAssertEqual(m.phase, .walkthrough(2))
        m.tapHotspot(); XCTAssertEqual(m.phase, .importing)   // last step -> importing
        m.tapHotspot(); XCTAssertEqual(m.phase, .success)
        m.tapHotspot(); XCTAssertEqual(m.phase, .cta)
        m.tapHotspot(); XCTAssertEqual(m.phase, .cta)         // cta is terminal
    }

    func testIdleFiredAdvancesLikeTap() {
        let m = TutorialFlowModel()
        m.idleFired()
        XCTAssertEqual(m.phase, .walkthrough(1))
    }

    func testTapMissNudgesWithoutAdvancing() {
        let m = TutorialFlowModel()
        XCTAssertEqual(m.nudgeToken, 0)
        m.tapMiss()
        XCTAssertEqual(m.phase, .walkthrough(0))
        XCTAssertEqual(m.nudgeToken, 1)
        m.tapMiss()
        XCTAssertEqual(m.nudgeToken, 2)
    }

    func testCurrentStepIsNilOncePastWalkthrough() {
        let m = TutorialFlowModel()
        m.tapHotspot(); m.tapHotspot(); m.tapHotspot() // into importing
        XCTAssertNil(m.currentStep)
    }

    func testHeadlineTracksPhase() {
        let m = TutorialFlowModel()
        XCTAssertEqual(m.headline, "Found a recipe you love?")
        m.tapHotspot()
        XCTAssertEqual(m.headline, "Just tap Share → Glutt")
        m.tapHotspot(); m.tapHotspot() // importing
        XCTAssertEqual(m.headline, "Pulling out the recipe…")
        m.tapHotspot() // success
        XCTAssertEqual(m.headline, "That's it — it's saved. ✨")
    }
}
```

- [ ] **Step 2: Delete the obsolete test and regenerate the project**

```bash
git rm GluttTests/TutorialPhaseTests.swift
xcodegen generate
```

Expected: project regenerates; `TutorialFlowModelTests.swift` is now in the test target, `TutorialPhaseTests.swift` is gone.

- [ ] **Step 3: Run the test to verify it fails**

```bash
xcodebuild test -project Glutt.xcodeproj -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:GluttTests/TutorialFlowModelTests CODE_SIGNING_ALLOWED=NO
```

Expected: **compile failure** — `cannot find 'TutorialFlowModel' in scope`.

- [ ] **Step 4: Write the minimal implementation**

Create `Glutt/Features/Onboarding/Support/TutorialFlowModel.swift`:

```swift
import CoreGraphics
import Observation

/// One frame of the interactive import walkthrough: a screenshot plus the
/// normalized location of the button the user must tap to advance.
struct TutorialStep: Identifiable {
    enum Pointer { case up, down }

    let id: Int
    let imageName: String
    let headline: String
    /// Normalized rect (0…1) relative to the displayed screenshot, origin top-left.
    let hotspot: CGRect
    let pointer: Pointer
    /// Frame 0 has no baked-in pill, so it draws its own "Tap here" label.
    let showsLabel: Bool
}

/// Pure, SwiftUI-free state machine for the import tutorial. Drives the
/// walkthrough → importing → success → cta progression. No real import happens.
@Observable
final class TutorialFlowModel {

    enum Phase: Equatable {
        case walkthrough(Int)
        case importing
        case success
        case cta
    }

    let steps: [TutorialStep]
    private(set) var phase: Phase = .walkthrough(0)
    /// Incremented on a wrong tap so the view can fire a one-shot "nudge" pulse.
    private(set) var nudgeToken = 0

    init(steps: [TutorialStep] = TutorialFlowModel.defaultSteps) {
        self.steps = steps
    }

    var currentStep: TutorialStep? {
        if case let .walkthrough(i) = phase, steps.indices.contains(i) { return steps[i] }
        return nil
    }

    var headline: String {
        switch phase {
        case let .walkthrough(i): return steps[i].headline
        case .importing:          return "Pulling out the recipe…"
        case .success, .cta:      return "That's it — it's saved. ✨"
        }
    }

    /// User tapped the highlighted hotspot — advance.
    func tapHotspot() { advance() }

    /// Idle timeout elapsed — advance anyway (safety net so no one gets stuck).
    func idleFired() { advance() }

    /// User tapped outside the hotspot — nudge the mark, do not advance.
    func tapMiss() { nudgeToken += 1 }

    private func advance() {
        switch phase {
        case let .walkthrough(i):
            let next = i + 1
            phase = steps.indices.contains(next) ? .walkthrough(next) : .importing
        case .importing: phase = .success
        case .success:   phase = .cta
        case .cta:       break // terminal — CTA buttons own the exit
        }
    }
}

extension TutorialFlowModel {
    /// Hotspot rects are first guesses; tune them live in the simulator using
    /// the DEBUG tap-coordinate print in `WalkthroughFrame` (see Task 5).
    static let defaultSteps: [TutorialStep] = [
        TutorialStep(
            id: 0,
            imageName: "tutorialPost",
            headline: "Found a recipe you love?",
            hotspot: CGRect(x: 0.78, y: 0.92, width: 0.18, height: 0.05),
            pointer: .up,
            showsLabel: true
        ),
        TutorialStep(
            id: 1,
            imageName: "tutorialShareSheetApp",
            headline: "Just tap Share → Glutt",
            hotspot: CGRect(x: 0.26, y: 0.85, width: 0.22, height: 0.08),
            pointer: .down,
            showsLabel: false
        ),
        TutorialStep(
            id: 2,
            imageName: "tutorialShareSheetSystem",
            headline: "Just tap Share → Glutt",
            hotspot: CGRect(x: 0.27, y: 0.55, width: 0.18, height: 0.11),
            pointer: .up,
            showsLabel: false
        ),
    ]
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
xcodebuild test -project Glutt.xcodeproj -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:GluttTests/TutorialFlowModelTests CODE_SIGNING_ALLOWED=NO
```

Expected: **TEST SUCCEEDED**, all 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Glutt/Features/Onboarding/Support/TutorialFlowModel.swift \
        GluttTests/TutorialFlowModelTests.swift \
        Glutt.xcodeproj/project.pbxproj
git add -u GluttTests/TutorialPhaseTests.swift
git commit -m "feat: add TutorialFlowModel state machine for interactive tutorial"
```

---

### Task 2: CoachMark view (pulsing ring + optional label)

The animated mark layered on top of the screenshot. Pure presentation; no unit test (verified by build + preview).

**Files:**
- Create: `Glutt/Features/Onboarding/Support/CoachMark.swift`

**Interfaces:**
- Consumes: `TutorialStep.Pointer` (from Task 1).
- Produces (consumed by Task 3): `struct CoachMark` with `init(pointer: TutorialStep.Pointer, showsLabel: Bool, nudgeToken: Int)`. Fills the frame it is given; never intercepts taps (`allowsHitTesting(false)`).

- [ ] **Step 1: Create the view**

Create `Glutt/Features/Onboarding/Support/CoachMark.swift`:

```swift
import SwiftUI

/// A pulsing "tap here" coach mark drawn on top of a tutorial screenshot.
/// Fills the frame it is given (sized to the target button by `WalkthroughFrame`)
/// and never intercepts touches.
struct CoachMark: View {
    let pointer: TutorialStep.Pointer
    let showsLabel: Bool
    /// Increment to fire a one-shot, larger "you missed" nudge.
    let nudgeToken: Int

    @State private var ripple = false
    @State private var breathe = false
    @State private var nudge = false

    var body: some View {
        ZStack {
            // Expanding "radar" ripple — fades as it grows past the button.
            Circle()
                .stroke(Theme.Colors.accent.opacity(0.9), lineWidth: 3)
                .scaleEffect(ripple ? 2.2 : 1.0)
                .opacity(ripple ? 0 : 0.8)

            // Steady ring that gently breathes on the button itself.
            Circle()
                .fill(Theme.Colors.accent.opacity(0.12))
                .overlay(Circle().stroke(Theme.Colors.accent, lineWidth: 3))
                .scaleEffect(breathe ? 1.08 : 0.94)
        }
        .scaleEffect(nudge ? 1.28 : 1.0)
        .overlay(alignment: pointer == .down ? .top : .bottom) {
            if showsLabel {
                label.fixedSize().offset(y: pointer == .down ? -18 : 18)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                ripple = true
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .onChange(of: nudgeToken) { _, _ in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) { nudge = true }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.16)) { nudge = false }
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            if pointer == .up { Text("👆") }
            Text("Tap here").font(.caption2.weight(.bold)).foregroundStyle(.white)
            if pointer == .down { Text("👇") }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.Colors.accent, in: Capsule())
    }
}

#Preview {
    ZStack {
        Theme.Colors.background
        CoachMark(pointer: .up, showsLabel: true, nudgeToken: 0)
            .frame(width: 56, height: 56)
    }
}
```

- [ ] **Step 2: Regenerate the project**

```bash
xcodegen generate
```

Expected: `CoachMark.swift` added to the Glutt target.

- [ ] **Step 3: Build to verify it compiles**

```bash
xcodebuild build -project Glutt.xcodeproj -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
```

Expected: **BUILD SUCCEEDED**.

- [ ] **Step 4: Commit**

```bash
git add Glutt/Features/Onboarding/Support/CoachMark.swift Glutt.xcodeproj/project.pbxproj
git commit -m "feat: add CoachMark pulsing tutorial overlay"
```

---

### Task 3: WalkthroughFrame view (screenshot + hotspot + tap routing + idle timer)

Renders one screenshot, maps the normalized hotspot to screen coordinates, places the `CoachMark`, routes taps, and runs the idle auto-advance.

**Files:**
- Create: `Glutt/Features/Onboarding/Support/WalkthroughFrame.swift`

**Interfaces:**
- Consumes: `TutorialStep` (Task 1), `CoachMark` (Task 2).
- Produces (consumed by Task 5): `struct WalkthroughFrame` with `init(step: TutorialStep, nudgeToken: Int, onHotspotTap: @escaping () -> Void, onMiss: @escaping () -> Void)`.

**Note on layout:** use `.resizable().aspectRatio(aspect, contentMode: .fit)` (NOT `.scaledToFit()`). With an explicit aspect ratio the Image view's own frame equals the fitted image rect, so the `.overlay` `GeometryReader` reads coordinates in the *image's* space — making the normalized → pixel hotspot mapping exact. `aspect` is read from the asset so each screenshot maps correctly.

- [ ] **Step 1: Create the view**

Create `Glutt/Features/Onboarding/Support/WalkthroughFrame.swift`:

```swift
import SwiftUI

/// Renders a tutorial screenshot fit-to-width and overlays a tappable, pulsing
/// hotspot over a real button. Tap inside → `onHotspotTap`; tap elsewhere →
/// `onMiss`; ~4s idle → `onHotspotTap` (safety net). Idle timer resets on any tap.
struct WalkthroughFrame: View {
    let step: TutorialStep
    let nudgeToken: Int
    let onHotspotTap: () -> Void
    let onMiss: () -> Void

    private static let idleSeconds: Double = 4

    @State private var idleResetToken = 0

    /// Aspect (w/h) read from the asset so the hotspot maps onto the real button.
    private var aspect: CGFloat {
        guard let image = UIImage(named: step.imageName), image.size.height > 0 else { return 0.46 }
        return image.size.width / image.size.height
    }

    var body: some View {
        Image(step.imageName)
            .resizable()
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let rect = hotspotRect(in: proxy.size)
                    ZStack {
                        CoachMark(pointer: step.pointer,
                                  showsLabel: step.showsLabel,
                                  nudgeToken: nudgeToken)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)

                        #if DEBUG
                        Rectangle()
                            .stroke(.red, lineWidth: 1)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                        #endif
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in handleTap(value.location, in: proxy.size) }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: Theme.Colors.textPrimary.opacity(0.12), radius: 14, y: 4)
            .task(id: "\(step.id)-\(idleResetToken)") {
                try? await Task.sleep(for: .seconds(Self.idleSeconds))
                guard !Task.isCancelled else { return }
                onHotspotTap()
            }
    }

    private func hotspotRect(in size: CGSize) -> CGRect {
        CGRect(x: step.hotspot.minX * size.width,
               y: step.hotspot.minY * size.height,
               width: step.hotspot.width * size.width,
               height: step.hotspot.height * size.height)
    }

    private func handleTap(_ location: CGPoint, in size: CGSize) {
        idleResetToken += 1 // any tap restarts the idle countdown
        #if DEBUG
        print("CoachMark tap — normalized x=\(location.x / size.width), y=\(location.y / size.height)")
        #endif
        if hotspotRect(in: size).contains(location) {
            onHotspotTap()
        } else {
            onMiss()
        }
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild build -project Glutt.xcodeproj -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
```

Expected: **BUILD SUCCEEDED**. (Image assets don't exist yet — that's fine; `Image(named:)` of a missing asset just renders empty. Real images land in Task 4.)

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Onboarding/Support/WalkthroughFrame.swift Glutt.xcodeproj/project.pbxproj
git commit -m "feat: add WalkthroughFrame screenshot + hotspot tap layer"
```

---

### Task 4: Add the three tutorial screenshots as imagesets

Copy the provided PNGs into the asset catalog. No `xcodegen generate` needed (assets live inside the already-referenced `Assets.xcassets`).

**Files:**
- Create: `Glutt/Resources/Assets.xcassets/tutorialPost.imageset/{Contents.json, tutorial-1.png}`
- Create: `Glutt/Resources/Assets.xcassets/tutorialShareSheetApp.imageset/{Contents.json, tutorial-2.png}`
- Create: `Glutt/Resources/Assets.xcassets/tutorialShareSheetSystem.imageset/{Contents.json, tutorial-3.png}`

- [ ] **Step 1: Create the imageset folders and copy the PNGs**

```bash
ASSETS="Glutt/Resources/Assets.xcassets"
mkdir -p "$ASSETS/tutorialPost.imageset" \
         "$ASSETS/tutorialShareSheetApp.imageset" \
         "$ASSETS/tutorialShareSheetSystem.imageset"
cp /Users/omarlahmimi/Downloads/tutorial-1.png "$ASSETS/tutorialPost.imageset/tutorial-1.png"
cp /Users/omarlahmimi/Downloads/tutorial-2.png "$ASSETS/tutorialShareSheetApp.imageset/tutorial-2.png"
cp /Users/omarlahmimi/Downloads/tutorial-3.png "$ASSETS/tutorialShareSheetSystem.imageset/tutorial-3.png"
```

- [ ] **Step 2: Write each Contents.json (single-scale universal)**

`Glutt/Resources/Assets.xcassets/tutorialPost.imageset/Contents.json`:

```json
{
  "images" : [
    { "filename" : "tutorial-1.png", "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`Glutt/Resources/Assets.xcassets/tutorialShareSheetApp.imageset/Contents.json`:

```json
{
  "images" : [
    { "filename" : "tutorial-2.png", "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`Glutt/Resources/Assets.xcassets/tutorialShareSheetSystem.imageset/Contents.json`:

```json
{
  "images" : [
    { "filename" : "tutorial-3.png", "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 3: Build to verify the asset catalog compiles**

```bash
xcodebuild build -project Glutt.xcodeproj -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
```

Expected: **BUILD SUCCEEDED**, no "unassigned children" / asset warnings for the three new sets.

- [ ] **Step 4: Commit**

```bash
git add Glutt/Resources/Assets.xcassets/tutorialPost.imageset \
        Glutt/Resources/Assets.xcassets/tutorialShareSheetApp.imageset \
        Glutt/Resources/Assets.xcassets/tutorialShareSheetSystem.imageset
git commit -m "assets: add interactive import tutorial screenshots"
```

---

### Task 5: Rewrite ImportTutorialScreen + retire the old scripted tutorial

Replace the abstract auto-play screen with the interactive flow. Remove the now-dead `TutorialPhase` enum and `ShareSheetMock`. Keep the existing importing spinner, saved card, and CTA buttons.

**Files:**
- Rewrite: `Glutt/Features/Onboarding/Screens/ImportTutorialScreen.swift`
- Delete: `Glutt/Features/Onboarding/Support/ShareSheetMock.swift` (only used by the old tutorial)
- (No change to `Glutt/Features/Onboarding/OnboardingFlow.swift` — same init.)

**Interfaces:**
- Consumes: `TutorialFlowModel` (Task 1), `WalkthroughFrame` (Task 3), `GlowBackground`, `Theme`, `.gluttPrimary` / `.gluttSecondary`.
- Produces: `ImportTutorialScreen(onImportNow:onFinish:)` — unchanged signature.

- [ ] **Step 1: Replace the file contents**

Overwrite `Glutt/Features/Onboarding/Screens/ImportTutorialScreen.swift`:

```swift
import SwiftUI

/// Interactive, ReciMe-style walkthrough of "save from anywhere → it's in Glutt".
/// The user taps the highlighted spot on each real screenshot to advance:
/// Share icon → "Share to…" → Glutt. Performs NO real import; the end CTA hands
/// off to the real importer.
struct ImportTutorialScreen: View {
    let onImportNow: () -> Void
    let onFinish: () -> Void

    @State private var model = TutorialFlowModel()

    var body: some View {
        ZStack {
            GlowBackground()

            VStack(spacing: Theme.Spacing.lg) {
                header
                Spacer(minLength: 0)
                stage
                Spacer(minLength: 0)
                footer
            }
            .padding(.top, Theme.Spacing.md)

            if model.currentStep != nil { skipButton }
        }
        .animation(.spring(duration: 0.45), value: model.phase)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(model.headline)
                .font(.gluttLargeTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textPrimary)
                .id(model.headline) // re-triggers the transition on change
                .transition(.opacity)
            if model.currentStep != nil {
                Text("Also works with TikTok, Pinterest, Safari & more.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Stage

    @ViewBuilder private var stage: some View {
        switch model.phase {
        case .walkthrough:
            if let step = model.currentStep {
                WalkthroughFrame(
                    step: step,
                    nudgeToken: model.nudgeToken,
                    onHotspotTap: { model.tapHotspot() },
                    onMiss: { model.tapMiss() }
                )
                .padding(.horizontal, Theme.Spacing.md)
                .transition(.opacity)
            }
        case .importing:
            VStack(spacing: Theme.Spacing.md) {
                ProgressView().controlSize(.large)
                Image(systemName: "fork.knife")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .task {
                try? await Task.sleep(for: .seconds(1.1))
                model.tapHotspot() // importing -> success
            }
        case .success, .cta:
            savedCard
        }
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        switch model.phase {
        case .success:
            // Brief beat on the saved card before the CTA slides in.
            Color.clear
                .frame(height: 1)
                .task {
                    try? await Task.sleep(for: .seconds(0.6))
                    model.tapHotspot() // success -> cta
                }
        case .cta:
            VStack(spacing: Theme.Spacing.sm) {
                Button("Import my first recipe", action: onImportNow)
                    .buttonStyle(.gluttPrimary)
                Button("I'll explore on my own", action: onFinish)
                    .buttonStyle(.gluttSecondary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        default:
            EmptyView()
        }
    }

    private var skipButton: some View {
        VStack {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.md)
            }
            Spacer()
        }
    }

    // MARK: - Saved result (presentational only — no Recipe model / network)

    private var savedCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Theme.Colors.successTint)
                .frame(width: 64, height: 64)
                .overlay(Text("🍝").font(.title))
            VStack(alignment: .leading, spacing: 4) {
                Text("Cheesy ramen")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Saved to your recipes")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.accent)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.accent)
                .font(.title2)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: Theme.Colors.textPrimary.opacity(0.1), radius: 12, y: 4)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

#Preview {
    ImportTutorialScreen(onImportNow: {}, onFinish: {})
}
```

- [ ] **Step 2: Delete the unused ShareSheetMock and regenerate**

```bash
git rm Glutt/Features/Onboarding/Support/ShareSheetMock.swift
xcodegen generate
```

Expected: project regenerates without `ShareSheetMock.swift`; no references remain (the old `ImportTutorialScreen` was the only consumer).

- [ ] **Step 3: Build and run the full test suite**

```bash
xcodebuild build -project Glutt.xcodeproj -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Glutt.xcodeproj -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
```

Expected: **BUILD SUCCEEDED** and **TEST SUCCEEDED** (no `TutorialPhase` references remain; `TutorialFlowModelTests` pass).

- [ ] **Step 4: Manual verification + hotspot tuning in the simulator**

```bash
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true
open -a Simulator
xcodebuild build -project Glutt.xcodeproj -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
xcrun simctl install booted "$(xcodebuild -project Glutt.xcodeproj -scheme Glutt -showBuildSettings -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')"
xcrun simctl launch booted com.omarlahmimi.glutt -onboarding
```

Then, in the running app, advance to the import tutorial and verify:
1. Each screenshot renders; the pulsing ring sits over the correct button (the DEBUG red rectangle shows the live hotspot).
2. Tapping the ring advances; the printed `CoachMark tap — normalized x=…, y=…` in the Xcode console gives exact coordinates. If a ring is off, copy the printed `x`/`y` of the real button center into the matching `TutorialStep.hotspot` in `TutorialFlowModel.defaultSteps` (`hotspot` is a centered rect: set `x = centerX - width/2`, `y = centerY - height/2`), rebuild, and re-check.
3. Tapping elsewhere nudges the ring without advancing.
4. Leaving a frame untouched ~4s auto-advances.
5. After frame 3: importing spinner → saved card → "Import my first recipe" / "I'll explore on my own". Both buttons fire their handlers. "Skip" exits during the walkthrough.

Iterate Step 4 until all three rings land on their buttons, then update `defaultSteps` with the tuned coordinates.

- [ ] **Step 5: Commit**

```bash
git add Glutt/Features/Onboarding/Screens/ImportTutorialScreen.swift \
        Glutt/Features/Onboarding/Support/TutorialFlowModel.swift \
        Glutt.xcodeproj/project.pbxproj
git add -u Glutt/Features/Onboarding/Support/ShareSheetMock.swift
git commit -m "feat: interactive ReciMe-style import tutorial with tap-to-advance"
```

---

## Notes for the implementer

- **Do not** alter `OnboardingFlow.swift` — it already calls `ImportTutorialScreen(onImportNow:onFinish:)` and treats the tutorial as the final, full-bleed step.
- The `#if DEBUG` red rectangle and tap-coordinate print exist purely for hotspot tuning. They compile out of Release; leave them in for future re-tuning.
- If frame 1's third-party content becomes an App Store concern (see spec "Open items"), only `tutorialPost.imageset` + its `TutorialStep` hotspot need to change; Tasks 1–3 are unaffected.
