import SwiftUI

/// Screen 7 — same template as Intro, with subhead + glutt-features.mp4.
/// Content only; the coordinator owns the fixed "Continue" footer + chrome.
struct AIFeaturesScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("AI shows up right where you cook", size: 27)
            // Was "Smart help, right where you're cooking", which is the
            // headline again in different words. Says what it actually does.
            OnboardingSubhead("Scale it, swap an ingredient, or invent dinner from what you have")
                .padding(.top, 8)
            videoFrame(resource: "glutt-features", scale: 1.08, yOffset: -0.08, fadeHeight: 0.22)
                .padding(.vertical, 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
    }
}
