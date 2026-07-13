import SwiftUI

/// Screen 7 — same template as Intro, with subhead + glutt-features.mp4.
struct AIFeaturesScreen: View {
    let onContinue: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("AI shows up right where you cook", size: 27)
            OnboardingSubhead("Smart help, right where you're cooking")
                .padding(.top, 8)
            videoFrame(resource: "glutt-features", scale: 1.08, yOffset: -0.08, fadeHeight: 0.22)
                .padding(.vertical, 14)
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .padding(.bottom, 10)
    }
}
