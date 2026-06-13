import SwiftData
import SwiftUI

/// First-run flow: goals → food rules → nutrition choice → first recipe.
/// Every screen is skippable — the app learns from usage either way.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router

    @State private var step = 0
    @State private var selectedGoals: Set<String> = []
    @State private var selectedRules: Set<DietaryRule> = []
    @State private var allergyText = ""
    @State private var dislikeText = ""
    @State private var nutritionMode: NutritionMode = .cookingOnly
    @State private var didAddStarters = false
    @State private var isShowingShareSetup = false

    let onFinish: () -> Void

    private static let goalOptions = [
        "Save recipes from TikTok & friends",
        "Cook what I already have",
        "Plan my week",
        "Waste less food",
        "Hit my macros",
        "Eat out less",
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $step) {
                highlightsStep.tag(0)
                goalsStep.tag(1)
                rulesStep.tag(2)
                nutritionStep.tag(3)
                firstRecipeStep.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)

            bottomBar
        }
        .background(Theme.Colors.background)
        .sheet(isPresented: $isShowingShareSetup) {
            ShareSheetSetupView()
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<5) { index in
                    Capsule()
                        .fill(index <= step ? Theme.Colors.accent : Theme.Colors.border)
                        .frame(width: index == step ? 24 : 8, height: 8)
                }
            }
            Spacer()
            Button("Skip") { finish() }
                .font(.gluttCaption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
    }

    private var bottomBar: some View {
        HStack {
            if step > 0 {
                Button("Back") {
                    step -= 1
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button {
                if step < 4 {
                    step += 1
                } else {
                    finish()
                }
            } label: {
                Text(continueLabel)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.gluttPrimary)
        }
        .padding(Theme.Spacing.md)
    }

    private var continueLabel: String {
        switch step {
        case 0: "Sounds good"
        case 4: "Let's cook"
        default: "Continue"
        }
    }

    private func finish() {
        let prefs = UserPrefs.current(in: context)
        prefs.goals = Array(selectedGoals)
        prefs.dietaryRules = Array(selectedRules)
        prefs.allergies = splitList(allergyText)
        prefs.dislikedIngredients = splitList(dislikeText)
        prefs.nutritionMode = nutritionMode
        prefs.hasCompletedOnboarding = true
        onFinish()
    }

    private func splitList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Step 0: what Glutt does (a glance, not a tutorial)

    private var highlightsStep: some View {
        stepLayout(
            title: "Hey — here's what I do",
            subtitle: "A quick look at the good stuff. Skip whenever — you'll bump into all of it naturally."
        ) {
            VStack(spacing: Theme.Spacing.sm) {
                featureRow(
                    "square.and.arrow.up",
                    "Save from anywhere",
                    "Share a TikTok or paste a link and I'll pull out the recipe."
                )
                featureRow(
                    "wand.and.stars",
                    "Cook what you already have",
                    "Tell me your ingredients and I'll invent a dish from scratch."
                )
                featureRow(
                    "camera.viewfinder",
                    "Just snap a photo",
                    "Scan your fridge to fill your pantry, or a plate to log what you ate."
                )
                featureRow(
                    "slider.horizontal.3",
                    "Make any recipe yours",
                    "Higher-protein, lighter, cheaper, or halal — in one tap."
                )
                featureRow(
                    "takeoutbag.and.cup.and.straw",
                    "Waste nothing",
                    "I'll remix last night's leftovers into something new."
                )
            }
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    // MARK: - Step 1: goals

    private var goalsStep: some View {
        stepLayout(
            title: "What do you want Glutt for?",
            subtitle: "Pick anything that sounds like you. This just sets up your home screen."
        ) {
            SelectableChips(
                options: Self.goalOptions,
                isSelected: { selectedGoals.contains($0) },
                toggle: { goal in
                    if !selectedGoals.insert(goal).inserted {
                        selectedGoals.remove(goal)
                    }
                }
            )
        }
    }

    // MARK: - Step 2: food rules

    private var rulesStep: some View {
        stepLayout(
            title: "Any food rules?",
            subtitle: "These are respected everywhere — suggestions, planning, and substitutions."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                SelectableChips(
                    options: DietaryRule.allCases.map(\.label),
                    isSelected: { label in
                        selectedRules.contains { $0.label == label }
                    },
                    toggle: { label in
                        guard let rule = DietaryRule.allCases.first(where: { $0.label == label }) else { return }
                        if selectedRules.contains(rule) {
                            selectedRules.remove(rule)
                        } else {
                            selectedRules.insert(rule)
                        }
                    }
                )

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Allergies")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    TextField("peanuts, shellfish…", text: $allergyText)
                        .textFieldStyle(.roundedBorder)
                    Text("Separate with commas. Anything here gets a hard warning, always.")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Things you just don't like")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    TextField("cilantro, olives…", text: $dislikeText)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    // MARK: - Step 3: nutrition

    private var nutritionStep: some View {
        stepLayout(
            title: "Want to track nutrition?",
            subtitle: "Totally optional. You can change this anytime in Settings."
        ) {
            VStack(spacing: Theme.Spacing.sm) {
                nutritionOption(
                    .cookingOnly,
                    icon: "frying.pan",
                    detail: "No calories, no macros, anywhere. Just good food."
                )
                nutritionOption(
                    .lightTracking,
                    icon: "chart.bar",
                    detail: "Gentle estimates on recipes and a daily summary."
                )
                nutritionOption(
                    .gymMode,
                    icon: "dumbbell",
                    detail: "Calorie & protein goals, charts, and per-serving macros."
                )
            }
        }
    }

    private func nutritionOption(_ mode: NutritionMode, icon: String, detail: String) -> some View {
        Button {
            nutritionMode = mode
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(nutritionMode == mode ? .white : Theme.Colors.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(.gluttHeadline)
                    Text(detail)
                        .font(.gluttCaption)
                        .opacity(0.8)
                }
                Spacer()
                Image(systemName: nutritionMode == mode ? "checkmark.circle.fill" : "circle")
            }
            .foregroundStyle(nutritionMode == mode ? .white : Theme.Colors.textPrimary)
            .padding(Theme.Spacing.md)
            .background(nutritionMode == mode ? Theme.Colors.accent : Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4: first recipe

    private var firstRecipeStep: some View {
        stepLayout(
            title: "Get your first recipe in",
            subtitle: "Glutt is built around your recipes — here are three ways to start."
        ) {
            VStack(spacing: Theme.Spacing.sm) {
                firstRecipeOption(
                    icon: "link",
                    title: "Paste a link",
                    detail: "TikTok, Instagram, YouTube, or any recipe site"
                ) {
                    finish()
                    router.perform(.importRecipe)
                }
                firstRecipeOption(
                    icon: "square.and.arrow.up",
                    title: "Share from another app",
                    detail: "Use the share button in TikTok → Glutt"
                ) {
                    isShowingShareSetup = true
                }
                firstRecipeOption(
                    icon: didAddStarters ? "checkmark.circle.fill" : "sparkles",
                    title: didAddStarters ? "Starter pack added" : "Start with our picks",
                    detail: didAddStarters
                        ? "Six easy recipes are waiting in your library"
                        : "Six easy, crowd-pleasing recipes to play with"
                ) {
                    guard !didAddStarters else { return }
                    StarterRecipes.install(context: context)
                    didAddStarters = true
                }
            }
        }
    }

    private func firstRecipeOption(
        icon: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(detail)
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Layout helpers

    private func stepLayout(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(.gluttLargeTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(.gluttBody)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                content()
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Wrapping multi-select chip grid.
private struct SelectableChips: View {
    let options: [String]
    let isSelected: (String) -> Bool
    let toggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: Theme.Spacing.sm) {
            ForEach(options, id: \.self) { option in
                Button {
                    toggle(option)
                } label: {
                    Chip(label: option, isSelected: isSelected(option))
                        .fixedSize()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal left-aligned wrapping layout for chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.height }.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
