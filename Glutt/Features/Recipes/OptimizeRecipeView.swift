import SwiftData
import SwiftUI

/// "Make it with what I have": shows every proposed swap with the reason it
/// works, warns about essentials, and saves the result as a separate version.
struct OptimizeRecipeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantryItems: [PantryItem]

    let recipe: Recipe

    @State private var didSave = false

    private var plan: RecipeOptimizer.Plan {
        let prefs = UserPrefs.current(in: context)
        return RecipeOptimizer.plan(
            for: recipe,
            pantry: pantryItems,
            rules: prefs.dietaryRules,
            allergies: prefs.allergies
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    let plan = plan
                    if plan.swaps.isEmpty && plan.unresolved.isEmpty && plan.essentialWarnings.isEmpty {
                        EmptyStateView(
                            icon: "checkmark.circle",
                            title: "Nothing to optimize",
                            message: "You already have everything this recipe needs."
                        )
                    } else {
                        if !plan.swaps.isEmpty {
                            swapsSection(plan.swaps)
                        }
                        if !plan.essentialWarnings.isEmpty {
                            essentialsSection(plan.essentialWarnings)
                        }
                        if !plan.unresolved.isEmpty {
                            unresolvedSection(plan.unresolved)
                        }
                        if plan.isWorthIt {
                            Button(didSave ? "Saved ✓" : "Save as pantry version") {
                                RecipeOptimizer.apply(plan, to: recipe, context: context)
                                didSave = true
                            }
                            .buttonStyle(.gluttPrimary)
                            .disabled(didSave)
                            Text("Saved as a version — the original recipe stays untouched.")
                                .font(.gluttCaption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Use what I have")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            RecipeImageView(recipe: recipe)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title)
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Adapted to your pantry")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
    }

    private func swapsSection(_ swaps: [RecipeOptimizer.Swap]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Swaps you can make")
            ForEach(swaps) { swap in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(swap.original.name)
                            .font(.gluttBody)
                            .strikethrough(color: Theme.Colors.textSecondary)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.accent)
                        Text(swap.substituteName)
                            .font(.gluttBody.weight(.semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    Text(swap.reason)
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .cardStyle()
            }
        }
    }

    private func essentialsSection(_ ingredients: [RecipeIngredient]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Don't substitute these")
            ForEach(ingredients) { ingredient in
                Label {
                    Text("\(ingredient.name) — swapping this changes the dish. Better to grab it.")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textPrimary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.warning)
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.warningTint)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
    }

    private func unresolvedSection(_ ingredients: [RecipeIngredient]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "No good swap in your kitchen")
            ForEach(ingredients) { ingredient in
                Text("• \(ingredient.name)")
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .cardStyle()
    }
}
