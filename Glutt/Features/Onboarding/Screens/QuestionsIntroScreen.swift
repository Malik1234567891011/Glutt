import SwiftUI

/// Screen 2 — a single centered line as a transition beat. Content only;
/// the coordinator owns the fixed "Continue" footer + chrome.
struct QuestionsIntroScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            OnboardingHeadline("Let's tune Glutt to how you actually cook", size: 29, maxWidth: 290)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
    }
}
