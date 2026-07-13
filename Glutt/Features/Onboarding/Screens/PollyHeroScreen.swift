import SwiftUI

struct PollyHeroScreen: View {
    let onContinue: () -> Void
    var body: some View {
        VStack {
            Spacer()
            OnboardingHeadline("Polly guides you through recipes, completely hands-free", size: 28, maxWidth: 310)
            Spacer()
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .padding(.top, 50)
    }
}
