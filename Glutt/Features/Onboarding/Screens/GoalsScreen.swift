import SwiftUI

struct GoalsScreen: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void
    var body: some View {
        VStack {
            OnboardingHeadline("Why do you want to cook more at home?", size: 26)
            Spacer()
            Button("toggle-first-goal-stub") { state.toggleGoal(OnboardingState.goalOptions[0]) }
            Spacer()
            if state.canContinueFromGoals {
                OnboardingPrimaryButton(title: "Continue", action: onContinue)
            } else {
                OnboardingDisabledPill(title: "Continue")
            }
        }
        .padding(.horizontal, 22).padding(.top, 44).padding(.bottom, 8)
    }
}
