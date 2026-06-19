import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @Query private var allPrefs: [UserPrefs]

    private var needsOnboarding: Bool {
        router.forceOnboarding || allPrefs.first?.hasCompletedOnboarding != true
    }

    var body: some View {
        @Bindable var router = router

        ZStack(alignment: .bottom) {
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

            if router.floatingButtonSuppressors == 0 {
                captureButton
            }
        }
        .sheet(isPresented: $router.isCaptureSheetPresented) {
            CaptureActionSheet()
                .presentationDetents([.medium])
                .presentationCornerRadius(Theme.Radius.sheet)
                .presentationBackground(Theme.Colors.background)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                router.checkForSharedImport()
                drainImportInbox()
            }
        }
        .task { drainImportInbox() }
        .fullScreenCover(isPresented: $router.demoCookOnLaunch) {
            if let recipe = recipes.first {
                CookModeView(recipe: recipe)
            }
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
        case .today: TodayView()
        case .recipes: RecipesView()
        case .plan: PlanView()
        case .kitchen: KitchenView()
        case .progress: ProgressTabView()
        }
    }

    /// Floating universal capture button. Deliberately quiet: it should read
    /// as part of the tab bar system, not compete with on-screen CTAs.
    private var captureButton: some View {
        Button {
            router.isCaptureSheetPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.Colors.accent)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.Colors.background, lineWidth: 3))
                .shadow(color: Theme.Colors.textPrimary.opacity(0.18), radius: 5, x: 0, y: 2)
        }
        .offset(y: -78)
        .accessibilityLabel("Add or import")
    }
}

#Preview {
    RootView()
        .environment(Router())
        .modelContainer(for: Recipe.self, inMemory: true)
}
