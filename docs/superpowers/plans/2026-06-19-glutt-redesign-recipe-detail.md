# Glutt Redesign — Recipe Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Restyle `RecipeDetailView` to the new look — full-bleed hero with back + favorite heart, an overlapping cream content sheet, a `SegmentedTabs` Ingredients | Steps switch (grocery-style pantry-aware checklist + numbered steps), Cook Mode as the primary action — while **keeping every existing feature**, reorganized: secondary actions into a hero overflow menu, the rest below the fold. Diet/allergy warnings stay visible (safety).

**Architecture:** One-file restructure of `Glutt/Features/Recipes/RecipeDetailView.swift`, reusing its existing state, computed props, and helpers (`pantryMatch`, `scale`, `toggleOwnership`, `dietWarnings`, `nutritionLine`, `notesSection`, `ratingSection`, `historySection`, `versionPicker`, `createVersion`, all sheets/covers). Adds `Recipe.isFavorite` and a small `IngredientCategoryStyle` helper (maps `GroceryCategory` → Phosphor glyph + tints + FRESH/PANTRY section). Consumes foundation `SegmentedTabs`, `IconChip`, `SectionLabel`, `StatPill`.

**Tech Stack:** SwiftUI, SwiftData (iOS 17), PhosphorSwift 2.1.0, scheme `Glutt`.

## Global Constraints

- **Build:** `xcodebuild build -scheme Glutt -destination 'id=1EEC6A07-E689-4149-ABC7-FF36F702BBF6' 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED| error:" | tail -8` → expect `** BUILD SUCCEEDED **`. Only on a DerivedData permission error re-run with the sandbox disabled.
- **New files** → `ruby Scripts/xcp_add.rb <relpath> Glutt`, commit the pbxproj change with the file.
- **Tokens/components:** use `Theme.*`, `Font.glutt*`, and foundation components (`SegmentedTabs`, `IconChip`, `SectionLabel`, `StatPill`). Phosphor names usable: `caretLeft`, `heart`, `dotsThree`, `basket`, `checkSquare`, `square`, `minus`, `plus`, `hamburger`, `plant`, `drop`, `bowlFood`, `clock`, `cellSignalMedium`, `star`.
- **No feature loss:** Cook Mode (+ PreCookChecklist), AI "Make it…", Add to plan, "Use what I have" (optimize), diet warnings, versions, nutrition, notes, rating, history, edit, save-as-version, collections, share, delete must all remain reachable. Diet warnings remain VISIBLE (not in overflow).
- **Reuse, don't reinvent:** keep `toggleOwnership(of:)`, `pantryMatch`, `GroceryListBuilder.add(...)`, `UnitConverter.display(...)`, `recipe.sortedSteps`, `createVersion()`, `CollectionsMenu` exactly. Servings scaling stays non-destructive (`displayServings`/`scale`).
- **Commits:** conventional; end body with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## File Structure

- Modify: `Glutt/Models/Recipe.swift` — add `isFavorite` (additive).
- Create: `Glutt/Features/Recipes/IngredientCategoryStyle.swift` — `GroceryCategory` → glyph/tint/section.
- Modify: `Glutt/Features/Recipes/RecipeDetailView.swift` — the view restructure.

---

### Task 1: Add `Recipe.isFavorite`

**Files:** Modify `Glutt/Models/Recipe.swift`

**Interfaces:** Produces `recipe.isFavorite: Bool` (default `false`; additive SwiftData property — no migration risk).

- [ ] **Step 1:** In the `Recipe` `@Model` class, next to `var rating: Int?` (line ~31), add:
```swift
    /// User-marked favorite (the detail-screen heart).
    var isFavorite: Bool = false
```
- [ ] **Step 2:** Build → `** BUILD SUCCEEDED **`.
- [ ] **Step 3:** Commit: `git commit -am "feat(model): add Recipe.isFavorite"`.

---

### Task 2: IngredientCategoryStyle helper

**Files:** Create `Glutt/Features/Recipes/IngredientCategoryStyle.swift`

**Interfaces:**
- Consumes: `GroceryCategorizer.categorize(_:) -> GroceryCategory`, `IconChip`, `Theme`.
- Produces:
  - `enum IngredientSection { case fresh, pantry }` with `var title: String` ("Fresh"/"Pantry").
  - `struct IngredientCategoryStyle { let section: IngredientSection; let chip: IconChip }` and a static `for(_ name: String) -> IngredientCategoryStyle` that categorizes the name and returns the section + a tinted `IconChip`.

- [ ] **Step 1:** Create the file:
```swift
import SwiftUI
import PhosphorSwift

/// FRESH vs PANTRY split for the ingredient checklist, derived from the same
/// canonical→GroceryCategory mapping the grocery list uses.
enum IngredientSection: Int, CaseIterable {
    case fresh, pantry
    var title: String { self == .fresh ? "Fresh" : "Pantry" }
}

enum IngredientCategoryStyle {
    /// Section + a tinted IconChip for an ingredient name.
    static func section(for name: String) -> IngredientSection {
        switch GroceryCategorizer.categorize(name) {
        case .produce, .meat, .dairy: return .fresh
        case .pantry, .frozen, .spices, .other: return .pantry
        }
    }

    @ViewBuilder
    static func chip(for name: String) -> some View {
        switch GroceryCategorizer.categorize(name) {
        case .meat:
            IconChip(icon: Ph.hamburger.fill, foreground: Theme.Colors.tomato, background: Theme.Colors.tomatoTint)
        case .produce:
            IconChip(icon: Ph.plant.fill, foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
        case .dairy:
            IconChip(icon: Ph.drop.fill, foreground: Theme.Colors.accent, background: Theme.Colors.successTint)
        case .pantry, .frozen, .spices, .other:
            IconChip(icon: Ph.bowlFood.fill, foreground: Theme.Colors.warning, background: Theme.Colors.warningTint)
        }
    }
}

#Preview("IngredientCategoryStyle chips") {
    HStack(spacing: 12) {
        IngredientCategoryStyle.chip(for: "ground beef")
        IngredientCategoryStyle.chip(for: "cucumber")
        IngredientCategoryStyle.chip(for: "jasmine rice")
    }
    .padding().background(Theme.Colors.background)
}
```
- [ ] **Step 2:** Register: `ruby Scripts/xcp_add.rb Glutt/Features/Recipes/IngredientCategoryStyle.swift Glutt`.
- [ ] **Step 3:** Build → `** BUILD SUCCEEDED **`. (If `GroceryCategorizer` isn't visible, confirm it's `enum GroceryCategorizer` in Services/GroceryListBuilder.swift — same module, no import needed.)
- [ ] **Step 4:** Commit file + pbxproj: `git commit -m "feat(recipes): add IngredientCategoryStyle (fresh/pantry + icon chips)"`.

---

### Task 3: Restyle RecipeDetailView (hero + segmented tabs + grocery checklist + reorganized extras)

**Files:** Modify `Glutt/Features/Recipes/RecipeDetailView.swift`

**Interfaces:** Consumes `SegmentedTabs`, `IngredientCategoryStyle`, `IconChip`, Phosphor, and ALL existing helpers (unchanged).

**KEEP UNCHANGED** (do not delete/edit): every `@State`, `init`, `scale`, `sessions`, `pantryMatch`, `dietWarnings`, `conflictColor`, `nutritionLine`, `notesSection`, `ratingSection`, `historySection`, `versionPicker`, `versionChips`, `toggleOwnership`, `nameColor`, `createVersion`, `formatDuration`, and the `CollectionsMenu` struct. Keep all `.sheet/.fullScreenCover/.confirmationDialog/.alert/.onAppear/.onDisappear` modifiers and the `floatingButtonSuppressors` bump.

**REPLACE / ADD** as follows.

- [ ] **Step 1:** Add `import PhosphorSwift` after `import SwiftUI`, and add a tab-selection state next to the other `@State` (after `isAdjusting`):
```swift
    @State private var selectedTab = 0   // 0 = Ingredients, 1 = Steps
```

- [ ] **Step 2:** Replace the entire `var body` (lines ~42-117) with the new structure (hero under the status bar, custom back/heart/overflow, overlapping content sheet, segmented tabs, Cook button). Keep ALL the trailing modifiers (`.fullScreenCover`/`.sheet`/`.confirmationDialog`/`.alert`/`.onAppear`/`.onDisappear`) exactly as they were — only the visible content + nav chrome change:
```swift
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroHeader
                contentSheet
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Theme.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { cookBar }
        // —— keep every existing modifier below this line unchanged ——
        .fullScreenCover(isPresented: $isCooking) {
            CookModeView(recipe: recipe, scale: scale)
        }
        .sheet(isPresented: $isShowingPreCookChecklist) {
            PreCookChecklistView(recipe: recipe) { isCooking = true }
        }
        .sheet(isPresented: $isShowingEditor) { RecipeEditorView(recipe: recipe) }
        .sheet(isPresented: $isAddingToPlan) {
            AddMealSheet(day: Calendar.current.startOfDay(for: .now), fixedRecipe: recipe)
        }
        .sheet(isPresented: $isOptimizing) { OptimizeRecipeView(recipe: recipe) }
        .sheet(isPresented: $isAdjusting) { AdjustRecipeView(recipe: recipe) }
        .confirmationDialog("Delete this recipe?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { context.delete(recipe); dismiss() }
        }
        .alert("Name this version", isPresented: $isNamingVersion) {
            TextField("e.g. High-protein version", text: $versionLabel)
            Button("Create") { createVersion() }
            Button("Cancel", role: .cancel) { versionLabel = "" }
        }
        .onAppear { router.floatingButtonSuppressors += 1 }
        .onDisappear { router.floatingButtonSuppressors -= 1 }
    }
```

- [ ] **Step 3:** Replace the old `hero` computed property (lines ~184-189) with the new `heroHeader` (full-bleed photo, top scrim, circular back/heart/overflow buttons):
```swift
    private var heroHeader: some View {
        ZStack(alignment: .top) {
            RecipeImageView(recipe: recipe)
                .frame(height: 340)
                .clipped()
            LinearGradient(colors: [Theme.Colors.textPrimary.opacity(0.35), .clear],
                           startPoint: .top, endPoint: .center)
                .frame(height: 340)
                .allowsHitTesting(false)
            HStack {
                circleButton(Ph.caretLeft.bold) { dismiss() }
                Spacer()
                circleButton(recipe.isFavorite ? Ph.heart.fill : Ph.heart.regular,
                             tint: recipe.isFavorite ? Theme.Colors.tomato : Theme.Colors.textPrimary) {
                    recipe.isFavorite.toggle()
                }
                overflowMenu
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, 56)
        }
        .frame(height: 340)
    }

    private func circleButton(_ icon: Image, tint: Color = Theme.Colors.textPrimary,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.resizable().scaledToFit().frame(width: 18, height: 18)
                .foregroundColor(tint)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 4:** Replace the old `actionRow` property (lines ~164-182) and the `toolbarMenu` property (lines ~558-578) with a single `overflowMenu` (consolidates Make it / Add to plan / Use what I have / Edit / Save as version / Collections / Share / Delete). Delete `actionRow` and `toolbarMenu` entirely; add:
```swift
    private var overflowMenu: some View {
        Menu {
            if LLMClient.isConfigured {
                Button("Make it…", systemImage: "sparkles") { isAdjusting = true }
            }
            Button("Add to plan", systemImage: "calendar.badge.plus") { isAddingToPlan = true }
            if !pantryMatch.missing.isEmpty {
                Button("Use what I have", systemImage: "wand.and.stars") { isOptimizing = true }
            }
            Divider()
            Button("Edit", systemImage: "pencil") { isShowingEditor = true }
            Button("Save as version", systemImage: "square.on.square") { isNamingVersion = true }
            CollectionsMenu(recipe: recipe)
            ShareLink(item: RecipeShareService.shareText(for: recipe, servings: displayServings)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
        } label: {
            Ph.dotsThree.bold.resizable().scaledToFit().frame(width: 18, height: 18)
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
```
(Also delete the now-unused `private var collectionsMenu` property if present — its body `CollectionsMenu(recipe:)` is now inlined above.)

- [ ] **Step 5:** Add the `contentSheet` — the overlapping cream sheet with title/kcal, meta, diet warnings (kept visible), segmented tabs, the tab body, and the below-fold extras:
```swift
    private var contentSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            titleBlock
            dietWarnings
            SegmentedTabs(titles: ["Ingredients", "Steps"], selection: $selectedTab)
            if selectedTab == 0 { ingredientsTab } else { stepsTab }
            // —— below the fold: kept, reorganized ——
            nutritionLine
            notesSection
            ratingSection
            versionPicker
            if !sessions.isEmpty { historySection }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.background)
        .clipShape(.rect(topLeadingRadius: 30, topTrailingRadius: 30))
        .offset(y: -24)            // overlap the hero
        .padding(.bottom, -24)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            (Text(recipe.title).font(.system(size: 26, weight: .heavy, design: .rounded))
                + Text(recipe.calories.map { ", \($0) Kcal" } ?? "")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary))
                .foregroundColor(Theme.Colors.textPrimary)
            if let summary = recipe.summary {
                Text(summary).font(.gluttBody).foregroundStyle(Theme.Colors.textSecondary)
            }
            HStack(spacing: 8) {
                StatPill.time(recipe.timeLabel)
                StatPill.difficulty(recipe.difficulty.label)
                if let rating = recipe.rating { StatPill.rating("\(rating)") }
                Spacer(minLength: 0)
            }
            if let confidence = recipe.importConfidence, confidence < 0.85 {
                ConfidenceBadge(confidence: confidence)
            }
        }
    }
```

- [ ] **Step 6:** Add the `stepsTab` (numbered green circles — same idea as the old `stepsSection`, lighter container) and DELETE the old `stepsSection`:
```swift
    private var stepsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(recipe.sortedSteps) { step in
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Text("\(step.index + 1)")
                        .font(.gluttHeadline).foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.Colors.accent).clipShape(Circle())
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(step.text).font(.gluttBody).foregroundStyle(Theme.Colors.textPrimary)
                        if let duration = step.durationSeconds {
                            Label(formatDuration(duration), systemImage: "timer")
                                .font(.gluttCaption.weight(.medium)).foregroundStyle(Theme.Colors.warning)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
```

- [ ] **Step 7:** Add the `ingredientsTab` — the grocery-style sectioned checklist with the servings stepper, FRESH/PANTRY sections (`IngredientCategoryStyle`), checkbox = "in your kitchen", and the "Add N missing to groceries" footer. DELETE the old `ingredientsSection`, `servingsAndUnits`, `ownershipIcon`. Keep `toggleOwnership` and `nameColor`:
```swift
    private var ingredientsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            servingsStepper
            ForEach(IngredientSection.allCases, id: \.self) { section in
                let rows = sortedIngredients.filter { IngredientCategoryStyle.section(for: $0.name) == section }
                if !rows.isEmpty {
                    SectionLabel(text: section.title)
                    VStack(spacing: 0) {
                        ForEach(rows) { ingredient in
                            ingredientRow(ingredient)
                            if ingredient !== rows.last { Divider().overlay(Theme.Colors.border) }
                        }
                    }
                }
            }
            if !pantryMatch.missing.isEmpty {
                Button {
                    GroceryListBuilder.add(ingredients: pantryMatch.missing, from: recipe,
                                           existing: groceryItems, context: context)
                } label: {
                    Label("Add \(pantryMatch.missing.count) missing to groceries", systemImage: "basket.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttPrimary)
                .padding(.top, Theme.Spacing.sm)
            }
        }
    }

    private var sortedIngredients: [RecipeIngredient] {
        recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var servingsStepper: some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: 14) {
                Button { if displayServings > 1 { displayServings -= 1 } } label: {
                    Ph.minus.bold.resizable().scaledToFit().frame(width: 14, height: 14)
                }
                Text("\(displayServings) serv").font(.gluttHeadline).monospacedDigit()
                Button { if displayServings < 24 { displayServings += 1 } } label: {
                    Ph.plus.bold.resizable().scaledToFit().frame(width: 14, height: 14)
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.card)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: 1))
            Picker("Units", selection: $unitSystem) {
                ForEach(MeasurementSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).tint(Theme.Colors.accent)
            Spacer()
        }
    }

    private func ingredientRow(_ ingredient: RecipeIngredient) -> some View {
        let owned = pantryMatch.owned.contains { $0 === ingredient }
        return HStack(spacing: Theme.Spacing.md) {
            IngredientCategoryStyle.chip(for: ingredient.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .strikethrough(owned, color: Theme.Colors.textSecondary)
                    .foregroundStyle(owned ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                HStack(spacing: 4) {
                    if let display = UnitConverter.display(quantity: ingredient.quantity, unit: ingredient.unit,
                                                           scale: scale, system: unitSystem) {
                        Text(display)
                    }
                    if owned { Text("· in your kitchen") }
                    else if ingredient.isOptional { Text("· optional") }
                }
                .font(.gluttCaption).foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button { toggleOwnership(of: ingredient) } label: {
                (owned ? Ph.checkSquare.fill : Ph.square.regular)
                    .resizable().scaledToFit().frame(width: 26, height: 26)
                    .foregroundColor(owned ? Theme.Colors.accent : Theme.Colors.border)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
```

- [ ] **Step 8:** Replace the old Cook `.safeAreaInset(edge: .bottom)` button (it was inline in `body`, now referenced as `cookBar`). Add:
```swift
    private var cookBar: some View {
        Button {
            if pantryMatch.missing.isEmpty { isCooking = true } else { isShowingPreCookChecklist = true }
        } label: {
            Label("Cook", systemImage: "frying.pan").frame(maxWidth: .infinity)
        }
        .buttonStyle(.gluttPrimary)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Colors.background.opacity(0.95))
    }
```

- [ ] **Step 9:** Build → `** BUILD SUCCEEDED **`. Resolve any leftover references to deleted properties (`hero`, `actionRow`, `toolbarMenu`, `collectionsMenu`, `ingredientsSection`, `servingsAndUnits`, `stepsSection`, `ownershipIcon`) — they must all be gone or replaced.
- [ ] **Step 10:** Commit: `git commit -am "feat(redesign): Recipe Detail — hero, Ingredients/Steps tabs, grocery checklist, overflow"`.

---

## Self-Review

**Spec coverage:** full-bleed hero + back + favorite heart (Task 1 + 3) ✓; overlapping cream sheet + title/kcal (3) ✓; SegmentedTabs Ingredients|Steps (3) ✓; numbered steps (3) ✓; grocery-style FRESH/PANTRY checklist with "in your kitchen" + servings stepper + "Add N missing to groceries", seeded from PantryMatcher (2 + 3) ✓; nutrition removed from inline but kept below-fold (3) ✓; all features reorganized into overflow/below-fold, Cook primary, diet warnings visible (3) ✓.

**Placeholders:** none. **Type consistency:** `selectedTab: Int` ↔ `SegmentedTabs(selection: Binding<Int>)`; `toggleOwnership`/`pantryMatch`/`GroceryListBuilder.add`/`UnitConverter.display` reused with existing signatures; `IngredientSection`/`IngredientCategoryStyle` from Task 2.

**Risks:**
- Hero under status bar (`.ignoresSafeArea(edges:.top)` + hidden nav bar) — verify the back/heart/overflow row clears the notch (`.padding(.top, 56)`); screenshot.
- The content sheet `.offset(y:-24)` overlap can clip the segmented control's tap targets at the seam — verify in screenshot.
- `Text(...) + Text(...)` concatenation for title+kcal must keep one rounded font; verify kcal renders muted.
- Deleting `toolbarMenu` removes the nav-bar share/⋯; confirm Share + all menu actions now live in `overflowMenu`.
