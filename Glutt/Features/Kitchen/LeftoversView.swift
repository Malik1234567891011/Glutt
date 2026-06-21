import SwiftData
import SwiftUI

/// Cooked food that's still around: eat it, freeze it, plan it, or toss it.
struct LeftoversView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Leftover.cookedAt, order: .reverse) private var leftovers: [Leftover]

    @State private var isAddingManually = false
    @State private var planningLeftover: Leftover?
    @State private var remixingLeftover: Leftover?

    private var fresh: [Leftover] { leftovers.filter { !$0.isFrozen && $0.servingsRemaining > 0 } }
    private var frozen: [Leftover] { leftovers.filter { $0.isFrozen && $0.servingsRemaining > 0 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if fresh.isEmpty && frozen.isEmpty {
                    EmptyStateView(
                        icon: "takeoutbag.and.cup.and.straw",
                        title: "No leftovers",
                        message: "Finish cooking a recipe and Glutt tracks the servings you didn't eat.",
                        actionLabel: "Add one manually",
                        action: { isAddingManually = true }
                    )
                } else {
                    ForEach(fresh) { leftover in
                        leftoverCard(leftover)
                    }
                    if !frozen.isEmpty {
                        HStack(spacing: Theme.Spacing.xs) {
                            Ph.snowflake.regular
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text("Freezer")
                                .font(.gluttHeadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        ForEach(frozen) { leftover in
                            leftoverCard(leftover)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.impact(.light)
                    isAddingManually = true
                } label: {
                    Ph.plus.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .sheet(isPresented: $isAddingManually) {
            LeftoverEditorView()
        }
        .sheet(item: $planningLeftover) { leftover in
            PlanLeftoverSheet(leftover: leftover)
                .presentationDetents([.medium])
        }
        .sheet(item: $remixingLeftover) { leftover in
            LeftoverRemixSheet(leftover: leftover)
                .presentationDetents([.medium, .large])
        }
    }

    private func leftoverCard(_ leftover: Leftover) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(leftover.title)
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("\(leftover.servingsRemaining.formatted()) servings · cooked \(ageLabel(leftover))")
                        .font(.gluttCaption)
                        .foregroundStyle(staleness(leftover))
                }
                Spacer()
                if leftover.isFrozen {
                    Ph.snowflake.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button("Log as eaten") {
                    Haptics.notify(.success)
                    eat(leftover)
                }
                .buttonStyle(.gluttPill)
                Button("Remix") {
                    Haptics.impact(.medium)
                    remixingLeftover = leftover
                }
                .buttonStyle(.gluttPillFilled)
                Button("Add to plan") {
                    Haptics.notify(.success)
                    planningLeftover = leftover
                }
                .buttonStyle(.gluttPill)
                Button(leftover.isFrozen ? "Thaw" : "Freeze") {
                    Haptics.impact(.light)
                    leftover.isFrozen.toggle()
                }
                .buttonStyle(.gluttPill)
                Spacer()
                Button {
                    Haptics.notify(.warning)
                    context.delete(leftover)
                } label: {
                    Ph.trash.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Theme.Colors.tomato)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    private func eat(_ leftover: Leftover) {
        let eaten = min(1, leftover.servingsRemaining)
        leftover.servingsRemaining -= eaten

        let log = FoodLog(
            title: leftover.title,
            source: .leftover,
            calories: leftover.caloriesPerServing.map { Int(Double($0) * eaten) },
            proteinGrams: leftover.proteinPerServing.map { Int(Double($0) * eaten) },
            leftover: leftover
        )
        context.insert(log)

        if leftover.servingsRemaining <= 0 {
            context.delete(leftover)
        }
    }

    private func ageLabel(_ leftover: Leftover) -> String {
        switch leftover.ageInDays {
        case 0: "today"
        case 1: "yesterday"
        default: "\(leftover.ageInDays) days ago"
        }
    }

    private func staleness(_ leftover: Leftover) -> Color {
        if leftover.isFrozen { return Theme.Colors.textSecondary }
        return leftover.ageInDays >= 3 ? Theme.Colors.tomato : Theme.Colors.textSecondary
    }
}

/// Manual leftover entry ("half a lasagna from mom").
struct LeftoverEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var servings = 2.0
    @State private var isFrozen = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("What is it?", text: $title)
                Stepper("Servings: \(servings.formatted())", value: $servings, in: 0.5...24, step: 0.5)
                    .onChange(of: servings) {
                        Haptics.selection()
                    }
                Toggle("It's in the freezer", isOn: $isFrozen)
                    .hapticOnChange(of: isFrozen)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Add leftover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Haptics.notify(.success)
                        let leftover = Leftover(title: title, servingsRemaining: servings, isFrozen: isFrozen)
                        context.insert(leftover)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Quick "leftovers for lunch tomorrow" scheduling.
struct PlanLeftoverSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let leftover: Leftover

    @State private var dayOffset = 1
    @State private var mealType: MealType = .lunch

    var body: some View {
        NavigationStack {
            Form {
                Picker("Day", selection: $dayOffset) {
                    Text("Today").tag(0)
                    Text("Tomorrow").tag(1)
                    ForEach(2..<7) { offset in
                        Text(dayLabel(offset)).tag(offset)
                    }
                }
                .onChange(of: dayOffset) {
                    Haptics.selection()
                }
                Picker("Meal", selection: $mealType) {
                    ForEach(MealType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .onChange(of: mealType) {
                    Haptics.selection()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Plan \u{201C}\(leftover.title)\u{201D}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to plan") {
                        Haptics.notify(.success)
                        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now)!
                        context.insert(PlannedMeal(date: date, mealType: mealType, leftover: leftover))
                        dismiss()
                    }
                }
            }
        }
    }

    private func dayLabel(_ offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: .now)!
        return date.formatted(.dateTime.weekday(.wide))
    }
}
