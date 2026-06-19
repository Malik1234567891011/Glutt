# Glutt Redesign — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the new design-language foundation — extended `Theme`/`Typography` tokens, the PhosphorSwift icon dependency, and six reusable SwiftUI primitives — so the later redesign plans (Tab bar, Browse, Recipe Detail, Onboarding) are cheap restyles that consume finished components.

**Architecture:** Pure additive work in `Glutt/DesignSystem/`. No existing screen is modified. Each primitive is a small, single-purpose `View` with a `#Preview`; the one piece of branching logic (headline word styling) gets an XCTest. Visual components are verified by compiling + their preview, since this repo has no snapshot-testing infra (only XCTest logic tests in `GluttTests/`).

**Tech Stack:** SwiftUI, SwiftData (iOS 17+), Xcode project `Glutt.xcodeproj`, scheme `Glutt`, PhosphorSwift (new SPM dependency), XCTest (`GluttTests`).

## Global Constraints

- **Platform:** iOS 17+ (SwiftData). The `Layout` protocol (used by `FlowLayout`) requires iOS 16+ — satisfied.
- **Tokens over raw hex:** Components must reference `Theme.Colors`/`Theme.Radius`/`Font.glutt*`. Every raw hex the mock uses is added as a `Theme` token in Task 2; components reference the token, never an inline hex.
- **Existing color constants are unchanged** — keep `accent`, `tomato`, `textPrimary`, `successTint`, `warningTint`, `warning`, `border`, etc. exactly as they are (README: match Glutt's tokens, not the brighter mock hexes).
- **Icons:** Use Phosphor via `Ph.<name>.<weight>` (e.g. `Ph.star.fill`), which returns a SwiftUI `Image`. Tint with `.foregroundColor(_:)` after `.resizable().scaledToFit()`.
- **Build command** (adjust simulator name to one from `xcrun simctl list devices available`):
  `xcodebuild build -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
- **Test command:**
  `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/<ClassName> -quiet`
- **Commits:** One per task, conventional-commit style, end the body with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## File Structure

- Modify: `Glutt/DesignSystem/Theme.swift` — add `Radius.cardLarge/.photo` and the new color tokens.
- Modify: `Glutt/DesignSystem/Typography.swift` — add `gluttSectionLabel` font + `SectionLabel` view.
- Create: `Glutt/DesignSystem/Components/StatPill.swift` — tinted icon+text stat capsule.
- Create: `Glutt/DesignSystem/Components/IconChip.swift` — 36pt tinted rounded-square glyph chip.
- Create: `Glutt/DesignSystem/Components/PageDots.swift` — onboarding page indicator.
- Create: `Glutt/DesignSystem/Components/SegmentedTabs.swift` — 2+ segment pill control.
- Create: `Glutt/DesignSystem/Components/FlowLayout.swift` — wrapping layout (used by headline + chip rows).
- Create: `Glutt/DesignSystem/Components/HighlightHeadline.swift` — per-word tinted-pill headline.
- Create: `Glutt/DesignSystem/Components/CategoryCircle.swift` — circular category thumbnail.
- Create: `GluttTests/HeadlineWordStyleTests.swift` — asserts headline word→color mapping.

New files must be added to the `Glutt` target (and the test file to `GluttTests`) in `Glutt.xcodeproj`. If you create files via Xcode's New File dialog this is automatic; if you create them on disk, add them to the target's `PBXBuildFile`/`PBXSourcesBuildPhase` (or open the project once in Xcode so it picks them up). Every task's build step will fail if the file isn't in the target — that's the check.

---

### Task 1: Add the PhosphorSwift SPM dependency

**Files:**
- Modify: `Glutt.xcodeproj/project.pbxproj` (package reference + product dependency)

**Interfaces:**
- Produces: `import PhosphorSwift` available to the `Glutt` target; `Ph.<name>.<weight> -> Image`.

- [ ] **Step 1: Add the package in Xcode**

Open `Glutt.xcodeproj` in Xcode → File ▸ Add Package Dependencies… → enter
`https://github.com/phosphor-icons/swift` → Dependency Rule: "Up to Next Major Version"
from `2.0.0` → Add Package → check the **PhosphorSwift** product against the **Glutt**
target → Add Package.

(Headless/scripted fallback if Xcode UI is unavailable: add an
`XCRemoteSwiftPackageReference` block for `https://github.com/phosphor-icons/swift`,
a matching `XCSwiftPackageProductDependency` with `productName = PhosphorSwift`, list
the package in the `PBXProject` `packageReferences`, and add a `PBXBuildFile` for the
product in the Glutt target's Frameworks build phase — mirror the existing
`Superwall-iOS` / `SuperwallKit` blocks in `project.pbxproj`. Then run
`xcodebuild -resolvePackageDependencies -scheme Glutt`.)

- [ ] **Step 2: Smoke-verify the import compiles**

Temporarily add this to the bottom of `Glutt/DesignSystem/Theme.swift`:

```swift
import PhosphorSwift
private func _phosphorSmoke() -> some View { Ph.heart.fill.resizable().frame(width: 1, height: 1) }
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: **BUILD SUCCEEDED**. If `Ph.heart.fill` does not resolve to an `Image`,
stop and confirm the installed PhosphorSwift major version's API before proceeding —
every later component depends on `Ph.<name>.<weight> -> Image`.

- [ ] **Step 4: Remove the smoke code**

Delete the `_phosphorSmoke()` function and the extra `import PhosphorSwift` from `Theme.swift`.

- [ ] **Step 5: Commit**

```bash
git add Glutt.xcodeproj
git commit -m "build: add PhosphorSwift SPM dependency"
```

---

### Task 2: Extend Theme tokens

**Files:**
- Modify: `Glutt/DesignSystem/Theme.swift`

**Interfaces:**
- Produces: `Theme.Radius.cardLarge: CGFloat (26)`, `Theme.Radius.photo: CGFloat (18)`,
  `Theme.Colors.tomatoTint`, `.peachPanel`, `.sagePanel`, `.creamText`,
  `.segmentTrack`, `.dotInactive`, `.mutedLabel`.

- [ ] **Step 1: Add the new color tokens**

In `Theme.Colors`, after the existing `warning` line, add:

```swift
        /// Soft tomato tint — difficulty pills, protein icon chips. (#F7DDD2)
        static let tomatoTint = Color(red: 0.969, green: 0.867, blue: 0.824)
        /// Decorative peach panel tint behind food photos. (#F7E2D4)
        static let peachPanel = Color(red: 0.969, green: 0.886, blue: 0.831)
        /// Decorative sage panel tint — semantic alias of successTint.
        static let sagePanel = successTint
        /// Cream text/glyph on dark or green fills (tab labels, CTA text, active segment). (#F4ECDF)
        static let creamText = Color(red: 0.957, green: 0.925, blue: 0.875)
        /// Segmented-control track. (#EBE2D4)
        static let segmentTrack = Color(red: 0.922, green: 0.886, blue: 0.831)
        /// Inactive page-dot fill. (#D8CDBE)
        static let dotInactive = Color(red: 0.847, green: 0.804, blue: 0.745)
        /// Muted label for inactive category names. (#9A8A7C)
        static let mutedLabel = Color(red: 0.604, green: 0.541, blue: 0.486)
```

- [ ] **Step 2: Add the new radius tokens**

In `Theme.Radius`, after the existing `card` line, add:

```swift
        /// Redesigned recipe/detail/section cards — softer than `card`.
        static let cardLarge: CGFloat = 26
        /// Photo tiles nested inside cards.
        static let photo: CGFloat = 18
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: **BUILD SUCCEEDED** (additive constants; nothing else references them yet).

- [ ] **Step 4: Commit**

```bash
git add Glutt/DesignSystem/Theme.swift
git commit -m "feat(design): add redesign color and radius tokens"
```

---

### Task 3: Add section-label typography

**Files:**
- Modify: `Glutt/DesignSystem/Typography.swift`

**Interfaces:**
- Produces: `Font.gluttSectionLabel`; `SectionLabel(_ text: String, color: Color = Theme.Colors.accent)` view rendering uppercased, tracked, colored text.

- [ ] **Step 1: Add the font token**

In `Typography.swift`, inside the `extension Font`, after `gluttCookStep`, add:

```swift
    /// Small uppercase section labels ("FRESH", "PANTRY", category headers).
    static let gluttSectionLabel = Font.system(size: 12, weight: .heavy, design: .rounded)
```

- [ ] **Step 2: Add the `SectionLabel` view**

At the end of `Typography.swift`, add:

```swift
/// Uppercase, letter-spaced, herb-green section label (FRESH / PANTRY / category headers).
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.Colors.accent

    var body: some View {
        Text(text.uppercased())
            .font(.gluttSectionLabel)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

#Preview("SectionLabel") {
    VStack(alignment: .leading, spacing: 12) {
        SectionLabel(text: "Fresh")
        SectionLabel(text: "Pantry")
    }
    .padding()
    .background(Theme.Colors.background)
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 4: Verify the preview**

Open `Typography.swift` in Xcode, resume the "SectionLabel" canvas preview. Confirm two
uppercase, spaced, green labels on cream. (Visual check — no snapshot infra in repo.)

- [ ] **Step 5: Commit**

```bash
git add Glutt/DesignSystem/Typography.swift
git commit -m "feat(design): add gluttSectionLabel + SectionLabel view"
```

---

### Task 4: StatPill component

**Files:**
- Create: `Glutt/DesignSystem/Components/StatPill.swift`

**Interfaces:**
- Produces:
  - `StatPill(icon: Image, text: String, foreground: Color, background: Color)`
  - `StatPill.rating(_ value: String) -> StatPill` (star, accent on successTint)
  - `StatPill.time(_ text: String) -> StatPill` (clock, warning on warningTint)
  - `StatPill.difficulty(_ text: String) -> StatPill` (cell-signal, tomato on tomatoTint)

- [ ] **Step 1: Create the component**

```swift
import SwiftUI
import PhosphorSwift

/// A small tinted stat capsule (icon + text). Powers the recipe-card stat row:
/// rating · time · difficulty. Radius 11, padding 7×12, 13pt heavy text.
struct StatPill: View {
    let icon: Image
    let text: String
    var foreground: Color = Theme.Colors.accent
    var background: Color = Theme.Colors.successTint

    var body: some View {
        HStack(spacing: 4) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundColor(foreground)
            Text(text)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(foreground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    /// ★ rating — herb-green on sage.
    static func rating(_ value: String) -> StatPill {
        StatPill(icon: Ph.star.fill, text: value,
                 foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
    }

    /// Clock time — amber on warm.
    static func time(_ text: String) -> StatPill {
        StatPill(icon: Ph.clock.regular, text: text,
                 foreground: Theme.Colors.warning, background: Theme.Colors.warningTint)
    }

    /// signal difficulty — tomato on soft tomato.
    static func difficulty(_ text: String) -> StatPill {
        StatPill(icon: Ph.cellSignalMedium.fill, text: text,
                 foreground: Theme.Colors.tomato, background: Theme.Colors.tomatoTint)
    }
}

#Preview("StatPill row") {
    HStack(spacing: 8) {
        StatPill.rating("4.9")
        StatPill.time("30 min")
        StatPill.difficulty("Medium")
    }
    .padding()
    .background(Theme.Colors.card)
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: **BUILD SUCCEEDED**. If `Ph.cellSignalMedium` doesn't exist under that exact
camelCase name, check the PhosphorSwift case list and use the matching name
(README maps it to `cell-signal-medium`); update the `difficulty(_:)` factory.

- [ ] **Step 3: Verify the preview**

Resume the "StatPill row" canvas. Confirm three pills — green ★4.9, amber clock 30 min,
tomato signal Medium — each on its tint.

- [ ] **Step 4: Commit**

```bash
git add Glutt/DesignSystem/Components/StatPill.swift
git commit -m "feat(design): add StatPill component"
```

---

### Task 5: IconChip component

**Files:**
- Create: `Glutt/DesignSystem/Components/IconChip.swift`

**Interfaces:**
- Produces: `IconChip(icon: Image, foreground: Color, background: Color)` — a 36pt rounded-square (radius 11) tinted glyph chip.

- [ ] **Step 1: Create the component**

```swift
import SwiftUI
import PhosphorSwift

/// A 36pt section-tinted rounded-square holding a Phosphor food glyph.
/// Used in the ingredient checklist (protein/produce/pantry tints).
struct IconChip: View {
    let icon: Image
    var foreground: Color = Theme.Colors.accent
    var background: Color = Theme.Colors.successTint

    var body: some View {
        icon
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .foregroundColor(foreground)
            .frame(width: 36, height: 36)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

#Preview("IconChip tints") {
    HStack(spacing: 12) {
        IconChip(icon: Ph.hamburger.fill,
                 foreground: Theme.Colors.tomato, background: Theme.Colors.tomatoTint)
        IconChip(icon: Ph.plant.fill,
                 foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
        IconChip(icon: Ph.bowlFood.fill,
                 foreground: Theme.Colors.warning, background: Theme.Colors.warningTint)
    }
    .padding()
    .background(Theme.Colors.card)
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: **BUILD SUCCEEDED**. If any glyph name (`hamburger`, `plant`, `bowlFood`)
doesn't resolve, substitute the nearest existing PhosphorSwift case (these are only
used in the preview here).

- [ ] **Step 3: Verify the preview**

Resume "IconChip tints". Confirm three 36pt rounded squares: tomato, green, amber.

- [ ] **Step 4: Commit**

```bash
git add Glutt/DesignSystem/Components/IconChip.swift
git commit -m "feat(design): add IconChip component"
```

---

### Task 6: PageDots component

**Files:**
- Create: `Glutt/DesignSystem/Components/PageDots.swift`

**Interfaces:**
- Produces: `PageDots(count: Int, index: Int)` — active dot is a 24×8 accent bar, inactive are 8×8 `dotInactive`.

- [ ] **Step 1: Create the component**

```swift
import SwiftUI

/// Onboarding page indicator: the active page is a 24×8 herb-green bar,
/// inactive pages are 8×8 muted dots.
struct PageDots: View {
    let count: Int
    let index: Int
    var active: Color = Theme.Colors.accent
    var inactive: Color = Theme.Colors.dotInactive

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i == index ? active : inactive)
                    .frame(width: i == index ? 24 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: index)
    }
}

#Preview("PageDots") {
    VStack(spacing: 20) {
        PageDots(count: 3, index: 0)
        PageDots(count: 3, index: 1)
        PageDots(count: 6, index: 4)
    }
    .padding()
    .background(Theme.Colors.background)
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Verify the preview**

Resume "PageDots". Confirm the active index renders as a wide green bar, others as small dots.

- [ ] **Step 4: Commit**

```bash
git add Glutt/DesignSystem/Components/PageDots.swift
git commit -m "feat(design): add PageDots component"
```

---

### Task 7: SegmentedTabs component

**Files:**
- Create: `Glutt/DesignSystem/Components/SegmentedTabs.swift`

**Interfaces:**
- Produces: `SegmentedTabs(titles: [String], selection: Binding<Int>)` — track `segmentTrack`, radius 14, active segment = accent fill + `creamText`, inactive = textSecondary.

- [ ] **Step 1: Create the component**

```swift
import SwiftUI

/// A pill segmented control (e.g. Ingredients | Steps). Active segment fills herb-green
/// with cream text; the track is a warm rounded rectangle.
struct SegmentedTabs: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { i in
                let isActive = i == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = i
                    }
                } label: {
                    Text(titles[i])
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(isActive ? Theme.Colors.creamText : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(isActive ? Theme.Colors.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Colors.segmentTrack)
        )
    }
}

#Preview("SegmentedTabs") {
    struct Demo: View {
        @State private var sel = 1
        var body: some View {
            SegmentedTabs(titles: ["Ingredients", "Steps"], selection: $sel)
                .padding()
                .background(Theme.Colors.background)
        }
    }
    return Demo()
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Verify the preview**

Resume "SegmentedTabs". Confirm a two-segment pill with "Steps" filled green (cream text)
and "Ingredients" muted; tapping a segment animates the fill across.

- [ ] **Step 4: Commit**

```bash
git add Glutt/DesignSystem/Components/SegmentedTabs.swift
git commit -m "feat(design): add SegmentedTabs component"
```

---

### Task 8: FlowLayout helper

**Files:**
- Create: `Glutt/DesignSystem/Components/FlowLayout.swift`

**Interfaces:**
- Produces: `FlowLayout(hSpacing: CGFloat = 8, vSpacing: CGFloat = 8)` conforming to `Layout` — left-aligned wrapping of its subviews. Consumed by Task 9 (`HighlightHeadline`).

- [ ] **Step 1: Create the layout**

```swift
import SwiftUI

/// A simple left-to-right wrapping layout. Places subviews in a row until the next one
/// would overflow the proposed width, then wraps to a new line.
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - hSpacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Commit**

```bash
git add Glutt/DesignSystem/Components/FlowLayout.swift
git commit -m "feat(design): add FlowLayout wrapping layout"
```

---

### Task 9: HighlightHeadline component (+ word-style test)

**Files:**
- Create: `Glutt/DesignSystem/Components/HighlightHeadline.swift`
- Create: `GluttTests/HeadlineWordStyleTests.swift`

**Interfaces:**
- Consumes: `FlowLayout` (Task 8).
- Produces:
  - `enum HeadlineWordStyle { case green, amber, tomato, plain }` with
    `var foreground: Color` and `var background: Color?` (`nil` = no pill).
  - `struct HeadlineWord { let text: String; let style: HeadlineWordStyle }`
  - `HighlightHeadline(words: [HeadlineWord])` — renders each word as a 31pt-black
    tinted pill (or plain text when `background == nil`), wrapping via `FlowLayout`.

- [ ] **Step 1: Write the failing test**

Create `GluttTests/HeadlineWordStyleTests.swift`:

```swift
import SwiftUI
import XCTest
@testable import Glutt

final class HeadlineWordStyleTests: XCTestCase {
    func testForegroundMapping() {
        XCTAssertEqual(HeadlineWordStyle.green.foreground, Theme.Colors.accent)
        XCTAssertEqual(HeadlineWordStyle.amber.foreground, Theme.Colors.warning)
        XCTAssertEqual(HeadlineWordStyle.tomato.foreground, Theme.Colors.tomato)
        XCTAssertEqual(HeadlineWordStyle.plain.foreground, Theme.Colors.textPrimary)
    }

    func testBackgroundMapping() {
        XCTAssertEqual(HeadlineWordStyle.green.background, Theme.Colors.successTint)
        XCTAssertEqual(HeadlineWordStyle.amber.background, Theme.Colors.warningTint)
        XCTAssertEqual(HeadlineWordStyle.tomato.background, Theme.Colors.tomatoTint)
        XCTAssertNil(HeadlineWordStyle.plain.background)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/HeadlineWordStyleTests -quiet`
Expected: **FAIL** — does not compile (`HeadlineWordStyle` undefined).

- [ ] **Step 3: Create the component**

Create `Glutt/DesignSystem/Components/HighlightHeadline.swift`:

```swift
import SwiftUI

/// Per-word styling for the onboarding headline.
enum HeadlineWordStyle {
    case green, amber, tomato, plain

    var foreground: Color {
        switch self {
        case .green:  return Theme.Colors.accent
        case .amber:  return Theme.Colors.warning
        case .tomato: return Theme.Colors.tomato
        case .plain:  return Theme.Colors.textPrimary
        }
    }

    /// Pill fill, or `nil` for a plain (pill-less) word.
    var background: Color? {
        switch self {
        case .green:  return Theme.Colors.successTint
        case .amber:  return Theme.Colors.warningTint
        case .tomato: return Theme.Colors.tomatoTint
        case .plain:  return nil
        }
    }
}

struct HeadlineWord: Identifiable {
    let id = UUID()
    let text: String
    let style: HeadlineWordStyle
}

/// A bold headline whose words wrap as individually tinted pills
/// (e.g. "Cook" green · "smarter" amber · "not" plain · "harder" tomato).
struct HighlightHeadline: View {
    let words: [HeadlineWord]

    var body: some View {
        FlowLayout(hSpacing: 8, vSpacing: 8) {
            ForEach(words) { word in
                Text(word.text)
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundColor(word.style.foreground)
                    .padding(.horizontal, word.style.background == nil ? 0 : 15)
                    .padding(.vertical, word.style.background == nil ? 0 : 5)
                    .background {
                        if let bg = word.style.background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(bg)
                        }
                    }
            }
        }
    }
}

#Preview("HighlightHeadline") {
    HighlightHeadline(words: [
        HeadlineWord(text: "Cook", style: .green),
        HeadlineWord(text: "smarter", style: .amber),
        HeadlineWord(text: "not", style: .plain),
        HeadlineWord(text: "harder", style: .tomato),
    ])
    .padding()
    .frame(width: 320, alignment: .leading)
    .background(Theme.Colors.background)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GluttTests/HeadlineWordStyleTests -quiet`
Expected: **TEST SUCCEEDED** (4 assertions pass).

- [ ] **Step 5: Verify the preview**

Resume "HighlightHeadline". Confirm four words wrapping as pills: green "Cook", amber
"smarter", plain "not" (no pill), tomato "harder".

- [ ] **Step 6: Commit**

```bash
git add Glutt/DesignSystem/Components/HighlightHeadline.swift GluttTests/HeadlineWordStyleTests.swift
git commit -m "feat(design): add HighlightHeadline component with word-style tests"
```

---

### Task 10: CategoryCircle component

**Files:**
- Create: `Glutt/DesignSystem/Components/CategoryCircle.swift`

**Interfaces:**
- Consumes: `Theme.Colors.mutedLabel` (Task 2).
- Produces: `CategoryCircle(image: Image, label: String, isActive: Bool, action: () -> Void)` — active 66pt with 3px green ring + sparkle accent; inactive 50pt, 0.78 opacity, muted label.

- [ ] **Step 1: Create the component**

```swift
import SwiftUI
import PhosphorSwift

/// A circular category thumbnail (recipe photo) + label for the Browse category row.
/// Active: 66pt with a herb-green ring and a sparkle accent. Inactive: 50pt, dimmed.
struct CategoryCircle: View {
    let image: Image
    let label: String
    var isActive: Bool = false
    var action: () -> Void = {}

    private var diameter: CGFloat { isActive ? 66 : 50 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                        .overlay(
                            Circle().strokeBorder(Theme.Colors.accent, lineWidth: isActive ? 3 : 0)
                        )
                        .opacity(isActive ? 1 : 0.78)

                    if isActive {
                        Ph.sparkle.fill
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundColor(Theme.Colors.warning)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(label)
                    .font(.system(size: isActive ? 14 : 13,
                                  weight: isActive ? .heavy : .bold,
                                  design: .rounded))
                    .foregroundColor(isActive ? Theme.Colors.textPrimary : Theme.Colors.mutedLabel)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }
}

#Preview("CategoryCircle") {
    HStack(spacing: 16) {
        CategoryCircle(image: Image(systemName: "photo"), label: "Breakfast")
        CategoryCircle(image: Image(systemName: "photo"), label: "Lunch", isActive: true)
        CategoryCircle(image: Image(systemName: "photo"), label: "Dinner")
    }
    .padding()
    .background(Theme.Colors.background)
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme Glutt -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Verify the preview**

Resume "CategoryCircle". Confirm the middle item is larger with a green ring + sparkle and
a dark heavy label; the others are smaller, dimmed, with muted labels.

- [ ] **Step 4: Commit**

```bash
git add Glutt/DesignSystem/Components/CategoryCircle.swift
git commit -m "feat(design): add CategoryCircle component"
```

---

## Self-Review

**Spec coverage (Foundation slice of the design spec):**
- Tokens `Radius.cardLarge`/`.photo`, `tomatoTint`, `peachPanel`, `sagePanel` → Task 2. ✓
- Additional tokens needed by components (`creamText`, `segmentTrack`, `dotInactive`, `mutedLabel`) → Task 2. ✓
- `gluttSectionLabel` typography → Task 3. ✓
- PhosphorSwift via SPM → Task 1. ✓
- `StatPill`, `IconChip`, `CategoryCircle`, `SegmentedTabs`, `PageDots`, `HighlightHeadline` → Tasks 4–10. ✓ (`FlowLayout` added in Task 8 as a dependency of `HighlightHeadline`.)
- Deferred to later plans (correctly out of scope here): `GluttTabBar` + RootView integration (Tab bar plan), `RecipeCard`/`Chip`/`Buttons` restyle (Browse plan), the screens, `Recipe.isFavorite` (Recipe Detail plan), the ingredient→category classification (Recipe Detail plan).

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every verification step has an exact command + expected result. ✓

**Type consistency:** `StatPill` factories return `StatPill`; `SegmentedTabs.selection` is `Binding<Int>`; `HeadlineWordStyle.background` is `Color?` (consumed as optional in `HighlightHeadline` and asserted `nil` for `.plain` in the test); `CategoryCircle` consumes `Theme.Colors.mutedLabel` defined in Task 2; `HighlightHeadline` consumes `FlowLayout` defined in Task 8. ✓

**Note carried to execution:** All Phosphor case names (`star`, `clock`, `cellSignalMedium`, `sparkle`, plus preview-only `hamburger`/`plant`/`bowlFood`) must match the installed PhosphorSwift version's Swift case names; Task 1 verifies the package API and each component task says to substitute the nearest case if a name differs.
