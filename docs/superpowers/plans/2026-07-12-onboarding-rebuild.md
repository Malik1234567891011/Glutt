# Onboarding 1:1 Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing 6-step onboarding with a pixel-faithful SwiftUI copy of the 11-screen prototype in `design_handoff_onboarding_flow/`, wired to UserPrefs, Superwall, real notification permission, and the demo import.

**Architecture:** Clean-room rewrite of `Glutt/Features/Onboarding/` (only `OnboardingPaywallHook` survives). A pure `OnboardingFlowModel` drives `screen 0–10` + `tutPhase 0–4`; one SwiftUI file per design screen; onboarding-scoped tokens (`OnboardingTheme`, bundled Bricolage/Nunito, vendored Material Symbols) so the global `Theme` is untouched.

**Tech Stack:** SwiftUI (iOS 17), SwiftData (`UserPrefs`), AVFoundation (looping mp4), UserNotifications, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-07-12-onboarding-redesign-design.md`. Exact pixel values come from `design_handoff_onboarding_flow/Glutt Onboarding.dc.html` — when a value in this plan and the HTML disagree, the HTML wins.

## Global Constraints

- iOS deployment target 17.0; Swift 5.10; iPhone-only, portrait-only, Light-only (already configured — do not change).
- `project.yml` is the source of truth. **After adding/removing ANY file or editing `project.yml`, run `xcodegen generate` before building.**
- Build/run/test through XcodeBuildMCP (`build_sim`, `test_sim`, `build_run_sim`), scheme `Glutt`. Call `session_show_defaults` once per session first; if unset: `session_set_defaults` with project `Glutt.xcodeproj`, scheme `Glutt`, and an iPhone 16 Pro (or newest available) simulator.
- All onboarding copy verbatim from the HTML, including "1M+ happy home cooks" and "4.9 ★ rated".
- Colors as exact hex from the HTML. Fixed font sizes (no Dynamic Type) inside onboarding.
- New enum cases `DietaryRule.nutFree` ("Nut-free") and `.keto` ("Keto"). Rule tile order: vegetarian, vegan, pescatarian, glutenFree, dairyFree, nutFree, halal, kosher, keto.
- Layout mapping rule: design top paddings are absolute in a 390×874 bezel — implement as `(design value − 54)` below the safe-area top; bottom paddings relative to safe-area bottom; horizontal paddings literal.
- Every task ends with a commit of only that task's files. Commit messages end with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01BNewK24eTszGiHde9MfSZW`.
- Font/icon assets are OFL/Apache-licensed — license files must be committed alongside.

## File map

| File | Responsibility |
|---|---|
| `Glutt/Resources/Fonts/{BricolageGrotesque-Variable.ttf, Nunito-Variable.ttf, OFL-*.txt}` | Bundled variable fonts + licenses |
| `Glutt/Resources/Videos/{glutt-intro.mp4, glutt-features.mp4}` | Looping design videos |
| `Glutt/Resources/Assets.xcassets/MaterialSymbols/*` | ~35 template vector glyph imagesets |
| `Glutt/Resources/Assets.xcassets/tutorialHotHoney.imageset` | Downscaled hot-honey photo |
| `Glutt/Features/Onboarding/Support/OnboardingFonts.swift` | Bricolage/Nunito Font builders (wght/opsz axes) |
| `Glutt/Features/Onboarding/Support/MaterialSymbol.swift` | `MS` enum → template Images |
| `Glutt/Features/Onboarding/Support/OnboardingTheme.swift` | Exact design hex tokens |
| `Glutt/Features/Onboarding/Support/OnboardingComponents.swift` | Primary/disabled/link buttons, chrome bar, headline/subhead |
| `Glutt/Features/Onboarding/Support/LoopingVideoView.swift` | Muted aspect-fill looper |
| `Glutt/Features/Onboarding/Support/CoachMark.swift` | Ripple + pulse + "Tap here 👇" bubble |
| `Glutt/Features/Onboarding/Support/MiniPhoneFrame.swift` | 240×510 bezel, 390×830 canvas ×0.61538 |
| `Glutt/Features/Onboarding/Support/TutorialFrames.swift` | 5 phase frames for the mini-phone |
| `Glutt/Features/Onboarding/OnboardingFlowModel.swift` | Pure screen/tutPhase state machine |
| `Glutt/Features/Onboarding/OnboardingState.swift` | Selections + `apply(to:)` (rewrite) |
| `Glutt/Features/Onboarding/OnboardingFlow.swift` | Coordinator (rewrite) |
| `Glutt/Features/Onboarding/Screens/*.swift` | 11 screens (all new; old 6 deleted) |
| `Glutt/Models/Enums.swift` | +2 DietaryRule cases |
| `Glutt/App/RootView.swift` | Notification gating change |
| `GluttTests/{OnboardingStateTests, OnboardingFlowModelTests}.swift` | Rewritten/new logic tests |

---

### Task 1: Bundle Bricolage Grotesque + Nunito and expose `OnboardingFonts`

**Files:**
- Create: `Glutt/Resources/Fonts/BricolageGrotesque-Variable.ttf`, `Glutt/Resources/Fonts/Nunito-Variable.ttf`, `Glutt/Resources/Fonts/OFL-BricolageGrotesque.txt`, `Glutt/Resources/Fonts/OFL-Nunito.txt`
- Create: `Glutt/Features/Onboarding/Support/OnboardingFonts.swift`
- Modify: `project.yml` (UIAppFonts under the `Glutt` target's `info.properties`)
- Test: `GluttTests/OnboardingFontsTests.swift`

**Interfaces:**
- Produces: `OnboardingFonts.bricolage(_ size: CGFloat, _ weight: CGFloat) -> Font` and `OnboardingFonts.nunito(_ size: CGFloat, _ weight: CGFloat) -> Font` (weight is the CSS-style axis value: 600, 700, 800). All later UI tasks consume these.

- [ ] **Step 1: Download fonts + licenses**

```bash
cd /Users/omarlahmimi/Documents/Glutt
mkdir -p Glutt/Resources/Fonts
curl -fsSL -o "Glutt/Resources/Fonts/BricolageGrotesque-Variable.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/bricolagegrotesque/BricolageGrotesque%5Bopsz%2Cwdth%2Cwght%5D.ttf"
curl -fsSL -o "Glutt/Resources/Fonts/Nunito-Variable.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/nunito/Nunito%5Bwght%5D.ttf"
curl -fsSL -o "Glutt/Resources/Fonts/OFL-BricolageGrotesque.txt" "https://raw.githubusercontent.com/google/fonts/main/ofl/bricolagegrotesque/OFL.txt"
curl -fsSL -o "Glutt/Resources/Fonts/OFL-Nunito.txt" "https://raw.githubusercontent.com/google/fonts/main/ofl/nunito/OFL.txt"
ls -la Glutt/Resources/Fonts/
```
Expected: 4 files; each TTF > 100KB. (If a URL 404s, list the dir via the GitHub API to find the exact filename — do not substitute a different font.)

- [ ] **Step 2: Register in project.yml**

In `project.yml`, inside `targets: Glutt: info: properties:` (sibling of `UIUserInterfaceStyle: Light`), add:

```yaml
        UIAppFonts:
          - BricolageGrotesque-Variable.ttf
          - Nunito-Variable.ttf
```

Then run: `xcodegen generate`
Expected: "Created project at .../Glutt.xcodeproj".

- [ ] **Step 3: Write the failing test**

Create `GluttTests/OnboardingFontsTests.swift`:

```swift
import XCTest
@testable import Glutt

final class OnboardingFontsTests: XCTestCase {
    func testBundledFontFamiliesAreRegistered() {
        XCTAssertTrue(UIFont.familyNames.contains("Bricolage Grotesque"),
                      "Bricolage Grotesque not registered — check UIAppFonts / bundle")
        XCTAssertTrue(UIFont.familyNames.contains("Nunito"),
                      "Nunito not registered — check UIAppFonts / bundle")
    }

    func testHelpersReturnRequestedFamily() {
        XCTAssertEqual(OnboardingFonts.uiBricolage(19, 600).familyName, "Bricolage Grotesque")
        XCTAssertEqual(OnboardingFonts.uiNunito(13, 700).familyName, "Nunito")
    }
}
```

- [ ] **Step 4: Run test to verify it fails**

XcodeBuildMCP `test_sim` (scheme `Glutt`). Expected: build FAILS — `OnboardingFonts` unresolved. (The familyNames test can't run yet; that's fine.)

- [ ] **Step 5: Implement `OnboardingFonts`**

Create `Glutt/Features/Onboarding/Support/OnboardingFonts.swift`:

```swift
import SwiftUI
import UIKit

/// Onboarding-only brand fonts, bundled as variable TTFs (see Resources/Fonts).
/// `weight` is the CSS axis value the design uses (600/700/800). Bricolage also
/// pins `opsz` to the point size, matching the browser's automatic optical sizing.
enum OnboardingFonts {
    private static let wght: Int = 0x77676874 // 'wght'
    private static let opsz: Int = 0x6F70737A // 'opsz'

    static func bricolage(_ size: CGFloat, _ weight: CGFloat) -> Font {
        Font(uiBricolage(size, weight))
    }

    static func nunito(_ size: CGFloat, _ weight: CGFloat) -> Font {
        Font(uiNunito(size, weight))
    }

    static func uiBricolage(_ size: CGFloat, _ weight: CGFloat) -> UIFont {
        variable("Bricolage Grotesque", size: size, axes: [wght: weight, opsz: size])
    }

    static func uiNunito(_ size: CGFloat, _ weight: CGFloat) -> UIFont {
        variable("Nunito", size: size, axes: [wght: weight])
    }

    private static func variable(_ family: String, size: CGFloat, axes: [Int: CGFloat]) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        #if DEBUG
        if font.familyName != family { assertionFailure("Missing bundled font \(family)") }
        #endif
        return font
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

XcodeBuildMCP `test_sim`. Expected: both `OnboardingFontsTests` PASS (test host is the app, so UIAppFonts are registered).

- [ ] **Step 7: Commit**

```bash
git add Glutt/Resources/Fonts project.yml Glutt.xcodeproj Glutt/Features/Onboarding/Support/OnboardingFonts.swift GluttTests/OnboardingFontsTests.swift
git commit -m "feat(onboarding): bundle Bricolage Grotesque + Nunito variable fonts"
```

### Task 2: Vendor Material Symbols Rounded glyphs (`MS` enum)

**Files:**
- Create: `Glutt/Resources/Assets.xcassets/MaterialSymbols/` (one imageset per glyph) + `Glutt/Resources/Fonts/LICENSE-MaterialSymbols.txt`
- Create: `Glutt/Features/Onboarding/Support/MaterialSymbol.swift`
- Test: build + a tiny existence test in `GluttTests/OnboardingFontsTests.swift` (same file, new case)

**Interfaces:**
- Produces: `enum MS: String, CaseIterable` with `var image: Image` (template-rendered, tint with `.foregroundStyle`). Cases named below — later tasks reference e.g. `MS.chevronLeft.image`, `MS.ecoFill.image`.

Glyphs and fill variants (from the HTML's `font-variation-settings`): **filled** (`_fill1`): check, eco, spa, set_meal, grain, icecream, no_meals, mosque, synagogue, egg, local_fire_department, kitchen, graphic_eq, mic, skillet, favorite, chat, chat_bubble, mail, check_circle, arrow_upward. **Outlined** (no fill): chevron_left, send, mode_comment, bookmark, search, add_circle, ios_share, link, wifi_tethering, content_copy, chrome_reader_mode, schedule, restaurant, local_fire_department (outlined ALSO needed — saved-recipe meta row).

- [ ] **Step 1: Download SVGs and build imagesets**

```bash
cd /Users/omarlahmimi/Documents/Glutt
DEST="Glutt/Resources/Assets.xcassets/MaterialSymbols"
mkdir -p "$DEST"
cat > "$DEST/Contents.json" <<'EOF'
{ "info" : { "author" : "xcode", "version" : 1 } }
EOF
FILLED="check eco spa set_meal grain icecream no_meals mosque synagogue egg local_fire_department kitchen graphic_eq mic skillet favorite chat chat_bubble mail check_circle arrow_upward"
OUTLINED="chevron_left send mode_comment bookmark search add_circle ios_share link wifi_tethering content_copy chrome_reader_mode schedule restaurant local_fire_department"
fetch() { # $1 glyph, $2 suffix ("-fill"|""), $3 svg variant ("_fill1"|"")
  name="ms-$(echo "$1" | tr '_' '-')$2"
  dir="$DEST/$name.imageset"; mkdir -p "$dir"
  curl -fsSL -o "$dir/$name.svg" \
    "https://raw.githubusercontent.com/google/material-design-icons/master/symbols/web/$1/materialsymbolsrounded/$1${3}_48px.svg" || { echo "MISS $1$3"; return 1; }
  cat > "$dir/Contents.json" <<EOF
{ "images" : [ { "filename" : "$name.svg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" } }
EOF
}
for g in $FILLED;  do fetch "$g" "-fill" "_fill1"; done
for g in $OUTLINED; do fetch "$g" "" ""; done
curl -fsSL -o Glutt/Resources/Fonts/LICENSE-MaterialSymbols.txt "https://raw.githubusercontent.com/google/material-design-icons/master/LICENSE"
ls "$DEST" | wc -l
```
Expected: no `MISS` lines; 36 entries (35 imagesets + Contents.json). If a glyph 404s, check its exact directory name via the GitHub API (`symbols/web/<name>/`) — do not swap in a different glyph.

- [ ] **Step 2: Write `MS` enum**

Create `Glutt/Features/Onboarding/Support/MaterialSymbol.swift`:

```swift
import SwiftUI

/// Vendored Material Symbols Rounded glyphs (template SVG imagesets under
/// Assets.xcassets/MaterialSymbols) — same pattern as the vendored Phosphor set.
/// `-fill` cases are the design's `FILL 1` variants. Tint via .foregroundStyle.
enum MS: String, CaseIterable {
    case checkFill = "ms-check-fill"
    case ecoFill = "ms-eco-fill"
    case spaFill = "ms-spa-fill"
    case setMealFill = "ms-set-meal-fill"
    case grainFill = "ms-grain-fill"
    case icecreamFill = "ms-icecream-fill"
    case noMealsFill = "ms-no-meals-fill"
    case mosqueFill = "ms-mosque-fill"
    case synagogueFill = "ms-synagogue-fill"
    case eggFill = "ms-egg-fill"
    case fireFill = "ms-local-fire-department-fill"
    case kitchenFill = "ms-kitchen-fill"
    case graphicEqFill = "ms-graphic-eq-fill"
    case micFill = "ms-mic-fill"
    case skilletFill = "ms-skillet-fill"
    case favoriteFill = "ms-favorite-fill"
    case chatFill = "ms-chat-fill"
    case chatBubbleFill = "ms-chat-bubble-fill"
    case mailFill = "ms-mail-fill"
    case checkCircleFill = "ms-check-circle-fill"
    case arrowUpwardFill = "ms-arrow-upward-fill"
    case chevronLeft = "ms-chevron-left"
    case send = "ms-send"
    case modeComment = "ms-mode-comment"
    case bookmark = "ms-bookmark"
    case search = "ms-search"
    case addCircle = "ms-add-circle"
    case iosShare = "ms-ios-share"
    case link = "ms-link"
    case wifiTethering = "ms-wifi-tethering"
    case contentCopy = "ms-content-copy"
    case chromeReaderMode = "ms-chrome-reader-mode"
    case schedule = "ms-schedule"
    case restaurant = "ms-restaurant"
    case fire = "ms-local-fire-department"

    var image: Image { Image(rawValue).renderingMode(.template).resizable() }

    /// Sized like the design's icon-font glyphs (font-size ≈ square box).
    func sized(_ pt: CGFloat) -> some View {
        image.scaledToFit().frame(width: pt, height: pt)
    }
}
```

- [ ] **Step 3: Add existence test**

Append to `GluttTests/OnboardingFontsTests.swift`:

```swift
final class MaterialSymbolTests: XCTestCase {
    func testEveryGlyphAssetExists() {
        for symbol in MS.allCases {
            XCTAssertNotNil(UIImage(named: symbol.rawValue),
                            "Missing imageset for \(symbol.rawValue)")
        }
    }
}
```

- [ ] **Step 4: Regenerate + run tests**

Run `xcodegen generate`, then XcodeBuildMCP `test_sim`. Expected: `testEveryGlyphAssetExists` PASS (catches any 404'd/renamed asset).

- [ ] **Step 5: Commit**

```bash
git add Glutt/Resources/Assets.xcassets/MaterialSymbols Glutt/Resources/Fonts/LICENSE-MaterialSymbols.txt Glutt/Features/Onboarding/Support/MaterialSymbol.swift GluttTests/OnboardingFontsTests.swift Glutt.xcodeproj
git commit -m "feat(onboarding): vendor Material Symbols Rounded glyphs as MS enum"
```

---

### Task 3: `OnboardingTheme` tokens + shared components

**Files:**
- Create: `Glutt/Features/Onboarding/Support/OnboardingTheme.swift`
- Create: `Glutt/Features/Onboarding/Support/OnboardingComponents.swift`
- Test: build + Xcode previews (visual); no logic to unit-test

**Interfaces:**
- Produces (consumed by every screen task):
  - `OnboardingTheme` statics: `cream`, `surface`, `videoFrame`, `tileBase`, `greenDeep`, `greenPressed`, `progressFill`, `progressFillDark`, `greenTint`, `greenMid`, `mintBright`, `sage`, `textHeading`, `textBase`, `textList`, `muted`, `mutedDeep`, `mutedWarm`, `timestamp`, `disabledBg`, `disabledText`, `creamText`, `coral`, `coralBright`, `Color(hex:)` init.
  - `OnboardingPrimaryButton(title:height:action:)` (height default 60)
  - `OnboardingDisabledPill(title:)`
  - `OnboardingTextLink(title:action:)`
  - `OnboardingChrome(progress:style:onBack:)` with `enum Style { case cream, overVideo }`
  - `OnboardingHeadline(_:size:maxWidth:)` and `OnboardingSubhead(_:maxWidth:)`

- [ ] **Step 1: Write `OnboardingTheme`**

```swift
import SwiftUI

/// Exact tokens from design_handoff_onboarding_flow (HTML is source of truth).
/// Scoped to onboarding — the app-wide `Theme` is deliberately untouched.
enum OnboardingTheme {
    static let cream = Color(hex: 0xFAF3E7)        // screen background
    static let surface = Color(hex: 0xFFFDF7)      // rows/cards
    static let videoFrame = Color(hex: 0xF4EDDC)   // video placeholder bg
    static let tileBase = Color(hex: 0xF1E9D6)     // welcome grid tile bg
    static let greenDeep = Color(hex: 0x2E5339)    // primary
    static let greenPressed = Color(hex: 0x356145)
    static let progressFill = Color(hex: 0x3E7A50)
    static let progressFillDark = Color(hex: 0x7BD48F)
    static let greenTint = Color(hex: 0xEAF1E7)
    static let greenMid = Color(hex: 0x4E7A5C)
    static let mintBright = Color(hex: 0x8FE3A3)
    static let sage = Color(hex: 0x6FB183)
    static let textHeading = Color(hex: 0x241E19)
    static let textBase = Color(hex: 0x2A2420)
    static let textList = Color(hex: 0x3A342C)
    static let muted = Color(hex: 0x9A9082)
    static let mutedDeep = Color(hex: 0x8A8072)
    static let mutedWarm = Color(hex: 0x6E6456)
    static let timestamp = Color(hex: 0xB3A99A)
    static let disabledBg = Color(hex: 0xDED6C4)
    static let disabledText = Color(hex: 0xA79D8B)
    static let creamText = Color(hex: 0xFBF5E9)
    static let coral = Color(hex: 0xD9483B)
    static let coralBright = Color(hex: 0xE1523D)
    /// rgba(42,36,32,x) — the design's warm-black overlay base.
    static func warmBlack(_ opacity: Double) -> Color { Color(hex: 0x2A2420).opacity(opacity) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
```

(If `Color(hex:)` already exists app-wide, reuse it and drop this extension — check with `grep -rn "init(hex" Glutt/` first.)

- [ ] **Step 2: Write `OnboardingComponents`**

```swift
import SwiftUI

/// Primary CTA: 60pt capsule, Bricolage 600/19, pressed = translateY(1).
struct OnboardingPrimaryButton: View {
    let title: String
    var height: CGFloat = 60
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.medium)
            action()
        } label: {
            Text(title)
                .font(OnboardingFonts.bricolage(height == 60 ? 19 : 18, 600))
                .kerning(0.2)
                .foregroundStyle(OnboardingTheme.creamText)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(OnboardingTheme.greenDeep, in: Capsule())
                .shadow(color: OnboardingTheme.greenDeep.opacity(0.3), radius: 12, y: 10)
        }
        .buttonStyle(PressOffsetStyle())
    }
}

struct PressOffsetStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 1 : 0)
    }
}

/// Goals-gate disabled state: non-interactive gray pill.
struct OnboardingDisabledPill: View {
    let title: String
    var body: some View {
        Text(title)
            .font(OnboardingFonts.bricolage(19, 600))
            .kerning(0.2)
            .foregroundStyle(OnboardingTheme.disabledText)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(OnboardingTheme.disabledBg, in: Capsule())
    }
}

/// "Maybe later" / "Not now" / "Skip tutorial" links (Nunito 700/15, muted).
struct OnboardingTextLink: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Text(title)
                .font(OnboardingFonts.nunito(15, 700))
                .foregroundStyle(OnboardingTheme.muted)
        }
        .buttonStyle(.plain)
    }
}

/// Top chrome: 40pt back circle + 8pt progress track. `overVideo` is the
/// Polly-screen glass variant. Sits at (design 60 − 54) = 6pt below safe top.
struct OnboardingChrome: View {
    enum Style { case cream, overVideo }
    let progress: Double
    var style: Style = .cream
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Haptics.impact(.light)
                onBack()
            } label: {
                MS.chevronLeft.sized(24)
                    .foregroundStyle(style == .cream ? Color(hex: 0x4A4238) : .white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(style == .cream ? AnyShapeStyle(Color.white)
                                                      : AnyShapeStyle(.white.opacity(0.24)))
                    )
                    .background(style == .overVideo ? AnyView(Circle().fill(.ultraThinMaterial)) : AnyView(EmptyView()))
                    .shadow(color: style == .cream ? OnboardingTheme.warmBlack(0.12) : .clear, radius: 3.5, y: 2)
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(style == .cream ? OnboardingTheme.warmBlack(0.09) : .white.opacity(0.32))
                    Capsule()
                        .fill(style == .cream ? OnboardingTheme.progressFill : OnboardingTheme.progressFillDark)
                        .frame(width: geo.size.width * progress)
                        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45), value: progress)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
    }
}

/// Screen H1 — Bricolage 600, tight tracking, centered, balanced wrap.
struct OnboardingHeadline: View {
    let text: String
    var size: CGFloat = 27
    var maxWidth: CGFloat = 300
    init(_ text: String, size: CGFloat = 27, maxWidth: CGFloat = 300) {
        self.text = text; self.size = size; self.maxWidth = maxWidth
    }
    var body: some View {
        Text(text)
            .font(OnboardingFonts.bricolage(size, 600))
            .kerning(-0.5)
            .lineSpacing(size * 0.18 / 2)
            .multilineTextAlignment(.center)
            .foregroundStyle(OnboardingTheme.textHeading)
            .frame(maxWidth: maxWidth)
    }
}

/// Subhead — Nunito 600 14.5, muted, centered.
struct OnboardingSubhead: View {
    let text: String
    var maxWidth: CGFloat = 280
    init(_ text: String, maxWidth: CGFloat = 280) { self.text = text; self.maxWidth = maxWidth }
    var body: some View {
        Text(text)
            .font(OnboardingFonts.nunito(14.5, 600))
            .multilineTextAlignment(.center)
            .foregroundStyle(OnboardingTheme.muted)
            .frame(maxWidth: maxWidth)
    }
}

#Preview("Components") {
    VStack(spacing: 20) {
        OnboardingChrome(progress: 0.3) {}
        OnboardingHeadline("Any food rules?")
        OnboardingSubhead("Tap all that apply")
        OnboardingPrimaryButton(title: "Continue") {}
        OnboardingDisabledPill(title: "Continue")
        OnboardingTextLink(title: "Maybe later") {}
    }
    .padding(24)
    .background(OnboardingTheme.cream)
}
```

- [ ] **Step 3: Build & verify**

`xcodegen generate`, then XcodeBuildMCP `build_sim`. Expected: build succeeds. (Screens verify these visually later; the preview exists for spot checks.)

- [ ] **Step 4: Commit**

```bash
git add Glutt/Features/Onboarding/Support/OnboardingTheme.swift Glutt/Features/Onboarding/Support/OnboardingComponents.swift Glutt.xcodeproj
git commit -m "feat(onboarding): design tokens + shared chrome/button components"
```

### Task 4: Media assets + `LoopingVideoView`

**Files:**
- Create: `Glutt/Resources/Videos/glutt-intro.mp4`, `Glutt/Resources/Videos/glutt-features.mp4` (copied), `Glutt/Resources/Assets.xcassets/tutorialHotHoney.imageset/`
- Create: `Glutt/Features/Onboarding/Support/LoopingVideoView.swift`
- Test: build + preview

**Interfaces:**
- Produces: `LoopingVideoView(resource: String, scale: CGFloat = 1, yOffsetFraction: CGFloat = 0)` — muted, aspect-fill, auto-looping, plays on appear / pauses on disappear. `scale`/`yOffsetFraction` reproduce the HTML's crop transforms (e.g. intro: `scale: 1.1, yOffsetFraction: -0.09`).
- Produces: asset `tutorialHotHoney` (used by Task 12's tutorial frames).

- [ ] **Step 1: Copy media**

```bash
cd /Users/omarlahmimi/Documents/Glutt
mkdir -p Glutt/Resources/Videos
cp design_handoff_onboarding_flow/assets/glutt-intro.mp4 Glutt/Resources/Videos/
cp design_handoff_onboarding_flow/assets/glutt-features.mp4 Glutt/Resources/Videos/
DIR=Glutt/Resources/Assets.xcassets/tutorialHotHoney.imageset
mkdir -p "$DIR"
sips -Z 1500 design_handoff_onboarding_flow/assets/hot-honey.png --out "$DIR/tutorialHotHoney.png"
cat > "$DIR/Contents.json" <<'EOF'
{ "images" : [ { "filename" : "tutorialHotHoney.png", "idiom" : "universal", "scale" : "2x" },
               { "idiom" : "universal", "scale" : "1x" }, { "idiom" : "universal", "scale" : "3x" } ],
  "info" : { "author" : "xcode", "version" : 1 } }
EOF
ls -la Glutt/Resources/Videos "$DIR"
```
Expected: two mp4s (~532KB, ~322KB) and a PNG well under 1MB.

- [ ] **Step 2: Write `LoopingVideoView`**

```swift
import AVFoundation
import SwiftUI

/// Muted, seamlessly-looping, aspect-fill video (the design's autoplay/loop/muted
/// <video>). `scale`/`yOffsetFraction` mirror the HTML crop transforms.
/// Uses .ambient + mixWithOthers so onboarding never interrupts the user's audio.
struct LoopingVideoView: UIViewRepresentable {
    let resource: String
    var scale: CGFloat = 1
    var yOffsetFraction: CGFloat = 0

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(resource: resource, scale: scale, yOffsetFraction: yOffsetFraction)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.stop()
    }

    final class PlayerContainerView: UIView {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private let playerLayer = AVPlayerLayer()
        private var scale: CGFloat = 1
        private var yOffsetFraction: CGFloat = 0

        func configure(resource: String, scale: CGFloat, yOffsetFraction: CGFloat) {
            self.scale = scale
            self.yOffsetFraction = yOffsetFraction
            guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
                assertionFailure("Missing video \(resource).mp4")
                return // cream frame behind stays — graceful no-op
            }
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer(items: [item])
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: item)
            player = queue
            playerLayer.player = queue
            playerLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(playerLayer)
            queue.play()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            playerLayer.setAffineTransform(
                CGAffineTransform(translationX: 0, y: bounds.height * yOffsetFraction)
                    .scaledBy(x: scale, y: scale)
            )
            CATransaction.commit()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            window == nil ? player?.pause() : player?.play()
        }

        func stop() {
            player?.pause()
            player = nil
            looper = nil
        }
    }
}
```

- [ ] **Step 3: Build & verify**

`xcodegen generate`, XcodeBuildMCP `build_sim`. Expected: success. Quick preview check optional (screens exercise it for real).

- [ ] **Step 4: Commit**

```bash
git add Glutt/Resources/Videos Glutt/Resources/Assets.xcassets/tutorialHotHoney.imageset Glutt/Features/Onboarding/Support/LoopingVideoView.swift Glutt.xcodeproj
git commit -m "feat(onboarding): bundle design videos + LoopingVideoView"
```

---

### Task 5: `DietaryRule.nutFree` + `.keto`

**Files:**
- Modify: `Glutt/Models/Enums.swift:141-164` (the `DietaryRule` enum)
- Test: `GluttTests/OnboardingStateTests.swift` (created here with just this test; Task 6 rewrites/extends it)

**Interfaces:**
- Produces: `DietaryRule.nutFree` (label "Nut-free"), `DietaryRule.keto` (label "Keto"). Consumed by Task 6's `OnboardingState.ruleOptions` and Task 9's RulesScreen.

- [ ] **Step 1: Write the failing test**

Replace `GluttTests/OnboardingStateTests.swift` content with:

```swift
import XCTest
@testable import Glutt

final class DietaryRuleTests: XCTestCase {
    func testNewCasesExistWithLabels() {
        XCTAssertEqual(DietaryRule.nutFree.label, "Nut-free")
        XCTAssertEqual(DietaryRule.keto.label, "Keto")
        XCTAssertEqual(DietaryRule.nutFree.rawValue, "nutFree")
        XCTAssertEqual(DietaryRule.keto.rawValue, "keto")
    }
}
```

(The old `OnboardingStateTests` in that file reference the old goal labels; delete them now — Task 6 adds the new state tests.)

- [ ] **Step 2: Run to verify failure**

XcodeBuildMCP `test_sim`. Expected: build FAILS — `nutFree`/`keto` unresolved.

- [ ] **Step 3: Add the cases**

In `Glutt/Models/Enums.swift`, add to `DietaryRule` following the existing pattern (case + label switch entry):

```swift
case nutFree
case keto
```
and in `var label: String`:
```swift
case .nutFree: "Nut-free"
case .keto: "Keto"
```
Keep existing cases untouched (`noPork` stays). Note this file is shared with the `GluttShare` target — additive changes are safe.

- [ ] **Step 4: Run tests**

`test_sim`. Expected: `DietaryRuleTests` PASS; the whole suite still green (Settings/Polly pick the new cases up automatically).

- [ ] **Step 5: Commit**

```bash
git add Glutt/Models/Enums.swift GluttTests/OnboardingStateTests.swift
git commit -m "feat: add nutFree + keto dietary rules"
```

---

### Task 6: The swap — new state machine, new coordinator, old flow deleted

This is the atomic replacement. After it, the app builds and navigates all 11 screens end-to-end with placeholder screen bodies (headline + Continue); Tasks 7–13 then make each screen pixel-true. Old onboarding files/tests/assets are gone.

**Files:**
- Create: `Glutt/Features/Onboarding/OnboardingFlowModel.swift`
- Rewrite: `Glutt/Features/Onboarding/OnboardingState.swift`, `Glutt/Features/Onboarding/OnboardingFlow.swift`
- Create: `Glutt/Features/Onboarding/Screens/` → `WelcomeScreen.swift`, `IntroVideoScreen.swift`, `QuestionsIntroScreen.swift`, `GoalsScreen.swift`, `RulesScreen.swift`, `FourWeeksScreen.swift`, `PollyHeroScreen.swift`, `AIFeaturesScreen.swift`, `NotificationsSoftAskScreen.swift`, `NotificationPermissionScreen.swift`, `ImportTutorialScreen.swift` (stubs; note: 6 of these paths replace old files)
- Delete: `Screens/NutritionScreen.swift`, `Screens/NotificationPrimerScreen.swift`, `Support/TutorialFlowModel.swift`, `Support/OnboardingScaffold.swift`, `Support/WalkthroughFrame.swift`, `Support/CoachMark.swift`, `GluttTests/TutorialFlowModelTests.swift`, imagesets `tutorialPost`, `tutorialShareSheetApp`, `tutorialShareSheetSystem`
- Modify: `Glutt/App/RootView.swift:55-61`
- Test: `GluttTests/OnboardingFlowModelTests.swift` (new), `GluttTests/OnboardingStateTests.swift` (extend)

**Interfaces:**
- Produces `OnboardingFlowModel` (`@Observable`, pure — no SwiftUI/SwiftData):
  - `private(set) var screen: Int` (0–10), `private(set) var tutPhase: Int` (0–4)
  - `var progress: Double` (= screen/10), `var showsChrome: Bool` ({1–5,7,8,9})
  - `func advance()`, `func back()`, `func go(_ n: Int)` (clamps; entering 10 resets tutPhase)
  - `func toPermission()` (→9), `func skipToTutorial()` (→10)
  - `func tutorialTap() -> Bool` (advances phase 0→3; returns true exactly when phase becomes 3 = "start import timer")
  - `func completeImport()` (3→4 only)
- Produces `OnboardingState` (`@Observable`):
  - `static let goalOptions: [String]` (6 design labels, in order)
  - `static let ruleOptions: [DietaryRule]` (9, design order)
  - `var selectedGoals: Set<String>`, `var selectedRules: Set<DietaryRule>`
  - `var canContinueFromGoals: Bool`
  - `func toggleGoal(_:)`, `func toggleRule(_:)`, `func apply(to context: ModelContext)`
- Produces screen-view signatures that Tasks 7–13 keep (only bodies change):
  - `WelcomeScreen(onStart: () -> Void)`
  - `IntroVideoScreen(onContinue: () -> Void)`, `QuestionsIntroScreen(onContinue:)`, `FourWeeksScreen(onContinue:)`, `PollyHeroScreen(onContinue:)`, `AIFeaturesScreen(onContinue:)`
  - `GoalsScreen(state: OnboardingState, onContinue: () -> Void)`
  - `RulesScreen(state: OnboardingState, onContinue: () -> Void)`
  - `NotificationsSoftAskScreen(onTurnOn: () -> Void, onMaybeLater: () -> Void)`
  - `NotificationPermissionScreen(onDone: () -> Void)` (fires the real prompt itself; calls `onDone` after any outcome, or immediately for "Not now")
  - `ImportTutorialScreen(flow: OnboardingFlowModel, onImportNow: () -> Void, onFinish: () -> Void)`

- [ ] **Step 1: Write failing tests for the flow model**

Create `GluttTests/OnboardingFlowModelTests.swift`:

```swift
import XCTest
@testable import Glutt

final class OnboardingFlowModelTests: XCTestCase {
    func testAdvanceBackAndClamping() {
        let m = OnboardingFlowModel()
        XCTAssertEqual(m.screen, 0)
        m.back()
        XCTAssertEqual(m.screen, 0, "clamped at 0")
        m.advance()
        XCTAssertEqual(m.screen, 1)
        m.go(10); m.advance()
        XCTAssertEqual(m.screen, 10, "clamped at 10")
    }

    func testChromeVisibilityMatchesDesign() {
        let m = OnboardingFlowModel()
        let expected: Set<Int> = [1, 2, 3, 4, 5, 7, 8, 9]
        for s in 0...10 {
            m.go(s)
            XCTAssertEqual(m.showsChrome, expected.contains(s), "screen \(s)")
        }
    }

    func testProgressIsScreenOverTen() {
        let m = OnboardingFlowModel()
        m.go(9)
        XCTAssertEqual(m.progress, 0.9, accuracy: 0.0001)
    }

    func testNotificationBranch() {
        let m = OnboardingFlowModel()
        m.go(8)
        m.toPermission()
        XCTAssertEqual(m.screen, 9)
        m.go(8)
        m.skipToTutorial()
        XCTAssertEqual(m.screen, 10)
    }

    func testTutorialPhaseMachine() {
        let m = OnboardingFlowModel()
        m.go(9)
        m.go(10)
        XCTAssertEqual(m.tutPhase, 0, "entering 10 resets phase")
        XCTAssertFalse(m.tutorialTap()) // 0→1
        XCTAssertFalse(m.tutorialTap()) // 1→2
        XCTAssertTrue(m.tutorialTap(), "reaching phase 3 starts the import timer") // 2→3
        XCTAssertFalse(m.tutorialTap(), "taps ignored during import")
        XCTAssertEqual(m.tutPhase, 3)
        m.completeImport()
        XCTAssertEqual(m.tutPhase, 4)
        m.completeImport()
        XCTAssertEqual(m.tutPhase, 4, "idempotent")
    }
}
```

- [ ] **Step 2: Write failing tests for the new state**

Replace `GluttTests/OnboardingStateTests.swift` with (keeping `DietaryRuleTests` from Task 5):

```swift
import SwiftData
import XCTest
@testable import Glutt

final class DietaryRuleTests: XCTestCase {
    func testNewCasesExistWithLabels() {
        XCTAssertEqual(DietaryRule.nutFree.label, "Nut-free")
        XCTAssertEqual(DietaryRule.keto.label, "Keto")
        XCTAssertEqual(DietaryRule.nutFree.rawValue, "nutFree")
        XCTAssertEqual(DietaryRule.keto.rawValue, "keto")
    }
}

final class OnboardingStateTests: XCTestCase {
    func testGoalOptionsAreTheSixDesignLabels() {
        XCTAssertEqual(OnboardingState.goalOptions, [
            "Eat healthier without the fuss",
            "Stop wasting food",
            "Spend less on takeout",
            "Cook with what I already have",
            "Build a real cooking habit",
            "Cook for people I love",
        ])
    }

    func testRuleOptionsAreTheNineTilesInDesignOrder() {
        XCTAssertEqual(OnboardingState.ruleOptions, [
            .vegetarian, .vegan, .pescatarian, .glutenFree, .dairyFree,
            .nutFree, .halal, .kosher, .keto,
        ])
    }

    func testGoalsGate() {
        let state = OnboardingState()
        XCTAssertFalse(state.canContinueFromGoals)
        state.toggleGoal("Stop wasting food")
        XCTAssertTrue(state.canContinueFromGoals)
        state.toggleGoal("Stop wasting food")
        XCTAssertFalse(state.canContinueFromGoals, "toggle off empties the gate")
    }

    func testApplyWritesGoalsRulesAndFlagOnly() throws {
        let container = try ModelContainer(
            for: UserPrefs.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let state = OnboardingState()
        state.toggleGoal("Cook for people I love")
        state.toggleRule(.keto)
        state.toggleRule(.nutFree)
        state.apply(to: context)

        let prefs = UserPrefs.current(in: context)
        XCTAssertEqual(Set(prefs.goals), ["Cook for people I love"])
        XCTAssertEqual(Set(prefs.dietaryRules), [.keto, .nutFree])
        XCTAssertTrue(prefs.hasCompletedOnboarding)
        XCTAssertEqual(prefs.nutritionMode, .cookingOnly, "untouched default")
        XCTAssertTrue(prefs.allergies.isEmpty, "no longer captured at onboarding")
    }
}
```

- [ ] **Step 3: Run to verify failure**

`test_sim`. Expected: build FAILS (`OnboardingFlowModel` missing; `OnboardingState` lacks `goalOptions: [String]` shape).

- [ ] **Step 4: Implement `OnboardingFlowModel`**

Create `Glutt/Features/Onboarding/OnboardingFlowModel.swift`:

```swift
import Observation

/// The prototype's `Component` state machine, verbatim: `screen` 0–10 clamped,
/// `tutPhase` 0–4. Pure of SwiftUI/SwiftData so it is unit-testable.
@Observable
final class OnboardingFlowModel {
    private(set) var screen = 0
    private(set) var tutPhase = 0

    private static let chromeScreens: Set<Int> = [1, 2, 3, 4, 5, 7, 8, 9]

    var progress: Double { Double(screen) / 10 }
    var showsChrome: Bool { Self.chromeScreens.contains(screen) }

    func go(_ n: Int) {
        let clamped = min(10, max(0, n))
        if clamped == 10 { tutPhase = 0 }
        screen = clamped
    }

    func advance() { go(screen + 1) }
    func back() { go(screen - 1) }
    func toPermission() { go(9) }
    func skipToTutorial() { go(10) }

    /// Tap anywhere on the mini-phone. Returns true exactly when the tap
    /// enters phase 3 (importing) — the caller starts the 1800ms timer.
    func tutorialTap() -> Bool {
        guard screen == 10, tutPhase < 3 else { return false }
        tutPhase += 1
        return tutPhase == 3
    }

    /// 1800ms after entering phase 3 (or timer re-arm on foreground).
    func completeImport() {
        guard tutPhase == 3 else { return }
        tutPhase = 4
    }
}
```

- [ ] **Step 5: Rewrite `OnboardingState`**

Replace `Glutt/Features/Onboarding/OnboardingState.swift` content:

```swift
import Foundation
import Observation
import SwiftData

/// Onboarding selections (design screens 3 + 4) → singleton `UserPrefs`.
/// Pure of SwiftUI so the logic is unit-testable.
@Observable
final class OnboardingState {

    /// Screen 3 goal rows, design order + copy verbatim.
    static let goalOptions: [String] = [
        "Eat healthier without the fuss",
        "Stop wasting food",
        "Spend less on takeout",
        "Cook with what I already have",
        "Build a real cooking habit",
        "Cook for people I love",
    ]

    /// Screen 4 rule tiles, design order.
    static let ruleOptions: [DietaryRule] = [
        .vegetarian, .vegan, .pescatarian, .glutenFree, .dairyFree,
        .nutFree, .halal, .kosher, .keto,
    ]

    var selectedGoals: Set<String> = []
    var selectedRules: Set<DietaryRule> = []

    /// Screen 3 gate: ≥1 goal required.
    var canContinueFromGoals: Bool { !selectedGoals.isEmpty }

    func toggleGoal(_ goal: String) {
        if !selectedGoals.insert(goal).inserted { selectedGoals.remove(goal) }
    }

    func toggleRule(_ rule: DietaryRule) {
        if !selectedRules.insert(rule).inserted { selectedRules.remove(rule) }
    }

    func apply(to context: ModelContext) {
        let prefs = UserPrefs.current(in: context)
        prefs.goals = Array(selectedGoals)
        prefs.dietaryRules = Array(selectedRules)
        prefs.hasCompletedOnboarding = true
    }
}
```

- [ ] **Step 6: Delete the old flow**

```bash
cd /Users/omarlahmimi/Documents/Glutt
git rm Glutt/Features/Onboarding/Screens/NutritionScreen.swift \
       Glutt/Features/Onboarding/Screens/NotificationPrimerScreen.swift \
       Glutt/Features/Onboarding/Support/TutorialFlowModel.swift \
       Glutt/Features/Onboarding/Support/OnboardingScaffold.swift \
       Glutt/Features/Onboarding/Support/WalkthroughFrame.swift \
       Glutt/Features/Onboarding/Support/CoachMark.swift \
       GluttTests/TutorialFlowModelTests.swift
git rm -r Glutt/Resources/Assets.xcassets/tutorialPost.imageset \
          Glutt/Resources/Assets.xcassets/tutorialShareSheetApp.imageset \
          Glutt/Resources/Assets.xcassets/tutorialShareSheetSystem.imageset
```
(The remaining old screen files — Welcome/Goals/Rules/ImportTutorial — are overwritten in Step 7.)

- [ ] **Step 7: Rewrite `OnboardingFlow` + stub all 11 screens**

Replace `Glutt/Features/Onboarding/OnboardingFlow.swift`:

```swift
import SwiftData
import SwiftUI

/// 1:1 rebuild of the design-handoff onboarding (11 screens, `screen` 0–10).
/// Spec: docs/superpowers/specs/2026-07-12-onboarding-redesign-design.md
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router

    let onFinish: () -> Void

    @State private var flow = OnboardingFlowModel()
    @State private var state = OnboardingState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The reel the tutorial depicts (crispy hot honey chicken bites) —
    /// "Import my first recipe" imports it for real.
    private static let demoImportURL = URL(string: "https://www.instagram.com/reel/DYxO-e7JPw3/")

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingTheme.cream.ignoresSafeArea()

            screenView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(flow.screen)
                .transition(.asymmetric(
                    // Reduce Motion: plain fade instead of the 12pt rise.
                    insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)),
                    removal: .identity
                ))

            // Cream chrome variant. Screen 6 (Polly) draws its own glass chrome.
            if flow.showsChrome, flow.screen != 6 {
                OnboardingChrome(progress: flow.progress) { flow.back() }
            }
        }
        .animation(.easeOut(duration: 0.45), value: flow.screen)
    }

    @ViewBuilder
    private var screenView: some View {
        switch flow.screen {
        case 0: WelcomeScreen { flow.advance() }
        case 1: IntroVideoScreen { flow.advance() }
        case 2: QuestionsIntroScreen { flow.advance() }
        case 3: GoalsScreen(state: state) { flow.advance() }
        case 4: RulesScreen(state: state) { flow.advance() }
        case 5: FourWeeksScreen { flow.advance() }
        case 6:
            PollyHeroScreen { flow.advance() }
                .overlay(alignment: .top) {
                    OnboardingChrome(progress: flow.progress, style: .overVideo) { flow.back() }
                }
        case 7: AIFeaturesScreen { flow.advance() }
        case 8:
            NotificationsSoftAskScreen(
                onTurnOn: { flow.toPermission() },
                onMaybeLater: { flow.skipToTutorial() }
            )
        case 9: NotificationPermissionScreen { flow.skipToTutorial() }
        default:
            ImportTutorialScreen(
                flow: flow,
                onImportNow: { finish(thenImport: true) },
                onFinish: { finish(thenImport: false) }
            )
        }
    }

    private func finish(thenImport: Bool) {
        state.apply(to: context)
        OnboardingPaywallHook.presentPostOnboarding {
            onFinish()
            if thenImport {
                router.pendingImportURL = Self.demoImportURL
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

Overwrite/create ALL 11 files in `Glutt/Features/Onboarding/Screens/` as stubs with the final signatures. Stub template (adjust name/title/callbacks per the signature list in **Interfaces** above):

```swift
import SwiftUI

struct IntroVideoScreen: View {
    let onContinue: () -> Void
    var body: some View {
        VStack {
            Spacer()
            OnboardingHeadline("Glutt is a whole new way to cook at home", size: 28, maxWidth: 310)
            Spacer()
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .padding(.top, 50)
    }
}
```

Two stubs need their real signatures wired now:

`GoalsScreen` stub (gate already functional):
```swift
import SwiftUI

struct GoalsScreen: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void
    var body: some View {
        VStack {
            OnboardingHeadline("Why do you want to cook more at home?", size: 26)
            Spacer()
            Button("toggle-first-goal-stub") { state.toggleGoal(OnboardingState.goalOptions[0]) }
            Spacer()
            if state.canContinueFromGoals {
                OnboardingPrimaryButton(title: "Continue", action: onContinue)
            } else {
                OnboardingDisabledPill(title: "Continue")
            }
        }
        .padding(.horizontal, 22).padding(.top, 44).padding(.bottom, 8)
    }
}
```

`NotificationPermissionScreen` stub (real permission wiring is Task 11; stub just continues):
```swift
import SwiftUI

struct NotificationPermissionScreen: View {
    let onDone: () -> Void
    var body: some View {
        VStack {
            Spacer()
            OnboardingHeadline("We'll remind you to cook so it becomes a habit")
            Spacer()
            OnboardingPrimaryButton(title: "Allow Notifications", action: onDone)
            OnboardingTextLink(title: "Not now", action: onDone).padding(.top, 16)
        }
        .padding(.horizontal, 24).padding(.bottom, 10).padding(.top, 50)
    }
}
```

`RulesScreen` stub:
```swift
import SwiftUI

struct RulesScreen: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void
    var body: some View {
        VStack {
            OnboardingHeadline("Any food rules?")
            Spacer()
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 22).padding(.top, 42).padding(.bottom, 8)
    }
}
```

`NotificationsSoftAskScreen` stub:
```swift
import SwiftUI

struct NotificationsSoftAskScreen: View {
    let onTurnOn: () -> Void
    let onMaybeLater: () -> Void
    var body: some View {
        VStack {
            OnboardingHeadline("Turn on gentle nudges")
            Spacer()
            OnboardingPrimaryButton(title: "Turn on notifications", action: onTurnOn)
            OnboardingTextLink(title: "Maybe later", action: onMaybeLater).padding(.top, 16)
        }
        .padding(.horizontal, 24).padding(.top, 50).padding(.bottom, 10)
    }
}
```

Remaining single-closure stubs use the `IntroVideoScreen` template with these exact names/titles/closures: `WelcomeScreen(onStart:)` "Cook anything you actually want" (button "Start"), `QuestionsIntroScreen(onContinue:)` "Let's tune Glutt to how you actually cook", `FourWeeksScreen(onContinue:)` "Here's where you'll be in 4 weeks", `PollyHeroScreen(onContinue:)` "Polly guides you through recipes, completely hands-free", `AIFeaturesScreen(onContinue:)` "AI shows up right where you cook".

`ImportTutorialScreen` stub:
```swift
import SwiftUI

struct ImportTutorialScreen: View {
    @Bindable var flow: OnboardingFlowModel
    let onImportNow: () -> Void
    let onFinish: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("tutorial phase \(flow.tutPhase)")
            Button("tap phone (stub)") { _ = flow.tutorialTap() }
            if flow.tutPhase == 4 {
                OnboardingPrimaryButton(title: "Import my first recipe", height: 58, action: onImportNow)
                Button("I'll explore on my own", action: onFinish)
            } else {
                OnboardingTextLink(title: "Skip tutorial", action: onFinish)
            }
            Spacer()
        }
        .padding(24)
    }
}
```

- [ ] **Step 8: Gate the launch-time notification request in `RootView`**

In `Glutt/App/RootView.swift`, add `import UserNotifications` at the top, and replace the notification `.task` (currently lines 55–61):

```swift
.task(id: needsOnboarding) {
    // Notification permission is requested exactly once, on onboarding
    // screen 9. At launch we only (re)schedule if it's already granted —
    // "Maybe later" must keep meaning *not now*.
    guard !needsOnboarding,
          !ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return }
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
        ReminderScheduler.schedulePlatesDailyReminder()
    }
}
```

- [ ] **Step 9: Regenerate, run all tests**

`xcodegen generate`, then `test_sim`. Expected: whole suite PASSES (flow-model, state, dietary-rule, fonts, symbols; `TutorialFlowModelTests` is gone). If `ReminderScheduler.requestPermissionIfNeeded()` is now unreferenced, leave the function — screen 9 wiring (Task 11) documents the request path; delete it only if still unused after Task 11.

- [ ] **Step 10: Smoke-run the flow**

XcodeBuildMCP `build_run_sim` with launch arg `-onboarding`. Tap through all 11 stub screens to the tutorial finish; verify no dead ends (goals gate blocks until the stub toggle is tapped; screens 8/9 branch; finish dismisses to the app).

- [ ] **Step 11: Commit**

```bash
git add -A Glutt/Features/Onboarding GluttTests Glutt/App/RootView.swift Glutt/Resources/Assets.xcassets Glutt.xcodeproj
git commit -m "feat(onboarding)!: replace old flow with 11-screen state machine (stub bodies)"
```

### Task 7: WelcomeScreen (screen 0)

**Files:**
- Rewrite: `Glutt/Features/Onboarding/Screens/WelcomeScreen.swift`
- Test: build + sim screenshot vs prototype

**Interfaces:** Consumes Task 3 components, `WelcomeScreen(onStart:)` signature unchanged.

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Screen 0 — full-bleed masonry of recipe photos under a rising cream scrim,
/// wordmark + H1 + social-proof pill + Start. Values from the design HTML.
struct WelcomeScreen: View {
    let onStart: () -> Void

    /// 11 tiles; spans from the HTML (tiles 1 & 5 span 3 rows, rest span 2).
    private static let tiles: [(asset: String, span: Int)] = [
        ("hotHoneyChickenRice", 3), ("greenGoddessSteakPlate", 2), ("chickenRiceBowl", 2),
        ("greekYogurtBowl", 2), ("garlicButterSteakPotatoBowl", 3), ("koftaFlatbreadWrap", 2),
        ("lemonDillSalmonBowl", 2), ("beefWrapWithWedges", 2), ("koreanBeefMealPrep", 2),
        ("pestoGnocchiMealPrep", 2), ("steakFajitaSalad", 2),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            masonry
                .padding(.horizontal, 12)
                .padding(.top, 0) // design 54 − 54: grid starts at safe-area top
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()

            scrim
            content
        }
        .background(OnboardingTheme.cream)
        .ignoresSafeArea(edges: .bottom)
    }

    /// 3-column masonry, 76pt row unit, 9pt gaps — hand-placed like the CSS grid.
    private var masonry: some View {
        let unit: CGFloat = 76, gap: CGFloat = 9
        func h(_ span: Int) -> CGFloat { CGFloat(span) * unit + CGFloat(span - 1) * gap }
        func tile(_ i: Int) -> some View {
            Image(Self.tiles[i].asset)
                .resizable().scaledToFill()
                .frame(height: h(Self.tiles[i].span))
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .background(RoundedRectangle(cornerRadius: 20).fill(OnboardingTheme.tileBase))
                .shadow(color: OnboardingTheme.warmBlack(0.06), radius: 8, y: 6)
        }
        // Three independent columns approximate the CSS auto-placed grid;
        // verify the silhouette against the prototype (see note below).
        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) { tile(0); tile(5); tile(8) }
            VStack(spacing: gap) { tile(1); tile(4); tile(9) }
            VStack(spacing: gap) { tile(2); tile(3); tile(6); tile(10) }
        }
    }

    private var scrim: some View {
        GeometryReader { geo in
            LinearGradient(stops: [
                .init(color: OnboardingTheme.cream, location: 0),
                .init(color: OnboardingTheme.cream, location: 0.46),
                .init(color: OnboardingTheme.cream.opacity(0.86), location: 0.60),
                .init(color: OnboardingTheme.cream.opacity(0), location: 1),
            ], startPoint: .bottom, endPoint: .top)
            .frame(height: geo.size.height * 0.62)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text("Glutt")
                    .font(OnboardingFonts.bricolage(22, 700)).kerning(-0.3)
                    .foregroundStyle(OnboardingTheme.textHeading)
                RoundedRectangle(cornerRadius: 3)
                    .fill(OnboardingTheme.coral)
                    .frame(width: 10, height: 10)
            }
            .padding(.bottom, 14)

            Text("Cook anything you actually want")
                .font(OnboardingFonts.bricolage(34, 600)).kerning(-1)
                .lineSpacing(34 * 0.08 / 2)
                .foregroundStyle(OnboardingTheme.textHeading)
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.bottom, 18)

            HStack(spacing: 8) {
                Text("1M+")
                    .font(OnboardingFonts.bricolage(14, 700))
                    .foregroundStyle(OnboardingTheme.greenDeep)
                Text("happy home cooks")
                    .font(OnboardingFonts.nunito(13.5, 700))
                    .foregroundStyle(OnboardingTheme.greenMid)
            }
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(OnboardingTheme.greenTint, in: Capsule())
            .padding(.bottom, 26)

            OnboardingPrimaryButton(title: "Start", action: onStart)
        }
        .padding(.leading, 28).padding(.trailing, 28)
        .padding(.bottom, 40)
    }
}

#Preview { WelcomeScreen(onStart: {}) }
```

Note on the masonry: verify column placement against the prototype screenshot — CSS `grid-auto-rows` auto-placement fills row-first. If the arrangement differs visibly from the prototype, re-order tiles between the three `VStack`s until the silhouette matches (spans must stay: two tall tiles, first in column 1 row 1, second mid-grid).

- [ ] **Step 2: Build, run, screenshot**

`build_run_sim` with `-onboarding`; XcodeBuildMCP `screenshot`. Compare against the prototype's Welcome (open `design_handoff_onboarding_flow/Glutt Onboarding.dc.html` in a browser). Match: grid silhouette, scrim height, wordmark+square, H1 wrap ("Cook anything you / actually want"), pill, button.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Onboarding/Screens/WelcomeScreen.swift Glutt.xcodeproj
git commit -m "feat(onboarding): welcome masonry screen 1:1"
```

---

### Task 8: IntroVideoScreen, AIFeaturesScreen, QuestionsIntroScreen (screens 1, 7, 2)

**Files:**
- Rewrite: `Screens/IntroVideoScreen.swift`, `Screens/AIFeaturesScreen.swift`, `Screens/QuestionsIntroScreen.swift`
- Test: build + sim screenshots

**Interfaces:** Signatures unchanged (`onContinue`). Consumes `LoopingVideoView` (Task 4).

- [ ] **Step 1: Implement all three**

`IntroVideoScreen.swift`:
```swift
import SwiftUI

/// Screen 1 — H1 over a flex-fill rounded video frame (glutt-intro.mp4).
struct IntroVideoScreen: View {
    let onContinue: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("Glutt is a whole new way to cook at home", size: 28, maxWidth: 310)
            videoFrame(resource: "glutt-intro", scale: 1.1, yOffset: -0.09, fadeHeight: 0.30)
                .padding(.vertical, 22)
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)   // design 104 − 54
        .padding(.bottom, 10)
    }
}

/// Shared rounded-28 video frame with a top cream fade (screens 1 & 7).
func videoFrame(resource: String, scale: CGFloat, yOffset: CGFloat, fadeHeight: CGFloat) -> some View {
    ZStack(alignment: .top) {
        OnboardingTheme.videoFrame
        LoopingVideoView(resource: resource, scale: scale, yOffsetFraction: yOffset)
        GeometryReader { geo in
            LinearGradient(stops: [
                .init(color: OnboardingTheme.videoFrame, location: 0),
                .init(color: OnboardingTheme.videoFrame, location: 0.70),
                .init(color: OnboardingTheme.videoFrame.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: geo.size.height * fadeHeight)
        }
        .allowsHitTesting(false)
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(OnboardingTheme.warmBlack(0.05), lineWidth: 1))
    .frame(maxHeight: .infinity)
}
```

`AIFeaturesScreen.swift`:
```swift
import SwiftUI

/// Screen 7 — same template as Intro, with subhead + glutt-features.mp4.
struct AIFeaturesScreen: View {
    let onContinue: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("AI shows up right where you cook", size: 27)
            OnboardingSubhead("Smart help, right where you're cooking")
                .padding(.top, 8)
            videoFrame(resource: "glutt-features", scale: 1.08, yOffset: -0.08, fadeHeight: 0.22)
                .padding(.vertical, 14)
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .padding(.bottom, 10)
    }
}
```

`QuestionsIntroScreen.swift`:
```swift
import SwiftUI

/// Screen 2 — a single centered line as a transition beat.
struct QuestionsIntroScreen: View {
    let onContinue: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            OnboardingHeadline("Let's tune Glutt to how you actually cook", size: 29, maxWidth: 290)
            Spacer()
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .padding(.bottom, 10)
    }
}
```

- [ ] **Step 2: Build, run, screenshot screens 1, 2, 7**

`build_run_sim` with `-onboarding`, tap through; screenshot each; compare with prototype (headline sizes/wrap, video crop showing the same framing, top fade, button). Videos must visibly loop.

- [ ] **Step 3: Commit**

```bash
git add Glutt/Features/Onboarding/Screens/IntroVideoScreen.swift Glutt/Features/Onboarding/Screens/AIFeaturesScreen.swift Glutt/Features/Onboarding/Screens/QuestionsIntroScreen.swift Glutt.xcodeproj
git commit -m "feat(onboarding): intro/AI-features video screens + questions beat 1:1"
```

---

### Task 9: GoalsScreen + RulesScreen (screens 3, 4)

**Files:**
- Rewrite: `Screens/GoalsScreen.swift`, `Screens/RulesScreen.swift`
- Test: build + sim screenshots + existing state unit tests still green

**Interfaces:** Signatures unchanged. Consumes `OnboardingState` (Task 6), `MS` glyphs (Task 2).

- [ ] **Step 1: Implement GoalsScreen**

```swift
import SwiftUI

/// Screen 3 — 6 selectable rows, ≥1 required to continue.
struct GoalsScreen: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("Why do you want to cook more at home?", size: 26)
            OnboardingSubhead("Pick anything that sounds like you").padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 11) {
                    ForEach(OnboardingState.goalOptions, id: \.self) { goal in
                        row(goal, selected: state.selectedGoals.contains(goal))
                    }
                }
                .padding(2)
            }
            .padding(.top, 20).padding(.bottom, 16)

            if state.canContinueFromGoals {
                OnboardingPrimaryButton(title: "Continue", action: onContinue)
            } else {
                OnboardingDisabledPill(title: "Continue")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 44)   // design 98 − 54
        .padding(.bottom, 8)
    }

    private func row(_ goal: String, selected: Bool) -> some View {
        Button {
            Haptics.selection()
            state.toggleGoal(goal)
        } label: {
            HStack(spacing: 14) {
                Text(goal)
                    .font(OnboardingFonts.nunito(15.5, 700))
                    .foregroundStyle(OnboardingTheme.textList)
                Spacer(minLength: 0)
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(selected ? OnboardingTheme.greenDeep : .clear)
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(selected ? OnboardingTheme.greenDeep : OnboardingTheme.warmBlack(0.2), lineWidth: 2)
                    if selected {
                        MS.checkFill.sized(18).foregroundStyle(OnboardingTheme.creamText)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .padding(18)
            .background(selected ? OnboardingTheme.greenTint : OnboardingTheme.surface,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selected ? OnboardingTheme.greenDeep : OnboardingTheme.warmBlack(0.06), lineWidth: 1.5))
            .shadow(color: OnboardingTheme.warmBlack(0.04), radius: 1.5, y: 1)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}
```

- [ ] **Step 2: Implement RulesScreen**

```swift
import SwiftUI

/// Screen 4 — 3×3 gradient tiles, optional multi-select.
struct RulesScreen: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    /// Per-tile visual defs from the HTML (gradient start/end, shadow, glyph).
    private static let tileDefs: [DietaryRule: (icon: MS, start: UInt32, end: UInt32, shadow: UInt32)] = [
        .vegetarian: (.ecoFill, 0x7FB56A, 0x3F7A3A, 0x3F7A3A),
        .vegan: (.spaFill, 0x6CC99A, 0x2C8A5E, 0x2C8A5E),
        .pescatarian: (.setMealFill, 0x6BB6C4, 0x2E7385, 0x2E7385),
        .glutenFree: (.grainFill, 0xE8C06A, 0xC08A2E, 0xC08A2E),
        .dairyFree: (.icecreamFill, 0xF0B98A, 0xD9884E, 0xD9884E),
        .nutFree: (.noMealsFill, 0xE0906E, 0xB85436, 0xB85436),
        .halal: (.mosqueFill, 0x5FA377, 0x2E5339, 0x2E5339),
        .kosher: (.synagogueFill, 0x9088CC, 0x574C9E, 0x574C9E),
        .keto: (.eggFill, 0xE28AA0, 0xBC4E6E, 0xBC4E6E),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("Any food rules?", size: 27)
            OnboardingSubhead("Tap all that apply").padding(.top, 9)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(OnboardingState.ruleOptions) { rule in
                        tile(rule, selected: state.selectedRules.contains(rule))
                    }
                }
                .padding(.horizontal, 4).padding(.vertical, 6)
            }
            .padding(.top, 20).padding(.bottom, 12)

            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 22)
        .padding(.top, 42)   // design 96 − 54
        .padding(.bottom, 8)
    }

    private func tile(_ rule: DietaryRule, selected: Bool) -> some View {
        let def = Self.tileDefs[rule]!
        return Button {
            Haptics.selection()
            state.toggleRule(rule)
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(.white.opacity(0.22))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 19))
                    def.icon.sized(33).foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.12), radius: 7, y: 6)

                Text(rule.label)
                    .font(OnboardingFonts.bricolage(15, 600)).kerning(-0.2)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1 / 1.1, contentMode: .fit)
            .background(
                ZStack {
                    LinearGradient(colors: [Color(hex: def.start), Color(hex: def.end)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    // Top-left white sheen + bottom legibility shade (HTML overlays).
                    RadialGradient(colors: [.white.opacity(0.38), .white.opacity(0)],
                                   center: .init(x: 0.18, y: 0.12), startRadius: 0, endRadius: 130)
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.32), location: 0),
                        .init(color: .black.opacity(0), location: 0.54),
                    ], startPoint: .bottom, endPoint: .top)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if selected {
                    ZStack {
                        Circle().fill(.white)
                        MS.checkFill.sized(15).foregroundStyle(OnboardingTheme.greenDeep)
                    }
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
                    .padding(10)
                }
            }
            // Selected: double ring (cream 3 + green 3) + lift; else soft colored shadow.
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(OnboardingTheme.greenDeep, lineWidth: selected ? 3 : 0)
                    .padding(-6)
            )
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(OnboardingTheme.cream, lineWidth: selected ? 3 : 0)
                    .padding(-3)
            )
            .shadow(color: Color(hex: def.shadow).opacity(selected ? 0.45 : 0.45),
                    radius: selected ? 13 : 9, y: selected ? 10 : 6.5)
            .offset(y: selected ? -3 : 0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: selected)
    }
}
```

- [ ] **Step 3: Build, run, screenshot, compare**

Screens 3 and 4 vs prototype: row/tile geometry, selection states (toggle several), gate behavior (Continue disabled-pill until a goal picked), 3×3 grid fits without scrolling on a 6.1" device.

- [ ] **Step 4: Commit**

```bash
git add Glutt/Features/Onboarding/Screens/GoalsScreen.swift Glutt/Features/Onboarding/Screens/RulesScreen.swift Glutt.xcodeproj
git commit -m "feat(onboarding): goals rows + dietary rule tiles 1:1"
```

### Task 10: FourWeeksScreen + PollyHeroScreen (screens 5, 6)

**Files:**
- Rewrite: `Screens/FourWeeksScreen.swift`, `Screens/PollyHeroScreen.swift`
- Test: build + sim screenshots

**Interfaces:** Signatures unchanged (`onContinue`). PollyHeroScreen does NOT render chrome — the coordinator overlays the `.overVideo` chrome (already wired in Task 6).

- [ ] **Step 1: Implement FourWeeksScreen**

```swift
import SwiftUI

/// Screen 5 — 3 aspirational benefit cards with glossy gradient icons.
struct FourWeeksScreen: View {
    let onContinue: () -> Void

    private static let cards: [(title: String, body: String, icon: MS, start: UInt32, end: UInt32, glow: UInt32)] = [
        ("Cook with confidence", "Hands-free guided recipes that actually work",
         .fireFill, 0xF4906F, 0xD9483B, 0xE1523D),
        ("A kitchen that runs itself", "Grocery lists build themselves from your plan",
         .kitchenFill, 0x6FB183, 0x2E5339, 0x2E5339),
        ("Less waste, less takeout", "Use what you have before it goes off",
         .ecoFill, 0xF3C877, 0xD99A3C, 0xD99A3C),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("Here's where you'll be in 4 weeks", size: 27, maxWidth: 290)
            VStack(spacing: 14) {
                ForEach(Self.cards, id: \.title) { card in
                    row(card)
                }
            }
            .frame(maxHeight: .infinity)
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .padding(.bottom, 10)
    }

    private func row(_ card: (title: String, body: String, icon: MS, start: UInt32, end: UInt32, glow: UInt32)) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(OnboardingFonts.bricolage(18, 600))
                    .foregroundStyle(OnboardingTheme.textHeading)
                Text(card.body)
                    .font(OnboardingFonts.nunito(13.5, 600))
                    .foregroundStyle(OnboardingTheme.muted)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                // Radial glow halo behind the icon square.
                RadialGradient(colors: [Color(hex: card.glow).opacity(0.55), Color(hex: card.glow).opacity(0)],
                               center: .center, startRadius: 0, endRadius: 52)
                    .frame(width: 104, height: 104)
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: card.start), Color(hex: card.end)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay( // inset top highlight + bottom shade (HTML inset shadows)
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .fill(LinearGradient(stops: [
                                .init(color: .white.opacity(0.35), location: 0),
                                .init(color: .white.opacity(0), location: 0.18),
                                .init(color: .black.opacity(0), location: 0.75),
                                .init(color: .black.opacity(0.16), location: 1),
                            ], startPoint: .top, endPoint: .bottom))
                    )
                    .frame(width: 62, height: 62)
                    .shadow(color: Color(hex: card.glow).opacity(0.45), radius: 10, y: 10)
                card.icon.sized(30).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .frame(width: 62, height: 62)
        }
        .padding(.vertical, 18).padding(.horizontal, 20)
        .background(OnboardingTheme.surface.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(OnboardingTheme.warmBlack(0.05), lineWidth: 1))
        .shadow(color: OnboardingTheme.warmBlack(0.05), radius: 11, y: 8)
    }
}
```

- [ ] **Step 2: Implement PollyHeroScreen**

```swift
import SwiftUI

/// Screen 6 — top-66% full-bleed looping video with scrim to cream, floating
/// voice-caption pill, rating badge, H1, mic pill, Continue.
struct PollyHeroScreen: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                OnboardingTheme.cream.ignoresSafeArea()

                ZStack {
                    Color(hex: 0x1A140F)
                    LoopingVideoView(resource: "glutt-intro", scale: 1, yOffsetFraction: -0.10)
                    LinearGradient(stops: [
                        .init(color: Color(hex: 0x140F0A).opacity(0.30), location: 0),
                        .init(color: .clear, location: 0.24),
                        .init(color: .clear, location: 0.52),
                        .init(color: OnboardingTheme.cream.opacity(0.55), location: 0.82),
                        .init(color: OnboardingTheme.cream, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .frame(height: geo.size.height * 0.66)
                .ignoresSafeArea(edges: .top)

                captionPill
                    .offset(y: geo.size.height * 0.185 - geo.safeAreaInsets.top)

                VStack(spacing: 0) {
                    Spacer()
                    ratingBadge.padding(.bottom, 18)
                    Text("Polly guides you through recipes, completely hands-free")
                        .font(OnboardingFonts.bricolage(29, 600)).kerning(-0.6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(OnboardingTheme.textHeading)
                        .frame(maxWidth: 330)
                    HStack(spacing: 8) {
                        MS.micFill.sized(17).foregroundStyle(OnboardingTheme.mintBright)
                        Text("Real-time voice + camera")
                            .font(OnboardingFonts.nunito(13, 800)).kerning(0.2)
                            .foregroundStyle(OnboardingTheme.greenTint)
                    }
                    .padding(.vertical, 9).padding(.horizontal, 16)
                    .background(OnboardingTheme.greenDeep, in: Capsule())
                    .padding(.top, 15).padding(.bottom, 22)
                    OnboardingPrimaryButton(title: "Continue", action: onContinue)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }
        }
    }

    private var captionPill: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(RadialGradient(colors: [OnboardingTheme.mintBright, OnboardingTheme.greenDeep],
                                             center: .init(x: 0.38, y: 0.30), startRadius: 0, endRadius: 22))
                MS.graphicEqFill.sized(18).foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            Text("\u{201C}Sear it 2 more minutes, I'll tell you when to flip.\u{201D}")
                .font(OnboardingFonts.nunito(13, 600))
                .foregroundStyle(.white)
                .lineSpacing(1.5)
        }
        .padding(.vertical, 11).padding(.leading, 13).padding(.trailing, 17)
        .frame(width: 286)
        .background(Color(hex: 0x140F0A).opacity(0.44), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.28), radius: 13, y: 10)
    }

    private var ratingBadge: some View {
        HStack(spacing: 10) {
            MS.ecoFill.sized(22).foregroundStyle(OnboardingTheme.greenDeep)
                .rotationEffect(.degrees(-18))
            VStack(spacing: 2) {
                Text("4.9 ★ rated")
                    .font(OnboardingFonts.bricolage(14, 700))
                    .foregroundStyle(OnboardingTheme.textHeading)
                Text("Loved by 1M+ home cooks")
                    .font(OnboardingFonts.nunito(11, 700))
                    .foregroundStyle(OnboardingTheme.mutedWarm)
            }
            MS.ecoFill.sized(22).foregroundStyle(OnboardingTheme.greenDeep)
                .rotationEffect(.degrees(18))
                .scaleEffect(x: -1)
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
        .background(OnboardingTheme.greenDeep.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
    }
}
```

- [ ] **Step 3: Build, run, screenshot, compare**

Screen 5: card layout, glow halos, gradient icon gloss. Screen 6: video occupies top ~2/3 fading into cream, caption pill position, white glass chrome (from coordinator) with light-green fill, badge/H1/pill/CTA stack. Verify the glass back button + `#7BD48F` progress fill render over the video.

- [ ] **Step 4: Commit**

```bash
git add Glutt/Features/Onboarding/Screens/FourWeeksScreen.swift Glutt/Features/Onboarding/Screens/PollyHeroScreen.swift Glutt.xcodeproj
git commit -m "feat(onboarding): four-weeks benefit cards + Polly video hero 1:1"
```

---

### Task 11: Notification screens (8, 9) with the real OS prompt

**Files:**
- Rewrite: `Screens/NotificationsSoftAskScreen.swift`, `Screens/NotificationPermissionScreen.swift`
- Test: build + sim screenshots + behavioral check (real alert appears)

**Interfaces:** Signatures unchanged. Screen 9 fires `UNUserNotificationCenter.requestAuthorization([.alert, .sound, .badge])` and calls `ReminderScheduler.schedulePlatesDailyReminder()` on grant; `onDone` runs after any outcome (main actor).

- [ ] **Step 1: Implement NotificationsSoftAskScreen**

```swift
import SwiftUI

/// Screen 8 — three floating example notifications, then the ask.
struct NotificationsSoftAskScreen: View {
    let onTurnOn: () -> Void
    let onMaybeLater: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let notes: [(title: String, body: String, time: String, duration: Double, delay: Double)] = [
        ("Tonight's dinner is 20 minutes away", "You've got everything for Creamy Tomato Rigatoni.", "now", 5.0, 0),
        ("Plan this week in 2 minutes", "Pick a few meals and Glutt builds your list.", "8:00 AM", 5.4, 0.55),
        ("Use it before it turns", "Your spinach and mushrooms expire Sunday.", "Sun", 5.8, 1.05),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("Turn on gentle nudges", size: 27, maxWidth: 280)
            OnboardingSubhead("Cook on rhythm, never nagging").padding(.top, 8)
            VStack(spacing: 12) {
                ForEach(Self.notes, id: \.title) { note in
                    card(note)
                        .modifier(FloatEffect(duration: note.duration, delay: note.delay, enabled: !reduceMotion))
                }
            }
            .frame(maxWidth: 344).frame(maxHeight: .infinity)
            OnboardingPrimaryButton(title: "Turn on notifications", action: onTurnOn)
            OnboardingTextLink(title: "Maybe later", action: onMaybeLater).padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .padding(.bottom, 10)
    }

    private func card(_ note: (title: String, body: String, time: String, duration: Double, delay: Double)) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x3C6B4B), Color(hex: 0x244430)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                MS.skilletFill.sized(23).foregroundStyle(OnboardingTheme.creamText)
            }
            .frame(width: 40, height: 40)
            .shadow(color: OnboardingTheme.greenDeep.opacity(0.3), radius: 4, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("GLUTT").font(OnboardingFonts.nunito(11, 800)).kerning(0.7)
                        .foregroundStyle(OnboardingTheme.muted)
                    Spacer()
                    Text(note.time).font(OnboardingFonts.nunito(11, 600))
                        .foregroundStyle(OnboardingTheme.timestamp)
                }
                .padding(.bottom, 1)
                Text(note.title).font(OnboardingFonts.bricolage(14.5, 600))
                    .foregroundStyle(OnboardingTheme.textHeading)
                Text(note.body).font(OnboardingFonts.nunito(12.5, 600))
                    .foregroundStyle(OnboardingTheme.mutedDeep)
            }
        }
        .padding(.vertical, 13).padding(.horizontal, 15)
        .background(OnboardingTheme.surface.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(OnboardingTheme.warmBlack(0.05), lineWidth: 1))
        .shadow(color: OnboardingTheme.warmBlack(0.1), radius: 15, y: 12)
    }
}

/// gluttOrb: gentle infinite Y float, staggered per card.
struct FloatEffect: ViewModifier {
    let duration: Double
    let delay: Double
    let enabled: Bool
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: enabled && up ? -6 : 0)
            .onAppear {
                guard enabled else { return }
                withAnimation(.easeInOut(duration: duration / 2).repeatForever(autoreverses: true).delay(delay)) {
                    up = true
                }
            }
    }
}
```

- [ ] **Step 2: Implement NotificationPermissionScreen**

```swift
import SwiftUI
import UserNotifications

/// Screen 9 — the designed mock alert + ring + arrow stays visible; the CTA
/// fires the REAL OS prompt, which lands centered over the mock so the arrow
/// points at the real Allow button. Any outcome advances.
struct NotificationPermissionScreen: View {
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("We'll remind you to cook so it becomes a habit", size: 27)
            OnboardingSubhead("Only cooking reminders, never spam").padding(.top, 8)
            VStack(spacing: 14) {
                mockAlert
                MS.arrowUpwardFill.sized(36)
                    .foregroundStyle(OnboardingTheme.greenDeep)
                    .modifier(FloatEffect(duration: 1.5, delay: 0, enabled: !reduceMotion))
                    .frame(maxWidth: 272, alignment: .center)
                    .offset(x: 272 * 0.25) // left:75% of the alert width
            }
            .frame(maxHeight: .infinity)
            OnboardingPrimaryButton(title: "Allow Notifications", action: requestPermission)
            OnboardingTextLink(title: "Not now", action: onDone).padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .padding(.bottom, 10)
    }

    private func requestPermission() {
        guard !requesting else { return }
        requesting = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                if granted { ReminderScheduler.schedulePlatesDailyReminder() }
                onDone()
            }
        }
    }

    /// Visual mock of the iOS alert (SF system font on purpose — it imitates the OS).
    private var mockAlert: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("\u{201C}Glutt\u{201D} Would Like to Send You Notifications")
                    .font(.system(size: 16, weight: .semibold)).kerning(-0.2)
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text("Just gentle reminders to cook. No spam, ever.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(hex: 0x6B6B70))
            }
            .multilineTextAlignment(.center)
            .padding(.top, 20).padding(.horizontal, 18).padding(.bottom, 15)

            Divider().overlay(Color(hex: 0x3C3C43).opacity(0.16))
            HStack(spacing: 0) {
                Text("Don't Allow").font(.system(size: 16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Color(hex: 0x3C3C43).opacity(0.16)).frame(width: 1)
                Text("Allow").font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background( // green teaching highlight over the Allow half
                        UnevenRoundedRectangle(bottomTrailingRadius: 14)
                            .fill(OnboardingTheme.greenDeep.opacity(0.08))
                            .strokeBorder(OnboardingTheme.greenDeep.opacity(0.85), lineWidth: 2)
                    )
            }
            .foregroundStyle(Color(hex: 0x0A84FF))
            .frame(height: 44)
        }
        .frame(width: 272)
        .background(Color(hex: 0xF9F9FA).opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: OnboardingTheme.warmBlack(0.28), radius: 30, y: 24)
    }
}
```

(If `UnevenRoundedRectangle.strokeBorder` on a filled shape doesn't compile, layer it: `.fill` in `background` + `.strokeBorder` in `overlay` on two copies of the same shape.)

- [ ] **Step 3: Behavioral check**

`build_run_sim` with `-onboarding`; navigate to screen 8 → "Turn on notifications" → screen 9 → "Allow Notifications": the REAL iOS alert must appear over the mock (fresh sim install; reset with `xcrun simctl privacy booted reset notifications com.omarlahmimi.glutt` if previously determined — or use XcodeBuildMCP's sim tools/erase). Tap real "Allow" → lands on tutorial. Also verify "Maybe later" and "Not now" both go to the tutorial, and back from 9 returns to 8.

- [ ] **Step 4: Screenshot screens 8 + 9 vs prototype; commit**

```bash
git add Glutt/Features/Onboarding/Screens/NotificationsSoftAskScreen.swift Glutt/Features/Onboarding/Screens/NotificationPermissionScreen.swift Glutt.xcodeproj
git commit -m "feat(onboarding): notification soft-ask + real permission over designed mock"
```

### Task 12: Mini-phone, coach mark, tutorial walkthrough frames (phases 0–2)

**Files:**
- Create: `Support/MiniPhoneFrame.swift`, `Support/CoachMark.swift`, `Support/TutorialFrames.swift` (SocialPostFrame + AppShareSheetFrame + SystemShareSheetFrame in this task)
- Test: build + previews (assembled into the screen in Task 13)

**Interfaces:**
- Produces `MiniPhoneFrame { content }` — 240×510 black bezel, radius 46, notch 82×23; `content` laid out at 390×830 and scaled by 240/390.
- Produces `CoachMark(diameter:ringRadius:label:)` — pulsing/rippling ring + bobbing red bubble, non-interactive overlay. `ringRadius` is the ripple's corner radius (circle by default; 20 for the Glutt share-sheet square).
- Produces `SocialPostFrame()`, `AppShareSheetFrame()`, `SystemShareSheetFrame()` — static 390×830 phase visuals.

- [ ] **Step 1: MiniPhoneFrame**

```swift
import SwiftUI

/// The tutorial's phone-within-the-phone: 240×510 bezel; content is authored
/// at the design's 390×830 canvas and scaled by 240/390 (the HTML's trick).
struct MiniPhoneFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            content
                .frame(width: 390, height: 830)
                .scaleEffect(240.0 / 390.0, anchor: .topLeading)
                .frame(width: 240, height: 510, alignment: .topLeading)

            Capsule().fill(.black) // notch
                .frame(width: 82, height: 23)
                .padding(.top, 9)
                .allowsHitTesting(false)
        }
        .frame(width: 240, height: 510)
        .background(Color(hex: 0x0D0D0F))
        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 46, style: .continuous)
            .strokeBorder(OnboardingTheme.warmBlack(0.05), lineWidth: 2))
        .shadow(color: OnboardingTheme.warmBlack(0.3), radius: 28, y: 26)
    }
}
```

- [ ] **Step 2: CoachMark**

```swift
import SwiftUI

/// Pulsing/rippling highlight + bobbing "Tap here 👇" bubble over a target.
/// Purely decorative — hit-testing passes through to the phase's tap handler.
struct CoachMark: View {
    var diameter: CGFloat = 48
    var ringRadius: CGFloat? = nil // nil → circle
    var label = "Tap here 👇"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private var radius: CGFloat { ringRadius ?? (diameter + 12) / 2 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous) // ripple
                .strokeBorder(OnboardingTheme.coralBright, lineWidth: 3)
                .frame(width: diameter + 12, height: diameter + 12)
                .scaleEffect(reduceMotion ? 1 : (animating ? 2.3 : 1))
                .opacity(reduceMotion ? 0.5 : (animating ? 0 : 0.8))
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: animating)

            RoundedRectangle(cornerRadius: radius, style: .continuous) // pulse
                .fill(OnboardingTheme.coralBright.opacity(0.16))
                .strokeBorder(OnboardingTheme.coralBright, lineWidth: 3)
                .frame(width: diameter + 12, height: diameter + 12)
                .scaleEffect(reduceMotion ? 1 : (animating ? 1.09 : 0.95))
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animating)

            Text(label) // bobbing bubble above
                .font(OnboardingFonts.nunito(13, 800))
                .foregroundStyle(.white)
                .padding(.vertical, 7).padding(.horizontal, 14)
                .background(OnboardingTheme.coralBright, in: Capsule())
                .shadow(color: OnboardingTheme.coralBright.opacity(0.55), radius: 10, y: 8)
                .fixedSize()
                .offset(y: -(diameter / 2 + 34) + (reduceMotion ? 0 : (animating ? -5 : 0)))
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animating)
        }
        .onAppear { animating = true }
        .allowsHitTesting(false)
    }
}
```

(`RoundedRectangle.strokeBorder` on the pulse needs fill+stroke layering: use `.background` for the fill copy if the compiler objects — same shape twice.)

- [ ] **Step 3: SocialPostFrame + AppShareSheetFrame + SystemShareSheetFrame**

Create `Support/TutorialFrames.swift`. All three are 390×830 static compositions; values from the HTML (tutorial section). Structure:

```swift
import SwiftUI

/// Phase 0 — the social video post with a coached share button.
struct SocialPostFrame: View {
    var body: some View {
        ZStack {
            Image("tutorialHotHoney").resizable().scaledToFill()
                .frame(width: 390, height: 830).clipped()
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120).frame(maxHeight: .infinity, alignment: .top)
            LinearGradient(colors: [.black.opacity(0.82), .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 300).frame(maxHeight: .infinity, alignment: .bottom)

            // Creator row (top-left, y≈64)
            HStack(spacing: 9) {
                Circle().fill(LinearGradient(colors: [OnboardingTheme.coralBright, Color(hex: 0xF0A24A)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                Text("thesapor").font(OnboardingFonts.bricolage(15, 700)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                Text("Follow").font(OnboardingFonts.nunito(11, 800)).foregroundStyle(.white)
                    .padding(.vertical, 2).padding(.horizontal, 10)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 18).padding(.top, 64)

            // Action rail (right, bottom 118), share icon coached
            VStack(spacing: 20) {
                railItem(MS.favoriteFill, 34, "44.7K")
                railItem(MS.modeComment, 33, "46")
                VStack(spacing: 4) {
                    ZStack {
                        MS.send.sized(33).foregroundStyle(.white)
                        CoachMark(diameter: 48)
                    }
                    .frame(width: 48, height: 48)
                    Text("14.8K").font(OnboardingFonts.nunito(12, 700)).foregroundStyle(.white)
                }
                railItem(MS.bookmark, 33, "Save")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12).padding(.bottom, 118)

            // Caption (bottom-left)
            VStack(alignment: .leading, spacing: 6) {
                Text("Crispy hot honey chicken bites 🍯🔥")
                    .font(.custom("Georgia-Italic", size: 21))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                Text("with cheesy ramen · 12 min · #weeknight")
                    .font(OnboardingFonts.nunito(13, 600)).foregroundStyle(.white.opacity(0.82))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 16).padding(.trailing, 80).padding(.bottom, 24)
        }
        .frame(width: 390, height: 830)
        .background(Color(hex: 0x0D0D0F))
    }

    private func railItem(_ glyph: MS, _ size: CGFloat, _ count: String) -> some View {
        VStack(spacing: 4) {
            glyph.sized(size).foregroundStyle(.white)
            Text(count).font(OnboardingFonts.nunito(12, 700)).foregroundStyle(.white)
        }
    }
}
```

`AppShareSheetFrame` (phase 1) — dimmed post backdrop + the app's share sheet sliding up, "Share to…" coached:

```swift
/// Phase 1 — the app's own share menu over the dimmed post.
struct AppShareSheetFrame: View {
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("tutorialHotHoney").resizable().scaledToFill()
                .frame(width: 390, height: 830).clipped()
            Color.black.opacity(0.58)

            VStack(spacing: 0) {
                Capsule().fill(Color(hex: 0x3C3C43).opacity(0.3))
                    .frame(width: 40, height: 5).padding(.top, 11)
                HStack(spacing: 9) {
                    MS.search.sized(19).foregroundStyle(Color(hex: 0x8A8A8E))
                    Text("Search").font(OnboardingFonts.nunito(14, 600))
                        .foregroundStyle(Color(hex: 0x8A8A8E))
                    Spacer()
                }
                .padding(.vertical, 11).padding(.horizontal, 13)
                .background(Color(hex: 0x787880).opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 18).padding(.top, 16)

                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle().fill(Color(hex: 0x3C3C43).opacity(0.1))
                            .frame(width: 54, height: 54)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 6)

                Rectangle().fill(Color(hex: 0x3C3C43).opacity(0.12)).frame(height: 1)
                    .padding(.horizontal, 18).padding(.top, 10)

                HStack(alignment: .top, spacing: 6) {
                    shareCircle(icon: MS.addCircle, tint: Color(hex: 0x2A2A2C), bg: .white, label: "Story", labelColor: Color(hex: 0x3A3A3C))
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().fill(.white)
                                .shadow(color: OnboardingTheme.greenDeep.opacity(0.3), radius: 4, y: 2)
                            MS.iosShare.sized(26).foregroundStyle(OnboardingTheme.greenDeep)
                            CoachMark(diameter: 54)
                        }
                        .frame(width: 54, height: 54)
                        Text("Share to…").font(OnboardingFonts.nunito(11, 700))
                            .foregroundStyle(OnboardingTheme.greenDeep)
                    }
                    .frame(maxWidth: .infinity)
                    shareCircle(icon: MS.link, tint: Color(hex: 0x2A2A2C), bg: .white, label: "Copy", labelColor: Color(hex: 0x3A3A3C))
                    shareCircle(icon: MS.chatFill, tint: .white, bg: Color(hex: 0x25D366), label: "WhatsApp", labelColor: Color(hex: 0x3A3A3C))
                }
                .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 22)
            }
            .background(Color(hex: 0xECEBED), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
            .shadow(color: .black.opacity(0.35), radius: 20, y: -12)
            .offset(y: shown ? 0 : 400)
            .animation(.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.4), value: shown)
        }
        .frame(width: 390, height: 830)
        .background(Color(hex: 0x0D0D0F))
        .onAppear { shown = true }
    }

    private func shareCircle(icon: MS, tint: Color, bg: Color, label: String, labelColor: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(bg).shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                icon.sized(26).foregroundStyle(tint)
            }
            .frame(width: 54, height: 54)
            Text(label).font(OnboardingFonts.nunito(11, 600)).foregroundStyle(labelColor)
        }
        .frame(maxWidth: .infinity)
    }
}
```

`SystemShareSheetFrame` (phase 2) — iOS share sheet with the link preview and Glutt coached:

```swift
/// Phase 2 — the system share sheet; Glutt is the coached target.
struct SystemShareSheetFrame: View {
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("tutorialHotHoney").resizable().scaledToFill()
                .frame(width: 390, height: 830).clipped()
            Color.black.opacity(0.58)

            VStack(spacing: 0) {
                Capsule().fill(Color(hex: 0x3C3C43).opacity(0.3))
                    .frame(width: 40, height: 5).padding(.top, 11)

                HStack(spacing: 12) { // link preview row
                    Image("tutorialHotHoney").resizable().scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Crispy hot honey chicken bites")
                            .font(OnboardingFonts.nunito(14, 700)).foregroundStyle(Color(hex: 0x1C1C1E))
                            .lineLimit(1)
                        Text("thesapor.com")
                            .font(OnboardingFonts.nunito(12, 600)).foregroundStyle(Color(hex: 0x8A8A8E))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12).padding(.horizontal, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16).padding(.top, 16)

                HStack(alignment: .top, spacing: 6) { // app targets
                    appTile(label: "AirDrop", labelColor: Color(hex: 0x3A3A3C)) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(RadialGradient(colors: [Color(hex: 0x4AA3FF), Color(hex: 0x0A6CF0)],
                                                 center: .init(x: 0.5, y: 0.42), startRadius: 0, endRadius: 40))
                        MS.wifiTethering.sized(27).foregroundStyle(.white)
                    }
                    VStack(spacing: 8) { // coached Glutt
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [Color(hex: 0x3C6B4B), Color(hex: 0x244430)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .shadow(color: OnboardingTheme.greenDeep.opacity(0.45), radius: 6, y: 4)
                            MS.skilletFill.sized(29).foregroundStyle(OnboardingTheme.creamText)
                            CoachMark(diameter: 56, ringRadius: 20)
                        }
                        .frame(width: 56, height: 56)
                        Text("Glutt").font(OnboardingFonts.nunito(11, 700))
                            .foregroundStyle(OnboardingTheme.greenDeep)
                    }
                    .frame(maxWidth: .infinity)
                    appTile(label: "Messages", labelColor: Color(hex: 0x3A3A3C)) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(colors: [Color(hex: 0x5BE36A), Color(hex: 0x12B32A)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        MS.chatBubbleFill.sized(27).foregroundStyle(.white)
                    }
                    appTile(label: "Mail", labelColor: Color(hex: 0x3A3A3C)) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(colors: [Color(hex: 0x4AA3FF), Color(hex: 0x0A6CF0)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        MS.mailFill.sized(26).foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 4)

                VStack(spacing: 0) { // actions list
                    listRow("Copy", MS.contentCopy)
                    Rectangle().fill(Color(hex: 0x3C3C43).opacity(0.12)).frame(height: 1)
                        .padding(.leading, 16)
                    listRow("Add to Reading List", MS.chromeReaderMode)
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 22)
            }
            .background(Color(hex: 0xECEBED), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
            .shadow(color: .black.opacity(0.35), radius: 20, y: -12)
            .offset(y: shown ? 0 : 400)
            .animation(.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.4), value: shown)
        }
        .frame(width: 390, height: 830)
        .background(Color(hex: 0x0D0D0F))
        .onAppear { shown = true }
    }

    private func appTile<Icon: View>(label: String, labelColor: Color, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 8) {
            ZStack { icon() }.frame(width: 56, height: 56)
            Text(label).font(OnboardingFonts.nunito(11, 600)).foregroundStyle(labelColor)
        }
        .frame(maxWidth: .infinity)
    }

    private func listRow(_ title: String, _ glyph: MS) -> some View {
        HStack {
            Text(title).font(OnboardingFonts.nunito(15, 600)).foregroundStyle(Color(hex: 0x1C1C1E))
            Spacer()
            glyph.sized(21).foregroundStyle(Color(hex: 0x1C1C1E))
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
    }
}
```


- [ ] **Step 4: Build + preview each frame**

`xcodegen generate`; `build_sim`. Add a temporary `#Preview` per frame wrapped in `MiniPhoneFrame` and eyeball against the prototype's phases 0–2 (drive the HTML with `startScreen="Tutorial"` + `startPhase`). Keep the previews.

- [ ] **Step 5: Commit**

```bash
git add Glutt/Features/Onboarding/Support/MiniPhoneFrame.swift Glutt/Features/Onboarding/Support/CoachMark.swift Glutt/Features/Onboarding/Support/TutorialFrames.swift Glutt.xcodeproj
git commit -m "feat(onboarding): mini-phone bezel, coach mark, walkthrough frames 0-2"
```

---

### Task 13: Importing + saved frames, tutorial screen assembly (screen 10)

**Files:**
- Modify: `Support/TutorialFrames.swift` (add ImportingFrame + SavedRecipeFrame)
- Rewrite: `Screens/ImportTutorialScreen.swift`
- Test: build + full flow run

**Interfaces:** Consumes `OnboardingFlowModel.tutorialTap()/completeImport()` (Task 6), `MiniPhoneFrame`, all five frames. `ImportTutorialScreen(flow:onImportNow:onFinish:)` signature unchanged.

- [ ] **Step 1: ImportingFrame + SavedRecipeFrame**

Append to `TutorialFrames.swift`:

```swift
/// Phase 3 — cream loader: 3 bouncing dots + sweeping bar. Auto-advance is the
/// screen's job (1800ms), not this view's.
struct ImportingFrame: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        VStack(spacing: 26) {
            HStack(spacing: 11) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(OnboardingTheme.greenDeep)
                        .frame(width: 14, height: 14)
                        .offset(y: reduceMotion ? 0 : (animating ? -13 : 0))
                        .opacity(reduceMotion ? 1 : (animating ? 1 : 0.45))
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16), value: animating)
                }
            }
            Text("Pulling out the recipe…")
                .font(OnboardingFonts.bricolage(22, 600))
                .foregroundStyle(OnboardingTheme.textHeading)
            ZStack(alignment: .leading) {
                Capsule().fill(OnboardingTheme.greenDeep.opacity(0.14))
                Capsule().fill(OnboardingTheme.greenDeep)
                    .frame(width: 180 * 0.42)
                    .offset(x: reduceMotion ? 52 : (animating ? 180 * 1.3 : -180 * 0.55))
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false), value: animating)
            }
            .frame(width: 180, height: 6)
            .clipShape(Capsule())
        }
        .frame(width: 390, height: 830)
        .background(OnboardingTheme.cream)
        .onAppear { animating = true }
    }
}

/// Phase 4 — the captured recipe with a popping "Saved" badge.
struct SavedRecipeFrame: View {
    @State private var badgeShown = false

    private static let ingredients = [
        "3 packs Otoki Cheesy Ramen", "1 lb chicken breast", "1 cup buttermilk",
        "Mozzarella + heavy cream", "Hot honey glaze",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 52)
            ZStack(alignment: .topLeading) {
                Image("tutorialHotHoney").resizable().scaledToFill()
                    .frame(width: 390, height: 230).clipped()
                LinearGradient(stops: [
                    .init(color: OnboardingTheme.cream, location: 0.02),
                    .init(color: .clear, location: 0.46),
                ], startPoint: .bottom, endPoint: .top)
                HStack(spacing: 6) {
                    MS.checkCircleFill.sized(16).foregroundStyle(.white)
                    Text("Saved to your recipes")
                        .font(OnboardingFonts.nunito(12.5, 800)).foregroundStyle(.white)
                }
                .padding(.vertical, 7).padding(.horizontal, 13)
                .background(OnboardingTheme.greenDeep.opacity(0.96), in: Capsule())
                .shadow(color: OnboardingTheme.greenDeep.opacity(0.35), radius: 8, y: 6)
                .padding(.top, 14).padding(.leading, 16)
                .scaleEffect(badgeShown ? 1 : 0.7)
                .opacity(badgeShown ? 1 : 0)
                .animation(.spring(duration: 0.5, bounce: 0.4), value: badgeShown)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Crispy hot honey chicken bites")
                    .font(OnboardingFonts.bricolage(25, 600)).kerning(-0.4)
                    .foregroundStyle(OnboardingTheme.textHeading)
                HStack(spacing: 16) {
                    meta(MS.schedule, "12 min")
                    meta(MS.fire, "540 cal")
                    meta(MS.restaurant, "Serves 4")
                }
                .padding(.top, 11)
                Text("INGREDIENTS")
                    .font(OnboardingFonts.nunito(11, 800)).kerning(0.7)
                    .foregroundStyle(OnboardingTheme.muted)
                    .padding(.top, 20).padding(.bottom, 11)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.ingredients, id: \.self) { item in
                        HStack(spacing: 10) {
                            MS.checkCircleFill.sized(16)
                                .foregroundStyle(OnboardingTheme.greenDeep.opacity(0.75))
                            Text(item).font(OnboardingFonts.nunito(14.5, 600))
                                .foregroundStyle(OnboardingTheme.textList)
                        }
                    }
                    Text("+ 4 more ingredients")
                        .font(OnboardingFonts.nunito(13.5, 600))
                        .foregroundStyle(OnboardingTheme.muted)
                        .padding(.leading, 26)
                }
            }
            .padding(.horizontal, 24).padding(.top, 34)
            Spacer(minLength: 0)
        }
        .frame(width: 390, height: 830, alignment: .top)
        .background(OnboardingTheme.cream)
        .onAppear { badgeShown = true }
    }

    private func meta(_ glyph: MS, _ text: String) -> some View {
        HStack(spacing: 5) {
            glyph.sized(17).foregroundStyle(OnboardingTheme.muted)
            Text(text).font(OnboardingFonts.nunito(13, 700)).foregroundStyle(OnboardingTheme.muted)
        }
    }
}
```

- [ ] **Step 2: Assemble ImportTutorialScreen**

Replace the Task 6 stub:

```swift
import SwiftUI

/// Screen 10 — the multi-phase import tutorial in a mini phone.
struct ImportTutorialScreen: View {
    @Bindable var flow: OnboardingFlowModel
    let onImportNow: () -> Void
    let onFinish: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    private static let headlines = [
        "Found a recipe you love?", "Open the share menu", "Pick Glutt",
        "Pulling out the recipe…", "That's it, it's saved!",
    ]
    private static let subheads = [
        "Tap the share button on the post.", "Tap your app's Share option.",
        "Choose Glutt from the share sheet.", "Reading ingredients, steps & macros.",
        "Glutt captured the full recipe for you.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 7) {
                OnboardingHeadline(Self.headlines[flow.tutPhase], size: 25)
                OnboardingSubhead(Self.subheads[flow.tutPhase], maxWidth: 272)
                    .font(OnboardingFonts.nunito(13.5, 600))
            }
            .frame(minHeight: 64, alignment: .top)

            GeometryReader { geo in
                let fit = min(1, (geo.size.height - 8) / 510)
                MiniPhoneFrame { phaseContent }
                    .scaleEffect(fit) // shrink uniformly on short devices only
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { handleTap() }
            }

            footer.padding(.top, flow.tutPhase == 4 ? 12 : 10)
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)   // design 80 − 54
        .padding(.bottom, 10)
        .task(id: flow.tutPhase == 3) {
            guard flow.tutPhase == 3 else { return }
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            flow.completeImport()
            Haptics.notify(.success)
        }
        .onChange(of: scenePhase) {
            // Returning mid-import: the .task(id:) above was cancelled on
            // background; re-arm by nudging the same mechanism.
            if scenePhase == .active, flow.tutPhase == 3 { flow.completeImport() }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch flow.tutPhase {
        case 0: SocialPostFrame().transition(.opacity)
        case 1: AppShareSheetFrame().transition(.opacity)
        case 2: SystemShareSheetFrame().transition(.opacity)
        case 3: ImportingFrame().transition(.opacity)
        default: SavedRecipeFrame().transition(.opacity)
        }
    }

    private func handleTap() {
        guard flow.tutPhase < 3 else { return }
        Haptics.impact(.light)
        withAnimation(.easeOut(duration: 0.3)) { _ = flow.tutorialTap() }
    }

    /// Design (`tWalk`): dots + skip on phases 0–2, nothing on 3, CTAs on 4.
    @ViewBuilder
    private var footer: some View {
        switch flow.tutPhase {
        case 0...2:
            VStack(spacing: 13) {
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i == flow.tutPhase ? OnboardingTheme.greenDeep : OnboardingTheme.warmBlack(0.18))
                            .frame(width: i == flow.tutPhase ? 22 : 7, height: 7)
                            .animation(.easeInOut(duration: 0.25), value: flow.tutPhase)
                    }
                }
                OnboardingTextLink(title: "Skip tutorial", action: onFinish)
            }
        case 3:
            Color.clear.frame(height: 56)
        default:
            VStack(spacing: 10) {
                OnboardingPrimaryButton(title: "Import my first recipe", height: 58, action: onImportNow)
                Button {
                    Haptics.impact(.light)
                    onFinish()
                } label: {
                    Text("I'll explore on my own")
                        .font(OnboardingFonts.bricolage(16, 600))
                        .foregroundStyle(OnboardingTheme.greenDeep)
                        .frame(maxWidth: .infinity).frame(height: 48)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 3: Full-flow behavioral run**

`build_run_sim` + `-onboarding`: welcome → … → tutorial; tap the phone 3× (post → app sheet → system sheet → loader), watch auto-advance ~1.8s later; verify dots track phases 0–2 and disappear on 3; "Skip tutorial" from phase 1 finishes; from phase 4, "I'll explore on my own" finishes into the app; re-force onboarding and take the "Import my first recipe" path — Recipes tab opens with the reel URL pre-filled.

- [ ] **Step 4: Screenshot phases 0–4 vs prototype; commit**

```bash
git add Glutt/Features/Onboarding/Support/TutorialFrames.swift Glutt/Features/Onboarding/Screens/ImportTutorialScreen.swift Glutt.xcodeproj
git commit -m "feat(onboarding): import tutorial mini-phone, all five phases 1:1"
```

---

### Task 14: Full-suite verification + visual QA pass

**Files:**
- Possibly small fixes anywhere in `Glutt/Features/Onboarding/`
- Delete: `ReminderScheduler.requestPermissionIfNeeded()` if now unreferenced (`grep -rn "requestPermissionIfNeeded" Glutt/`)

- [ ] **Step 1: Run the entire test suite** — `test_sim`; expected all green.
- [ ] **Step 2: Dead-reference sweep**

```bash
grep -rn "TutorialFlowModel\|WalkthroughFrame\|OnboardingScaffold\|tutorialShareSheet\|tutorialPost\|NutritionScreen\|NotificationPrimerScreen" Glutt GluttTests GluttShare || echo CLEAN
```
Expected: `CLEAN`.

- [ ] **Step 3: Side-by-side visual pass** — per `docs/superpowers/verify-screenshots/`: run the app (`-onboarding`) on the default simulator; screenshot all 11 screens + 5 tutorial phases; open the prototype HTML in Chrome (drive `startScreen`/`startPhase`); compare 1:1 (typography, colors, spacing, selection states, animations by eye). Fix any diffs; re-screenshot until matching.
- [ ] **Step 4: Fresh-install behavioral matrix** — erase sim; run WITHOUT `-onboarding` (fresh prefs → onboarding shows): complete with "Maybe later" → verify NO OS permission alert appears at any point and app lands normally; re-erase, complete via screen 9 "Allow" → real alert → grant → verify `plates-daily` pending notification exists (`xcrun simctl` or re-launch and check no re-prompt). Verify onboarding does NOT reappear on relaunch. Verify Superwall placement fires at finish (log or paywall in sandbox).
- [ ] **Step 5: Reduce Motion spot check** — enable Reduce Motion in sim Settings; verify coach marks/floats render static and screens still advance.
- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "chore(onboarding): visual QA fixes from prototype comparison"
```

---

## Self-review checklist (spec → plan)

- Spec §Decisions 1–9 → Tasks: 1 (fonts), 2 (icons), 6 (swap/no-skip/finish/RootView), 11 (screen 9 real prompt), 13 (import CTA), copy verbatim throughout. ✓
- Spec §Screens 0–10 → Tasks 7–13, chrome/transitions in Task 6. ✓
- Spec §Data → Tasks 5–6. §Integration 1–4 → Tasks 1, 5, 6. §Error handling → Tasks 4 (video), 11 (permission), 13 (timer re-arm). §Testing → Tasks 5, 6, 14. ✓
- Deletions (old screens/support/assets/tests) → Task 6 Step 6 + Task 14 sweep. ✓

