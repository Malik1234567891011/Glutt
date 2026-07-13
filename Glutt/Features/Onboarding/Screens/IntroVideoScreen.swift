import SwiftUI

struct IntroVideoScreen: View {
    let onContinue: () -> Void
    var body: some View {
        VStack {
            Spacer()
            OnboardingHeadline("Glutt is a whole new way to cook at home", size: 28, maxWidth: 310)
            Spacer()
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .padding(.top, 50)
    }
}
