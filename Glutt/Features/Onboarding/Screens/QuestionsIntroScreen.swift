import SwiftUI

struct QuestionsIntroScreen: View {
    let onContinue: () -> Void
    var body: some View {
        VStack {
            Spacer()
            OnboardingHeadline("Let's tune Glutt to how you actually cook", size: 28, maxWidth: 310)
            Spacer()
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .padding(.top, 50)
    }
}
