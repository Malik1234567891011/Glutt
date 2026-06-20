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
                        .onChange(of: selectedDay) { Haptics.selection() }
                    }
                }
                Section {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mealType) { Haptics.selection() }

                    Toggle("Exact time", isOn: $hasExactTime)
                        .onChange(of: hasExactTime) { Haptics.impact(.light) }
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
                        .onChange(of: source) { Haptics.selection() }
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
                    Button("Add") {
                        Haptics.notify(.success)
                        save()
                    }
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
                    Haptics.selection()
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
                            Ph.check.bold
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
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
                    Haptics.selection()
                    selectedLeftover = leftover
                } label: {
                    HStack {
                        Text("\(leftover.title) (\(leftover.servingsRemaining.formatted()) left)")
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        if selectedLeftover === leftover {
                            Ph.check.bold
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
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

/// Tap a planned meal -> this sheet. Everything you'd want to do with it:
/// view the recipe, mark status, change time/type, move it, remove it.
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
                    HStack {
                        Text(meal.displayTitle)
                            .font(.gluttHeadline)
                        Spacer()
                        Text(meal.date.formatted(.dateTime.weekday(.wide)))
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    if let recipe = meal.recipe {
                        NavigationLink("View recipe") {
                            RecipeDetailView(recipe: recipe)
                        }
                    }
                }

                Section("Status") {
                    Picker("Status", selection: $meal.status) {
                        Text("Planned").tag(MealStatus.planned)
                        Text("Cooked").tag(MealStatus.cooked)
                        Text("Eaten").tag(MealStatus.eaten)
                        Text("Skipped").tag(MealStatus.skipped)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: meal.status) { Haptics.selection() }
                }

                Section {
                    Picker("Meal", selection: $meal.mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .onChange(of: meal.mealType) { Haptics.selection() }
                    Toggle("Exact time", isOn: $hasExactTime)
                        .onChange(of: hasExactTime) { Haptics.impact(.light) }
                    if hasExactTime {
                        DatePicker("At", selection: $exactTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    Button("Move to tomorrow", systemImage: "arrow.right") {
                        Haptics.impact(.medium)
                        meal.date = Calendar.current.date(byAdding: .day, value: 1, to: meal.date)!
                        ReminderScheduler.schedule(for: meal)
                        dismiss()
                    }
                    Button("Remove from plan", systemImage: "trash", role: .destructive) {
                        Haptics.notify(.warning)
                        ReminderScheduler.cancel(for: meal)
                        context.delete(meal)
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.impact(.medium)
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
