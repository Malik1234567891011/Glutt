import SwiftUI

struct FourWeeksScreen: View {
    let onContinue: () -> Void
    var body: some View {
        VStack {
            Spacer()
            OnboardingHeadline("Here's where you'll be in 4 weeks", size: 28, maxWidth: 310)
            Spacer()
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .padding(.top, 50)
    }
}
