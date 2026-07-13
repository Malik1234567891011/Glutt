import SwiftUI

struct NotificationsSoftAskScreen: View {
    let onTurnOn: () -> Void
    let onMaybeLater: () -> Void
    var body: some View {
        VStack {
            OnboardingHeadline("Turn on gentle nudges")
            Spacer()
            OnboardingPrimaryButton(title: "Turn on notifications", action: onTurnOn)
            OnboardingTextLink(title: "Maybe later", action: onMaybeLater).padding(.top, 16)
        }
        .padding(.horizontal, 24).padding(.top, 50).padding(.bottom, 10)
    }
}
