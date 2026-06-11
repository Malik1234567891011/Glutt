import SwiftData
import SwiftUI

/// Add a meal to a day: pick a recipe, use a leftover, or note a freeform
/// meal ("eating out"). Optional exact time enables cooking-start reminders.
struct AddMealSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Query private var leftovers: [Leftover]
    @Query private var pantryItems: [PantryItem]

    let day: Date
    /// Skips the source picker when launched from a recipe's detail screen.
    var fixedRecipe: Recipe?

    enum Source: String, CaseIterable {
        case recipe = "Recipe"
        case leftover = "Leftover"
        case other = "Other"
    }

    @State private var source: Source = .recipe
    @State private var selectedDay: Date?
    @State private var mealType: MealType = .dinner
    @State private var selectedRecipe: Recipe?
    @State private var selectedLeftover: Leftover?
    @State private var freeformTitle = ""
    @State private var hasExactTime = false
    @State private var exactTime = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now)!
    @State private var searchText = ""

    private var effectiveDay: Date { selectedDay ?? day }

    private var dayBinding: Binding<Date> {
        Binding(get: { effectiveDay }, set: { selectedDay = $0 })
    }

    private var upcomingDays: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: today)! }
    }

    private func dayLabel(_ candidate: Date) -> String {
        let today = Calendar.current.startOfDay(for: .now)
        if candidate == today { return "Today" }
        if candidate == Calendar.current.date(byAdding: .day, value: 1, to: today) { return "Tomorrow" }
        return candidate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var availableLeftovers: [Leftover] {
        leftovers.filter { $0.servingsRemaining > 0 }
    }

    private var filteredRecipes: [Recipe] {
        let library = recipes.filter { $0.parentRecipe == nil }
        guard !searchText.isEmpty else { return library }
        return library.filter { $0.title.lowercased().contains(searchText.lowercased()) }
    }

    private var canSave: Bool {
        switch source {
        case .recipe: fixedRecipe != nil || selectedRecipe != nil
        case .leftover: selectedLeftover != nil
        case .other: !freeformTitle.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if fixedRecipe != nil {
                    Section {
                        Picker("Day", selection: dayBinding) {
                            ForEach(upcomingDays, id: \.self) { candidate in
                                Text(dayLabel(candidate)).tag(candidate)
                            }
                        }
                    }
                }
                Section {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Exact time", isOn: $hasExactTime)
                    if hasExactTime {
                        DatePicker("At", selection: $exactTime, displayedComponents: .hourAndMinute)
                    }
                }

                if fixedRecipe == nil {
                    Section {
                        Picker("What", selection: $source) {
                            ForEach(Source.allCases, id: \.self) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    switch source {
                    case .recipe: recipePicker
                    case .leftover: leftoverPicker
                    case .other:
                        Section {
                            TextField("e.g. Eating out, mom's dinner…", text: $freeformTitle)
                        }
                    }
                } else {
                    Section {
                        Text(fixedRecipe!.title)
                            .font(.gluttHeadline)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Add to \(effectiveDay.formatted(.dateTime.weekday(.wide)))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var recipePicker: some View {
        Section("Pick a recipe") {
            TextField("Search…", text: $searchText)
            ForEach(filteredRecipes.prefix(20)) { recipe in
                Button {
                    selectedRecipe = recipe
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.title)
                                .font(.gluttBody)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            let match = PantryMatcher.match(recipe: recipe, pantry: pantryItems)
                            Text("\(recipe.totalMinutes) min · have \(match.ownedCount)/\(match.totalCount)")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        if selectedRecipe === recipe {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                }
            }
        }
    }

    private var leftoverPicker: some View {
        Section("Pick a leftover") {
            if availableLeftovers.isEmpty {
                Text("No leftovers right now")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ForEach(availableLeftovers) { leftover in
                Button {
                    selectedLeftover = leftover
                } label: {
                    HStack {
                        Text("\(leftover.title) (\(leftover.servingsRemaining.formatted()) left)")
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        if selectedLeftover === leftover {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                }
            }
        }
    }

    private func save() {
        let time = hasExactTime ? combine(day: effectiveDay, time: exactTime) : nil
        let meal = PlannedMeal(
            date: effectiveDay,
            mealType: mealType,
            exactTime: time,
            recipe: fixedRecipe ?? (source == .recipe ? selectedRecipe : nil),
            leftover: source == .leftover ? selectedLeftover : nil,
            freeformTitle: source == .other ? freeformTitle : nil
        )
        context.insert(meal)
        ReminderScheduler.requestPermissionIfNeeded()
        ReminderScheduler.schedule(for: meal)
        dismiss()
    }

    private func combine(day: Date, time: Date) -> Date {
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
        return Calendar.current.date(
            bySettingHour: timeComponents.hour ?? 19,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: day
        )!
    }
}

/// Edit an existing planned meal: time, type, status, day.
struct EditMealSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var meal: PlannedMeal

    @State private var hasExactTime: Bool
    @State private var exactTime: Date

    init(meal: PlannedMeal) {
        self.meal = meal
        _hasExactTime = State(initialValue: meal.exactTime != nil)
        _exactTime = State(initialValue: meal.exactTime ?? Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: meal.date)!)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(meal.displayTitle)
                        .font(.gluttHeadline)
                }
                Picker("Meal", selection: $meal.mealType) {
                    ForEach(MealType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                Picker("Status", selection: $meal.status) {
                    Text("Planned").tag(MealStatus.planned)
                    Text("Cooked").tag(MealStatus.cooked)
                    Text("Eaten").tag(MealStatus.eaten)
                    Text("Skipped").tag(MealStatus.skipped)
                    Text("Replaced").tag(MealStatus.replaced)
                }
                Toggle("Exact time", isOn: $hasExactTime)
                if hasExactTime {
                    DatePicker("At", selection: $exactTime, displayedComponents: .hourAndMinute)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        meal.exactTime = hasExactTime
                            ? Calendar.current.date(
                                bySettingHour: Calendar.current.component(.hour, from: exactTime),
                                minute: Calendar.current.component(.minute, from: exactTime),
                                second: 0,
                                of: meal.date
                            )
                            : nil
                        ReminderScheduler.schedule(for: meal)
                        dismiss()
                    }
                }
            }
        }
    }
}
