import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
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
                        .tabItem {
                            Label(tab.label, systemImage: tab.icon)
                        }
                        .tag(tab)
                }
            }
            .tint(Theme.Colors.accent)

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
            }
        }
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
        .offset(y: -34)
        .accessibilityLabel("Add or import")
    }
}

#Preview {
    RootView()
        .environment(Router())
        .modelContainer(for: Recipe.self, inMemory: true)
}
