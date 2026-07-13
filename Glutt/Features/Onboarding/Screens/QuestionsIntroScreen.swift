import SwiftUI

/// Screen 2 — a single centered line as a transition beat.
struct QuestionsIntroScreen: View {
    let onContinue: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            OnboardingHeadline("Let's tune Glutt to how you actually cook", size: 29, maxWidth: 290)
            Spacer()
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .padding(.bottom, 10)
    }
}
