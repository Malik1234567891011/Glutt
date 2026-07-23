import SwiftData
import SwiftUI

/// Kitchen tab, redesigned to `Glutt Screens.dc.html` (screen "Kitchen"): a cream
/// header ("Your kitchen" / Kitchen + a scan + add button), a segmented control
/// (Ingredients / Tools / Groceries), and grouped inventory sections with food-icon
/// tiles and status pills.
struct KitchenView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case inventory = "Ingredients"
        case tools = "Tools"
        case groceries = "Groceries"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .inventory
    @State private var isAddingPantryItem = false
    @State private var isAddingGroceryItem = false
    @State private var isScanning = false

    private var segmentIndex: Binding<Int> {
        Binding(
            get: { Segment.allCases.firstIndex(of: segment) ?? 0 },
            set: { segment = Segment.allCases[$0] }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                header
                SegmentedTabs(titles: Segment.allCases.map(\.rawValue), selection: segmentIndex)
                    .padding(.horizontal, 20)

                switch segment {
                case .inventory: InventoryView(isAddingItem: $isAddingPantryItem, isScanning: $isScanning)
                case .tools: ToolsView()
                case .groceries: GroceriesView(isAddingItem: $isAddingGroceryItem)
                }
            }
            .contentMargins(.bottom, 56, for: .scrollContent)
            .background(Theme.Colors.background)
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your kitchen")
                    .font(BrandFont.nunito(12, 800)).tracking(1.6).textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.accent)
                Text("Kitchen")
                    .font(BrandFont.bricolage(31, 700))
                    .foregroundStyle(Theme.Colors.heading)
            }
            Spacer()
            HStack(spacing: 9) {
                if segment == .inventory, LLMClient.isConfigured {
                    Button {
                        Haptics.impact(.light); isScanning = true
                    } label: {
                        MS.photoCamera.sized(21).foregroundStyle(Theme.Colors.accent)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(Theme.Colors.card))
                            .overlay(Circle().strokeBorder(Theme.Colors.accent.opacity(0.35), lineWidth: 1.5))
                            .shadow(color: Theme.Colors.textPrimary.opacity(0.05), radius: 10, y: 3)
                    }
                    .buttonStyle(.plain)
                }
                if segment != .tools {
                    Button {
                        Haptics.impact(.light)
                        if segment == .inventory { isAddingPantryItem = true } else { isAddingGroceryItem = true }
                    } label: {
                        MS.add.sized(24).foregroundStyle(Theme.Colors.creamText)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(Theme.Colors.accent))
                            .shadow(color: Theme.Colors.textPrimary.opacity(0.12), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}
