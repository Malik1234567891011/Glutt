import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router

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

            captureButton
        }
        .sheet(isPresented: $router.isCaptureSheetPresented) {
            CaptureActionSheet()
                .presentationDetents([.medium])
                .presentationCornerRadius(Theme.Radius.sheet)
                .presentationBackground(Theme.Colors.background)
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

    /// Floating universal capture button, raised above the tab bar center.
    private var captureButton: some View {
        Button {
            router.isCaptureSheetPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.Colors.accent)
                .clipShape(Circle())
                .shadow(color: Theme.Colors.accent.opacity(0.35), radius: 10, x: 0, y: 4)
        }
        .offset(y: -38)
        .accessibilityLabel("Add or import")
    }
}

#Preview {
    RootView()
        .environment(Router())
        .modelContainer(for: Recipe.self, inMemory: true)
}
