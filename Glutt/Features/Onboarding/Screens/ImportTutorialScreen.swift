import SwiftUI

/// Screen 10 — the multi-phase import tutorial in a mini phone.
struct ImportTutorialScreen: View {
    @Bindable var flow: OnboardingFlowModel
    let onImportNow: () -> Void
    let onFinish: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    private static let headlines = [
        "Found a recipe you love?", "Open the share menu", "Pick Glutt",
        "Pulling out the recipe…", "That's it, it's saved!",
    ]
    private static let subheads = [
        "Tap the share button on the post.", "Tap your app's Share option.",
        "Choose Glutt from the share sheet.", "Reading ingredients, steps & macros.",
        "Glutt captured the full recipe for you.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 7) {
                OnboardingHeadline(Self.headlines[flow.tutPhase], size: 25)
                OnboardingSubhead(Self.subheads[flow.tutPhase], maxWidth: 272)
                    .font(OnboardingFonts.nunito(13.5, 600))
            }
            .frame(minHeight: 64, alignment: .top)

            GeometryReader { geo in
                let fit = min(1, (geo.size.height - 8) / 510)
                MiniPhoneFrame { phaseContent }
                    .scaleEffect(fit) // shrink uniformly on short devices only
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { handleTap() }
            }

            footer.padding(.top, flow.tutPhase == 4 ? 12 : 10)
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)   // design 80 − 54
        .padding(.bottom, 10)
        .task(id: flow.tutPhase == 3) {
            guard flow.tutPhase == 3 else { return }
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            flow.completeImport()
            Haptics.notify(.success)
        }
        .onChange(of: scenePhase) {
            // Returning mid-import: the .task(id:) above was cancelled on
            // background; re-arm by nudging the same mechanism.
            if scenePhase == .active, flow.tutPhase == 3 { flow.completeImport() }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch flow.tutPhase {
        case 0: SocialPostFrame().transition(.opacity)
        case 1: AppShareSheetFrame().transition(.opacity)
        case 2: SystemShareSheetFrame().transition(.opacity)
        case 3: ImportingFrame().transition(.opacity)
        default: SavedRecipeFrame().transition(.opacity)
        }
    }

    private func handleTap() {
        guard flow.tutPhase < 3 else { return }
        Haptics.impact(.light)
        withAnimation(.easeOut(duration: 0.3)) { _ = flow.tutorialTap() }
    }

    /// Design (`tWalk`): dots + skip on phases 0–2, nothing on 3, CTAs on 4.
    @ViewBuilder
    private var footer: some View {
        switch flow.tutPhase {
        case 0...2:
            VStack(spacing: 13) {
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i == flow.tutPhase ? OnboardingTheme.greenDeep : OnboardingTheme.warmBlack(0.18))
                            .frame(width: i == flow.tutPhase ? 22 : 7, height: 7)
                            .animation(.easeInOut(duration: 0.25), value: flow.tutPhase)
                    }
                }
                OnboardingTextLink(title: "Skip tutorial", action: onFinish)
            }
        case 3:
            Color.clear.frame(height: 56)
        default:
            VStack(spacing: 10) {
                OnboardingPrimaryButton(title: "Import my first recipe", height: 58, action: onImportNow)
                Button {
                    Haptics.impact(.light)
                    onFinish()
                } label: {
                    Text("I'll explore on my own")
                        .font(OnboardingFonts.bricolage(16, 600))
                        .foregroundStyle(OnboardingTheme.greenDeep)
                        .frame(maxWidth: .infinity).frame(height: 48)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
