import SwiftUI

struct RulesScreen: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void
    var body: some View {
        VStack {
            OnboardingHeadline("Any food rules?")
            Spacer()
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 22).padding(.top, 42).padding(.bottom, 8)
    }
}
