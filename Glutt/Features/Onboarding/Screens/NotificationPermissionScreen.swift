import SwiftUI

struct NotificationPermissionScreen: View {
    let onDone: () -> Void
    var body: some View {
        VStack {
            Spacer()
            OnboardingHeadline("We'll remind you to cook so it becomes a habit")
            Spacer()
            OnboardingPrimaryButton(title: "Allow Notifications", action: onDone)
            OnboardingTextLink(title: "Not now", action: onDone).padding(.top, 16)
        }
        .padding(.horizontal, 24).padding(.bottom, 10).padding(.top, 50)
    }
}
