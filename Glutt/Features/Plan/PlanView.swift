import PhosphorSwift
import SwiftData
import SwiftUI

/// The week: stacked day sections (not a dense calendar), prep tasks,
/// grocery generation, and the planning wizard.
struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query(sort: \PlannedMeal.date) private var allMeals: [PlannedMeal]
    @Query private var pantryItems: [PantryItem]
    @Query private var groceryItems: [GroceryItem]
    @Query private var leftovers: [Leftover]

    @State private var addingMealForDay: Date?
    @State private var editingMeal: PlannedMeal?
    @State private var isShowingWizard = false
    @State private var didGenerateGroceries = false

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }

    /// The next 7 days, always shown even when empty.
    private var weekDays: [Date] {
        (0..<7).map { calendar.date(byAdding: .day, value: $0, to: today)! }
    }

    private var weekMeals: [PlannedMeal] {
        let end = calendar.date(byAdding: .day, value: 7, to: today)!
        return allMeals.filter { $0.date >= today && $0.date < end }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    weekSummary

                    ForEach(weekDays, id: \.self) { day in
                        daySection(day)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .contentMargins(.bottom, 56, for: .scrollContent)
            .background(Theme.Colors.background)
            .navigationTitle("Plan")
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.impact(.medium)
                        isShowingWizard = true
                    } label: {
                        HStack(spacing: 5) {
                            Ph.magicWand.bold
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                            Text("Plan my week")
                                .font(.gluttCaption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.gluttPillFilled)
                }
            }
            .sheet(item: $addingMealForDay) { day in
                AddMealSheet(day: day)
            }
            .sheet(item: $editingMeal) { meal in
                EditMealSheet(meal: meal)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isShowingWizard) {
                WeekPlannerWizard()
            }
            .onAppear {
                if router.demoWizardOnLaunch {
                    router.demoWizardOnLaunch = false
                    isShowingWizard = true
                }
            }
            .alert("Grocery list updated", isPresented: $didGenerateGroceries) {
                Button("OK") {}
            } message: {
                Text("Missing ingredients from this week's meals were added to your Kitchen → Groceries.")
            }
        }
    }

    // MARK: - Week summary

    private var weekSummary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("This week")
                .font(.gluttTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            HStack(spacing: Theme.Spacing.lg) {
                summaryStat(value: "\(weekMeals.count)", label: "meals planned")
                summaryStat(value: cookingTimeLabel, label: "cooking time")
                summaryStat(value: "\(groceryItems.filter { !$0.isChecked }.count)", label: "items to buy")
            }

            // One or two live status lines — the plan should feel like it
            // knows your kitchen, not just count rows.
            if let coverage = pantryCoverage {
                HStack(spacing: 6) {
                    if coverage >= 100 {
                        Ph.checkCircle.fill
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                            .foregroundStyle(Theme.Colors.accent)
                    } else {
                        Ph.basket.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                            .foregroundStyle(coverage >= 70 ? Theme.Colors.accent : Theme.Colors.warning)
                    }
                    Text(
                        coverage >= 100
                            ? "You already have everything for this week"
                            : "You already have \(coverage)% of this week's ingredients"
                    )
                    .font(.gluttCaption.weight(.medium))
                    .foregroundStyle(coverage >= 70 ? Theme.Colors.accent : Theme.Colors.warning)
                }
            }
            let reusable = leftovers.filter { $0.servingsRemaining > 0 && !$0.isFrozen }.count
            if reusable > 0 {
                HStack(spacing: 6) {
                    Ph.bowlFood.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("^[\(reusable) leftover](inflect: true) ready to reuse")
                        .font(.gluttCaption.weight(.medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }

            Button("Generate grocery list from plan") {
                Haptics.notify(.success)
                generateGroceries()
            }
            .buttonStyle(.gluttSecondary)
            .disabled(weekMeals.compactMap(\.recipe).isEmpty)
        }
        .cardStyle()
    }

    private func summaryStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.gluttTitle)
                .foregroundStyle(Theme.Colors.accent)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// Aggregate pantry coverage across the week's recipe meals (nil when no recipes planned).
    private var pantryCoverage: Int? {
        let recipes = weekMeals.compactMap(\.recipe)
        guard !recipes.isEmpty else { return nil }
        var owned = 0
        var total = 0
        for recipe in recipes {
            let match = PantryMatcher.match(recipe: recipe, pantry: pantryItems)
            owned += match.ownedCount
            total += match.totalCount
        }
        guard total > 0 else { return nil }
        return Int((Double(owned) / Double(total) * 100).rounded())
    }

    private var cookingTimeLabel: String {
        let minutes = weekMeals.compactMap(\.recipe).reduce(0) { $0 + $1.totalMinutes }
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private func generateGroceries() {
        for meal in weekMeals {
            guard let recipe = meal.recipe else { continue }
            let missing = GroceryListBuilder.missingIngredients(for: recipe, pantry: pantryItems)
            GroceryListBuilder.add(
                ingredients: missing,
                from: recipe,
                existing: (try? context.fetch(FetchDescriptor<GroceryItem>())) ?? [],
                context: context
            )
        }
        didGenerateGroceries = true
    }

    // MARK: - Day sections

    private func daySection(_ day: Date) -> some View {
        let meals = weekMeals
            .filter { $0.date == day }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
        let prepTasks = meals
            .compactMap(\.recipe)
            .flatMap(PrepDetector.tasks(for:))

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(day.formatted(.dateTime.day()))
                    .font(.gluttHeadline)
                    .foregroundStyle(day == today ? .white : Theme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(day == today ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.08))
                    .clipShape(Circle())
                Text(dayLabel(day))
                    .font(.gluttHeadline)
                    .foregroundStyle(day == today ? Theme.Colors.accent : Theme.Colors.textPrimary)
                Spacer()
                Button {
                    Haptics.impact(.medium)
                    addingMealForDay = day
                } label: {
                    Ph.plusCircle.fill
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
            }

            if meals.isEmpty {
                Button {
                    Haptics.impact(.medium)
                    addingMealForDay = day
                } label: {
                    HStack(spacing: 6) {
                        Ph.plus.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                        Text("Add a meal")
                    }
                    .font(.gluttCaption.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Theme.Colors.border, style: StrokeStyle(lineWidth: 1, dash: [6]))
                    )
                }
                .buttonStyle(.plain)
            } else {
                ForEach(meals) { meal in
                    mealRow(meal)
                }
                ForEach(prepTasks, id: \.text) { task in
                    HStack(spacing: 6) {
                        Ph.alarm.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 11, height: 11)
                            .foregroundStyle(Theme.Colors.warning)
                        Text(task.text)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.warning)
                    }
                }
            }
        }
    }

    private func mealRow(_ meal: PlannedMeal) -> some View {
        Button {
            Haptics.impact(.light)
            editingMeal = meal
        } label: {
            MealCard(meal: meal)
        }
        .buttonStyle(.plain)
    }

    private func dayLabel(_ day: Date) -> String {
        if day == today { return "Today" }
        if day == calendar.date(byAdding: .day, value: 1, to: today) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide))
    }
}

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}
