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

    /// Who is signed in. A separate axis from `gate` on purpose: paying does
    /// not sign you in, and signing in does not unlock the app.
    @State private var session = AccountSession()

    /// Backs the library with Supabase. Third axis, and the quietest one: it
    /// does nothing at all until somebody is signed in, and a failure never
    /// reaches a screen. See docs/plan-recipe-sync.md.
    @State private var sync = SyncCoordinator()

    /// Polly v2 transport spike (Phase 1, `-pollyV2Spike`). Deleted with the
    /// spike before the v2 merge.
    @State private var showPollyV2Spike = ProcessInfo.processInfo.arguments.contains("-pollyV2Spike")

    /// `-importScreen`: the share extension's sheet, staged over the app so its
    /// three states are reachable in the simulator at all.
    @State private var stagedImport: ShareImportViewModel?

    private var needsOnboarding: Bool {
        router.forceOnboarding || allPrefs.first?.hasCompletedOnboarding != true
    }

    /// A locked user who is past onboarding. Drives the automatic paywall
    /// presentation below.
    private var shouldPresentPaywall: Bool {
        gate.access == .locked && !needsOnboarding
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
        // So Settings (presented from deep inside a tab) can offer sign out and
        // account deletion without threading the session through every screen.
        .environment(session)
        // Sign out has to flush the queue before it wipes the local library, so
        // Settings needs to reach the coordinator too.
        .environment(sync)
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
            case .unlocked: unlockedOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: gate.access)
        .animation(.easeInOut(duration: 0.2), value: session.state)
        .task { gate.start() }
        .task { session.start() }
        // Present the wall the moment a locked user lands, rather than waiting
        // for them to tap: pressing Continue at the end of onboarding should
        // open the paywall, never the app. Held back until onboarding is done,
        // or it would fire behind the onboarding cover on a first launch.
        .task(id: shouldPresentPaywall) {
            guard shouldPresentPaywall else { return }
            // A beat for the onboarding cover to finish dismissing. Presenting
            // into a view controller that is still going away gets the paywall
            // torn down with it.
            try? await Task.sleep(nanoseconds: 350_000_000)
            gate.presentPaywallOnce()
        }
        // Who is signed in decides whether anything syncs at all, and a change
        // of account has to re-point the coordinator before the next sweep.
        .task(id: session.userID) {
            RecipeIdentity.backfill(in: context)
            sync.configure(userID: session.userID, context: context)
            guard session.userID != nil else { return }
            // Immediate rather than debounced: this is the moment a new phone
            // gets its library back, and two seconds of an empty shelf reads as
            // "my recipes are gone".
            await sync.syncNow()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                router.checkForSharedImport()
                drainImportInbox()
                Task { await RecipeImageBackfill.sweep(in: context) }
                sync.requestSync()
            }
            // Also on the way out: the share extension runs while the app is
            // backgrounded, and this is what lets it count what's in the kitchen.
            mirrorPantryForShareExtension()
        }
        .task { drainImportInbox() }
        .task { mirrorPantryForShareExtension() }
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
        .task(id: router.pollyCookOnLaunch) {
            // `-pollyCook`: jump straight into a live Polly session so the cook
            // screen's connecting / failed / mic-denied states are reachable in
            // the simulator. Routed through pollyLaunch rather than a separate
            // cover so it exercises the real presentation path.
            guard router.pollyCookOnLaunch, let recipe = recipes.first else { return }
            router.pollyCookOnLaunch = false
            router.pollyLaunch = PollyLaunch(recipe: recipe, scale: 1, heardBriefing: false, awaitVerbalGo: false)
        }
        .fullScreenCover(item: $router.pollyLaunch) { launch in
            PollySessionView(
                recipe: launch.recipe,
                scale: launch.scale,
                heardBriefing: launch.heardBriefing,
                awaitVerbalGo: launch.awaitVerbalGo
            )
        }
        .fullScreenCover(isPresented: $showPollyV2Spike) {
            PollyV2SpikeView()
        }
        // `-importScreen importing|saved|failed`: the share extension's sheet,
        // staged over the app. See ImportScreenStaging.
        .fullScreenCover(isPresented: Binding(
            get: { stagedImport != nil },
            set: { if !$0 { stagedImport = nil } }
        )) {
            if let stagedImport {
                ImportSheet(
                    viewModel: stagedImport,
                    onViewRecipe: { _ in self.stagedImport = nil },
                    onClose: { self.stagedImport = nil }
                )
                // So the dimmed backdrop reads against the app, the way the
                // extension reads against the host app.
                .presentationBackground(.clear)
            }
        }
        .task {
            guard let scenario = ImportScreenStaging.requested else { return }
            let model = ImportScreenStaging.viewModel(for: scenario)
            stagedImport = model
            await model.start()
        }
        .fullScreenCover(isPresented: Binding(
            get: { needsOnboarding },
            set: { if !$0 { router.forceOnboarding = false } }
        )) {
            OnboardingFlow(
                onFinish: { router.forceOnboarding = false },
                session: session,
                gate: gate
            )
            .interactiveDismissDisabled()
        }
    }

    /// Materializes recipes the share extension finished into SwiftData, and
    /// tells the router which import ids map to which saved recipes (so a
    /// "View recipe" deep link can navigate to the right one).
    private func drainImportInbox() {
        let map = ImportInboxDrainer.drain(into: context)
        guard !map.isEmpty else { return }
        router.noteImported(map)
        // A recipe imported from the share sheet is the single most expensive
        // thing to lose, so it does not wait for the next foreground.
        sync.requestSync()
    }

    /// Mirrors the kitchen into the app group so the share extension can say how
    /// many of an imported recipe's ingredients are already on hand. The staples
    /// are folded in here so `PantryMatcher` — and the SwiftData models it needs
    /// — never have to exist inside the extension.
    private func mirrorPantryForShareExtension() {
        let items = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        let stocked = items.filter { $0.roughQuantity != .out }.map(\.canonicalName)
        let outOfStock = Set(items.filter { $0.roughQuantity == .out }.map(\.canonicalName))
        let staples = PantryMatcher.assumedStapleCanonicals.filter { !outOfStock.contains($0) }
        PantrySnapshot.write(canonicalNames: stocked + staples)
    }

    /// The second axis, reached only once entitlement is resolved and active.
    ///
    /// `.signedOut` is the cell that would otherwise bite: someone pays, then
    /// kills the app before signing in. Next launch they are entitled with no
    /// account, and this catches them.
    @ViewBuilder private var unlockedOverlay: some View {
        switch session.state {
        case .resolving:
            GateSplashView()
        case .signedOut where !session.deferredThisLaunch
            && !ProcessInfo.processInfo.arguments.contains("-seed")
            && !ProcessInfo.processInfo.arguments.contains("-uiPreview"):
            SignInView(session: session)
        default:
            EmptyView()
        }
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
