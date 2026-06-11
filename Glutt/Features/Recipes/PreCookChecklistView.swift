import SwiftData
import SwiftUI

/// Shown before Cook Mode when ingredients are missing:
/// what's missing, what can be swapped with pantry items, and the choice
/// to shop, swap, or cook anyway.
struct PreCookChecklistView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantryItems: [PantryItem]
    @Query private var groceryItems: [GroceryItem]

    let recipe: Recipe
    let onCookAnyway: () -> Void

    private var match: PantryMatcher.MatchResult {
        PantryMatcher.match(recipe: recipe, pantry: pantryItems)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    summaryCard

                    ForEach(match.missing) { ingredient in
                        missingCard(ingredient)
                    }

                    if !match.missingOptional.isEmpty {
                        Text("Optional, also missing: \(match.missingOptional.map(\.name).joined(separator: ", "))")
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    VStack(spacing: Theme.Spacing.sm) {
                        Button("Add missing to groceries") {
                            GroceryListBuilder.add(
                                ingredients: match.missing,
                                from: recipe,
                                existing: groceryItems,
                                context: context
                            )
                            dismiss()
                        }
                        .buttonStyle(.gluttSecondary)

                        Button("Cook anyway") {
                            dismiss()
                            onCookAnyway()
                        }
                        .buttonStyle(.gluttPrimary)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Before you cook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "basket")
                .font(.title2)
                .foregroundStyle(Theme.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("You have \(match.ownedCount) of \(match.totalCount) ingredients")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Missing \(match.missing.count) — but some have swaps you already own.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.warningTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func missingCard(_ ingredient: RecipeIngredient) -> some View {
        let available = SubstitutionService.availableSubstitutions(for: ingredient.name, pantry: pantryItems)
        let essential = SubstitutionService.isEssential(ingredient.name)

        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(Theme.Colors.tomato)
                Text(ingredient.name)
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if let display = UnitConverter.display(quantity: ingredient.quantity, unit: ingredient.unit) {
                    Text(display)
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            if essential {
                Label("Core ingredient — substituting will change the dish", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.tomato)
            } else if let swap = available.first {
                Label("You have a swap: \(swap.name)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.gluttCaption.weight(.medium))
                    .foregroundStyle(Theme.Colors.accent)
                Text(swap.explanation)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if let suggestion = SubstitutionService.substitutions(for: ingredient.name).first {
                Text("Possible swap: \(suggestion.name) (not in your kitchen)")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .cardStyle()
    }
}
