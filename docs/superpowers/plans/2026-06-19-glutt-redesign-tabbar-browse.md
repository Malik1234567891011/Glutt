# Glutt Redesign — Tab Bar + Browse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the bottom tab bar (dark, rounded-top, Phosphor glyphs, 5 tabs + floating +) and the Browse/Recipes screen (new `RecipeCard`, tag-driven category row, count header, grid toggle) onto the redesign foundation, with zero loss of existing Browse behavior (search, filters, collections, sort, import).

**Architecture:** Consumes the Phase-1 foundation (tokens, Phosphor, `StatPill`, `CategoryCircle`, etc.). The tab bar keeps `TabView(selection:)` for content/state but hides the native bar and overlays a custom `GluttTabBar` (no navigation fork). Browse stays a `NavigationStack` + `ScrollView`; the recipe list gains a list/grid toggle and a category row derived from existing tag-filter state. `RecipeCard` is restyled in place (its `pantryMatch` API is preserved).

**Tech Stack:** SwiftUI, SwiftData (iOS 17), PhosphorSwift 2.1.0, scheme `Glutt`.

## Global Constraints

- **Build:** `xcodebuild build -scheme Glutt -destination 'id=1EEC6A07-E689-4149-ABC7-FF36F702BBF6' 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED| error:" | tail -8` → expect `** BUILD SUCCEEDED **`. Run normally; only on a DerivedData "operation not permitted" error re-run with the sandbox disabled.
- **New files** must be registered: `ruby Scripts/xcp_add.rb <relpath> Glutt`, and the pbxproj change committed with the file.
- **Tokens over literals:** use `Theme.Colors`/`Theme.Radius`/`Font.glutt*` and the foundation components; add any new shared constant to `Theme`, don't inline hex/radii.
- **Phosphor:** `Ph.<case>.<weight>` → `Image` (already resizable), template-rendered (tint with `.foregroundColor`). Confirmed names usable here: `house`, `bookOpen`, `calendarBlank`, `cookingPot`, `chartLineUp`, `squaresFour`, `slidersHorizontal`, `forkKnife`, `flame`, `star`, `clock`, `cellSignalMedium`, `plus`, `basket`.
- **No behavior regressions:** Browse search, tag/cooked/cleanup filters, collections row, sort menu, import/create menu, pantry-match, deep-link open, and capture (+) must all still work.
- **Commits:** conventional-commit; end body with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Tab order (unchanged):** today, recipes, plan, kitchen, progress. Tab→Phosphor: today `house`, recipes `bookOpen`, plan `calendarBlank`, kitchen `cookingPot`, progress `chartLineUp`. Active tab uses `.fill` weight + cream label + light-green glyph; inactive uses `.regular` + `tabInactive`.

## File Structure

- Modify: `Glutt/DesignSystem/Theme.swift` — add tab + tag tokens.
- Create: `Glutt/DesignSystem/Components/GluttTabBar.swift` — the custom dark bar.
- Modify: `Glutt/App/RootView.swift` — hide native bar, overlay `GluttTabBar`, reposition the floating +.
- Modify: `Glutt/DesignSystem/Components/CategoryCircle.swift` — generalize image to a ViewBuilder (keep the `Image` convenience) so it can wrap `RecipeImageView`.
- Modify: `Glutt/DesignSystem/Components/RecipeCard.swift` — restyle media block + StatPill row.
- Modify: `Glutt/Features/Recipes/RecipesView.swift` — category row, count/grid/filter header, grid mode.

---

### Task 1: Tab + tag color/radius tokens

**Files:** Modify `Glutt/DesignSystem/Theme.swift`

**Interfaces:** Produces `Theme.Colors.tabInactive`, `Theme.Colors.activeTabGlyph`; `Theme.Radius.tabBarTop` (30), `Theme.Radius.tag` (13).

- [ ] **Step 1:** In `Theme.Colors`, after `mutedLabel`, add:
```swift
        /// Inactive bottom-tab glyph + label on the dark bar. (#928377)
        static let tabInactive = Color(red: 0.573, green: 0.514, blue: 0.467)
        /// Active bottom-tab glyph (light green) on the dark bar. (#CFE6CC)
        static let activeTabGlyph = Color(red: 0.812, green: 0.902, blue: 0.800)
```
- [ ] **Step 2:** In `Theme.Radius`, after `segment`, add:
```swift
        /// Dark tab bar top corners.
        static let tabBarTop: CGFloat = 30
        /// Card tag pill (top-right of media).
        static let tag: CGFloat = 13
```
- [ ] **Step 3:** Build → `** BUILD SUCCEEDED **` (additive).
- [ ] **Step 4:** Commit: `git commit -am "feat(design): add tab + tag tokens"`.

---

### Task 2: GluttTabBar component

**Files:** Create `Glutt/DesignSystem/Components/GluttTabBar.swift`

**Interfaces:**
- Consumes: `AppTab` (App/Router.swift), `Theme.Colors.{textPrimary,creamText,activeTabGlyph,tabInactive}`, `Theme.Radius.tabBarTop`.
- Produces: `GluttTabBar(selection: Binding<AppTab>)` — a full-width dark bar with rounded top, 5 Phosphor tabs, that sets `selection` on tap. Maps each `AppTab` to its Phosphor glyph internally (keeps Phosphor out of the model-layer `Router`).

- [ ] **Step 1:** Create the file:
```swift
import SwiftUI
import PhosphorSwift

/// The redesigned bottom tab bar: a full-width dark bar with rounded top corners
/// and Phosphor glyphs. Drives `Router.selectedTab` via the binding — it does NOT
/// own navigation; the host `TabView` still switches content.
struct GluttTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isActive = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        glyph(for: tab, active: isActive)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundColor(isActive ? Theme.Colors.activeTabGlyph : Theme.Colors.tabInactive)
                        Text(tab.label)
                            .font(.system(size: 11, weight: isActive ? .bold : .semibold, design: .rounded))
                            .foregroundColor(isActive ? Theme.Colors.creamText : Theme.Colors.tabInactive)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 6)
        .background(
            Theme.Colors.textPrimary
                .clipShape(.rect(topLeadingRadius: Theme.Radius.tabBarTop,
                                 topTrailingRadius: Theme.Radius.tabBarTop))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func glyph(for tab: AppTab, active: Bool) -> Image {
        switch tab {
        case .today:    return active ? Ph.house.fill : Ph.house.regular
        case .recipes:  return active ? Ph.bookOpen.fill : Ph.bookOpen.regular
        case .plan:     return active ? Ph.calendarBlank.fill : Ph.calendarBlank.regular
        case .kitchen:  return active ? Ph.cookingPot.fill : Ph.cookingPot.regular
        case .progress: return active ? Ph.chartLineUp.fill : Ph.chartLineUp.regular
        }
    }
}

#Preview("GluttTabBar") {
    struct Demo: View {
        @State private var tab: AppTab = .recipes
        var body: some View {
            VStack { Spacer(); GluttTabBar(selection: $tab) }
                .background(Theme.Colors.background)
        }
    }
    return Demo()
}
```
- [ ] **Step 2:** Register: `ruby Scripts/xcp_add.rb Glutt/DesignSystem/Components/GluttTabBar.swift Glutt`.
- [ ] **Step 3:** Build → `** BUILD SUCCEEDED **`. (If any Phosphor name fails, it's confirmed present — re-check spelling.)
- [ ] **Step 4:** Commit file + pbxproj: `git commit -m "feat(design): add GluttTabBar component"`.

---

### Task 3: Wire GluttTabBar into RootView

**Files:** Modify `Glutt/App/RootView.swift`

**Interfaces:** Consumes `GluttTabBar`. The native `TabView` bar is hidden; `GluttTabBar` overlays the bottom and the floating + sits above it.

- [ ] **Step 1:** Hide the native tab bar by adding the modifier to the tab content and drop the `.tabItem`/`.tint`. Replace the `TabView { ForEach ... }` block (currently lines ~19-28) with:
```swift
            TabView(selection: $router.selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    tabContent(for: tab)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(tab)
                }
            }
```
- [ ] **Step 2:** Add the custom bar as the bottom overlay. Immediately after the `TabView { ... }` closing (before the `if router.floatingButtonSuppressors == 0` block), add:
```swift
            GluttTabBar(selection: $router.selectedTab)
```
(The enclosing `ZStack(alignment: .bottom)` pins it to the bottom; its background already `ignoresSafeArea(edges: .bottom)`.)
- [ ] **Step 3:** Reposition the floating + so it clears the dark bar. In `captureButton`, change `.offset(y: -34)` to `.offset(y: -78)` (lifts it above the ~64pt bar). Leave the rest of `captureButton` as-is.
- [ ] **Step 4:** Give scrollable tab content room so nothing hides behind the bar. This plan only owns Recipes; in Task 6 we set its bottom content margin. Other tabs are handled in their own later plans — acceptable for now (their content simply ends a little lower). Note this as DONE_WITH_CONCERNS if any non-Recipes tab's last row is clearly occluded in the build screenshot.
- [ ] **Step 5:** Build → `** BUILD SUCCEEDED **`.
- [ ] **Step 6: Visual verify (required for this task).** Boot the sim and screenshot Recipes:
```
xcrun simctl boot 1EEC6A07-E689-4149-ABC7-FF36F702BBF6 2>/dev/null; \
xcrun simctl install booted "$(xcodebuild -showBuildSettings -scheme Glutt -destination 'id=1EEC6A07-E689-4149-ABC7-FF36F702BBF6' 2>/dev/null | awk -F' = ' '/ TARGET_BUILD_DIR /{d=$2} / FULL_PRODUCT_NAME /{p=$2} END{print d"/"p}')"; \
xcrun simctl launch booted com.* 2>/dev/null; sleep 4; \
xcrun simctl io booted screenshot /tmp/glutt_tabbar.png
```
(Adjust the bundle id from the build settings `PRODUCT_BUNDLE_IDENTIFIER` if the wildcard launch fails.) Confirm: dark rounded-top bar, 5 Phosphor tabs, Recipes active (cream label / light-green glyph), floating + clearing the bar. Attach `/tmp/glutt_tabbar.png` observations to the report.
- [ ] **Step 7:** Commit: `git commit -am "feat(redesign): dark GluttTabBar in RootView, reposition capture button"`.

---

### Task 4: Generalize CategoryCircle to wrap any image source

**Files:** Modify `Glutt/DesignSystem/Components/CategoryCircle.swift`

**Interfaces:**
- Produces (additive, source-compatible): a generic `CategoryCircle<Thumb: View>` whose image area is a `@ViewBuilder thumb: () -> Thumb`, PLUS a convenience `init` taking `image: Image` (so the existing preview and any `Image` caller keep working). Browse will pass `{ RecipeImageView(recipe: r) }`.

- [ ] **Step 1:** Replace the whole `struct CategoryCircle` with the generic form (keeps active 66 / inactive 50, ring, sparkle, label exactly as before, but the thumbnail is injected):
```swift
import SwiftUI
import PhosphorSwift

/// A circular category thumbnail + label for the Browse category row.
/// Active: 66pt with a herb-green ring and a sparkle accent. Inactive: 50pt, dimmed.
/// The thumbnail is injected so callers can pass a static `Image` or a live
/// `RecipeImageView` (asset/photo/remote).
struct CategoryCircle<Thumb: View>: View {
    let label: String
    var isActive: Bool = false
    var action: () -> Void = {}
    @ViewBuilder var thumb: () -> Thumb

    private var diameter: CGFloat { isActive ? 66 : 50 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    thumb()
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.Colors.accent, lineWidth: isActive ? 3 : 0))
                        .opacity(isActive ? 1 : 0.78)
                    Ph.sparkle.fill
                        .resizable().scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundColor(Theme.Colors.warning)
                        .offset(x: 4, y: -4)
                        .opacity(isActive ? 1 : 0)
                }
                .frame(width: 66, height: 66)            // reserve max slot → no sibling reflow on activate
                Text(label)
                    .font(.system(size: isActive ? 14 : 13, weight: isActive ? .heavy : .bold, design: .rounded))
                    .foregroundColor(isActive ? Theme.Colors.textPrimary : Theme.Colors.mutedLabel)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
    }
}

/// Convenience for a static image thumbnail.
extension CategoryCircle where Thumb == _CategoryImageThumb {
    init(image: Image, label: String, isActive: Bool = false, action: @escaping () -> Void = {}) {
        self.init(label: label, isActive: isActive, action: action) { _CategoryImageThumb(image: image) }
    }
}

struct _CategoryImageThumb: View {
    let image: Image
    var body: some View { image.resizable().scaledToFill() }
}

#Preview("CategoryCircle") {
    HStack(spacing: 16) {
        CategoryCircle(image: Image(systemName: "photo"), label: "Breakfast")
        CategoryCircle(image: Image(systemName: "photo"), label: "Lunch", isActive: true)
        CategoryCircle(image: Image(systemName: "photo"), label: "Dinner")
    }
    .padding().background(Theme.Colors.background)
}
```
- [ ] **Step 2:** Build → `** BUILD SUCCEEDED **`. The existing `Image`-based preview must still compile via the convenience init.
- [ ] **Step 3:** Commit: `git commit -am "refactor(design): generalize CategoryCircle thumbnail to a ViewBuilder"`.

---

### Task 5: Restyle RecipeCard (media block + StatPill row)

**Files:** Modify `Glutt/DesignSystem/Components/RecipeCard.swift`

**Interfaces:**
- Preserves the public API: `RecipeCard(recipe:pantryMatch:)`.
- Consumes: `StatPill`, `RecipeImageView`, `Theme.Radius.{cardLarge,photo,tag}`, `Theme.Colors.{sagePanel,peachPanel,card}`.
- Behavior: media block height 148, radius `photo`(18), panel-tint background (sage/peach chosen by a stable hash of the recipe id), photo left at ~63% width, tag pill (first tag) top-right; below: title (21 heavy), summary (secondary), StatPill row = time + difficulty + (rating if set) and the pantry-match as a green StatPill when provided.

- [ ] **Step 1:** Replace the whole `struct RecipeCard` body with the restyle (keep the struct's two stored properties `recipe` and `pantryMatch`):
```swift
    private var panelTint: Color {
        // stable per-recipe pick from the rotating decorative set
        abs(recipe.persistentModelID.hashValue) % 2 == 0 ? Theme.Colors.sagePanel : Theme.Colors.peachPanel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            mediaBlock
            Text(recipe.title)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
            if let summary = recipe.summary, !summary.isEmpty {
                Text(summary)
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            statRow
        }
        .padding(12)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous)
                .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Theme.Colors.textPrimary.opacity(0.07), radius: 10, x: 0, y: 3)
    }

    private var mediaBlock: some View {
        ZStack(alignment: .topTrailing) {
            panelTint
            HStack(spacing: 0) {
                RecipeImageView(recipe: recipe)
                    .containerRelativeFrame(.horizontal) { w, _ in w * 0.63 }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.photo, style: .continuous))
                Spacer(minLength: 0)
            }
            if let tag = recipe.tags.first {
                tagPill(tag)
                    .padding(8)
            }
        }
        .frame(height: 148)
        .frame(maxWidth: .infinity)
        .background(panelTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.photo, style: .continuous))
    }

    private func tagPill(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Ph.forkKnife.regular.resizable().scaledToFit().frame(width: 11, height: 11)
            Text(tag).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tag, style: .continuous))
    }

    @ViewBuilder private var statRow: some View {
        HStack(spacing: 8) {
            StatPill.time("\(recipe.estimatedMinutes) min")
            StatPill.difficulty(recipe.difficulty.label)
            if let rating = recipe.rating {
                StatPill.rating("\(rating)")
            }
            if let pantryMatch, pantryMatch.total > 0 {
                StatPill(icon: Ph.basket.fill,
                         text: "\(pantryMatch.owned)/\(pantryMatch.total)",
                         foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
            }
            Spacer(minLength: 0)
        }
    }
```
Add `import PhosphorSwift` at the top of the file (after `import SwiftUI`). Delete the old `recipeImage` and `ingredientMatchIndicator` helpers (replaced by `mediaBlock`/`statRow`).
- [ ] **Step 2:** Build → `** BUILD SUCCEEDED **`. Confirm `recipe.estimatedMinutes`, `recipe.difficulty.label`, `recipe.rating`, `recipe.summary`, `recipe.tags` exist (they do per the model); if `estimatedMinutes` isn't found, use `totalMinutes`.
- [ ] **Step 3:** Commit: `git commit -am "feat(redesign): restyle RecipeCard with panel-tint media and StatPill row"`.

---

### Task 6: Browse header, category row, and grid/list mode

**Files:** Modify `Glutt/Features/Recipes/RecipesView.swift`

**Interfaces:** Consumes `CategoryCircle`, `RecipeImageView`, `StatPill` (via card), `SectionLabel` (optional), Phosphor. Adds `@State private var isGrid` and a `categoryTags` helper. Reuses existing `selectedFilter`/`visibleRecipes`/`filterChips`/search/collections/sort.

- [ ] **Step 1:** Add grid state near the other `@State` (after `sortOrder`):
```swift
    @State private var isGrid = false
```
- [ ] **Step 2:** Add a category helper after `filterChips` — the top tags (excluding the two special chips) with a representative recipe photo each:
```swift
    /// Tag-driven categories: the most-used real tags, each with a representative recipe.
    private var categoryTags: [(tag: String, recipe: Recipe)] {
        let special: Set = [Self.cookedBeforeFilter, Self.needsCleanupFilter]
        return filterChips
            .filter { !special.contains($0) }
            .prefix(8)
            .compactMap { tag in
                libraryRecipes.first(where: { $0.tags.contains(tag) }).map { (tag, $0) }
            }
    }
```
- [ ] **Step 3:** Add the category row + count/controls header above `ChipRow`. Replace the `ChipRow(labels: filterChips, selection: $selectedFilter)` line with:
```swift
                    if !categoryTags.isEmpty {
                        categoryRow
                    }
                    countHeader
                    ChipRow(labels: filterChips, selection: $selectedFilter)
```
- [ ] **Step 4:** Add the new subviews after `collectionsRow` (before the closing `}` of the struct, alongside other private vars):
```swift
    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(categoryTags, id: \.tag) { item in
                    CategoryCircle(
                        label: item.tag,
                        isActive: selectedFilter == item.tag,
                        action: { selectedFilter = (selectedFilter == item.tag) ? nil : item.tag }
                    ) {
                        RecipeImageView(recipe: item.recipe)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }

    private var countHeader: some View {
        HStack {
            Text("^[\(visibleRecipes.count) recipe](inflect: true)")
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Button { isGrid.toggle() } label: {
                Ph.squaresFour.fill.resizable().scaledToFit().frame(width: 18, height: 18)
                    .foregroundStyle(isGrid ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
```
- [ ] **Step 5:** Make the non-search list honor grid mode. Replace the `LazyVStack { ForEach(visibleRecipes) ... }` block (the `else` branch under `if visibleRecipes.isEmpty`) with a switch on `isGrid`:
```swift
                        } else if isGrid {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.md),
                                                GridItem(.flexible(), spacing: Theme.Spacing.md)],
                                      spacing: Theme.Spacing.md) {
                                ForEach(visibleRecipes) { recipe in
                                    recipeLink(recipe, reasons: [])
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        } else {
                            LazyVStack(spacing: Theme.Spacing.md) {
                                ForEach(visibleRecipes) { recipe in
                                    recipeLink(recipe, reasons: [])
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
```
- [ ] **Step 6:** Add `import PhosphorSwift` at the top (after `import SwiftUI`). Keep `.contentMargins(.bottom, 56, ...)` (already present) so the list clears the new tab bar; bump it to `76` to clear the taller dark bar.
- [ ] **Step 7:** Build → `** BUILD SUCCEEDED **`.
- [ ] **Step 8: Visual verify.** Rebuild/reinstall and screenshot (same approach as Task 3 Step 6) to `/tmp/glutt_browse.png`. Confirm: category circles with photos (active ringed), "N recipes" header + grid toggle, restyled cards (panel-tint media, stat pills), tab bar. Toggle grid in code preview if needed. Note observations in the report.
- [ ] **Step 9:** Commit: `git commit -am "feat(redesign): Browse category row, count/grid header, grid mode"`.

---

## Self-Review

**Spec coverage (Browse + tab-bar slice of the design spec):**
- Dark 5-tab bar, Phosphor glyphs, rounded top, floating + retained → Tasks 1-3. ✓
- Tag-driven circular category row → Tasks 4, 6. ✓
- Count header + grid toggle + filter (existing sort/filter menu retained) → Task 6. ✓
- Restyled RecipeCard (panel-tint media, photo, tag pill, StatPill row, pantry-match kept) → Task 5. ✓
- No behavior regression (search/filters/collections/sort/import/deep-link/capture) → preserved by additive edits; verified by build + screenshots. ✓
- Deferred to later plans: Recipe Detail, Onboarding, other tabs' content margins (noted in Task 3 Step 4).

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** `CategoryCircle` generic + `image:` convenience both compile (Task 4); `RecipeCard(recipe:pantryMatch:)` API unchanged (Task 5); `pantryMatch.owned/.total` tuple matches existing call site in `recipeLink` (`(match.ownedCount, match.totalCount)`); `AppTab` cases match `glyph(for:)` switch (Task 2).

**Risks:**
- Native tab-bar hiding (`.toolbar(.hidden, for: .tabBar)`) + custom overlay can leave a gap or double bar on some layouts → Task 3 screenshot catches it; fallback is `UITabBar.appearance().isHidden = true` at app init.
- `containerRelativeFrame` 0.63 width inside the card may need a `GeometryReader` fallback if it measures the screen instead of the card → verify in Task 5/6 screenshot; fallback to `GeometryReader`.
- `recipe.estimatedMinutes` vs `totalMinutes` naming → Task 5 Step 2 notes the fallback.
