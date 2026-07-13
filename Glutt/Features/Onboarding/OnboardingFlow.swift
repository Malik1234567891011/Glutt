import SwiftData
import SwiftUI

/// 1:1 rebuild of the design-handoff onboarding (11 screens, `screen` 0–10).
/// Spec: docs/superpowers/specs/2026-07-12-onboarding-redesign-design.md
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router

    let onFinish: () -> Void

    @State private var flow = OnboardingFlowModel()
    @State private var state = OnboardingState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The reel the tutorial depicts (crispy hot honey chicken bites) —
    /// "Import my first recipe" imports it for real.
    private static let demoImportURL = URL(string: "https://www.instagram.com/reel/DYxO-e7JPw3/")

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingTheme.cream.ignoresSafeArea()

            screenView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(flow.screen)
                .transition(screenTransition)

            // Cream chrome variant. Screen 6 (Polly) draws its own glass chrome.
            if flow.showsChrome, flow.screen != 6 {
                OnboardingChrome(progress: flow.progress) { flow.back() }
            }
        }
        .animation(.easeOut(duration: 0.45), value: flow.screen)
        .onAppear {
            #if DEBUG
            // Staging hook (parity with the prototype's startScreen/startPhase props):
            // launch with `-onboardingScreen 6`, plus `-onboardingPhase 2` on screen 10.
            let jump = UserDefaults.standard.integer(forKey: "onboardingScreen")
            guard jump > 0 else { return }
            flow.go(jump)
            if jump == 10 {
                let phase = UserDefaults.standard.integer(forKey: "onboardingPhase")
                for _ in 0..<min(phase, 3) { _ = flow.tutorialTap() }
                if phase >= 4 { flow.completeImport() }
            }
            #endif
        }
    }

    /// Screen swap: incoming fades in with a 12pt rise (the design's gluttFade).
    /// The welcome screen exits with a zoom-through (scales up while fading) so
    /// tapping Start feels like diving into the app. Reduce Motion: plain fade.
    private var screenTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let insertion = AnyTransition.opacity.combined(with: .offset(y: 12))
        let removal: AnyTransition = flow.screen == 0
            ? .scale(scale: 1.12).combined(with: .opacity)
            : .identity
        return .asymmetric(insertion: insertion, removal: removal)
    }

    @ViewBuilder
    private var screenView: some View {
        switch flow.screen {
        case 0: WelcomeScreen { flow.advance() }
        case 1: IntroVideoScreen { flow.advance() }
        case 2: QuestionsIntroScreen { flow.advance() }
        case 3: GoalsScreen(state: state) { flow.advance() }
        case 4: RulesScreen(state: state) { flow.advance() }
        case 5: FourWeeksScreen { flow.advance() }
        case 6:
            PollyHeroScreen { flow.advance() }
                .overlay(alignment: .top) {
                    OnboardingChrome(progress: flow.progress, style: .overVideo) { flow.back() }
                }
        case 7: AIFeaturesScreen { flow.advance() }
        case 8:
            NotificationsSoftAskScreen(
                onTurnOn: { flow.toPermission() },
                onMaybeLater: { flow.skipToTutorial() }
            )
        case 9: NotificationPermissionScreen { flow.skipToTutorial() }
        default:
            ImportTutorialScreen(
                flow: flow,
                onImportNow: { finish(thenImport: true) },
                onFinish: { finish(thenImport: false) }
            )
        }
    }

    private func finish(thenImport: Bool) {
        state.apply(to: context)
        OnboardingPaywallHook.presentPostOnboarding {
            onFinish()
            if thenImport {
                router.pendingImportURL = Self.demoImportURL
                router.perform(.importRecipe)
            }
        }
    }
}

#Preview {
    OnboardingFlow(onFinish: {})
        .environment(Router())
        .modelContainer(for: UserPrefs.self, inMemory: true)
}
