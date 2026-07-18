import SwiftUI

/// The redesigned bottom tab bar: a full-width dark bar with rounded top corners
/// and Phosphor glyphs. Drives `Router.selectedTab` via the binding — it does NOT
/// own navigation; the host `TabView` still switches content.
struct GluttTabBar: View {
    /// Vertical footprint the bar occupies over content. Screens that pin
    /// content/CTAs to the bottom use this to clear the bar. Keep in sync with
    /// the bar's layout (top padding + glyph/label height).
    static let reservedHeight: CGFloat = 76

    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isActive = tab == selection
                Button {
                    Haptics.selection()
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        glyph(for: tab, active: isActive)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundColor(isActive ? Theme.Colors.activeTabGlyph : Theme.Colors.tabInactive)
                        Text(tab.label)
                            .font(.system(size: 11, weight: isActive ? .bold : .semibold, design: .rounded))
                            .foregroundColor(isActive ? Theme.Colors.creamText : Theme.Colors.tabInactive)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 6)
        .background(
            Theme.Colors.textPrimary
                .clipShape(.rect(topLeadingRadius: Theme.Radius.tabBarTop,
                                 topTrailingRadius: Theme.Radius.tabBarTop))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func glyph(for tab: AppTab, active: Bool) -> Image {
        switch tab {
        case .recipes:  return active ? Ph.bookOpen.fill : Ph.bookOpen.regular
        case .discover: return active ? Ph.sparkle.fill : Ph.sparkle.regular
        case .kitchen:  return active ? Ph.cookingPot.fill : Ph.cookingPot.regular
        }
    }
}

#Preview("GluttTabBar") {
    struct Demo: View {
        @State private var tab: AppTab = .recipes
        var body: some View {
            VStack { Spacer(); GluttTabBar(selection: $tab) }
                .background(Theme.Colors.background)
        }
    }
    return Demo()
}
