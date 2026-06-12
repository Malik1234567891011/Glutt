import SwiftData
import SwiftUI

/// Today: planned meals with one-tap resolution, the day's food log,
/// leftovers nudge, and the assistant. Full command center lands Phase 8.
struct TodayView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query private var meals: [PlannedMeal]
    @Query private var leftovers: [Leftover]
    @Query(sort: \FoodLog.timestamp, order: .reverse) private var logs: [FoodLog]

    @State private var isAskingWhatToCook = false
    @State private var isShowingSettings = false
    @State private var isLoggingFood = false
    @State private var editingMeal: PlannedMeal?

    private var todaysMeals: [PlannedMeal] {
        let today = Calendar.current.startOfDay(for: .now)
        return meals
            .filter { $0.date == today }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
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
                    Text(greeting)
                        .font(.gluttLargeTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    if prefs.nutritionMode.showsNutrition {
                        nutritionSummary
                    }

                    askButton

                    if todaysMeals.isEmpty {
                        EmptyStateView(
                            icon: "sun.max",
                            title: "Nothing planned today",
                            message: "Plan a meal or ask what to cook — your day starts here."
                        )
                    } else {
                        SectionHeader(title: "Today's meals")
                        ForEach(todaysMeals) { meal in
                            mealRow(meal)
                        }
                    }

                    logSection

                    if let leftover = leftovers.first(where: { $0.servingsRemaining > 0 && !$0.isFrozen }) {
                        leftoverReminder(leftover)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $isAskingWhatToCook) {
                WhatToCookView()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isLoggingFood) {
                LogFoodView()
            }
            .sheet(item: $editingMeal) { meal in
                EditMealSheet(meal: meal)
                    .presentationDetents([.medium, .large])
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

    // MARK: - Sections

    /// Calm numbers, no red ink: just where you are against the goal.
    private var nutritionSummary: some View {
        let calories = todaysLogs.compactMap(\.calories).reduce(0, +)
        let protein = todaysLogs.compactMap(\.proteinGrams).reduce(0, +)

        return HStack(spacing: Theme.Spacing.lg) {
            goalGauge(
                value: calories,
                goal: prefs.dailyCalorieGoal,
                label: "calories",
                unit: ""
            )
            goalGauge(
                value: protein,
                goal: prefs.dailyProteinGoal,
                label: "protein",
                unit: "g"
            )
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

    /// One-tap resolution: the checkmark logs it and marks it eaten.
    private func mealRow(_ meal: PlannedMeal) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                editingMeal = meal
            } label: {
                MealCard(meal: meal)
            }
            .buttonStyle(.plain)

            if meal.status == .planned || meal.status == .cooked {
                Button {
                    markEaten(meal)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
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
                    isLoggingFood = true
                } label: {
                    Label("Log", systemImage: "plus.circle.fill")
                        .font(.gluttCaption.weight(.semibold))
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
            Image(systemName: icon(for: entry.source))
                .font(.caption)
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
            Button("Delete", systemImage: "trash", role: .destructive) {
                context.delete(entry)
            }
        }
    }

    private func icon(for source: FoodLogSource) -> String {
        switch source {
        case .cookedMeal: "frying.pan"
        case .leftover: "takeoutbag.and.cup.and.straw"
        case .restaurant: "storefront"
        case .quickAdd: "bolt"
        case .photo: "camera"
        case .barcode: "barcode"
        case .manual: "pencil"
        }
    }

    private var askButton: some View {
        Button {
            isAskingWhatToCook = true
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What should I cook?")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Based on your kitchen, your time, and your mood")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .cardStyle()
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private func leftoverReminder(_ leftover: Leftover) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "takeoutbag.and.cup.and.straw")
                .font(.title3)
                .foregroundStyle(Theme.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Leftovers waiting")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("You still have \(leftover.servingsRemaining.formatted()) servings of \(leftover.title.lowercased()).")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.warningTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
