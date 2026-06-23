import SwiftData
import SwiftUI

/// "Make this higher protein / lighter / cheaper / match my rules."
/// Pick a goal, the AI rewrites the recipe, you review the changes,
/// and it saves as a version. Original never touched.
struct AdjustRecipeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe

    enum Phase {
        case pickGoal
        case working(RecipeAdjuster.Goal)
        case result(RecipeAdjuster.Goal, RecipeAdjuster.Adjustment)
        case failed(String)
    }

    @State private var phase: Phase = .pickGoal
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    switch phase {
                    case .pickGoal:
                        goalPicker
                    case .working(let goal):
                        workingView(goal)
                    case .result(let goal, let adjustment):
                        resultView(goal, adjustment)
                    case .failed(let message):
                        EmptyStateView(
                            icon: "exclamationmark.triangle",
                            title: "Couldn't adjust it",
                            message: message,
                            actionLabel: "Try again",
                            action: { phase = .pickGoal }
                        )
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Make it…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Goal picker

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("What should change about \u{201C}\(recipe.title)\u{201D}?")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(RecipeAdjuster.Goal.allCases) { goal in
                Button {
                    Haptics.impact(.medium)
                    run(goal)
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        goalIcon(for: goal)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 32)
                        Text(goal.label)
                            .font(.gluttHeadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Ph.caretRight.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Text("The result saves as a new version — the original stays exactly as it is.")
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// Maps each Goal to a Phosphor icon (already resizable).
    private func goalIcon(for goal: RecipeAdjuster.Goal) -> Image {
        switch goal {
        case .higherProtein: Ph.barbell.regular
        case .lighter:       Ph.leaf.regular
        case .cheaper:       Ph.tag.regular
        case .foodRules:     Ph.checkCircle.regular
        }
    }

    private func run(_ goal: RecipeAdjuster.Goal) {
        phase = .working(goal)
        let prefs = UserPrefs.current(in: context)
        Task {
            do {
                let adjustment = try await RecipeAdjuster.adjust(
                    recipe: recipe,
                    goal: goal,
                    rules: prefs.dietaryRules,
                    allergies: prefs.allergies
                )
                Haptics.notify(.success)
                phase = .result(goal, adjustment)
            } catch {
                Haptics.notify(.error)
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Working / result

    private func workingView(_ goal: RecipeAdjuster.Goal) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .controlSize(.large)
            Text("Rewriting for \u{201C}\(goal.label.lowercased())\u{201D}\u{2026}")
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl * 2)
    }

    private func resultView(_ goal: RecipeAdjuster.Goal, _ adjustment: RecipeAdjuster.Adjustment) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if let summary = adjustment.summary {
                Text(summary)
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.accent)
            }

            if let macros = macros(for: adjustment) {
                macroDeltaCard(before: macros.before, after: macros.after)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: "What changed")
                ForEach(adjustment.changes, id: \.self) { change in
                    HStack(spacing: Theme.Spacing.sm) {
                        Ph.swap.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Theme.Colors.accent)
                        Text(change)
                            .font(.gluttBody)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: "New ingredients")
                ForEach(adjustment.ingredients, id: \.self) { line in
                    Text("• \(line)")
                        .font(.gluttBody)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            if didSave {
                HStack(spacing: Theme.Spacing.sm) {
                    Ph.checkCircle.fill
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Saved as \u{201C}\(goal.versionLabel)\u{201D} \u{2014} find it under versions on the recipe")
                        .font(.gluttCaption.weight(.medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
            } else {
                Button("Save as \(goal.versionLabel.lowercased())") {
                    Haptics.notify(.success)
                    RecipeAdjuster.apply(adjustment, goal: goal, to: recipe, context: context)
                    didSave = true
                }
                .buttonStyle(.gluttPrimary)
            }

            Button("Try a different goal") {
                Haptics.impact(.light)
                didSave = false
                phase = .pickGoal
            }
            .buttonStyle(.gluttSecondary)
        }
    }

    // MARK: - Macro delta (before → after)

    /// Scores the original and the proposed version with the SAME nutrition
    /// engine, so the before/after numbers are honest and comparable rather
    /// than the LLM guessing math.
    private func macros(for adjustment: RecipeAdjuster.Adjustment)
        -> (before: NutritionEstimator.Estimate, after: NutritionEstimator.Estimate)? {
        guard let before = NutritionEstimator.estimate(for: recipe) else { return nil }
        let ingredients = adjustment.ingredients.map { line -> RecipeIngredient in
            let parsed = IngredientLineParser.parse(line)
            return RecipeIngredient(name: parsed.name, quantity: parsed.quantity,
                                    unit: parsed.unit, isEstimated: parsed.isEstimated)
        }
        guard let after = NutritionEstimator.estimate(ingredients: ingredients, servings: recipe.servings) else {
            return nil
        }
        return (before, after)
    }

    private func macroDeltaCard(before: NutritionEstimator.Estimate,
                                after: NutritionEstimator.Estimate) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("THE DIFFERENCE · PER SERVING")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)

            macroRow(icon: Ph.barbell.regular, label: "Protein",
                     before: before.proteinGrams, after: after.proteinGrams,
                     suffix: "g", goodWhenHigher: true)
            Divider().overlay(Theme.Colors.border)
            macroRow(icon: Ph.flame.regular, label: "Calories",
                     before: before.calories, after: after.calories,
                     suffix: "", goodWhenHigher: false)

            Text("Estimated from ingredients — real numbers vary with brands and portions.")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func macroRow(icon: Image, label: String, before: Int, after: Int,
                          suffix: String, goodWhenHigher: Bool) -> some View {
        let delta = after - before
        let isWin = goodWhenHigher ? delta > 0 : delta < 0
        let deltaColor = delta == 0 ? Theme.Colors.textSecondary
            : (isWin ? Theme.Colors.accent : Theme.Colors.warning)
        let sign = delta > 0 ? "+" : (delta < 0 ? "−" : "")

        return HStack(spacing: Theme.Spacing.md) {
            icon.resizable().scaledToFit().frame(width: 20, height: 20)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 28)
            Text(label)
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                Text("\(before)\(suffix)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .strikethrough(delta != 0, color: Theme.Colors.textSecondary)
                Ph.arrowRight.bold.resizable().scaledToFit().frame(width: 12, height: 12)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("\(after)\(suffix)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            if delta != 0 {
                Text("\(sign)\(abs(delta))\(suffix)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(deltaColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(deltaColor.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
    }
}
