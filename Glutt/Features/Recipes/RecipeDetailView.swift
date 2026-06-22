import SwiftData
import SwiftUI

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @Query private var pantryItems: [PantryItem]
    @Query private var groceryItems: [GroceryItem]
    @Bindable var recipe: Recipe

    @State private var displayServings: Int
    @State private var unitSystem: MeasurementSystem = .original
    @State private var isShowingEditor = false
    @State private var isConfirmingDelete = false
    @State private var isNamingVersion = false
    @State private var versionLabel = ""
    @State private var isCooking = false
    @State private var isShowingPreCookChecklist = false
    @State private var isAddingToPlan = false
    @State private var isOptimizing = false
    @State private var isAdjusting = false
    @State private var selectedTab = 0   // 0 = Ingredients, 1 = Steps

    init(recipe: Recipe) {
        self.recipe = recipe
        _displayServings = State(initialValue: recipe.servings)
    }

    private var scale: Double {
        guard recipe.servings > 0 else { return 1 }
        return Double(displayServings) / Double(recipe.servings)
    }

    private var sessions: [CookSession] {
        recipe.cookSessions(in: context)
    }

    private var pantryMatch: PantryMatcher.MatchResult {
        PantryMatcher.match(recipe: recipe, pantry: pantryItems)
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

    // MARK: - Hero

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
                    Haptics.impact(.medium)
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

    // MARK: - Overflow menu

    private var overflowMenu: some View {
        Menu {
            if LLMClient.isConfigured {
                Button("Make it…", systemImage: "sparkles") { isAdjusting = true }
            }
            Button("Add to plan", systemImage: "calendar.badge.plus") { isAddingToPlan = true }
            if !pantryMatch.missing.isEmpty {
                Button("Use what I have", systemImage: "wand.and.stars") { isOptimizing = true }
            }
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
            Ph.dotsThree.bold.resizable().scaledToFit().frame(width: 18, height: 18)
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: - Content sheet

    private var contentSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            titleBlock
            dietWarnings
            if recipe.sourcePlatform == .youtube,
               let urlString = recipe.sourceURL,
               let id = YouTubeEmbed.videoId(from: urlString) {
                YouTubePlayerView(videoId: id)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.segment, style: .continuous))
            }
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
            Text(recipe.sourceCreator ?? recipe.sourcePlatform.label)
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: 8) {
                StatPill.time(recipe.timeLabel)
                StatPill.difficulty(recipe.difficulty.label)
                if let rating = recipe.rating { StatPill.rating("\(rating)") }
                Spacer(minLength: 0)
            }
            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(recipe.tags, id: \.self) { tag in
                            Chip(label: tag).fixedSize()
                        }
                    }
                }
            }
            if let confidence = recipe.importConfidence, confidence < 0.85 {
                ConfidenceBadge(confidence: confidence)
            }
        }
    }

    // MARK: - Sections

    /// Allergy and rule conflicts, shown plainly — never silently hidden,
    /// because the user may be cooking for someone else.
    @ViewBuilder
    private var dietWarnings: some View {
        let prefs = UserPrefs.current(in: context)
        let conflicts = DietGuard.conflicts(
            in: recipe,
            rules: prefs.dietaryRules,
            allergies: prefs.allergies,
            dislikes: prefs.dislikedIngredients
        )
        if !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(conflicts) { conflict in
                    Label(
                        conflict.message,
                        systemImage: conflict.isBlocking ? "exclamationmark.triangle.fill" : "hand.thumbsdown"
                    )
                    .font(.gluttCaption.weight(.medium))
                    .foregroundStyle(conflictColor(conflict))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(
                conflicts.contains { $0.severity == .allergy }
                    ? Theme.Colors.tomato.opacity(0.12)
                    : Theme.Colors.warningTint
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private func conflictColor(_ conflict: DietGuard.Conflict) -> Color {
        switch conflict.severity {
        case .allergy: Theme.Colors.tomato
        case .rule: Theme.Colors.warning
        case .dislike: Theme.Colors.textSecondary
        }
    }

    // MARK: - Steps tab

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

    // MARK: - Ingredients tab

    private var ingredientsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            servingsControl
            if displayServings != recipe.servings {
                HStack(spacing: Theme.Spacing.sm) {
                    Label(
                        "Scaled from \(recipe.servings) \(recipe.servings == 1 ? "serving" : "servings")",
                        systemImage: "arrow.up.arrow.down"
                    )
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Button("Reset") { displayServings = recipe.servings }
                        .font(.gluttCaption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            if pantryMatch.totalCount > 0 {
                Label(
                    pantryMatch.hasEverything
                        ? "You have everything"
                        : "You have \(pantryMatch.ownedCount) of \(pantryMatch.totalCount) — missing \(pantryMatch.missing.count)",
                    systemImage: pantryMatch.hasEverything ? "checkmark.circle.fill" : "basket"
                )
                .font(.gluttCaption.weight(.semibold))
                .foregroundStyle(pantryMatch.hasEverything ? Theme.Colors.accent : Theme.Colors.warning)
            }
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
            if !pantryMatch.missing.isEmpty { groceriesFooter }
        }
    }

    /// Cream gradient fade rising above a full-width herb-green "add to groceries"
    /// button — the missing count mirrors the unchecked / not-owned rows.
    private var groceriesFooter: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Theme.Colors.background.opacity(0), Theme.Colors.background],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
                .allowsHitTesting(false)
            Button {
                Haptics.notify(.success)
                GroceryListBuilder.add(ingredients: pantryMatch.missing, from: recipe,
                                       existing: groceryItems, context: context)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Ph.basket.fill.resizable().scaledToFit().frame(width: 18, height: 18)
                    Text("Add \(pantryMatch.missing.count) missing to groceries")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(Theme.Colors.creamText)
                .padding(.vertical, 16)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var sortedIngredients: [RecipeIngredient] {
        recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// A slim servings control. The recipe's name and photo already sit at the top of
    /// the detail, so the ingredients tab doesn't repeat them — it just needs to adjust
    /// servings. The metric/original unit toggle lives in the overflow menu.
    private var servingsControl: some View {
        HStack {
            Text("Servings")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            GluttStepper(value: $displayServings, in: 1...24, step: 1) { "\($0)" }
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
                    .foregroundStyle(owned ? Theme.Colors.textSecondary : nameColor(for: ingredient))
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
            Button { Haptics.impact(.light); toggleOwnership(of: ingredient) } label: {
                (owned ? Ph.checkSquare.fill : Ph.square.regular)
                    .resizable().scaledToFit().frame(width: 26, height: 26)
                    .foregroundColor(owned ? Theme.Colors.accent : Theme.Colors.border)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Cook bar

    private var cookBar: some View {
        Button {
            Haptics.impact(.medium)
            if pantryMatch.missing.isEmpty { isCooking = true } else { isShowingPreCookChecklist = true }
        } label: {
            Label("Cook", systemImage: "frying.pan").frame(maxWidth: .infinity)
        }
        .buttonStyle(.gluttPrimary)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, GluttTabBar.reservedHeight)
        .background(Theme.Colors.background.opacity(0.95))
    }

    // MARK: - Below-fold sections (kept unchanged)

    /// Nutrition only appears when the user opted into tracking — and it's
    /// transparent about being an estimate, never fake-precise.
    @ViewBuilder
    private var nutritionLine: some View {
        let prefs = UserPrefs.current(in: context)
        if prefs.nutritionMode.showsNutrition, let estimate = NutritionEstimator.estimate(for: recipe) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "chart.bar")
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("~\(estimate.calories) cal · \(estimate.proteinGrams)g protein per serving")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Estimated from \(estimate.matchedCount)/\(estimate.totalCount) ingredients — likely \(estimate.caloriesRange.lowerBound)–\(estimate.caloriesRange.upperBound) cal")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
            }
            .cardStyle()
            .onAppear {
                // Cache so cook-finish logging and meal cards can reuse it.
                if recipe.calories == nil {
                    recipe.calories = estimate.calories
                    recipe.proteinGrams = estimate.proteinGrams
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "My notes")
            TextField("add more lemon, too salty, cook longer…", text: $recipe.notes, axis: .vertical)
                .font(.gluttBody)
                .lineLimit(3...8)
                .cardStyle()
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
                            .font(.title3)
                            .foregroundStyle(Theme.Colors.warning)
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                versionChips(allVersions, original: original)
            }
        }
    }

    private func versionChips(_ allVersions: [Recipe], original: Recipe) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(allVersions) { version in
                    NavigationLink(value: version) {
                        Chip(
                            label: version === original ? "Original" : (version.versionLabel ?? "My version"),
                            isSelected: version === recipe
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(version === recipe)
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Cooked before")
            ForEach(sessions) { session in
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "frying.pan")
                        .foregroundStyle(Theme.Colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.date, format: .dateTime.month().day())
                            .font(.gluttHeadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("\(session.servingsMade) servings made")
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        if let notes = session.notes {
                            Text("\u{201C}\(notes)\u{201D}")
                                .font(.gluttCaption.italic())
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                    if let rating = session.rating {
                        Label("\(rating)", systemImage: "star.fill")
                            .font(.gluttCaption.weight(.medium))
                            .foregroundStyle(Theme.Colors.warning)
                    }
                }
                .cardStyle()
            }
        }
    }

    // MARK: - Helpers (kept unchanged)

    /// Missing required ingredients read in warning gold — scannable at a glance.
    private func nameColor(for ingredient: RecipeIngredient) -> Color {
        let owned = pantryMatch.owned.contains { $0 === ingredient }
        let optionalMissing = pantryMatch.missingOptional.contains { $0 === ingredient }
        if owned { return Theme.Colors.textPrimary }
        return optionalMissing ? Theme.Colors.textSecondary : Theme.Colors.warning
    }

    /// Tap an ingredient to flip "I have this" — updates the pantry directly
    /// so the user doesn't have to detour through Kitchen → Inventory.
    private func toggleOwnership(of ingredient: RecipeIngredient) {
        let canonical = ingredient.canonicalName
        let isOwned = pantryMatch.owned.contains { $0 === ingredient }

        if isOwned {
            if let item = PantryMatcher.item(covering: canonical, in: pantryItems) {
                item.roughQuantity = .out
            } else if PantryMatcher.staples.contains(canonical) {
                // Staples have no pantry row; create one marked as out.
                let item = PantryItem(
                    name: ingredient.name,
                    category: GroceryCategorizer.categorize(ingredient.name),
                    roughQuantity: .out
                )
                context.insert(item)
            }
        } else {
            if let item = PantryMatcher.item(covering: canonical, in: pantryItems) {
                item.roughQuantity = .full
            } else {
                let item = PantryItem(
                    name: ingredient.name,
                    category: GroceryCategorizer.categorize(ingredient.name)
                )
                context.insert(item)
            }
        }
    }

    private func createVersion() {
        let label = versionLabel.trimmingCharacters(in: .whitespaces)
        let copy = Recipe(
            title: recipe.title,
            summary: recipe.summary,
            sourceCreator: recipe.sourceCreator,
            sourceURL: recipe.sourceURL,
            sourcePlatform: recipe.sourcePlatform,
            servings: recipe.servings,
            prepMinutes: recipe.prepMinutes,
            cookMinutes: recipe.cookMinutes,
            difficulty: recipe.difficulty,
            tags: recipe.tags
        )
        copy.imageAssetName = recipe.imageAssetName
        copy.imageData = recipe.imageData
        copy.imageURL = recipe.imageURL
        copy.ingredients = recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }.map {
            RecipeIngredient(
                name: $0.name, quantity: $0.quantity, unit: $0.unit, note: $0.note,
                isOptional: $0.isOptional, role: $0.role, sortIndex: $0.sortIndex
            )
        }
        copy.steps = recipe.sortedSteps.map {
            RecipeStep(index: $0.index, text: $0.text, durationSeconds: $0.durationSeconds)
        }
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
                    if isMember {
                        collection.recipes.removeAll { $0 === recipe }
                    } else {
                        collection.recipes.append(recipe)
                    }
                } label: {
                    if isMember {
                        Label(collection.name, systemImage: "checkmark")
                    } else {
                        Text(collection.name)
                    }
                }
            }
        }
    }
}
