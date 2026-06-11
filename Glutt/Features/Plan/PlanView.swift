import SwiftData
import SwiftUI

/// Phase 0 placeholder for the week planner. Full planning, grocery
/// generation, and reminders arrive in Phase 5.
struct PlanView: View {
    @Query(sort: \PlannedMeal.date) private var meals: [PlannedMeal]

    private var mealsByDay: [(day: Date, meals: [PlannedMeal])] {
        Dictionary(grouping: meals) { $0.date }
            .sorted { $0.key < $1.key }
            .map { (day: $0.key, meals: $0.value.sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if meals.isEmpty {
                        EmptyStateView(
                            icon: "calendar",
                            title: "Nothing planned yet",
                            message: "Plan your week and Glutt will build the grocery list and remind you when to start cooking."
                        )
                    } else {
                        ForEach(mealsByDay, id: \.day) { group in
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text(group.day, format: .dateTime.weekday(.wide).month().day())
                                    .font(.gluttHeadline)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                ForEach(group.meals) { meal in
                                    MealCard(meal: meal)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Plan")
        }
    }
}
