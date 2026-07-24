import SwiftData
import SwiftUI
import UserNotifications

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @Query private var allPrefs: [UserPrefs]

    /// The hard-paywall gate. Glutt is unusable without an active subscription;
    /// this owns that decision app-wide (see `SubscriptionGate`).
    @State private var gate = SubscriptionGate()

    /// Polly v2 transport spike (Phase 1, `-pollyV2Spike`). Deleted with the
    /// spike before the v2 merge.
    @State private var showPollyV2Spike = ProcessInfo.processInfo.arguments.contains("-pollyV2Spike")

    private var needsOnboarding: Bool {
        router.forceOnboarding || allPrefs.first?.hasCompletedOnboarding != true
    }

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                tabContent(for: tab)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
            }
        }
        // Restore the app-wide accent tint (the native tab bar's `.tint` was
        // removed with the custom bar; without this, toolbar/system controls
        // fall back to system blue). The hidden native bar ignores it.
        .tint(Theme.Colors.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GluttTabBar(selection: $router.selectedTab)
        }
        // Hard paywall. `.resolving` covers the app with a neutral splash while
        // entitlement loads; `.locked` lets the tabs show but swallows every
        // touch and bounces to the paywall; `.unlocked` is the full app.
        // Sits under the onboarding/cook/Polly covers (they present above), so
        // a locked user still can't reach them — every touch bounces first.
        .overlay {
            switch gate.access {
            case .resolving: GateSplashView()
            case .locked: PaywallGateOverlay { gate.presentPaywall() }
            case .unlocked: EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: gate.access)
        .task { gate.start() }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                router.checkForSharedImport()
                drainImportInbox()
                Task { await RecipeImageBackfill.sweep(in: context) }
            }
        }
        .task { drainImportInbox() }
        .task { await RecipeImageBackfill.sweep(in: context) }
        .task(id: needsOnboarding) {
            // Notification permission is requested exactly once, on onboarding
            // screen 9. At launch we only (re)schedule if it's already granted —
            // "Maybe later" must keep meaning *not now*.
            guard !needsOnboarding,
                  !ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                ReminderScheduler.schedulePlatesDailyReminder()
            }
        }
        .fullScreenCover(isPresented: $router.demoCookOnLaunch) {
            if let recipe = recipes.first {
                CookModeView(recipe: recipe)
            }
        }
        .fullScreenCover(item: $router.pollyLaunch) { launch in
            PollySessionView(recipe: launch.recipe, scale: launch.scale)
        }
        .fullScreenCover(isPresented: $showPollyV2Spike) {
            PollyV2SpikeView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { needsOnboarding },
            set: { if !$0 { router.forceOnboarding = false } }
        )) {
            OnboardingFlow {
                router.forceOnboarding = false
            }
            .interactiveDismissDisabled()
        }
    }

    /// Materializes recipes the share extension finished into SwiftData, and
    /// tells the router which import ids map to which saved recipes (so a
    /// "View recipe" deep link can navigate to the right one).
    private func drainImportInbox() {
        let map = ImportInboxDrainer.drain(into: context)
        if !map.isEmpty { router.noteImported(map) }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .recipes: RecipesView()
        case .discover: DiscoverTabView()
        case .kitchen: KitchenView()
        }
    }
}

#Preview {
    RootView()
        .environment(Router())
        .modelContainer(for: Recipe.self, inMemory: true)
}
