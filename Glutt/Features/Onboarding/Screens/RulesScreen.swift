import SwiftUI

/// Dietary rules (multi-select) + allergies + dislikes free text.
struct RulesScreen: View {
    @Bindable var state: OnboardingState

    var body: some View {
        OnboardingScaffold(
            title: "Any food rules?",
            subtitle: "Respected everywhere — suggestions, planning, and substitutions."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(DietaryRule.allCases, id: \.self) { rule in
                        OptionRow(
                            systemImage: "leaf",
                            title: rule.label,
                            isSelected: state.selectedRules.contains(rule)
                        ) {
                            state.toggleRule(rule)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Allergies")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    TextField("peanuts, shellfish…", text: $state.allergyText)
                        .textFieldStyle(.roundedBorder)
                    Text("Separate with commas. Anything here gets a hard warning, always.")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Things you just don't like")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    TextField("cilantro, olives…", text: $state.dislikeText)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}

#Preview {
    RulesScreen(state: OnboardingState())
        .background(Theme.Colors.background)
}
