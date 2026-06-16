import SwiftUI

/// Multi-select goals as full-width emoji rows.
struct GoalsScreen: View {
    @Bindable var state: OnboardingState

    var body: some View {
        OnboardingScaffold(
            title: "What do you want Glutt for?",
            subtitle: "Pick anything that sounds like you. This just sets up your home screen."
        ) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(OnboardingState.goalOptions) { option in
                    OptionRow(
                        emoji: option.emoji,
                        title: option.label,
                        isSelected: state.selectedGoals.contains(option.label)
                    ) {
                        state.toggleGoal(option.label)
                    }
                }
            }
        }
    }
}

#Preview {
    GoalsScreen(state: OnboardingState())
        .background(Theme.Colors.background)
}
