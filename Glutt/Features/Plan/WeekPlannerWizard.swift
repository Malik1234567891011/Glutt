import SwiftData
import SwiftUI

/// Guided "plan my week": a few questions, a swappable draft, then commit.
struct WeekPlannerWizard: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var recipes: [Recipe]
    @Query private var pantryItems: [PantryItem]
    @Query private var leftovers: [Leftover]
    @Query private var cookSessions: [CookSession]

    enum Phase {
        case questions
        case draft
    }

    @State private var phase: Phase = .questions
    @State private var days = 5
    @State private var includeLunch = false
    @State private var includeDinner = true
    @State private var useLeftovers = true
    @State private var alsoGenerateGroceries = true
    @State private var draftSlots: [WeekPlanner.DraftSlot] = []

    private var plannerInput: WeekPlanner.Input {
        WeekPlanner.Input(
            days: days,
            mealTypes: selectedMealTypes,
            useLeftovers: useLeftovers,
            recipes: recipes,
            pantry: pantryItems,
            leftovers: leftovers,
            recentSessions: cookSessions
        )
    }

    private var selectedMealTypes: [MealType] {
        var types: [MealType] = []
        if includeLunch { types.append(.lunch) }
        if includeDinner { types.append(.dinner) }
        return types
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .questions: questionsForm
                case .draft: draftList
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle("Plan my week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Step 1: questions

    private var questionsForm: some View {
        Form {
            Section("How many days?") {
                Stepper("\(days) days", value: $days, in: 2...7)
            }
            Section("Which meals?") {
                Toggle("Lunch", isOn: $includeLunch)
                Toggle("Dinner", isOn: $includeDinner)
            }
            Section {
                Toggle("Use my leftovers first", isOn: $useLeftovers)
                Toggle("Generate grocery list after", isOn: $alsoGenerateGroceries)
            }
            Section {
                Button("Build my week") {
                    draftSlots = WeekPlanner.draft(plannerInput)
                    phase = .draft
                }
                .disabled(selectedMealTypes.isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Step 2: review the draft

    private var draftList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(groupedDays, id: \.self) { day in
                    Section(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                        ForEach(draftSlots.filter { $0.date == day }) { slot in
                            draftRow(slot)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)

            VStack(spacing: Theme.Spacing.sm) {
                Button("Looks good — add to plan") {
                    commit()
                }
                .buttonStyle(.gluttPrimary)
                Button("Start over") {
                    phase = .questions
                }
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var groupedDays: [Date] {
        var seen: [Date] = []
        for slot in draftSlots where !seen.contains(slot.date) {
            seen.append(slot.date)
        }
        return seen
    }

    private func draftRow(_ slot: WeekPlanner.DraftSlot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.mealType.label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(slot.title)
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let recipe = slot.recipe {
                    let match = PantryMatcher.match(recipe: recipe, pantry: pantryItems)
                    Text("\(recipe.totalMinutes) min · have \(match.ownedCount)/\(match.totalCount)")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer()
            if slot.recipe != nil {
                Button {
                    swapSlot(slot)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func swapSlot(_ slot: WeekPlanner.DraftSlot) {
        guard let index = draftSlots.firstIndex(where: { $0.id == slot.id }),
              let replacement = WeekPlanner.swap(slot: slot, in: draftSlots, input: plannerInput)
        else { return }
        draftSlots[index].recipe = replacement
    }

    private func commit() {
        for slot in draftSlots where slot.recipe != nil || slot.leftover != nil {
            let meal = PlannedMeal(
                date: slot.date,
                mealType: slot.mealType,
                recipe: slot.recipe,
                leftover: slot.leftover
            )
            context.insert(meal)
            ReminderScheduler.schedule(for: meal)
        }
        if alsoGenerateGroceries {
            let existing = (try? context.fetch(FetchDescriptor<GroceryItem>())) ?? []
            for slot in draftSlots {
                guard let recipe = slot.recipe else { continue }
                let missing = GroceryListBuilder.missingIngredients(for: recipe, pantry: pantryItems)
                GroceryListBuilder.add(ingredients: missing, from: recipe, existing: existing, context: context)
            }
        }
        ReminderScheduler.requestPermissionIfNeeded()
        dismiss()
    }
}
