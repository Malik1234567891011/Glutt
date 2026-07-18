import SwiftData
import SwiftUI

/// Kitchen tab shell: Ingredients / Tools / Groceries.
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

    /// Int-based selection index bridged to/from `Segment` for `SegmentedTabs`.
    private var segmentIndex: Binding<Int> {
        Binding(
            get: { Segment.allCases.firstIndex(of: segment) ?? 0 },
            set: { segment = Segment.allCases[$0] }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                SegmentedTabs(
                    titles: Segment.allCases.map(\.rawValue),
                    selection: segmentIndex
                )
                .padding(.horizontal, Theme.Spacing.md)

                switch segment {
                case .inventory: InventoryView(isAddingItem: $isAddingPantryItem)
                case .tools: ToolsView()
                case .groceries: GroceriesView(isAddingItem: $isAddingGroceryItem)
                }
            }
            .contentMargins(.bottom, 56, for: .scrollContent)
            .background(Theme.Colors.background)
            .navigationTitle("Kitchen")
        }
    }
}
