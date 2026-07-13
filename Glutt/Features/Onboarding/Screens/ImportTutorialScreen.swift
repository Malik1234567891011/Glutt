import SwiftUI

struct ImportTutorialScreen: View {
    @Bindable var flow: OnboardingFlowModel
    let onImportNow: () -> Void
    let onFinish: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("tutorial phase \(flow.tutPhase)")
            Button("tap phone (stub)") { _ = flow.tutorialTap() }
            if flow.tutPhase == 4 {
                OnboardingPrimaryButton(title: "Import my first recipe", height: 58, action: onImportNow)
                Button("I'll explore on my own", action: onFinish)
            } else {
                OnboardingTextLink(title: "Skip tutorial", action: onFinish)
            }
            Spacer()
        }
        .padding(24)
    }
}
