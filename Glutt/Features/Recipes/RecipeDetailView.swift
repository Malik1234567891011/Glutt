import SwiftData
import SwiftUI

/// Recipe detail, redesigned to `Glutt Screens.dc.html` (screen "Recipe detail"):
/// a tall hero, a rounded cream content sheet with title/kcal, stats, tags, an
/// adapt row, an Ingredients/Steps segmented control, grouped food-icon ingredient
/// rows with pantry match, an "add missing to groceries" button, and a pinned
/// "Cook with Polly" bar. Extras (tools, macros, notes, rating, versions, history)
/// move into the more_horiz overflow's "More details" sheet — kept, off the surface.
struct RecipeDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @Query private var pantryItems: [PantryItem]
    @Query private var groceryItems: [GroceryItem]
    @Query private var ownedTools: [KitchenTool]
    @Bindable var recipe: Recipe

    @State private var displayServings: Int
    @State private var unitSystem: MeasurementSystem = .original
    @State private var isShowingEditor = false
    @State private var isConfirmingDelete = false
    @State private var isNamingVersion = false
    @State private var versionLabel = ""
    @State private var isCooking = false
    @State private var isShowingPreCookChecklist = false
    @State private var isShowingCookBriefing = false
    @State private var isOptimizing = false
    @State private var isAdjusting = false
    @State private var isShowingDetails = false
    @State private var substituteTarget: DietGuard.Conflict?
    @State private var selectedTab = 0   // 0 = Ingredients, 1 = Steps

    init(recipe: Recipe) {
        self.recipe = recipe
        _displayServings = State(initialValue: recipe.servings)
    }

    private var scale: Double {
        guard recipe.servings > 0 else { return 1 }
        return Double(displayServings) / Double(recipe.servings)
    }

    private var sessions: [CookSession] { recipe.cookSessions(in: context) }

    private var pantryMatch: PantryMatcher.MatchResult {
        PantryMatcher.match(recipe: recipe, pantry: pantryItems)
    }

    private var requiredTools: [String] {
        let text = ([recipe.title, recipe.summary ?? ""] + recipe.steps.map(\.text)).joined(separator: " ")
        return KitchenToolCatalog.requiredTools(inText: text)
    }

    private var headerNutrition: (calories: Int, protein: Int)? {
        if let c = recipe.calories, let p = recipe.proteinGrams { return (c, p) }
        if let est = NutritionEstimator.estimate(for: recipe) { return (est.calories, est.proteinGrams) }
        return nil
    }

    private var sortedIngredients: [RecipeIngredient] {
        recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }
    }

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
        .fullScreenCover(isPresented: $isCooking) { CookModeView(recipe: recipe, scale: scale) }
        .fullScreenCover(isPresented: $isShowingCookBriefing) {
            PreCookBriefingView(recipe: recipe, scale: scale) { heard, awaitGo in
                router.pollyLaunch = PollyLaunch(
                    recipe: recipe,
                    scale: scale,
                    heardBriefing: heard,
                    awaitVerbalGo: awaitGo
                )
            }
        }
        .sheet(isPresented: $isShowingPreCookChecklist) {
            PreCookChecklistView(recipe: recipe) { isCooking = true }
        }
        .sheet(isPresented: $isShowingEditor) { RecipeEditorView(recipe: recipe) }
        .sheet(isPresented: $isOptimizing) { OptimizeRecipeView(recipe: recipe) }
        .sheet(isPresented: $isAdjusting) { AdjustRecipeView(recipe: recipe) }
        .sheet(isPresented: $isShowingDetails) { detailsSheet }
        .sheet(item: $substituteTarget) { conflict in
            SubstituteSheet(recipe: recipe, conflict: conflict)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete this recipe?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { context.delete(recipe); dismiss() }
        }
        .alert("Name this version", isPresented: $isNamingVersion) {
            TextField("e.g. High-protein version", text: $versionLabel)
            Button("Create") { createVersion() }
            Button("Cancel", role: .cancel) { versionLabel = "" }
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .top) {
            RecipeImageView(recipe: recipe)
                .frame(height: 330)
                .clipped()
            LinearGradient(colors: [Color.black.opacity(0.4), .clear], startPoint: .top, endPoint: .center)
                .frame(height: 150)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            HStack {
                circleButton(MS.chevronLeft) { Haptics.impact(.light); dismiss() }
                Spacer()
                circleButton(recipe.isFavorite ? MS.favoriteFill : MS.favorite,
                             tint: recipe.isFavorite ? Theme.Colors.tomato : Theme.Colors.heading) {
                    Haptics.impact(.medium); recipe.isFavorite.toggle()
                }
                overflowMenu
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
        }
        .frame(height: 330)
    }

    private func circleButton(_ icon: MS, tint: Color = Theme.Colors.heading,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.sized(21).foregroundColor(tint)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Theme.Colors.card.opacity(0.85)))
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var overflowMenu: some View {
        Menu {
            Button("More details", systemImage: "list.bullet.rectangle") { isShowingDetails = true }
            Divider()
            Picker("Units", selection: $unitSystem) {
                ForEach(MeasurementSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
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
            MS.moreHoriz.sized(21).foregroundColor(Theme.Colors.heading)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Theme.Colors.card.opacity(0.85)))
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: - Content sheet

    private var contentSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock
            if !recipe.isCookingBasic { adaptRow.padding(.top, 18) }
            dietWarnings
            SegmentedTabs(titles: ["Ingredients", "Steps"], selection: $selectedTab)
                .padding(.top, 22)
            if selectedTab == 0 { ingredientsTab.padding(.top, 20) } else { stepsTab.padding(.top, 20) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.background)
        .clipShape(.rect(topLeadingRadius: 30, topTrailingRadius: 30))
        .offset(y: -26)
        .padding(.bottom, -26)
    }

    private var titleBlock: some View {
        let showNutrition = UserPrefs.current(in: context).nutritionMode.showsNutrition
        return VStack(alignment: .leading, spacing: 8) {
            (Text(recipe.title).foregroundColor(Theme.Colors.heading)
             + kcalSuffix(show: showNutrition))
                .font(BrandFont.bricolage(27, 700))
                .lineLimit(3)
            if let summary = recipe.summary, !summary.isEmpty {
                Text(summary)
                    .font(BrandFont.nunito(14.5, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            HStack(spacing: 6) {
                MS.person.sized(16).foregroundStyle(Theme.Colors.muted)
                Text(recipe.sourceCreator ?? recipe.sourcePlatform.label)
                    .font(BrandFont.nunito(13, 700)).foregroundStyle(Theme.Colors.muted)
            }
            .padding(.top, 1)
            statPills(showNutrition: showNutrition).padding(.top, 6)
            if !recipe.tags.isEmpty { tagRow.padding(.top, 4) }
            if let confidence = recipe.importConfidence, confidence < 0.85 {
                ConfidenceBadge(confidence: confidence)
            }
        }
    }

    private func kcalSuffix(show: Bool) -> Text {
        guard show, let cal = headerNutrition?.calories else { return Text("") }
        return Text(", \(cal) Kcal").foregroundColor(Theme.Colors.muted)
    }

    private func statPills(showNutrition: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                detailPill(MS.schedule, recipe.timeLabel, fg: Color(hex: 0x4A4238), bg: Theme.Colors.surface2, icon: Theme.Colors.textSecondary)
                detailPill(MS.signalCellularAlt, recipe.difficulty.label, fg: Color(hex: 0x4A4238), bg: Theme.Colors.surface2, icon: Theme.Colors.textSecondary)
                if showNutrition, let n = headerNutrition {
                    detailPill(MS.fireFill, "\(n.calories) cal", fg: Theme.Colors.tomato, bg: Theme.Colors.tomatoTint, icon: Theme.Colors.tomato)
                    detailPill(MS.boltFill, "\(n.protein)g", fg: Theme.Colors.accent, bg: Theme.Colors.greenTint, icon: Theme.Colors.accent)
                }
                if let rating = recipe.rating {
                    detailPill(MS.starFill, "\(rating)", fg: Theme.Colors.amber, bg: Theme.Colors.amberChip, icon: Theme.Colors.amber)
                }
            }
        }
    }

    private func detailPill(_ icon: MS, _ text: String, fg: Color, bg: Color, icon iconColor: Color) -> some View {
        HStack(spacing: 5) {
            icon.sized(15).foregroundStyle(iconColor)
            Text(text).font(BrandFont.nunito(12.5, 800)).foregroundStyle(fg)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(bg))
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(recipe.tags, id: \.self) { tag in
                    Text(tag)
                        .font(BrandFont.nunito(12.5, 700))
                        .foregroundStyle(Color(hex: 0x3A342C))
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Colors.card))
                        .overlay(Capsule().strokeBorder(Theme.Colors.textPrimary.opacity(0.08), lineWidth: 1.5))
                }
            }
        }
    }

    // MARK: - Adapt row

    private var adaptRow: some View {
        HStack(spacing: 9) {
            if LLMClient.isConfigured {
                adaptPill(MS.autoAwesomeFill, "Make it…") { isAdjusting = true }
            }
            if !pantryMatch.missing.isEmpty {
                adaptPill(MS.autoFixHighFill, "Use what I have") { isOptimizing = true }
            }
        }
    }

    private func adaptPill(_ icon: MS, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light); action()
        } label: {
            HStack(spacing: 7) {
                icon.sized(17)
                Text(label).font(BrandFont.nunito(14, 700))
            }
            .foregroundColor(Theme.Colors.accent)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Capsule().fill(Theme.Colors.accent.opacity(0.10)))
            .overlay(Capsule().strokeBorder(Theme.Colors.accent.opacity(0.22), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Diet warnings (inline, conditional safety info)

    @ViewBuilder
    private var dietWarnings: some View {
        let prefs = UserPrefs.current(in: context)
        let conflicts = DietGuard.conflicts(in: recipe, rules: prefs.dietaryRules,
                                            allergies: prefs.allergies, dislikes: prefs.dislikedIngredients)
        if !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(conflicts) { conflict in
                    HStack(spacing: Theme.Spacing.sm) {
                        Label(conflict.message, systemImage: conflict.isBlocking ? "exclamationmark.triangle.fill" : "hand.thumbsdown")
                            .font(.gluttCaption.weight(.medium))
                            .foregroundStyle(conflictColor(conflict))
                        Spacer(minLength: 0)
                        if conflict.severity != .dislike {
                            Button {
                                Haptics.impact(.light); substituteTarget = conflict
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Substitute").font(.gluttCaption.weight(.heavy))
                                }
                                .foregroundStyle(Theme.Colors.accent)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Theme.Colors.background.opacity(0.6), in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.Colors.accent.opacity(0.35)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(conflicts.contains { $0.severity == .allergy } ? Theme.Colors.tomato.opacity(0.12) : Theme.Colors.warningTint)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .padding(.top, 16)
        }
    }

    private func conflictColor(_ conflict: DietGuard.Conflict) -> Color {
        switch conflict.severity {
        case .allergy: Theme.Colors.tomato
        case .rule: Theme.Colors.amber
        case .dislike: Theme.Colors.textSecondary
        }
    }

    // MARK: - Ingredients tab

    private var ingredientsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            servingsControl
            if pantryMatch.totalCount > 0 { pantryMatchLine }
            ForEach(IngredientSection.allCases, id: \.self) { section in
                let rows = sortedIngredients.filter { IngredientCategoryStyle.section(for: $0.name) == section }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: section.title)
                        ingredientGroup(rows)
                    }
                }
            }
            if !pantryMatch.missing.isEmpty { groceriesButton }
        }
    }

    private var servingsControl: some View {
        HStack {
            Text("Servings")
                .font(BrandFont.bricolage(17, 600))
                .foregroundStyle(Theme.Colors.heading)
            Spacer()
            GluttStepper(value: $displayServings, in: 1...24, step: 1) { "\($0)" }
        }
    }

    private var pantryMatchLine: some View {
        HStack(spacing: 6) {
            (pantryMatch.hasEverything ? MS.checkCircleFill : MS.shoppingBasketFill)
                .sized(17)
                .foregroundStyle(pantryMatch.hasEverything ? Theme.Colors.accent : Theme.Colors.amber)
            Text(pantryMatch.hasEverything
                 ? "You have everything"
                 : "You have \(pantryMatch.ownedCount) of \(pantryMatch.totalCount), missing \(pantryMatch.missing.count)")
                .font(BrandFont.nunito(13.5, 700))
                .foregroundStyle(pantryMatch.hasEverything ? Theme.Colors.accent : Theme.Colors.amber)
        }
    }

    private func ingredientGroup(_ rows: [RecipeIngredient]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { ingredient in
                ingredientRow(ingredient)
                if ingredient !== rows.last {
                    Rectangle().fill(Color(hex: 0xEFE7D6)).frame(height: 1).padding(.leading, 59)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
            .strokeBorder(Theme.Colors.textPrimary.opacity(0.06), lineWidth: 1))
        .shadow(color: Theme.Colors.textPrimary.opacity(0.04), radius: 16, y: 6)
    }

    private func ingredientRow(_ ingredient: RecipeIngredient) -> some View {
        let owned = pantryMatch.owned.contains { $0 === ingredient }
        return HStack(spacing: 13) {
            IngredientTile(name: ingredient.name, isMissing: !owned)
            VStack(alignment: .leading, spacing: 1) {
                Text(ingredient.name)
                    .font(BrandFont.nunito(15, 700))
                    .foregroundStyle(Theme.Colors.heading)
                Text(ingredientSubtitle(ingredient, owned: owned))
                    .font(BrandFont.nunito(12.5, 700))
                    .foregroundStyle(owned ? Color(hex: 0x829A86) : Theme.Colors.amber)
            }
            Spacer(minLength: 0)
            Button { Haptics.impact(.light); toggleOwnership(of: ingredient) } label: {
                checkbox(owned: owned)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private func checkbox(owned: Bool) -> some View {
        Group {
            if owned {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.Colors.accent)
                    .overlay(MS.checkFill.sized(17).foregroundStyle(Theme.Colors.creamText))
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color(hex: 0xDCD2C1), lineWidth: 2)
            }
        }
        .frame(width: 27, height: 27)
    }

    private func ingredientSubtitle(_ ingredient: RecipeIngredient, owned: Bool) -> String {
        var amount = ""
        if let display = UnitConverter.display(quantity: ingredient.quantity, unit: ingredient.unit,
                                               scale: scale, system: unitSystem, ingredientName: ingredient.name) {
            amount = ingredient.isEstimated ? "~\(display)" : display
            // Keep the source's other unit visible ("0.8 lb (400 g)") in original units.
            if unitSystem == .original, let alt = alternateAmount(from: ingredient.note) {
                amount += " (\(alt))"
            }
        }
        let status = owned ? "in your kitchen" : "add to groceries"
        return amount.isEmpty ? status : "\(amount) · \(status)"
    }

    /// The ingredient note only when it reads like an alternate measurement
    /// (e.g. "400 g", "1 cup"), so the source's parenthetical unit survives.
    private func alternateAmount(from note: String?) -> String? {
        guard let note = note?.trimmingCharacters(in: .whitespaces), !note.isEmpty,
              note.first?.isNumber == true else { return nil }
        let units = ["g", "kg", "ml", "l", "oz", "lb", "lbs", "cup", "cups", "tbsp", "tsp",
                     "gram", "grams", "pound", "pounds", "ounce", "ounces"]
        return units.contains(where: note.lowercased().contains) ? note : nil
    }

    private var groceriesButton: some View {
        Button {
            Haptics.notify(.success)
            GroceryListBuilder.add(ingredients: pantryMatch.missing, from: recipe,
                                   existing: groceryItems, context: context)
        } label: {
            HStack(spacing: 9) {
                MS.shoppingBasketFill.sized(19)
                Text("Add \(pantryMatch.missing.count) missing to groceries")
                    .font(BrandFont.nunito(16, 800))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(Theme.Colors.creamText)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Colors.accent))
            .shadow(color: Theme.Colors.textPrimary.opacity(0.13), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Steps tab

    private var stepsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(recipe.sortedSteps) { step in
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Text("\(step.index + 1)")
                        .font(.gluttHeadline).foregroundStyle(Theme.Colors.creamText)
                        .frame(width: 28, height: 28)
                        .background(Theme.Colors.accent).clipShape(Circle())
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(step.text).font(.gluttBody).foregroundStyle(Theme.Colors.textPrimary)
                        if let duration = step.durationSeconds {
                            Label(formatDuration(duration), systemImage: "timer")
                                .font(.gluttCaption.weight(.medium)).foregroundStyle(Theme.Colors.amber)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Cook bar

    private var cookBar: some View {
        VStack(spacing: 12) {
            if LLMClient.isConfigured {
                Button {
                    Haptics.impact(.medium)
                    isShowingCookBriefing = true
                } label: {
                    HStack(spacing: 10) {
                        MS.graphicEqFill.sized(22).foregroundStyle(Theme.Colors.brightAccent)
                        Text(recipe.isCookingBasic ? "Learn with Polly" : "Cook with Polly")
                            .font(BrandFont.nunito(16.5, 800)).foregroundStyle(Theme.Colors.creamText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Theme.Colors.accent))
                    .shadow(color: Theme.Colors.textPrimary.opacity(0.14), radius: 18, y: 10)
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.impact(.light)
                    if pantryMatch.missing.isEmpty { isCooking = true } else { isShowingPreCookChecklist = true }
                } label: {
                    HStack(spacing: 7) {
                        MS.formatListNumbered.sized(18).foregroundStyle(Theme.Colors.muted)
                        Text(recipe.isCookingBasic ? "Or practice step by step" : "Or cook step by step")
                            .font(BrandFont.nunito(14, 700)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Haptics.impact(.medium)
                    if pantryMatch.missing.isEmpty { isCooking = true } else { isShowingPreCookChecklist = true }
                } label: {
                    HStack(spacing: 10) {
                        MS.skilletFill.sized(20).foregroundStyle(Theme.Colors.creamText)
                        Text("Cook").font(BrandFont.nunito(16.5, 800)).foregroundStyle(Theme.Colors.creamText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Theme.Colors.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, GluttTabBar.reservedHeight - 12)
        .background(Theme.Colors.background.opacity(0.98))
    }

    // MARK: - "More details" sheet (relocated extras, kept reachable)

    private var detailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    gearWarning
                    nutritionLine
                    notesSection
                    ratingSection
                    versionPicker
                    if !sessions.isEmpty { historySection }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingDetails = false } } }
        }
    }

    @ViewBuilder
    private var gearWarning: some View {
        let required = requiredTools
        if !required.isEmpty {
            let owned = Set(ownedTools.map(\.canonicalName))
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Tools you'll need", systemImage: "wrench.and.screwdriver")
                    .font(.gluttCaption.weight(.semibold)).foregroundStyle(Theme.Colors.textSecondary)
                FlowLayout(hSpacing: Theme.Spacing.xs, vSpacing: Theme.Spacing.xs) {
                    ForEach(required, id: \.self) { tool in
                        let have = owned.contains(tool.lowercased())
                        HStack(spacing: 4) {
                            Image(systemName: have ? "checkmark.circle.fill" : "plus.circle")
                            Text(tool)
                        }
                        .font(.gluttCaption.weight(.medium))
                        .foregroundStyle(have ? Theme.Colors.accent : Theme.Colors.amber)
                        .padding(.horizontal, Theme.Spacing.sm).padding(.vertical, 6)
                        .background(have ? Theme.Colors.successTint : Theme.Colors.warningTint)
                        .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    @ViewBuilder
    private var nutritionLine: some View {
        let prefs = UserPrefs.current(in: context)
        if prefs.nutritionMode.showsNutrition {
            if recipe.carbGrams != nil, recipe.fatGrams != nil {
                MacroStrip(recipe: recipe).cardStyle()
            } else if let estimate = NutritionEstimator.estimate(for: recipe) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "chart.bar").foregroundStyle(Theme.Colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("~\(estimate.calories) cal · \(estimate.proteinGrams)g protein per serving")
                            .font(.gluttHeadline).foregroundStyle(Theme.Colors.textPrimary)
                        Text("Estimated from \(estimate.matchedCount)/\(estimate.totalCount) ingredients, likely \(estimate.caloriesRange.lowerBound) to \(estimate.caloriesRange.upperBound) cal")
                            .font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                }
                .cardStyle()
                .onAppear {
                    if recipe.calories == nil {
                        recipe.calories = estimate.calories
                        recipe.proteinGrams = estimate.proteinGrams
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "My notes")
            TextField("add more lemon, too salty, cook longer…", text: $recipe.notes, axis: .vertical)
                .font(.gluttBody).lineLimit(3...8).cardStyle()
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "How was it?")
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        recipe.rating = recipe.rating == star ? nil : star
                    } label: {
                        Image(systemName: star <= (recipe.rating ?? 0) ? "star.fill" : "star")
                            .font(.title3).foregroundStyle(Theme.Colors.amber)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private var versionPicker: some View {
        let original = recipe.parentRecipe ?? recipe
        let allVersions = [original] + original.versions
        if allVersions.count > 1 {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("MY VERSIONS OF THIS RECIPE")
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.Colors.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(allVersions) { version in
                            NavigationLink(value: version) {
                                Chip(label: version === original ? "Original" : (version.versionLabel ?? "My version"),
                                     isSelected: version === recipe)
                            }
                            .buttonStyle(.plain).disabled(version === recipe)
                        }
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Cooked before")
            ForEach(sessions) { session in
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "frying.pan").foregroundStyle(Theme.Colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.date, format: .dateTime.month().day())
                            .font(.gluttHeadline).foregroundStyle(Theme.Colors.textPrimary)
                        Text("\(session.servingsMade) servings made")
                            .font(.gluttCaption).foregroundStyle(Theme.Colors.textSecondary)
                        if let notes = session.notes {
                            Text("\u{201C}\(notes)\u{201D}")
                                .font(.gluttCaption.italic()).foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                    if let rating = session.rating {
                        Label("\(rating)", systemImage: "star.fill")
                            .font(.gluttCaption.weight(.medium)).foregroundStyle(Theme.Colors.amber)
                    }
                }
                .cardStyle()
            }
        }
    }

    // MARK: - Helpers

    private func toggleOwnership(of ingredient: RecipeIngredient) {
        let canonical = ingredient.canonicalName
        let isOwned = pantryMatch.owned.contains { $0 === ingredient }
        if isOwned {
            if let item = PantryMatcher.item(covering: canonical, in: pantryItems) {
                item.roughQuantity = .out
            } else if PantryMatcher.staples.contains(canonical) {
                context.insert(PantryItem(name: ingredient.name,
                                          category: GroceryCategorizer.categorize(ingredient.name),
                                          roughQuantity: .out))
            }
        } else {
            if let item = PantryMatcher.item(covering: canonical, in: pantryItems) {
                item.roughQuantity = .full
            } else {
                context.insert(PantryItem(name: ingredient.name,
                                          category: GroceryCategorizer.categorize(ingredient.name)))
            }
        }
    }

    private func createVersion() {
        let label = versionLabel.trimmingCharacters(in: .whitespaces)
        let copy = Recipe(
            title: recipe.title, summary: recipe.summary, sourceCreator: recipe.sourceCreator,
            sourceURL: recipe.sourceURL, sourcePlatform: recipe.sourcePlatform, servings: recipe.servings,
            prepMinutes: recipe.prepMinutes, cookMinutes: recipe.cookMinutes,
            difficulty: recipe.difficulty, tags: recipe.tags
        )
        copy.imageAssetName = recipe.imageAssetName
        copy.imageData = recipe.imageData
        copy.imageURL = recipe.imageURL
        copy.ingredients = recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }.map {
            RecipeIngredient(name: $0.name, quantity: $0.quantity, unit: $0.unit, note: $0.note,
                             isOptional: $0.isOptional, isEstimated: $0.isEstimated, role: $0.role, sortIndex: $0.sortIndex)
        }
        copy.steps = recipe.sortedSteps.map { RecipeStep(index: $0.index, text: $0.text, durationSeconds: $0.durationSeconds) }
        copy.parentRecipe = recipe.parentRecipe ?? recipe
        copy.versionLabel = label.isEmpty ? "My version" : label
        context.insert(copy)
        versionLabel = ""
    }

    private func formatDuration(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60) min" : "\(seconds) sec"
    }
}

/// "Add to collection" submenu, shared between detail and context menus.
struct CollectionsMenu: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecipeCollection.createdAt) private var collections: [RecipeCollection]
    let recipe: Recipe

    var body: some View {
        Menu("Collections") {
            ForEach(collections) { collection in
                let isMember = collection.recipes.contains { $0 === recipe }
                Button {
                    if isMember { collection.recipes.removeAll { $0 === recipe } }
                    else { collection.recipes.append(recipe) }
                } label: {
                    if isMember { Label(collection.name, systemImage: "checkmark") }
                    else { Text(collection.name) }
                }
            }
        }
    }
}
