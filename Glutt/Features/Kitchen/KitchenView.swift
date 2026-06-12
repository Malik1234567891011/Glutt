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

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                Picker("Section", selection: $segment) {
                    ForEach(Segment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
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
