import SwiftData
import SwiftUI

/// Offered from a diet-conflict banner: shows a recommended swap plus a couple
/// of alternatives for an ingredient that breaks the cook's rules or allergies.
/// Every option is curated and re-checked so it's itself compliant. Tapping one
/// rewrites that ingredient in the recipe and clears the warning.
struct SubstituteSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var recipe: Recipe
    let conflict: DietGuard.Conflict
    /// Hands the conflicting ingredient to the chat. Nil hides the link, so
    /// this sheet still works anywhere the chat isn't reachable.
    var onAskChef: ((String) -> Void)?

    private var options: [SubstitutionService.Substitution] {
        let prefs = UserPrefs.current(in: context)
        return SubstitutionService.dietSubstitutions(
            for: conflict.ingredientName,
            rules: prefs.dietaryRules,
            allergies: prefs.allergies
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    if options.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: Theme.Spacing.sm) {
                            ForEach(Array(options.enumerated()), id: \.offset) { index, sub in
                                optionRow(sub, isRecommended: index == 0)
                            }
                        }
                    }

                    askChefLink
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.background)
            // `-chatScreen substitute`: follows the link below for you, through
            // the same call the button makes. Inert without the launch argument.
            .task {
                guard RecipeChatStaging.requested == .substitute else { return }
                try? await Task.sleep(for: RecipeChatStaging.beat)
                guard !Task.isCancelled else { return }
                onAskChef?(conflict.ingredientName)
            }
            .navigationTitle("Substitute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The list above is curated, instant, and finite. When none of it fits the
    /// dish the cook is actually looking at, the chef can think about it.
    @ViewBuilder
    private var askChefLink: some View {
        if let onAskChef {
            Button {
                Haptics.impact(.light)
                onAskChef(conflict.ingredientName)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    MS.chatBubbleFill.sized(16)
                    Text("Ask Polly about this instead")
                        .font(.gluttBody.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.Colors.accent)
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.accent.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Swap out \(conflict.ingredientName)")
                .font(.gluttTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(reasonText)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reasonText: String {
        switch conflict.severity {
        case .allergy:
            return "This is flagged as an allergy. Here are safe swaps that keep the dish close."
        case .rule(let rule):
            return "This conflicts with \(rule.label.lowercased()). Pick a swap that fits your rules."
        case .dislike:
            return "Here are a few alternatives you might prefer."
        }
    }

    private func optionRow(_ sub: SubstitutionService.Substitution, isRecommended: Bool) -> some View {
        Button {
            apply(sub)
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(sub.name)
                            .font(.gluttHeadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if isRecommended {
                            Text("RECOMMENDED")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(0.5)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.Colors.accent, in: Capsule())
                        }
                    }
                    Text(sub.explanation)
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Ph.caretRight.regular.resizable().scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.top, 4)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isRecommended ? Theme.Colors.accent.opacity(0.4) : Theme.Colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("No good direct swap", systemImage: "info.circle")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("This ingredient is hard to replace one-for-one. Try “Make it…” to have the recipe reworked around your rules, or leave it out if it's optional.")
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// Rewrites every matching ingredient to the chosen swap and notes the
    /// original, so the diet warning clears and the shopping list is correct.
    private func apply(_ sub: SubstitutionService.Substitution) {
        let target = IngredientCanonicalizer.canonicalize(conflict.ingredientName)
        let newName = sub.name
        var changed = false
        for ingredient in recipe.ingredients {
            let canonical = ingredient.canonicalName
            let matches = canonical == target
                || canonical.contains(target)
                || target.contains(canonical)
                || ingredient.name.localizedCaseInsensitiveContains(conflict.ingredientName)
            guard matches else { continue }
            let original = ingredient.name
            ingredient.name = newName
            ingredient.canonicalName = IngredientCanonicalizer.canonicalize(newName)
            ingredient.note = "swapped from \(original)"
            changed = true
        }
        if changed {
            try? context.save()
            Haptics.celebrate()
        }
        dismiss()
    }
}
