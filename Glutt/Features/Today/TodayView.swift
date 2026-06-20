import SwiftData
import SwiftUI

/// The command center. Composes everything the app knows into one calm
/// screen: what's next, what needs attention, what you've eaten.
/// Smart cards are capped — never a wall of alerts.
struct TodayView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query private var meals: [PlannedMeal]
    @Query private var leftovers: [Leftover]
    @Query private var pantryItems: [PantryItem]
    @Query private var groceryItems: [GroceryItem]
    @Query private var recipes: [Recipe]
    @Query(sort: \FoodLog.timestamp, order: .reverse) private var logs: [FoodLog]

    @State private var isAskingWhatToCook = false
    @State private var isShowingSettings = false
    @State private var isLoggingFood = false
    @State private var isShowingShareSetup = false
    @State private var gettingStartedCollapsed = false
    @State private var editingMeal: PlannedMeal?
    @State private var cookingRecipe: Recipe?
    @State private var checklistRecipe: Recipe?
    @State private var optimizingRecipe: Recipe?

    private var todaysMeals: [PlannedMeal] {
        let today = Calendar.current.startOfDay(for: .now)
        return meals
            .filter { $0.date == today }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
    }

    private var nextUp: PlannedMeal? {
        TodayPlanner.nextUp(meals: meals)
    }

    private var todaysLogs: [FoodLog] {
        let today = Calendar.current.startOfDay(for: .now)
        return logs.filter { Calendar.current.startOfDay(for: $0.timestamp) == today }
    }

    private var prefs: UserPrefs {
        UserPrefs.current(in: context)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    header

                    if showGettingStarted {
                        gettingStartedCard
                    }

                    if let nextUp, nextUp.recipe != nil {
                        nextUpCard(nextUp)
                    } else if todaysMeals.isEmpty, !showGettingStarted {
                        emptyDayCard
                    }

                    quickActionsRow

                    if prefs.nutritionMode.showsNutrition {
                        nutritionSummary
                    }

                    smartCards

                    let rest = todaysMeals.filter { $0 !== nextUp }
                    if !rest.isEmpty {
                        SectionHeader(title: "Also today")
                        ForEach(rest) { meal in
                            mealRow(meal)
                        }
                    }

                    logSection
                }
                .padding(Theme.Spacing.md)
            }
            .contentMargins(.bottom, 56, for: .scrollContent)
            .background(Theme.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.impact(.light)
                        isShowingSettings = true
                    } label: {
                        Ph.gearSix.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $isAskingWhatToCook) { WhatToCookView() }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .sheet(isPresented: $isLoggingFood) { LogFoodView() }
            .sheet(isPresented: $isShowingShareSetup) { ShareSheetSetupView() }
            .sheet(item: $editingMeal) { meal in
                EditMealSheet(meal: meal)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $checklistRecipe) { recipe in
                PreCookChecklistView(recipe: recipe) {
                    cookingRecipe = recipe
                }
            }
            .sheet(item: $optimizingRecipe) { recipe in
                OptimizeRecipeView(recipe: recipe)
            }
            .fullScreenCover(item: $cookingRecipe) { recipe in
                CookModeView(recipe: recipe)
            }
            .onAppear(perform: handlePendingAction)
            .onChange(of: router.pendingAction) { handlePendingAction() }
        }
    }

    private func handlePendingAction() {
        switch router.pendingAction {
        case .askWhatToCook:
            router.pendingAction = nil
            isAskingWhatToCook = true
        case .logFood:
            router.pendingAction = nil
            isLoggingFood = true
        default:
            break
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .font(.gluttLargeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: - Getting started

    /// A self-dismissing checklist (à la ReciMe). Surfaces the three things a
    /// new user needs to discover, then disappears for good once they're done.
    /// Nothing here is the *only* path to a feature — it's a shortcut, so
    /// dismissing it never costs discoverability.
    private struct GettingStartedStep: Identifiable {
        let id = UUID()
        let title: String
        let done: Bool
        let action: () -> Void
    }

    private var gettingStartedSteps: [GettingStartedStep] {
        [
            GettingStartedStep(
                title: "Add your first recipe",
                done: !recipes.isEmpty,
                action: { router.perform(.importRecipe) }
            ),
            GettingStartedStep(
                title: "Save from TikTok & Instagram",
                done: prefs.hasSeenShareGuide,
                action: { isShowingShareSetup = true }
            ),
            GettingStartedStep(
                title: "Plan a meal",
                done: !meals.isEmpty,
                action: { router.selectedTab = .plan }
            ),
        ]
    }

    private var showGettingStarted: Bool {
        guard !prefs.didDismissGettingStarted else { return false }
        return gettingStartedSteps.contains { !$0.done }
    }

    private var gettingStartedCard: some View {
        let steps = gettingStartedSteps
        let doneCount = steps.filter(\.done).count

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Let's get cooking")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("\(doneCount) of \(steps.count) complete")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Button {
                    Haptics.impact(.light)
                    withAnimation { gettingStartedCollapsed.toggle() }
                } label: {
                    (gettingStartedCollapsed ? Ph.caretDown.regular : Ph.caretUp.regular)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Button {
                    Haptics.impact(.light)
                    withAnimation { prefs.didDismissGettingStarted = true }
                } label: {
                    Ph.x.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityLabel("Dismiss checklist")
            }

            if !gettingStartedCollapsed {
                VStack(spacing: 0) {
                    ForEach(steps) { step in
                        Button {
                            Haptics.impact(.light)
                            step.action()
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Group {
                                    if step.done {
                                        Ph.checkCircle.fill
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundStyle(Theme.Colors.accent)
                                    } else {
                                        Ph.circle.regular
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundStyle(Theme.Colors.border)
                                    }
                                }
                                .frame(width: 20, height: 20)
                                Text(step.title)
                                    .font(.gluttBody)
                                    .foregroundStyle(step.done ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                                    .strikethrough(step.done, color: Theme.Colors.textSecondary)
                                Spacer()
                                if !step.done {
                                    Ph.caretRight.regular
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 12, height: 12)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.sm)
                        }
                        .buttonStyle(.plain)
                        .disabled(step.done)
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Next up

    private func nextUpCard(_ meal: PlannedMeal) -> some View {
        let recipe = meal.recipe!
        let missingLine = TodayPlanner.missingLine(
            for: recipe,
            pantry: pantryItems,
            rules: prefs.dietaryRules,
            allergies: prefs.allergies
        )
        let hasMissing = missingLine != nil

        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: recipe) {
                ZStack(alignment: .bottomLeading) {
                    RecipeImageView(recipe: recipe)
                        .frame(height: 180)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.65)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT UP — \(meal.mealType.label.uppercased())")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(recipe.title)
                            .font(.gluttTitle)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.md) {
                    if let time = meal.exactTime {
                        HStack(spacing: 4) {
                            Ph.forkKnife.regular
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12, height: 12)
                            Text(time.formatted(date: .omitted, time: .shortened))
                        }
                    }
                    if let start = meal.suggestedStartTime {
                        HStack(spacing: 4) {
                            Ph.timer.regular
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12, height: 12)
                            Text("start by \(start.formatted(date: .omitted, time: .shortened))")
                        }
                        .foregroundStyle(Theme.Colors.warning)
                    }
                    HStack(spacing: 4) {
                        Ph.clock.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                        Text(recipe.timeLabel)
                    }
                }
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)

                // Missing ingredients live in one connected strip with their
                // own labeled fixes — not floating icon buttons.
                if let missingLine {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(missingLine)
                            .font(.gluttCaption.weight(.medium))
                            .foregroundStyle(Theme.Colors.warning)
                        HStack(spacing: Theme.Spacing.sm) {
                            Button("Add missing to list") {
                                Haptics.notify(.success)
                                let missing = GroceryListBuilder.missingIngredients(for: recipe, pantry: pantryItems)
                                GroceryListBuilder.add(
                                    ingredients: missing,
                                    from: recipe,
                                    existing: groceryItems,
                                    context: context
                                )
                            }
                            .buttonStyle(.gluttPillFilled)
                            Button("Use what I have") {
                                Haptics.impact(.light)
                                optimizingRecipe = recipe
                            }
                            .buttonStyle(.gluttPill)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.warningTint)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                }

                Button {
                    Haptics.impact(.medium)
                    if hasMissing {
                        checklistRecipe = recipe
                    } else {
                        cookingRecipe = recipe
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Ph.cookingPot.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text("Cook")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttPrimary)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
        .shadow(color: Theme.Colors.textPrimary.opacity(0.08), radius: 10, x: 0, y: 3)
    }

    private var emptyDayCard: some View {
        Button {
            Haptics.impact(.light)
            isAskingWhatToCook = true
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                Ph.sparkle.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Theme.Colors.accent)
                Text("Nothing planned — what should I cook?")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Tap for ideas from your own kitchen")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .buttonStyle(.plain)
        .cardStyle()
    }

    // MARK: - Quick actions

    private var quickActionsRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            quickAction("Import", icon: Ph.link.regular) {
                Haptics.selection()
                router.perform(.importRecipe)
            }
            quickAction("Scan", icon: Ph.camera.regular) {
                Haptics.selection()
                router.perform(.scanPantry)
            }
            quickAction("Log", icon: Ph.forkKnife.regular) {
                Haptics.selection()
                isLoggingFood = true
            }
            quickAction("Ask", icon: Ph.sparkle.regular) {
                Haptics.selection()
                isAskingWhatToCook = true
            }
        }
    }

    /// Deliberately quiet: utilities, not destinations. The hero card is the star.
    private func quickAction(_ label: String, icon: Image, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.Colors.accent.opacity(0.09))
                    .clipShape(Circle())
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Smart cards (max two — attention is finite)

    @ViewBuilder
    private var smartCards: some View {
        let useSoon = TodayPlanner.useSoonItems(pantry: pantryItems)
        let waitingLeftover = leftovers.first { $0.servingsRemaining > 0 && !$0.isFrozen }

        if !useSoon.isEmpty {
            useSoonCard(useSoon)
        }
        if let waitingLeftover {
            leftoverReminder(waitingLeftover)
        }
    }

    private func useSoonCard(_ items: [PantryItem]) -> some View {
        let names = items.prefix(3).map(\.name).joined(separator: ", ")
        return HStack(spacing: Theme.Spacing.md) {
            Ph.leaf.regular
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(items.count == 1 ? "\(names) needs using" : "Use these soon")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if items.count > 1 {
                    Text(names)
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer()
            Button("Find a recipe") {
                Haptics.impact(.light)
                isAskingWhatToCook = true
            }
            .buttonStyle(.gluttPillFilled)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.warningTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func leftoverReminder(_ leftover: Leftover) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Ph.bowlFood.regular
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Leftovers waiting")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(leftover.servingsRemaining.formatted()) servings of \(leftover.title.lowercased())")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button("Eat one") {
                Haptics.notify(.success)
                logLeftoverEaten(leftover)
            }
            .buttonStyle(.gluttPillFilled)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.successTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func logLeftoverEaten(_ leftover: Leftover) {
        let entry = FoodLog(
            title: leftover.title,
            source: .leftover,
            calories: leftover.caloriesPerServing,
            proteinGrams: leftover.proteinPerServing,
            leftover: leftover
        )
        leftover.servingsRemaining = max(0, leftover.servingsRemaining - 1)
        context.insert(entry)
    }

    // MARK: - Nutrition summary (gym/light mode)

    private var nutritionSummary: some View {
        let calories = todaysLogs.compactMap(\.calories).reduce(0, +)
        let protein = todaysLogs.compactMap(\.proteinGrams).reduce(0, +)

        return HStack(spacing: Theme.Spacing.lg) {
            goalGauge(value: calories, goal: prefs.dailyCalorieGoal, label: "calories", unit: "")
            goalGauge(value: protein, goal: prefs.dailyProteinGoal, label: "protein", unit: "g")
        }
        .cardStyle()
    }

    private func goalGauge(value: Int, goal: Int?, label: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)\(unit)")
                    .font(.gluttTitle)
                    .foregroundStyle(Theme.Colors.accent)
                if let goal {
                    Text("/ \(goal)\(unit)")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let goal, goal > 0 {
                ProgressView(value: min(1, Double(value) / Double(goal)))
                    .tint(Theme.Colors.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Timeline & log

    private func mealRow(_ meal: PlannedMeal) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                Haptics.impact(.light)
                editingMeal = meal
            } label: {
                MealCard(meal: meal)
            }
            .buttonStyle(.plain)

            if meal.status == .planned || meal.status == .cooked {
                Button {
                    Haptics.notify(.success)
                    markEaten(meal)
                } label: {
                    Ph.checkCircle.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .accessibilityLabel("Mark eaten")
            }
        }
    }

    private func markEaten(_ meal: PlannedMeal) {
        meal.status = .eaten
        let entry = FoodLog(
            title: meal.displayTitle,
            source: meal.leftover != nil ? .leftover : .cookedMeal,
            calories: meal.recipe?.calories ?? meal.leftover?.caloriesPerServing,
            proteinGrams: meal.recipe?.proteinGrams ?? meal.leftover?.proteinPerServing,
            plannedMeal: meal,
            leftover: meal.leftover
        )
        if let leftover = meal.leftover {
            leftover.servingsRemaining = max(0, leftover.servingsRemaining - 1)
        }
        context.insert(entry)
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                SectionHeader(title: "Eaten today")
                Spacer()
                Button {
                    Haptics.impact(.medium)
                    isLoggingFood = true
                } label: {
                    HStack(spacing: 4) {
                        Ph.plusCircle.fill
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                        Text("Log")
                            .font(.gluttCaption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }

            if todaysLogs.isEmpty {
                Text("Nothing logged yet")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
            } else {
                VStack(spacing: 0) {
                    ForEach(todaysLogs) { entry in
                        logRow(entry)
                        if entry !== todaysLogs.last {
                            Divider().overlay(Theme.Colors.border)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .cardStyle(padding: Theme.Spacing.xs)
            }
        }
    }

    private func logRow(_ entry: FoodLog) -> some View {
        HStack {
            icon(for: entry.source)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if prefs.nutritionMode.showsNutrition, let calories = entry.calories {
                Text("\(calories) cal")
                    .font(.gluttCaption.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .contextMenu {
            Button("Delete", role: .destructive) {
                Haptics.impact(.rigid)
                context.delete(entry)
            }
        }
    }

    private func icon(for source: FoodLogSource) -> Image {
        switch source {
        case .cookedMeal: Ph.cookingPot.regular
        case .leftover:   Ph.bowlFood.regular
        case .restaurant: Ph.storefront.regular
        case .quickAdd:   Ph.lightning.regular
        case .photo:      Ph.camera.regular
        case .barcode:    Ph.barcode.regular
        case .manual:     Ph.pencil.regular
        }
    }
}
