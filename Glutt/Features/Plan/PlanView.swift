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
                        isShowingWizard = true
                    } label: {
                        Label("Plan my week", systemImage: "wand.and.stars")
                            .labelStyle(.titleAndIcon)
                            .font(.gluttCaption.weight(.semibold))
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
            Button("Generate grocery list from plan") {
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
                    addingMealForDay = day
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }

            if meals.isEmpty {
                Button {
                    addingMealForDay = day
                } label: {
                    HStack {
                        Image(systemName: "plus")
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
                    Label(task.text, systemImage: "alarm")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.warning)
                }
            }
        }
    }

    private func mealRow(_ meal: PlannedMeal) -> some View {
        Button {
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
