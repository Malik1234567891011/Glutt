import SwiftData
import SwiftUI

/// Rebuild of the design-handoff onboarding, 10 screens (`screen` 0–9). The
/// design's separate OS-permission page was folded into the soft-ask, so the
/// import tutorial is screen 9.
/// Spec: docs/superpowers/specs/2026-07-12-onboarding-redesign-design.md
///
/// The linear question/info screens (1–5, 7, 8) share a cream *scaffold*: a
/// fixed top progress bar and a fixed bottom CTA, with only the middle content
/// sliding horizontally between screens (forward = out to the left, in from the
/// right). Welcome (0), Polly (6) and the import tutorial (9) are full-screen
/// specials that fade in/out — Welcome keeps its own zoom-through exit.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context

    let onFinish: () -> Void
    /// Enables the "Already have an account? Log in" path on screen 0. Nil in
    /// previews, where there is no session to sign into.
    var session: AccountSession?
    /// Gates that same link on entitlement — see `canLogIn`.
    var gate: SubscriptionGate?

    @State private var showLogIn = false
    /// Restoring a purchase after the log-in tap. Swaps the link for a status
    /// line so the wait isn't a dead press.
    @State private var isCheckingLogIn = false
    @State private var flow = OnboardingFlowModel()
    @State private var state = OnboardingState()
    /// The screen we're leaving. Lets the content slide only *between* adjacent
    /// scaffold screens and fade when a full-screen special is on either side.
    @State private var fromScreen = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Screens that share the cream chrome + footer scaffold.
    private static let scaffoldScreens: Set<Int> = [1, 2, 3, 4, 5, 7, 8]

    /// "Already have an account? Log in" is always offered. What it does next
    /// depends on whether there is a subscription to find.
    ///
    /// Signing in with Apple **creates** the Supabase user when none exists (no
    /// sign-in-only mode exists for OIDC), so the Apple sheet must never open
    /// for someone who has not paid, or `profiles` stops being exactly the
    /// paying customers. Rather than hide the link, this checks entitlement
    /// first: a returning user is restored and then asked to sign in, and
    /// someone who never subscribed is told so and never reaches Apple.
    ///
    /// Restoring is the right first step regardless. The subscription lives on
    /// the Apple ID, so it is the part that actually gets their app back; the
    /// account only skips onboarding and re-links their history.
    private func logInTapped() {
        guard let gate, !isCheckingLogIn else { return }

        if gate.access == .unlocked {
            showLogIn = true
            return
        }

        isCheckingLogIn = true
        Task {
            let entitled = await gate.restorePurchases()
            isCheckingLogIn = false
            if entitled {
                showLogIn = true
            } else {
                // Superwall raises its own "nothing to restore" alert here, so
                // adding one would show the user two. Worth counting, though:
                // people who believe they have an account and don't.
                Analytics.capture(.loginNoSubscription)
            }
        }
    }

    /// Analytics labels for `screen` 0–9 — a funnel reading `screen: 7` alone
    /// tells you nothing a year from now.
    private static let screenNames = [
        "welcome", "intro_video", "questions_intro", "goals", "rules",
        "four_weeks", "polly_hero", "ai_features", "notifications",
        "import_tutorial",
    ]

    /// `flow.screen` is clamped 0–9, but an analytics label is never worth an
    /// out-of-bounds crash if that ever changes.
    private static func screenName(_ screen: Int) -> String {
        screenNames.indices.contains(screen) ? screenNames[screen] : "unknown"
    }

    var body: some View {
        ZStack {
            OnboardingTheme.cream.ignoresSafeArea()
            // Polly's cooking backdrop — its own layer so it cross-fades in/out
            // (behind the sliding pages) while only the copy slides.
            if flow.screen == 6 {
                PollyBackdrop()
                    .transition(.opacity)
            }
            screenLayer
        }
        // Fixed progress bar above the sliding pages — it stays put and just
        // grows as you advance, including across the Polly video page. (Welcome
        // 0 and the tutorial 9 show no bar.)
        .overlay(alignment: .top) {
            if (1...8).contains(flow.screen) {
                OnboardingChrome(progress: flow.progress)
            }
        }
        .animation(screenAnimation, value: flow.screen)
        .sheet(isPresented: $showLogIn) {
            if let session {
                SignInView(session: session, canDismiss: true) {
                    showLogIn = false
                    // Signed in on a new phone: skip the remaining screens.
                    // They've answered these questions before, and their
                    // subscription restores from the Apple ID independently.
                    if session.userID != nil { finish() }
                }
            }
        }
        // `initial: true` covers screen 0 as well, so the top of the funnel is
        // one event type rather than a separate "started".
        .onChange(of: flow.screen, initial: true) { _, screen in
            Analytics.capture(.onboardingScreenViewed, [
                "screen": screen,
                "name": Self.screenName(screen),
            ])
        }
        .onAppear {
            #if DEBUG
            // Staging hook: launch with `-onboardingScreen 6`, plus
            // `-onboardingPhase 2` on screen 9 (the import tutorial).
            let jump = UserDefaults.standard.integer(forKey: "onboardingScreen")
            guard jump > 0 else { return }
            fromScreen = jump
            flow.go(jump)
            if jump == 9 {
                let phase = UserDefaults.standard.integer(forKey: "onboardingPhase")
                for _ in 0..<min(phase, 3) { _ = flow.tutorialTap() }
                if phase >= 4 { flow.completeImport() }
            }
            #endif
        }
    }

    private var screenAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.42, dampingFraction: 0.92)
    }

    /// Welcome (0), Polly (6) and the tutorial (9) render full-screen; every
    /// other screen renders inside the shared scaffold.
    @ViewBuilder private var screenLayer: some View {
        switch flow.screen {
        case 0:
            // Self-animates a zoom-through exit before advancing; its removal is
            // instant (it has already faded itself out), so `.identity`.
            WelcomeScreen(
                onStart: { advance() },
                onLogIn: (session == nil || gate == nil) ? nil : logInTapped,
                isCheckingLogIn: isCheckingLogIn
            )
            .transition(.identity)
        case 6:
            // Copy slides in; the backdrop (a separate layer, above) fades.
            PollyHeroScreen { advance() }
                .transition(pageTransition)
        case 9:
            ImportTutorialScreen(flow: flow, onFinish: { finish() })
                .transition(pageTransition)
        default:
            scaffold
                .transition(pageTransition)
        }
    }

    /// Fixed bottom CTA; only `pageContent` slides between scaffold screens.
    /// (The progress bar is a fixed coordinator-level overlay.)
    private var scaffold: some View {
        VStack(spacing: 0) {
            pageContent(flow.screen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(flow.screen)
                .transition(contentTransition)
            pageFooter(flow.screen)
        }
        // Opaque, so Polly's video backdrop never bleeds through a scaffold page
        // as it slides past on the way in/out.
        .background(OnboardingTheme.cream.ignoresSafeArea())
    }

    /// Whole-page transition (Polly, tutorial, and the scaffold as one unit):
    /// forward slide, except a fade at the Welcome boundary (its zoom-through
    /// handoff) or under Reduce Motion.
    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        if fromScreen == 0 || flow.screen == 0 { return .opacity }
        return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
    }

    /// The scaffold's middle content slides between adjacent scaffold screens;
    /// when entering/leaving a full-screen special the whole scaffold slides, so
    /// the content just rides along (`.identity`).
    private var contentTransition: AnyTransition {
        if reduceMotion { return .opacity }
        if Self.scaffoldScreens.contains(fromScreen), Self.scaffoldScreens.contains(flow.screen) {
            return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        }
        return .identity
    }

    @ViewBuilder private func pageContent(_ screen: Int) -> some View {
        switch screen {
        case 1: IntroVideoScreen()
        case 2: QuestionsIntroScreen()
        case 3: GoalsScreen(state: state)
        case 4: RulesScreen(state: state)
        case 5: FourWeeksScreen()
        case 7: AIFeaturesScreen()
        default: NotificationsSoftAskScreen() // 8
        }
    }

    /// The fixed CTA for each scaffold screen. Horizontal + bottom padding match
    /// each screen's design insets so the button lines up with its content.
    @ViewBuilder private func pageFooter(_ screen: Int) -> some View {
        switch screen {
        case 3:
            Group {
                if state.canContinueFromGoals {
                    OnboardingPrimaryButton(title: "Continue", action: advance)
                } else {
                    OnboardingDisabledPill(title: "Continue")
                }
            }
            .padding(.horizontal, 22).padding(.bottom, 8)
        case 4:
            OnboardingPrimaryButton(title: "Continue", action: advance)
                .padding(.horizontal, 22).padding(.bottom, 8)
        case 8:
            // The single notifications page: "Turn on" fires the real OS prompt,
            // "Maybe later" skips — both land on the import tutorial.
            NotificationsFooter(onDone: { navigate { flow.skipToTutorial() } })
        default: // 1, 2, 5, 7
            OnboardingPrimaryButton(title: "Continue", action: advance)
                .padding(.horizontal, 24).padding(.bottom, 10)
        }
    }

    // MARK: - Navigation (records the outgoing screen for slide direction)

    private func advance() { navigate { flow.advance() } }

    private func navigate(_ step: () -> Void) {
        fromScreen = flow.screen
        step()
    }

    private func finish() {
        Analytics.capture(.onboardingCompleted, [
            "goals": state.selectedGoals.count,
            "dietary_rules": state.selectedRules.count,
        ])
        state.apply(to: context)
        // Land straight into the app. The hard-paywall gate takes over from
        // here — the first touch bounces to the paywall (see `SubscriptionGate`).
        onFinish()
    }
}

#Preview {
    OnboardingFlow(onFinish: {})
        .environment(Router())
        .modelContainer(for: UserPrefs.self, inMemory: true)
}
