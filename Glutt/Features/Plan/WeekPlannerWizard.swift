import PhosphorSwift
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
            recentSessions: cookSessions,
            rules: UserPrefs.current(in: context).dietaryRules,
            allergies: UserPrefs.current(in: context).allergies
        )
    }

    private var selectedMealTypes: [MealType] {
        var types: [MealType] = []
        if includeLunch { types.append(.lunch) }
        if includeDinner { types.append(.dinner) }
        return types
    }

    // Phase index: 0 = questions, 1 = draft
    private var phaseIndex: Int { phase == .questions ? 0 : 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // PageDots progress indicator
                PageDots(count: 2, index: phaseIndex)
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)

                Group {
                    switch phase {
                    case .questions: questionsForm
                    case .draft: draftList
                    }
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
        VStack(spacing: 0) {
            Form {
                Section("How many days?") {
                    Stepper("\(days) days", value: $days, in: 2...7)
                        .onChange(of: days) { Haptics.impact(.light) }
                }
                Section("Which meals?") {
                    Toggle("Lunch", isOn: $includeLunch)
                        .onChange(of: includeLunch) { Haptics.impact(.light) }
                    Toggle("Dinner", isOn: $includeDinner)
                        .onChange(of: includeDinner) { Haptics.impact(.light) }
                }
                Section {
                    Toggle("Use my leftovers first", isOn: $useLeftovers)
                        .onChange(of: useLeftovers) { Haptics.impact(.light) }
                    Toggle("Generate grocery list after", isOn: $alsoGenerateGroceries)
                        .onChange(of: alsoGenerateGroceries) { Haptics.impact(.light) }
                }
            }
            .scrollContentBackground(.hidden)

            // Green capsule CTA — consistent with onboarding style
            Button {
                Haptics.impact(.medium)
                draftSlots = WeekPlanner.draft(plannerInput)
                withAnimation { phase = .draft }
            } label: {
                HStack(spacing: 8) {
                    Ph.sparkle.bold
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                    Text("Build my week")
                        .font(.gluttBody.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.gluttPrimary)
            .disabled(selectedMealTypes.isEmpty)
            .padding(Theme.Spacing.md)
        }
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
                // Green capsule primary CTA
                Button {
                    Haptics.notify(.success)
                    commit()
                } label: {
                    HStack(spacing: 8) {
                        Ph.checkCircle.fill
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        Text("Looks good — add to plan")
                            .font(.gluttBody.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttPrimary)

                Button {
                    Haptics.impact(.light)
                    withAnimation { phase = .questions }
                } label: {
                    Text("Start over")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
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
                    Haptics.impact(.light)
                    swapSlot(slot)
                } label: {
                    Ph.arrowsClockwise.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
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
