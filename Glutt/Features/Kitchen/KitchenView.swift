import SwiftData
import SwiftUI

/// Kitchen tab, redesigned to `Glutt Screens.dc.html` (screen "Kitchen"): a cream
/// header ("Your kitchen" / Kitchen + one add menu), a segmented control
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
    /// Which way into the scan sheet the menu picked, and whether it is open.
    @State private var scanEntry: PantryScanView.Entry?

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
                case .inventory:
                    InventoryView(isAddingItem: $isAddingPantryItem, scanEntry: $scanEntry)
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
                switch segment {
                case .inventory: addIngredientsMenu
                case .groceries:
                    Button {
                        Haptics.impact(.light)
                        isAddingGroceryItem = true
                    } label: { plusCircle }
                    .buttonStyle(.plain)
                case .tools:
                    EmptyView()
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// Every way of getting food into the kitchen, behind one control.
    ///
    /// There used to be a camera button here as well, and tapping it opened a
    /// sheet whose first screen offered a photo, the library and voice all over
    /// again. Two buttons, one of which was a menu wearing a camera icon.
    private var addIngredientsMenu: some View {
        Menu {
            if LLMClient.isConfigured {
                if CameraPicker.isAvailable {
                    Button { scanEntry = .camera } label: {
                        Label("Scan with a photo", systemImage: "camera.fill")
                    }
                }
                Button { scanEntry = .library } label: {
                    Label("Choose a photo", systemImage: "photo.on.rectangle")
                }
                Button { scanEntry = .voice } label: {
                    Label("Tell us what you have", systemImage: "mic.fill")
                }
            }
            // Always last, and always present. The three above need the AI
            // configured; typing a tin of chickpeas in never does.
            Button {
                isAddingPantryItem = true
            } label: { Label("Add manually", systemImage: "square.and.pencil") }
        } label: {
            plusCircle
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.impact(.light) })
    }

    private var plusCircle: some View {
        MS.add.sized(24).foregroundStyle(Theme.Colors.creamText)
            .frame(width: 42, height: 42)
            .background(Circle().fill(Theme.Colors.accent))
            .shadow(color: Theme.Colors.textPrimary.opacity(0.12), radius: 18, y: 8)
    }
}
