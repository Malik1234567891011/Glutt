# Onboarding Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Glutt's single-file onboarding with a decomposed, RIZZ-structured / ReciMe-tutorial flow rendered in Glutt's existing cream/green brand.

**Architecture:** A coordinator (`OnboardingFlow`) drives a step machine and shared chrome; each screen is its own focused SwiftUI view; selection logic lives in a plain `@Observable` `OnboardingState` so it is unit-testable without the UI. The import tutorial is a deterministic, scripted animation (no real network import) that can hand off to the real importer at the end. Onboarding finishes through a single `OnboardingPaywallHook` call site reserved for a later Superwall placement.

**Tech Stack:** Swift 5.10, SwiftUI, SwiftData, XCTest, XcodeGen (`project.yml`), `xcodebuild`.

## Global Constraints

- Deployment target **iOS 17.0**; **Swift 5.10**. (`project.yml`)
- **Light mode only** — app is `UIUserInterfaceStyle: Light` by design. No dark-mode code, no `.preferredColorScheme`.
- **No hardcoded colors/fonts** — use `Theme.Colors.*`, `Theme.Spacing.*`, `Theme.Radius.*`, the `.glutt*` fonts, and the `.glutt*` button styles. The only place raw colors are derived is inside `GlowBackground`, and they must be derived from `Theme.Colors`.
- **No new third-party dependencies.** The Superwall SDK is NOT added in this plan — the paywall is a stub call site only.
- **Original copy only.** Do not copy any text, asset, logo, or layout chrome from the RIZZ or ReciMe apps. Borrow patterns, write Glutt's own words.
- **Every step is skippable** — the top chrome always exposes "Skip", which finishes onboarding (matches current behavior).
- XcodeGen globs the `Glutt/` and `GluttTests/` folders, so new files are picked up by re-running `xcodegen generate`. Commit the regenerated `Glutt.xcodeproj/project.pbxproj` alongside new files.

**Canonical commands** (copy-paste; verified against this machine):

```bash
# BUILD — regenerate project + compile. Uses the GENERIC simulator destination,
# which is unambiguous and doesn't boot a sim (plain `name=iPhone 16` is ambiguous
# here — the same name exists across OS 18.6/26.x). Run after adding/removing files:
xcodegen generate && xcodebuild build -scheme Glutt -destination 'generic/platform=iOS Simulator' -quiet

# TEST a suite — targets the one installed plain "iPhone 16" sim by UDID (unique).
# Refresh the id with: xcrun simctl list devices available | grep 'iPhone 16 ('
TEST_DEST='id=1EEC6A07-E689-4149-ABC7-FF36F702BBF6'
xcodebuild test -scheme Glutt -destination "$TEST_DEST" -only-testing:GluttTests/OnboardingStateTests -quiet
```

> **Verification honesty:** Pure-visual views (backgrounds, screens, mocks) are not meaningfully unit-tested. Their verification step is a successful **BUILD** plus the SwiftUI `#Preview` and the manual checklist in Task 13 — not a fabricated `XCTest`. Real `XCTest`s exist only where there is real logic: `OnboardingState` (Task 3) and `TutorialPhase` (Task 11).

---

## File Structure

**Create:**
- `Glutt/DesignSystem/Components/OptionRow.swift` — full-width selectable row (emoji/icon + title + check).
- `Glutt/DesignSystem/Components/GlowBackground.swift` — ambient animated background in Glutt palette.
- `Glutt/Features/Onboarding/OnboardingState.swift` — `@Observable` selection model + `apply(to:)`.
- `Glutt/Features/Onboarding/Support/OnboardingScaffold.swift` — shared title/subtitle/scroll layout.
- `Glutt/Features/Onboarding/Support/OnboardingPaywallHook.swift` — post-onboarding paywall stub.
- `Glutt/Features/Onboarding/Support/ShareSheetMock.swift` — simulated share sheet for the tutorial.
- `Glutt/Features/Onboarding/Screens/WelcomeScreen.swift`
- `Glutt/Features/Onboarding/Screens/GoalsScreen.swift`
- `Glutt/Features/Onboarding/Screens/RulesScreen.swift`
- `Glutt/Features/Onboarding/Screens/NutritionScreen.swift`
- `Glutt/Features/Onboarding/Screens/NotificationPrimerScreen.swift`
- `Glutt/Features/Onboarding/Screens/ImportTutorialScreen.swift` — `TutorialPhase` + scripted view.
- `Glutt/Features/Onboarding/OnboardingFlow.swift` — coordinator (replaces `OnboardingView`).
- `GluttTests/OnboardingStateTests.swift`
- `GluttTests/TutorialPhaseTests.swift`

**Modify:**
- `Glutt/App/RootView.swift:53` — swap `OnboardingView { … }` → `OnboardingFlow { … }`.

**Delete:**
- `Glutt/Features/Onboarding/OnboardingView.swift` (in Task 13, after the new flow is wired). Its private `FlowLayout`/`SelectableChips` are not used elsewhere and retire with it.

---

### Task 1: `OptionRow` design-system component

**Files:**
- Create: `Glutt/DesignSystem/Components/OptionRow.swift`

**Interfaces:**
- Produces: `OptionRow(emoji: String?, systemImage: String?, title: String, subtitle: String?, isSelected: Bool, action: () -> Void)` — a `View`.

- [ ] **Step 1: Create the component**

```swift
import SwiftUI

/// Full-width selectable row used by onboarding goal/nutrition pickers:
/// leading emoji or SF Symbol, a title (+ optional subtitle), trailing check.
struct OptionRow: View {
    var emoji: String? = nil
    var systemImage: String? = nil
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                leading
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.border)
                    .font(.title3)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.border.opacity(0.55),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var leading: some View {
        if let emoji {
            Text(emoji).font(.title2)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.Colors.accent)
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        OptionRow(emoji: "🥗", title: "Eat healthier", isSelected: true) {}
        OptionRow(systemImage: "dumbbell", title: "Gym mode", subtitle: "Calories & protein", isSelected: false) {}
    }
    .padding()
    .background(Theme.Colors.background)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the **BUILD** command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Glutt/DesignSystem/Components/OptionRow.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add OptionRow selectable row component\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 2: `GlowBackground` design-system component

**Files:**
- Create: `Glutt/DesignSystem/Components/GlowBackground.swift`

**Interfaces:**
- Produces: `GlowBackground()` — a `View` meant to sit at the back of a `ZStack`; ignores safe area.

- [ ] **Step 1: Create the component**

```swift
import SwiftUI

/// Ambient, slowly drifting glow behind hero/celebration onboarding screens.
/// Built from Theme colors so it stays on-brand (cream base, warm green/tomato bloom).
struct GlowBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.Colors.background

            Circle()
                .fill(Theme.Colors.accent.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: drift ? -90 : -60, y: drift ? -160 : -120)

            Circle()
                .fill(Theme.Colors.tomato.opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: drift ? 110 : 80, y: drift ? 200 : 240)

            Circle()
                .fill(Theme.Colors.warning.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 90)
                .offset(x: drift ? 90 : 120, y: drift ? -180 : -140)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

#Preview {
    GlowBackground()
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the **BUILD** command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Glutt/DesignSystem/Components/GlowBackground.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add GlowBackground ambient hero background\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 3: `OnboardingState` model + tests

**Files:**
- Create: `Glutt/Features/Onboarding/OnboardingState.swift`
- Test: `GluttTests/OnboardingStateTests.swift`

**Interfaces:**
- Produces:
  - `OnboardingState` (`@Observable final class`) with mutable `selectedGoals: Set<String>`, `selectedRules: Set<DietaryRule>`, `allergyText: String`, `dislikeText: String`, `nutritionMode: NutritionMode`.
  - `struct GoalOption: Identifiable { var id: String { label }; let emoji: String; let label: String }`
  - `static let goalOptions: [GoalOption]`
  - `func toggleGoal(_ goal: String)`, `func toggleRule(_ rule: DietaryRule)`
  - `func apply(to context: ModelContext)` — writes the singleton `UserPrefs` and sets `hasCompletedOnboarding = true`.
  - `static func splitList(_ text: String) -> [String]`

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftData
import XCTest
@testable import Glutt

final class OnboardingStateTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserPrefs.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testToggleGoalInsertsThenRemoves() {
        let state = OnboardingState()
        state.toggleGoal("Plan my week")
        XCTAssertTrue(state.selectedGoals.contains("Plan my week"))
        state.toggleGoal("Plan my week")
        XCTAssertFalse(state.selectedGoals.contains("Plan my week"))
    }

    func testSplitListTrimsAndDropsEmpties() {
        XCTAssertEqual(OnboardingState.splitList(" peanuts ,  shellfish ,,"),
                       ["peanuts", "shellfish"])
        XCTAssertEqual(OnboardingState.splitList(""), [])
    }

    @MainActor
    func testApplyWritesPrefsAndCompletesOnboarding() throws {
        let context = try makeContext()
        let state = OnboardingState()
        state.toggleGoal("Cook what I already have")
        state.allergyText = "peanuts, shellfish"
        state.dislikeText = "cilantro"
        state.nutritionMode = .gymMode

        state.apply(to: context)

        let prefs = UserPrefs.current(in: context)
        XCTAssertEqual(prefs.goals, ["Cook what I already have"])
        XCTAssertEqual(prefs.allergies, ["peanuts", "shellfish"])
        XCTAssertEqual(prefs.dislikedIngredients, ["cilantro"])
        XCTAssertEqual(prefs.nutritionMode, .gymMode)
        XCTAssertTrue(prefs.hasCompletedOnboarding)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `TEST GluttTests/OnboardingStateTests` (see Global Constraints). Expected: FAIL — `cannot find 'OnboardingState' in scope`.

- [ ] **Step 3: Write the model**

```swift
import Foundation
import Observation
import SwiftData

/// Holds onboarding selections and maps them onto the singleton `UserPrefs`.
/// Pure of SwiftUI so the flow's logic is unit-testable.
@Observable
final class OnboardingState {

    struct GoalOption: Identifiable {
        var id: String { label }
        let emoji: String
        let label: String
    }

    /// Glutt's own goals (not ReciMe's) — these set up the home screen.
    static let goalOptions: [GoalOption] = [
        .init(emoji: "📲", label: "Save recipes from TikTok & friends"),
        .init(emoji: "🧊", label: "Cook what I already have"),
        .init(emoji: "🗓️", label: "Plan my week"),
        .init(emoji: "♻️", label: "Waste less food"),
        .init(emoji: "💪", label: "Hit my macros"),
        .init(emoji: "🏠", label: "Eat out less"),
    ]

    var selectedGoals: Set<String> = []
    var selectedRules: Set<DietaryRule> = []
    var allergyText: String = ""
    var dislikeText: String = ""
    var nutritionMode: NutritionMode = .cookingOnly

    func toggleGoal(_ goal: String) {
        if !selectedGoals.insert(goal).inserted {
            selectedGoals.remove(goal)
        }
    }

    func toggleRule(_ rule: DietaryRule) {
        if selectedRules.contains(rule) {
            selectedRules.remove(rule)
        } else {
            selectedRules.insert(rule)
        }
    }

    func apply(to context: ModelContext) {
        let prefs = UserPrefs.current(in: context)
        prefs.goals = Array(selectedGoals)
        prefs.dietaryRules = Array(selectedRules)
        prefs.allergies = Self.splitList(allergyText)
        prefs.dislikedIngredients = Self.splitList(dislikeText)
        prefs.nutritionMode = nutritionMode
        prefs.hasCompletedOnboarding = true
    }

    static func splitList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `TEST GluttTests/OnboardingStateTests`. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Glutt/Features/Onboarding/OnboardingState.swift GluttTests/OnboardingStateTests.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add OnboardingState model with tests\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 4: Shared support — `OnboardingScaffold` + `OnboardingPaywallHook`

**Files:**
- Create: `Glutt/Features/Onboarding/Support/OnboardingScaffold.swift`
- Create: `Glutt/Features/Onboarding/Support/OnboardingPaywallHook.swift`

**Interfaces:**
- Produces:
  - `OnboardingScaffold<Content: View>(title: String, subtitle: String?, content: () -> Content)` — a `View`.
  - `enum OnboardingPaywallHook { static func presentPostOnboarding(completion: @escaping () -> Void) }`

- [ ] **Step 1: Create `OnboardingScaffold`**

```swift
import SwiftUI

/// Shared title/subtitle + scrolling content layout for standard onboarding steps.
struct OnboardingScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(.gluttLargeTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.gluttBody)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content()
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
```

- [ ] **Step 2: Create `OnboardingPaywallHook`**

```swift
import Foundation

/// Single integration point for the post-onboarding paywall.
///
/// Today there is no paywall — this completes immediately. When Superwall is
/// added (separate task), register the placement here and call `completion`
/// when the paywall is dismissed, e.g.:
///
///     Superwall.shared.register(placement: "onboarding_complete") { completion() }
///
/// Keeping it isolated means onboarding code never changes when the paywall lands.
enum OnboardingPaywallHook {
    static func presentPostOnboarding(completion: @escaping () -> Void) {
        completion()
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run the **BUILD** command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Glutt/Features/Onboarding/Support/OnboardingScaffold.swift Glutt/Features/Onboarding/Support/OnboardingPaywallHook.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add onboarding scaffold and paywall hook\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 5: `WelcomeScreen`

**Files:**
- Create: `Glutt/Features/Onboarding/Screens/WelcomeScreen.swift`

**Interfaces:**
- Produces: `WelcomeScreen(onStart: () -> Void)` — a `View` (full-screen; draws its own CTA).

- [ ] **Step 1: Create the screen**

```swift
import SwiftUI

/// First onboarding screen: branded hero over the ambient glow + one CTA.
struct WelcomeScreen: View {
    let onStart: () -> Void

    @State private var float = false

    var body: some View {
        ZStack {
            GlowBackground()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.card)
                        .frame(width: 200, height: 260)
                        .shadow(color: Theme.Colors.textPrimary.opacity(0.12), radius: 18, y: 8)
                        .overlay(
                            VStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 56))
                                    .foregroundStyle(Theme.Colors.accent)
                                Text("Glutt")
                                    .font(.gluttLargeTitle)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                        )
                        .rotationEffect(.degrees(float ? -3 : 3))
                        .offset(y: float ? -8 : 8)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Your kitchen, sorted.")
                        .font(.gluttLargeTitle)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Save recipes from anywhere, cook what you already have, and waste less — all in one place.")
                        .font(.gluttBody)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.md)
                }

                Spacer()

                Button("Get started", action: onStart)
                    .buttonStyle(.gluttPrimary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                float = true
            }
        }
    }
}

#Preview {
    WelcomeScreen(onStart: {})
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the **BUILD** command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Onboarding/Screens/WelcomeScreen.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add onboarding WelcomeScreen\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 6: `GoalsScreen`

**Files:**
- Create: `Glutt/Features/Onboarding/Screens/GoalsScreen.swift`

**Interfaces:**
- Consumes: `OnboardingState` (Task 3), `OptionRow` (Task 1), `OnboardingScaffold` (Task 4).
- Produces: `GoalsScreen(state: OnboardingState)` — a `View`.

- [ ] **Step 1: Create the screen**

```swift
import SwiftUI

/// Multi-select goals as full-width emoji rows.
struct GoalsScreen: View {
    @Bindable var state: OnboardingState

    var body: some View {
        OnboardingScaffold(
            title: "What do you want Glutt for?",
            subtitle: "Pick anything that sounds like you. This just sets up your home screen."
        ) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(OnboardingState.goalOptions) { option in
                    OptionRow(
                        emoji: option.emoji,
                        title: option.label,
                        isSelected: state.selectedGoals.contains(option.label)
                    ) {
                        state.toggleGoal(option.label)
                    }
                }
            }
        }
    }
}

#Preview {
    GoalsScreen(state: OnboardingState())
        .background(Theme.Colors.background)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the **BUILD** command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Onboarding/Screens/GoalsScreen.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add onboarding GoalsScreen\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 7: `RulesScreen`

**Files:**
- Create: `Glutt/Features/Onboarding/Screens/RulesScreen.swift`

**Interfaces:**
- Consumes: `OnboardingState` (Task 3), `OptionRow` (Task 1), `OnboardingScaffold` (Task 4), `DietaryRule` (existing; `allCases`, `.label`).
- Produces: `RulesScreen(state: OnboardingState)` — a `View`.

- [ ] **Step 1: Create the screen**

```swift
import SwiftUI

/// Dietary rules (multi-select) + allergies + dislikes free text.
struct RulesScreen: View {
    @Bindable var state: OnboardingState

    var body: some View {
        OnboardingScaffold(
            title: "Any food rules?",
            subtitle: "Respected everywhere — suggestions, planning, and substitutions."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(DietaryRule.allCases, id: \.self) { rule in
                        OptionRow(
                            systemImage: "leaf",
                            title: rule.label,
                            isSelected: state.selectedRules.contains(rule)
                        ) {
                            state.toggleRule(rule)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Allergies")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    TextField("peanuts, shellfish…", text: $state.allergyText)
                        .textFieldStyle(.roundedBorder)
                    Text("Separate with commas. Anything here gets a hard warning, always.")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Things you just don't like")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    TextField("cilantro, olives…", text: $state.dislikeText)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}

#Preview {
    RulesScreen(state: OnboardingState())
        .background(Theme.Colors.background)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the **BUILD** command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Onboarding/Screens/RulesScreen.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add onboarding RulesScreen\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 8: `NutritionScreen`

**Files:**
- Create: `Glutt/Features/Onboarding/Screens/NutritionScreen.swift`

**Interfaces:**
- Consumes: `OnboardingState` (Task 3), `OptionRow` (Task 1), `OnboardingScaffold` (Task 4), `NutritionMode` (existing; `.cookingOnly/.lightTracking/.gymMode`, `.label`).
- Produces: `NutritionScreen(state: OnboardingState)` — a `View`.

- [ ] **Step 1: Create the screen**

```swift
import SwiftUI

/// Single-select nutrition mode.
struct NutritionScreen: View {
    @Bindable var state: OnboardingState

    private struct ModeRow {
        let mode: NutritionMode
        let icon: String
        let detail: String
    }

    private let rows: [ModeRow] = [
        .init(mode: .cookingOnly, icon: "frying.pan", detail: "No calories, no macros, anywhere. Just good food."),
        .init(mode: .lightTracking, icon: "chart.bar", detail: "Gentle estimates on recipes and a daily summary."),
        .init(mode: .gymMode, icon: "dumbbell", detail: "Calorie & protein goals, charts, and per-serving macros."),
    ]

    var body: some View {
        OnboardingScaffold(
            title: "Want to track nutrition?",
            subtitle: "Totally optional. You can change this anytime in Settings."
        ) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(rows, id: \.mode) { row in
                    OptionRow(
                        systemImage: row.icon,
                        title: row.mode.label,
                        subtitle: row.detail,
                        isSelected: state.nutritionMode == row.mode
                    ) {
                        state.nutritionMode = row.mode
                    }
                }
            }
        }
    }
}

#Preview {
    NutritionScreen(state: OnboardingState())
        .background(Theme.Colors.background)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the **BUILD** command. Expected: `BUILD SUCCEEDED`.
> If the build errors with `NutritionMode` not conforming to `Hashable` for `ForEach(id: \.mode)`, the existing enum already is (it's used in `Set`-free contexts); if not, switch the `ForEach` to `id: \.mode.label`.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Onboarding/Screens/NutritionScreen.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add onboarding NutritionScreen\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 9: `NotificationPrimerScreen`

**Files:**
- Create: `Glutt/Features/Onboarding/Screens/NotificationPrimerScreen.swift`

**Interfaces:**
- Consumes: `GlowBackground` (Task 2).
- Produces: `NotificationPrimerScreen(onDone: () -> Void)` — a `View`; draws its own two buttons. `onDone` is called after either the OS prompt resolves ("Enable") or the user taps "Not now".

- [ ] **Step 1: Create the screen**

```swift
import SwiftUI
import UserNotifications

/// Soft pre-prompt before the iOS notification permission dialog.
struct NotificationPrimerScreen: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            GlowBackground()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()
                Image(systemName: "bell.badge")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.Colors.accent)
                VStack(spacing: Theme.Spacing.sm) {
                    Text("Want a nudge at dinnertime?")
                        .font(.gluttLargeTitle)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("We'll remind you what you planned to cook — and when something's about to go off. Off by default; change it anytime.")
                        .font(.gluttBody)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                Spacer()
                VStack(spacing: Theme.Spacing.sm) {
                    Button("Enable nudges", action: requestThenDone)
                        .buttonStyle(.gluttPrimary)
                    Button("Not now", action: onDone)
                        .buttonStyle(.gluttSecondary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
    }

    private func requestThenDone() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run { onDone() }
        }
    }
}

#Preview {
    NotificationPrimerScreen(onDone: {})
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the **BUILD** command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Onboarding/Screens/NotificationPrimerScreen.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add onboarding NotificationPrimerScreen\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 10: `ShareSheetMock`

**Files:**
- Create: `Glutt/Features/Onboarding/Support/ShareSheetMock.swift`

**Interfaces:**
- Produces: `ShareSheetMock(highlightGlutt: Bool)` — a presentational `View` mimicking an iOS share sheet with a highlighted Glutt row.

- [ ] **Step 1: Create the mock**

```swift
import SwiftUI

/// Purely decorative stand-in for the iOS share sheet, used by the import
/// tutorial. Not a real share sheet — original styling, no system chrome.
struct ShareSheetMock: View {
    var highlightGlutt: Bool

    private struct App: Identifiable {
        var id: String { name }
        let name: String
        let symbol: String
        let tint: Color
    }

    private let apps: [App] = [
        .init(name: "Messages", symbol: "message.fill", tint: .green),
        .init(name: "Notes", symbol: "note.text", tint: .yellow),
        .init(name: "Glutt", symbol: "fork.knife", tint: Theme.Colors.accent),
        .init(name: "Mail", symbol: "envelope.fill", tint: .blue),
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Capsule()
                .fill(Theme.Colors.border)
                .frame(width: 36, height: 5)
                .padding(.top, Theme.Spacing.sm)

            HStack(spacing: Theme.Spacing.lg) {
                ForEach(apps) { app in
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(app.tint.opacity(0.18))
                                .frame(width: 56, height: 56)
                            Image(systemName: app.symbol)
                                .font(.title2)
                                .foregroundStyle(app.tint)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.Colors.accent,
                                              lineWidth: highlightGlutt && app.name == "Glutt" ? 3 : 0)
                        )
                        .scaleEffect(highlightGlutt && app.name == "Glutt" ? 1.08 : 1)
                        Text(app.name)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
        .shadow(color: Theme.Colors.textPrimary.opacity(0.15), radius: 16, y: -4)
    }
}

#Preview {
    ShareSheetMock(highlightGlutt: true)
        .padding()
        .background(Theme.Colors.background)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the **BUILD** command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Onboarding/Support/ShareSheetMock.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add ShareSheetMock for import tutorial\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 11: `ImportTutorialScreen` + `TutorialPhase` (+ phase tests)

**Files:**
- Create: `Glutt/Features/Onboarding/Screens/ImportTutorialScreen.swift`
- Test: `GluttTests/TutorialPhaseTests.swift`

**Interfaces:**
- Consumes: `ShareSheetMock` (Task 10), `GlowBackground` (Task 2).
- Produces:
  - `enum TutorialPhase: Int, CaseIterable { case intro, showPost, coachTapShare, shareSheet, importing, success, cta; var next: TutorialPhase?; var isTerminal: Bool }`
  - `ImportTutorialScreen(onImportNow: () -> Void, onFinish: () -> Void)` — a `View`. `onImportNow` = finish + route to real importer; `onFinish` = finish only.

- [ ] **Step 1: Write the failing phase tests**

```swift
import XCTest
@testable import Glutt

final class TutorialPhaseTests: XCTestCase {

    func testPhaseOrder() {
        XCTAssertEqual(TutorialPhase.allCases,
                       [.intro, .showPost, .coachTapShare, .shareSheet, .importing, .success, .cta])
    }

    func testNextAdvancesUntilTerminal() {
        XCTAssertEqual(TutorialPhase.intro.next, .showPost)
        XCTAssertEqual(TutorialPhase.success.next, .cta)
        XCTAssertNil(TutorialPhase.cta.next)
    }

    func testOnlyCtaIsTerminal() {
        for phase in TutorialPhase.allCases where phase != .cta {
            XCTAssertFalse(phase.isTerminal, "\(phase) should not be terminal")
        }
        XCTAssertTrue(TutorialPhase.cta.isTerminal)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `TEST GluttTests/TutorialPhaseTests`. Expected: FAIL — `cannot find 'TutorialPhase' in scope`.

- [ ] **Step 3: Write `TutorialPhase` + the screen**

```swift
import SwiftUI

enum TutorialPhase: Int, CaseIterable {
    case intro, showPost, coachTapShare, shareSheet, importing, success, cta

    var next: TutorialPhase? { TutorialPhase(rawValue: rawValue + 1) }
    var isTerminal: Bool { self == .cta }
}

/// Scripted, deterministic walkthrough of "save from anywhere → it's in Glutt".
/// Performs NO real import; the optional end CTA hands off to the real importer.
struct ImportTutorialScreen: View {
    let onImportNow: () -> Void
    let onFinish: () -> Void

    @State private var phase: TutorialPhase = .intro

    var body: some View {
        ZStack {
            GlowBackground()

            VStack(spacing: Theme.Spacing.lg) {
                Text(headline)
                    .font(.gluttLargeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xl)
                    .id(headline) // re-triggers transition on change
                    .transition(.opacity)

                Spacer()
                stage
                Spacer()

                if phase == .cta {
                    VStack(spacing: Theme.Spacing.sm) {
                        Button("Import my first recipe", action: onImportNow)
                            .buttonStyle(.gluttPrimary)
                        Button("I'll explore on my own", action: onFinish)
                            .buttonStyle(.gluttSecondary)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .task { await runScript() }
    }

    private var headline: String {
        switch phase {
        case .intro, .showPost: "Found a recipe you love?"
        case .coachTapShare, .shareSheet: "Just tap Share → Glutt"
        case .importing: "Pulling out the recipe…"
        case .success, .cta: "That's it — it's saved. ✨"
        }
    }

    @ViewBuilder private var stage: some View {
        switch phase {
        case .intro, .showPost, .coachTapShare:
            postCard
        case .shareSheet:
            ShareSheetMock(highlightGlutt: true)
                .padding(.horizontal, Theme.Spacing.md)
        case .importing:
            VStack(spacing: Theme.Spacing.md) {
                ProgressView().controlSize(.large)
                Image(systemName: "fork.knife")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Colors.accent)
            }
        case .success, .cta:
            savedCard
        }
    }

    /// Generic social-post stand-in (original art, not a real platform's chrome).
    private var postCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.accent.opacity(0.15))
                .frame(height: 180)
                .overlay(Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Colors.accent))
            HStack {
                Text("15-min garlic butter noodles")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                ZStack {
                    Circle().fill(Theme.Colors.accent.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Theme.Colors.accent)
                }
                .scaleEffect(phase == .coachTapShare ? 1.18 : 1)
                .overlay(alignment: .bottom) {
                    if phase == .coachTapShare {
                        Text("Tap here")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.Colors.accent, in: Capsule())
                            .offset(y: 26)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: Theme.Colors.textPrimary.opacity(0.1), radius: 12, y: 4)
        .padding(.horizontal, Theme.Spacing.md)
    }

    /// Pre-baked "imported" result — presentational only, no Recipe model / network.
    private var savedCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Theme.Colors.successTint)
                .frame(width: 64, height: 64)
                .overlay(Text("🍝").font(.title))
            VStack(alignment: .leading, spacing: 4) {
                Text("Garlic butter noodles")
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

    private func runScript() async {
        let timings: [(TutorialPhase, Double)] = [
            (.showPost, 1.4), (.coachTapShare, 1.6), (.shareSheet, 1.8),
            (.importing, 1.4), (.success, 1.4), (.cta, 0.6),
        ]
        for (next, delay) in timings {
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            withAnimation(.spring(duration: 0.5)) { phase = next }
        }
    }
}

#Preview {
    ImportTutorialScreen(onImportNow: {}, onFinish: {})
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `TEST GluttTests/TutorialPhaseTests`. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Glutt/Features/Onboarding/Screens/ImportTutorialScreen.swift GluttTests/TutorialPhaseTests.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add scripted import tutorial screen with phase tests\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 12: `OnboardingFlow` coordinator

**Files:**
- Create: `Glutt/Features/Onboarding/OnboardingFlow.swift`

**Interfaces:**
- Consumes: every screen (Tasks 5–9, 11), `OnboardingState` (Task 3), `OnboardingPaywallHook` (Task 4), `Router` (existing; `perform(.importRecipe)`), `UserPrefs` via `state.apply(to:)`.
- Produces: `OnboardingFlow(onFinish: () -> Void)` — a `View`. Drop-in replacement for `OnboardingView(onFinish:)`.

- [ ] **Step 1: Create the coordinator**

```swift
import SwiftData
import SwiftUI

/// First-run flow coordinator: branded welcome → goals → rules → nutrition →
/// notification primer → scripted import tutorial → finish (paywall hook).
/// Every step is skippable; the app learns from usage either way.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router

    let onFinish: () -> Void

    @State private var state = OnboardingState()
    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, goals, rules, nutrition, notifications, tutorial

        var next: Step? { Step(rawValue: rawValue + 1) }
        /// Welcome and tutorial are full-bleed and own their own buttons.
        var usesChrome: Bool { self != .welcome && self != .tutorial }
        var usesStandardFooter: Bool {
            self == .goals || self == .rules || self == .nutrition
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if step.usesChrome { topBar }

            Group {
                switch step {
                case .welcome:
                    WelcomeScreen { advance() }
                case .goals:
                    GoalsScreen(state: state)
                case .rules:
                    RulesScreen(state: state)
                case .nutrition:
                    NutritionScreen(state: state)
                case .notifications:
                    NotificationPrimerScreen { advance() }
                case .tutorial:
                    ImportTutorialScreen(
                        onImportNow: { finish(thenImport: true) },
                        onFinish: { finish(thenImport: false) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if step.usesStandardFooter { standardFooter }
        }
        .background(Theme.Colors.background)
        .animation(.easeInOut, value: step)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let _ = backTarget {
                Button { goBack() } label: {
                    Image(systemName: "chevron.left").font(.headline)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            progressBar
            Button("Skip") { finish(thenImport: false) }
                .font(.gluttCaption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.border)
                Capsule().fill(Theme.Colors.accent)
                    .frame(width: geo.size.width * progressFraction)
            }
        }
        .frame(height: 6)
    }

    /// Progress across the chrome'd steps (goals…tutorial); welcome is pre-progress.
    private var progressFraction: CGFloat {
        let total = CGFloat(Step.allCases.count - 1) // exclude welcome
        let done = CGFloat(max(0, step.rawValue))    // goals == 1
        return min(1, done / total)
    }

    private var standardFooter: some View {
        Button("Continue") { advance() }
            .buttonStyle(.gluttPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Navigation

    private var backTarget: Step? {
        // No back from the first chrome'd step (goals) into welcome.
        step == .goals ? nil : Step(rawValue: step.rawValue - 1)
    }

    private func goBack() {
        if let target = backTarget { step = target }
    }

    private func advance() {
        if let next = step.next {
            step = next
        } else {
            finish(thenImport: false)
        }
    }

    private func finish(thenImport: Bool) {
        state.apply(to: context)
        OnboardingPaywallHook.presentPostOnboarding {
            onFinish()
            if thenImport {
                router.perform(.importRecipe)
            }
        }
    }
}

#Preview {
    OnboardingFlow(onFinish: {})
        .environment(Router())
        .modelContainer(for: UserPrefs.self, inMemory: true)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the **BUILD** command. Expected: `BUILD SUCCEEDED`. (`OnboardingView` still exists and is still wired in `RootView` — the app builds and runs unchanged.)

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Onboarding/OnboardingFlow.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: add OnboardingFlow coordinator\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 13: Wire `OnboardingFlow` into `RootView`, delete old `OnboardingView`, full verify

**Files:**
- Modify: `Glutt/App/RootView.swift:53`
- Delete: `Glutt/Features/Onboarding/OnboardingView.swift`

**Interfaces:**
- Consumes: `OnboardingFlow(onFinish:)` (Task 12).

- [ ] **Step 1: Swap the entry point**

In `Glutt/App/RootView.swift`, inside the `fullScreenCover` (around line 53), replace:

```swift
            OnboardingView {
                router.forceOnboarding = false
            }
            .interactiveDismissDisabled()
```

with:

```swift
            OnboardingFlow {
                router.forceOnboarding = false
            }
            .interactiveDismissDisabled()
```

- [ ] **Step 2: Delete the old onboarding file**

```bash
git rm Glutt/Features/Onboarding/OnboardingView.swift
```

- [ ] **Step 3: Build + run the full test suite**

Run the **BUILD** command, then:

```bash
xcodebuild test -scheme Glutt -destination "$SIM" -quiet
```

Expected: `BUILD SUCCEEDED` and `TEST SUCCEEDED` (OnboardingStateTests + TutorialPhaseTests pass; no references to the deleted `OnboardingView` remain).

- [ ] **Step 4: Manual device/simulator walkthrough**

Run the **Glutt Beta** scheme (or pass `-onboarding` to force first-run), then confirm:
- Welcome hero animates over the glow; "Get started" advances.
- Progress bar + back chevron appear from Goals onward; Skip finishes at any step.
- Goals multi-select toggles; Rules dietary rows + allergy/dislike fields work; Nutrition single-select.
- Notification primer: "Enable nudges" shows the iOS prompt then advances; "Not now" advances.
- Tutorial auto-plays intro → post → coach → share sheet → importing → saved → CTAs. "Import my first recipe" lands on the real import screen (Recipes tab); "I'll explore on my own" drops into the app.
- Relaunch does NOT show onboarding again (`hasCompletedOnboarding` persisted).

- [ ] **Step 5: Commit**

```bash
git add Glutt/App/RootView.swift Glutt.xcodeproj/project.pbxproj
git commit -m "$(printf 'feat: replace OnboardingView with new OnboardingFlow\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Self-Review

**Spec coverage:**
- Welcome hero → Task 5. Goals → Task 6. Rules+allergies → Task 7. Nutrition → Task 8. Notification primer → Task 9. Import tutorial (scripted, with real-import hand-off) → Tasks 10–11. Superwall hook → Task 4 + wired in Task 12. Finish/gating → Task 12 (`state.apply`) + Task 13 (RootView). Decompose into coordinator + per-screen files → Tasks 3–13. Design-system additions (`OptionRow`, `GlowBackground`) → Tasks 1–2. Dropped social-proof/attribution → not built (correct). All spec sections covered.

**Placeholder scan:** No "TBD/TODO/implement later" in steps. The `OnboardingPaywallHook` comment documents a real, complete (pass-through) implementation and a future integration example — not a missing step.

**Type consistency:** `OnboardingState` API (`selectedGoals`, `selectedRules`, `allergyText`, `dislikeText`, `nutritionMode`, `toggleGoal`, `toggleRule`, `apply(to:)`, `goalOptions`, `GoalOption`) is defined in Task 3 and consumed identically in Tasks 6–8 and 12. `TutorialPhase` (Task 11) `next`/`isTerminal`/`allCases` match its tests. `OnboardingFlow(onFinish:)` (Task 12) matches the `RootView` swap (Task 13) and mirrors the old `OnboardingView(onFinish:)` signature. `OptionRow` params match all call sites. `OnboardingPaywallHook.presentPostOnboarding(completion:)` matches its single caller.
