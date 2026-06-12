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
            Text("What should change about “\(recipe.title)”?")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(RecipeAdjuster.Goal.allCases) { goal in
                Button {
                    run(goal)
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: goal.icon)
                            .font(.title3)
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 32)
                        Text(goal.label)
                            .font(.gluttHeadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
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

            Text("The result saves as a new version — the original stays exactly as it is.")
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
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
                phase = .result(goal, adjustment)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Working / result

    private func workingView(_ goal: RecipeAdjuster.Goal) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .controlSize(.large)
            Text("Rewriting for “\(goal.label.lowercased())”…")
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

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: "What changed")
                ForEach(adjustment.changes, id: \.self) { change in
                    Label(change, systemImage: "arrow.triangle.swap")
                        .font(.gluttBody)
                        .foregroundStyle(Theme.Colors.textPrimary)
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
                Label("Saved as “\(goal.versionLabel)” — find it under versions on the recipe", systemImage: "checkmark.circle.fill")
                    .font(.gluttCaption.weight(.medium))
                    .foregroundStyle(Theme.Colors.accent)
            } else {
                Button("Save as \(goal.versionLabel.lowercased())") {
                    RecipeAdjuster.apply(adjustment, goal: goal, to: recipe, context: context)
                    didSave = true
                }
                .buttonStyle(.gluttPrimary)
            }

            Button("Try a different goal") {
                didSave = false
                phase = .pickGoal
            }
            .buttonStyle(.gluttSecondary)
        }
    }
}
