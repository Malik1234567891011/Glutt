import PhosphorSwift
import SwiftData
import SwiftUI

/// Kitchen tab shell: Inventory / Groceries / Leftovers.
struct KitchenView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case inventory = "Inventory"
        case groceries = "Groceries"
        case leftovers = "Leftovers"
        var id: String { rawValue }
    }

    @Environment(Router.self) private var router
    @State private var segment: Segment = .inventory
    @State private var isAddingPantryItem = false
    @State private var isAddingGroceryItem = false
    @State private var isScanningPantry = false

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
                case .groceries: GroceriesView(isAddingItem: $isAddingGroceryItem)
                case .leftovers: LeftoversView()
                }
            }
            .contentMargins(.bottom, 56, for: .scrollContent)
            .background(Theme.Colors.background)
            .navigationTitle("Kitchen")
        }
        .onAppear(perform: handlePendingAction)
        .onChange(of: router.pendingAction) { handlePendingAction() }
        .sheet(isPresented: $isScanningPantry) {
            PantryScanView()
        }
    }

    private func handlePendingAction() {
        switch router.pendingAction {
        case .addGroceryItem:
            router.pendingAction = nil
            segment = .groceries
            isAddingGroceryItem = true
        case .scanPantry:
            router.pendingAction = nil
            segment = .inventory
            // AI photo scan when available; manual add as the offline path.
            if LLMClient.isConfigured {
                isScanningPantry = true
            } else {
                isAddingPantryItem = true
            }
        default:
            break
        }
    }
}
