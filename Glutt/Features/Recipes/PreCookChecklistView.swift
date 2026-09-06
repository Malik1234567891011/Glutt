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

    @State private var isOptimizing = false

    private var match: PantryMatcher.MatchResult {
        PantryMatcher.match(recipe: recipe, pantry: pantryItems)
    }

    /// The missing ingredients that something in the cook's kitchen can stand
    /// in for. Essentials are excluded: the rows below refuse to offer a swap
    /// for those, so counting them here would promise help the sheet will not
    /// give.
    private var swappable: [RecipeIngredient] {
        match.missing.filter { ingredient in
            !SubstitutionService.isEssential(ingredient.name)
                && !SubstitutionService.availableSubstitutions(
                    for: ingredient.name, pantry: pantryItems).isEmpty
        }
    }

    private var hasOwnedSwaps: Bool { !swappable.isEmpty }

    /// What the header says, derived rather than asserted.
    ///
    /// It used to read "Missing 2, but some have swaps you already own" on
    /// every visit, including the one where both rows underneath said the swap
    /// was NOT in your kitchen. A header that contradicts its own list is worse
    /// than no header.
    private var summaryLine: String {
        let missing = match.missing.count
        guard hasOwnedSwaps else {
            return missing == 1
                ? "Nothing in your kitchen stands in for it."
                : "Nothing in your kitchen stands in for them."
        }
        return swappable.count == 1
            ? "You can swap one of them for something you already have."
            : "You can swap \(swappable.count) of them for things you already have."
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

                }
                .padding(Theme.Spacing.md)
            }
            // Pinned rather than scrolled with the list.
            //
            // At the medium detent the third action was cut in half by the
            // bottom of the sheet on open, which reads as a broken layout on a
            // screen whose whole job is asking somebody to choose. Pinning
            // means the choices are always fully visible however long the
            // missing list gets or however large the cook's text is, and the
            // list scrolls underneath them.
            .safeAreaInset(edge: .bottom) {
                    // The strongest button is the one that solves the
                    // problem the sheet just described.
                    //
                    // "Cook anyway" used to be the filled green one, which made
                    // "ignore the missing ingredients" the recommendation on a
                    // screen whose entire job is to point out that something is
                    // missing. It is still one tap away, just no longer the
                    // thing the eye lands on.
                    VStack(spacing: Theme.Spacing.sm) {
                        if hasOwnedSwaps {
                            Button("Use what I have instead") {
                                Haptics.impact(.light)
                                isOptimizing = true
                            }
                            .buttonStyle(.gluttPrimary)

                            Button("Add missing to groceries") {
                                addMissingToGroceries()
                            }
                            .buttonStyle(.gluttSecondary)
                        } else {
                            Button("Add missing to groceries") {
                                addMissingToGroceries()
                            }
                            .buttonStyle(.gluttPrimary)

                            // Still offered with nothing to swap in, because
                            // adapting the recipe can find a way round an
                            // ingredient the substitution table does not know.
                            Button("Use what I have instead") {
                                Haptics.impact(.light)
                                isOptimizing = true
                            }
                            .buttonStyle(.gluttSecondary)
                        }

                        Button("Cook anyway") {
                            Haptics.impact(.medium)
                            dismiss()
                            onCookAnyway()
                        }
                        .font(BrandFont.bricolage(17, 600, relativeTo: .headline, maxSize: 24))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                    }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.background)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Before you cook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isOptimizing) {
                OptimizeRecipeView(recipe: recipe)
            }
        }
    }

    private func addMissingToGroceries() {
        Haptics.notify(.success)
        GroceryListBuilder.add(
            ingredients: match.missing,
            from: recipe,
            existing: groceryItems,
            context: context
        )
        dismiss()
    }

    private var summaryCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            Ph.basket.regular
                .resizable().scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(Theme.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("You have \(match.ownedCount) of \(match.totalCount) ingredients")
                    .font(BrandFont.bricolage(17, 600, relativeTo: .headline, maxSize: 26))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(summaryLine)
                    .font(BrandFont.nunito(14, 600, relativeTo: .subheadline, maxSize: 22))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                Ph.xCircle.regular
                    .resizable().scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.Colors.tomato)
                Text(ingredient.name)
                    .font(BrandFont.bricolage(17, 600, relativeTo: .headline, maxSize: 26))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if let display = UnitConverter.display(quantity: ingredient.quantity, unit: ingredient.unit) {
                    Text(display)
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            if essential {
                HStack(spacing: 4) {
                    Ph.warning.regular
                        .resizable().scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.Colors.tomato)
                    Text("Core ingredient. Substituting will change the dish.")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.tomato)
                }
            } else if let swap = available.first {
                HStack(spacing: 4) {
                    Ph.arrowsClockwise.regular
                        .resizable().scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("You have a swap: \(swap.name)")
                        .font(.gluttCaption.weight(.medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
                Text(swap.explanation)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            // A swap the cook also does not have is not a suggestion, it is a
            // second missing ingredient. The row used to print "Possible swap:
            // lime (not in your kitchen)", which reads as help and is not.
        }
        .cardStyle()
    }
}
