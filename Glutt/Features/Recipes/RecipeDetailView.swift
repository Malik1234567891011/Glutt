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
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                hero
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    versionPicker
                    servingsAndUnits
                    ingredientsSection
                    stepsSection
                    notesSection
                    ratingSection
                    if !sessions.isEmpty {
                        historySection
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarMenu }
        .safeAreaInset(edge: .bottom) {
            Button {
                if pantryMatch.missing.isEmpty {
                    isCooking = true
                } else {
                    isShowingPreCookChecklist = true
                }
            } label: {
                Label("Cook", systemImage: "frying.pan")
            }
            .buttonStyle(.gluttPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
            .background(Theme.Colors.background.opacity(0.95))
        }
        .fullScreenCover(isPresented: $isCooking) {
            CookModeView(recipe: recipe, scale: scale)
        }
        .sheet(isPresented: $isShowingPreCookChecklist) {
            PreCookChecklistView(recipe: recipe) {
                isCooking = true
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            RecipeEditorView(recipe: recipe)
        }
        .sheet(isPresented: $isAddingToPlan) {
            AddMealSheet(day: Calendar.current.startOfDay(for: .now), fixedRecipe: recipe)
        }
        .sheet(isPresented: $isOptimizing) {
            OptimizeRecipeView(recipe: recipe)
        }
        .confirmationDialog("Delete this recipe?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(recipe)
                dismiss()
            }
        }
        .alert("Name this version", isPresented: $isNamingVersion) {
            TextField("e.g. High-protein version", text: $versionLabel)
            Button("Create") { createVersion() }
            Button("Cancel", role: .cancel) { versionLabel = "" }
        }
        // The floating + would sit right on top of the Cook button.
        .onAppear { router.floatingButtonSuppressors += 1 }
        .onDisappear { router.floatingButtonSuppressors -= 1 }
    }

    // MARK: - Sections

    private var hero: some View {
        RecipeImageView(recipe: recipe)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .padding(.horizontal, Theme.Spacing.md)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(recipe.title)
                .font(.gluttLargeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)

            if let summary = recipe.summary {
                Text(summary)
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(spacing: Theme.Spacing.sm) {
                if let creator = recipe.sourceCreator {
                    Text(creator)
                } else {
                    Text(recipe.sourcePlatform.label)
                }
                Text("·")
                Label("\(recipe.totalMinutes) min", systemImage: "clock")
                Text("·")
                Text(recipe.difficulty.label)
            }
            .font(.gluttCaption)
            .foregroundStyle(Theme.Colors.textSecondary)

            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(recipe.tags, id: \.self) { tag in
                            Chip(label: tag)
                                .fixedSize()
                        }
                    }
                }
            }

            if let confidence = recipe.importConfidence, confidence < 0.85 {
                ConfidenceBadge(confidence: confidence)
            }
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

    private var servingsAndUnits: some View {
        HStack {
            Stepper(value: $displayServings, in: 1...24) {
                Text("\(displayServings) servings")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            Picker("Units", selection: $unitSystem) {
                ForEach(MeasurementSystem.allCases, id: \.self) { system in
                    Text(system.rawValue).tag(system)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        .cardStyle()
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Ingredients")

            if pantryMatch.totalCount > 0 {
                HStack {
                    Label(
                        pantryMatch.hasEverything
                            ? "You have everything"
                            : "You have \(pantryMatch.ownedCount)/\(pantryMatch.totalCount)",
                        systemImage: pantryMatch.hasEverything ? "checkmark.circle.fill" : "basket"
                    )
                    .font(.gluttCaption.weight(.medium))
                    .foregroundStyle(pantryMatch.hasEverything ? Theme.Colors.accent : Theme.Colors.warning)
                    Spacer()
                    if !pantryMatch.missing.isEmpty {
                        Button("Add missing to groceries") {
                            GroceryListBuilder.add(
                                ingredients: pantryMatch.missing,
                                from: recipe,
                                existing: groceryItems,
                                context: context
                            )
                        }
                        .buttonStyle(.gluttPill)
                    }
                }
            }

            VStack(spacing: 0) {
                let sorted = recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }
                ForEach(sorted) { ingredient in
                    HStack {
                        Button {
                            toggleOwnership(of: ingredient)
                        } label: {
                            HStack {
                                ownershipIcon(for: ingredient)
                                Text(ingredient.name)
                                    .font(.gluttBody)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                if ingredient.isOptional {
                                    Text("optional")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        if let display = UnitConverter.display(
                            quantity: ingredient.quantity,
                            unit: ingredient.unit,
                            scale: scale,
                            system: unitSystem
                        ) {
                            Text(display)
                                .font(.gluttBody.weight(.medium))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                    if ingredient !== sorted.last {
                        Divider().overlay(Theme.Colors.border)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .cardStyle(padding: Theme.Spacing.xs)
        }
    }

    private func ownershipIcon(for ingredient: RecipeIngredient) -> some View {
        let owned = pantryMatch.owned.contains { $0 === ingredient }
        let optionalMissing = pantryMatch.missingOptional.contains { $0 === ingredient }
        return Image(systemName: owned ? "checkmark.circle.fill" : "circle")
            .font(.body)
            .foregroundStyle(
                owned ? Theme.Colors.accent : (optionalMissing ? Theme.Colors.border : Theme.Colors.warning)
            )
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

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Steps")
            ForEach(recipe.sortedSteps) { step in
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Text("\(step.index + 1)")
                        .font(.gluttHeadline)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.Colors.accent)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(step.text)
                            .font(.gluttBody)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if let duration = step.durationSeconds {
                            Label(formatDuration(duration), systemImage: "timer")
                                .font(.gluttCaption.weight(.medium))
                                .foregroundStyle(Theme.Colors.warning)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .cardStyle()
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
            SectionHeader(title: "My rating")
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
                            Text("“\(notes)”")
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

    // MARK: - Toolbar & actions

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Edit", systemImage: "pencil") { isShowingEditor = true }
                Button("Add to plan", systemImage: "calendar.badge.plus") { isAddingToPlan = true }
                Button("Use what I have", systemImage: "sparkles") { isOptimizing = true }
                Button("Save as version", systemImage: "square.on.square") { isNamingVersion = true }
                collectionsMenu
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var collectionsMenu: some View {
        CollectionsMenu(recipe: recipe)
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
