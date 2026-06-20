import SwiftData
import SwiftUI

/// First-run flow coordinator: branded welcome → goals → rules → nutrition →
/// notification primer → scripted import tutorial → finish (paywall hook).
/// Every step is skippable; the app learns from usage either way.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router

    let onFinish: () -> Void

    @State private var state = OnboardingState()
    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, goals, rules, nutrition, notifications, tutorial

        var next: Step? { Step(rawValue: rawValue + 1) }
        /// Welcome and tutorial are full-bleed and own their own buttons.
        var usesChrome: Bool { self != .welcome && self != .tutorial }
        var usesStandardFooter: Bool {
            self == .goals || self == .rules || self == .nutrition
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if step.usesChrome { topBar }

            Group {
                switch step {
                case .welcome:
                    WelcomeScreen { advance() }
                case .goals:
                    GoalsScreen(state: state)
                case .rules:
                    RulesScreen(state: state)
                case .nutrition:
                    NutritionScreen(state: state)
                case .notifications:
                    NotificationPrimerScreen { advance() }
                case .tutorial:
                    ImportTutorialScreen(
                        onImportNow: { finish(thenImport: true) },
                        onFinish: { finish(thenImport: false) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if step.usesStandardFooter { standardFooter }
        }
        .background(Theme.Colors.background)
        .animation(.easeInOut, value: step)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            if backTarget != nil {
                Button { Haptics.impact(.light); goBack() } label: {
                    Image(systemName: "chevron.left").font(.headline)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            PageDots(count: Step.allCases.count, index: step.rawValue)
            Spacer()
            Button("Skip") { Haptics.impact(.light); finish(thenImport: false) }
                .font(.gluttCaption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
    }

    private var standardFooter: some View {
        Button { Haptics.impact(.medium); advance() } label: {
            HStack(spacing: 8) {
                Text("Continue").font(.system(size: 16, weight: .bold, design: .rounded))
                Ph.arrowRight.bold.resizable().scaledToFit().frame(width: 16, height: 16)
            }
            .foregroundStyle(Theme.Colors.creamText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.Colors.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Navigation

    private var backTarget: Step? {
        // No back from the first chrome'd step (goals) into welcome.
        step == .goals ? nil : Step(rawValue: step.rawValue - 1)
    }

    private func goBack() {
        if let target = backTarget { step = target }
    }

    private func advance() {
        if let next = step.next {
            step = next
        } else {
            finish(thenImport: false)
        }
    }

    /// The recipe the tutorial demonstrates — the cheesy ramen reel shown in frame 0.
    /// "Import my first recipe" imports it for real, so onboarding ends with a
    /// relevant recipe landing in the user's library (via the normal review screen).
    private static let demoImportURL = URL(string: "https://www.instagram.com/reel/DYxO-e7JPw3/")

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
