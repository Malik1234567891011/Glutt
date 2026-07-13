import SwiftUI

struct WelcomeScreen: View {
    let onStart: () -> Void
    var body: some View {
        VStack {
            Spacer()
            OnboardingHeadline("Cook anything you actually want", size: 28, maxWidth: 310)
            Spacer()
            OnboardingPrimaryButton(title: "Start", action: onStart)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .padding(.top, 50)
    }
}
