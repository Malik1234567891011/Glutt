import SwiftData
import SwiftUI

/// One shopping list, five dinners.
///
/// Opened from the Recipes tab, because that is where the result lives: saving
/// a week drops five ordinary recipes into the library, grouped in a
/// collection, and pushes one merged list into Groceries.
///
/// Three phases. Setup asks what the week has to look like, generation makes
/// the whole set in one pass so the meals overlap, and the plan shows the
/// dinners next to the single shop they add up to. Swapping a dinner is held to
/// the ingredients the others already established, so the list barely moves,
/// and whatever did move is reported.
struct WeekPlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantryItems: [PantryItem]

    /// Handed the saved collection so the caller can open it.
    var onSaved: (RecipeCollection) -> Void = { _ in }

    private enum Phase { case setup, generating, plan }

    @State private var phase: Phase = .setup
    @State private var mealCount = 5
    @State private var servings = 4
    @State private var budget = 60
    /// Distinct things to buy. Defaults to about four and a half per dinner,
    /// which is roughly what the old fixed "20 to 28 for five" worked out to,
    /// so the untouched default plans the same week it always did.
    @State private var ingredientTarget = 22
    /// Set once the cook moves the ingredient stepper themselves, after which
    /// the dinner count stops nudging it.
    @State private var hasTunedIngredients = false
    @State private var mustIncludeText = ""

    /// Roughly four and a half items per dinner, which is about what the old
    /// fixed "20 to 28 items for five dinners" came to.
    static func suggestedIngredients(for mealCount: Int) -> Int {
        min(35, max(8, Int((Double(mealCount) * 4.5).rounded())))
    }
    @State private var avoidText = ""
    @State private var plan: WeekPlanner.Plan?
    @State private var lines: [MealPlanConsolidator.Line] = []
    @State private var listChange: MealPlanConsolidator.Change?
    @State private var swappingIndex: Int?
    @State private var refineText = ""
    @State private var isRefining = false
    @State private var errorMessage: String?

    private var toBuy: [MealPlanConsolidator.Line] { lines.filter { !$0.alreadyHave } }
    private var alreadyHave: [MealPlanConsolidator.Line] { lines.filter(\.alreadyHave) }
    private var isBusy: Bool { swappingIndex != nil || isRefining }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    switch phase {
                    case .setup: setupBody
                    case .generating: generatingBody
                    case .plan: planBody
                    }
                }
                .padding(Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle(phase == .plan ? "Your week" : "Plan a week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if phase == .plan {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(isBusy)
                    }
                }
            }
            .alert("Couldn't plan the week", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Setup

    private var setupBody: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("One shop, a week of dinners")
                    .font(.gluttTitle)
                    .foregroundStyle(Theme.Colors.heading)
                Text(headline)
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if !LLMClient.isConfigured {
                EmptyStateView(
                    icon: "sparkles",
                    title: "Week planning needs Glutt's AI",
                    message: "This build isn't connected yet, so planning a week is unavailable."
                )
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    settingRow("Dinners", detail: "Cooked once each") {
                        GluttStepper(value: $mealCount, in: 3...7, step: 1) { "\($0)" }
                    }
                    settingRow("Servings", detail: "Per dinner") {
                        GluttStepper(value: $servings, in: 1...8, step: 1) { "\($0)" }
                    }
                    settingRow("Budget", detail: "What you'd like to spend") {
                        GluttStepper(value: $budget, in: 20...200, step: 10) { "$\($0)" }
                    }
                    settingRow("Ingredients", detail: "How much to carry home") {
                        GluttStepper(value: $ingredientTarget, in: 8...35, step: 1) { "\($0)" }
                    }
                }
                .cardStyle()
                // Follow the dinner count until the cook overrules it. Leaving
                // it pinned at 22 while they drop to three dinners would suggest
                // a full week's shop for half a week's food, and most people
                // never touch a control that already looks right.
                .onChange(of: mealCount) { _, count in
                    guard !hasTunedIngredients else { return }
                    ingredientTarget = Self.suggestedIngredients(for: count)
                }
                .onChange(of: ingredientTarget) { _, target in
                    if target != Self.suggestedIngredients(for: mealCount) {
                        hasTunedIngredients = true
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionLabel(text: "Anything you want in there")
                    TextField("salmon, halloumi, the mangoes on offer", text: $mustIncludeText, axis: .vertical)
                        .font(.gluttBody)
                        .lineLimit(1...3)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.card)
                        .clipShape(
                            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionLabel(text: "Anything to avoid")
                    TextField("no pork, one vegetarian night", text: $avoidText, axis: .vertical)
                        .font(.gluttBody)
                        .lineLimit(1...3)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.card)
                        .clipShape(
                            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }

                Button {
                    Haptics.impact(.medium)
                    generate()
                } label: {
                    Text("Plan my week").frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttPrimary)
            }
        }
    }

    private var headline: String {
        let total = mealCount * servings
        return "\(mealCount) recipes, \(servings) servings each, so \(total) meals from one trip. "
            + "The dinners are designed together, which is what keeps the list short."
    }

    private func settingRow(
        _ title: String,
        detail: String,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.gluttBody.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            control()
        }
    }

    // MARK: - Generating

    private var generatingBody: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.Colors.accent)
            Text("Building a week that shares a shopping list…")
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Plan

    @ViewBuilder
    private var planBody: some View {
        if let plan {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if let change = listChange {
                    changeBanner(change)
                }

                if !plan.sharedCore.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        SectionLabel(text: "What carries the week")
                        Text(plan.sharedCore.joined(separator: ", "))
                            .font(.gluttBody)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionLabel(text: "\(plan.meals.count) dinners")
                    ForEach(Array(plan.meals.enumerated()), id: \.element.id) { index, meal in
                        mealCard(meal, index: index)
                    }
                }

                refineRow

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionLabel(text: "One shopping list")
                    Text("^[\(toBuy.count) item](inflect: true) for the whole week.")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    costEstimateRow
                    ForEach(GroceryCategory.allCases) { category in
                        let items = toBuy.filter { $0.category == category }
                        if !items.isEmpty {
                            listSection(category.label, items: items)
                        }
                    }
                    if !alreadyHave.isEmpty {
                        listSection("Already in your kitchen", items: alreadyHave, dimmed: true)
                    }
                }

                Button {
                    Haptics.impact(.medium)
                    save()
                } label: {
                    Text("Save this week").frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttPrimary)
                .disabled(isBusy)
            }
        }
    }

    private func changeBanner(_ change: MealPlanConsolidator.Change) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: change.isEmpty ? "checkmark.circle.fill" : "cart.badge.plus")
                .foregroundStyle(change.isEmpty ? Theme.Colors.accent : Theme.Colors.amber)
            Text(change.summary ?? "Your shopping list didn't change.")
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(change.isEmpty ? Theme.Colors.greenTint : Theme.Colors.amberChip)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
    }

    private func mealCard(_ meal: WeekPlanner.Meal, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dinner \(index + 1)")
                        .font(.gluttCaption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.accent)
                    Text(meal.title)
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.heading)
                }
                Spacer(minLength: Theme.Spacing.sm)
                if swappingIndex == index {
                    ProgressView().tint(Theme.Colors.accent)
                } else {
                    Button {
                        Haptics.impact(.light)
                        swap(index)
                    } label: {
                        Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.gluttPill)
                    .disabled(isBusy)
                }
            }

            if let summary = meal.summary, !summary.isEmpty {
                Text(summary)
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(spacing: Theme.Spacing.md) {
                Label("\(meal.servings) servings", systemImage: "person.2")
                let minutes = meal.prepMinutes + meal.cookMinutes
                if minutes > 0 {
                    Label("\(minutes) min", systemImage: "clock")
                }
            }
            .font(.gluttCaption)
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var refineRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel(text: "Change the whole week")
            HStack(spacing: Theme.Spacing.sm) {
                TextField("less chicken, make one vegetarian", text: $refineText)
                    .font(.gluttBody)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.card)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    )
                    .onSubmit(refine)
                if isRefining {
                    ProgressView().tint(Theme.Colors.accent)
                } else {
                    Button("Apply") { refine() }
                        .buttonStyle(.gluttPill)
                        .disabled(
                            isBusy || refineText.trimmingCharacters(in: .whitespaces).isEmpty
                        )
                }
            }
        }
    }

    /// What the shop might cost, with the uncertainty said out loud.
    ///
    /// The number is a language model's guess at supermarket prices, so the
    /// caveat is not fine print to be tucked away, it is the honest half of the
    /// claim and sits directly under the figure at the same weight the figure
    /// has. A range rather than a total for the same reason: "$61" reads as a
    /// promise that the till will say $61, and it will not.
    ///
    /// Absent until the estimate lands, and absent for good if it never does.
    /// Nothing here is worth an error state; the cook came for dinners.
    @ViewBuilder
    private var costEstimateRow: some View {
        if let cost = plan?.cost {
            VStack(alignment: .leading, spacing: 2) {
                Text("Roughly \(cost.range)")
                    .font(.gluttBody.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("A rough guess, not a quote. Grocery prices move a lot by store and city.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .transition(.opacity)
        }
    }

    private func listSection(
        _ title: String,
        items: [MealPlanConsolidator.Line],
        dimmed: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.gluttCaption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(items) { line in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                            .font(.gluttBody)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if let shared = line.sharedLabel {
                            Text(shared)
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                    if let quantity = line.displayQuantity {
                        Text(quantity)
                            .font(.gluttCaption.weight(.medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        .opacity(dimmed ? 0.7 : 1)
    }

    // MARK: - Actions

    private var request: WeekPlanner.Request {
        WeekPlanner.Request(
            mealCount: mealCount,
            servings: servings,
            budgetTarget: budget,
            ingredientTarget: ingredientTarget,
            mustInclude: mustIncludeText.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: avoidText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Price the plan in the background and fill the figure in when it lands.
    ///
    /// Deliberately not awaited before the meals are shown. The estimate is a
    /// nice-to-have and the plan is the thing the cook is waiting on, so making
    /// them stare at a spinner for a second call would be paying for the wrong
    /// one. The row appears a moment later, and never at all if the call fails.
    private func estimateCost(for generated: WeekPlanner.Plan, list: [MealPlanConsolidator.Line]) {
        // Price the trolley, not the recipes. Lines the pantry covers are not
        // being bought and must not be charged for.
        let shoppingList = list.filter { !$0.alreadyHave }.map(\.name)
        Task {
            guard let estimate = await WeekPlanner.estimateCost(
                for: generated, shoppingList: shoppingList
            ) else { return }
            // The cook may have swapped or refined while this was in flight, in
            // which case it is priced against a list that no longer exists.
            guard plan?.id == generated.id, plan?.cost == nil else { return }
            guard plan?.meals.map(\.title) == generated.meals.map(\.title) else { return }
            plan?.cost = estimate
        }
    }

    private func generate() {
        phase = .generating
        listChange = nil
        Analytics.capture(.aiToolUsed, ["tool": "week-plan", "meals": mealCount])
        let prefs = UserPrefs.current(in: context)
        let pantry = pantryItems
        let ask = request
        Task {
            do {
                let generated = try await WeekPlanner.generate(
                    request: ask, pantry: pantry, prefs: prefs
                )
                plan = generated
                let consolidated = MealPlanConsolidator.consolidate(meals: generated.meals, pantry: pantry)
                lines = consolidated
                phase = .plan
                Haptics.notify(.success)
                estimateCost(for: generated, list: consolidated)
            } catch {
                phase = .setup
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't plan the week just now. Try again in a moment."
            }
        }
    }

    private func swap(_ index: Int) {
        guard let current = plan, !isBusy else { return }
        swappingIndex = index
        listChange = nil
        let prefs = UserPrefs.current(in: context)
        let pantry = pantryItems
        let before = lines
        Task {
            defer { swappingIndex = nil }
            do {
                let updated = try await WeekPlanner.swap(
                    mealAt: index, in: current, pantry: pantry, prefs: prefs
                )
                let after = MealPlanConsolidator.consolidate(meals: updated.meals, pantry: pantry)
                plan = updated
                lines = after
                listChange = MealPlanConsolidator.diff(before: before, after: after)
                Haptics.notify(.success)
                estimateCost(for: updated, list: after)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't swap that dinner. Try again in a moment."
            }
        }
    }

    private func refine() {
        guard let current = plan, !isBusy else { return }
        let instruction = refineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        isRefining = true
        listChange = nil
        let prefs = UserPrefs.current(in: context)
        let pantry = pantryItems
        let before = lines
        Task {
            defer { isRefining = false }
            do {
                let updated = try await WeekPlanner.refine(
                    current, instruction: instruction, pantry: pantry, prefs: prefs
                )
                let after = MealPlanConsolidator.consolidate(meals: updated.meals, pantry: pantry)
                plan = updated
                lines = after
                listChange = MealPlanConsolidator.diff(before: before, after: after)
                refineText = ""
                Haptics.notify(.success)
                estimateCost(for: updated, list: after)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't change the week just now. Try again in a moment."
            }
        }
    }

    private func save() {
        guard let plan else { return }
        Haptics.notify(.success)
        let record = MealPlanCommitter.commit(
            plan,
            lines: lines,
            name: MealPlanCommitter.defaultName(),
            in: context
        )
        Analytics.capture(.recipeCreated, ["source": "week-plan"])
        if let collection = record.collection { onSaved(collection) }
        dismiss()
    }
}
