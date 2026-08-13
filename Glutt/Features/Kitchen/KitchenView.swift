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

    /// The whole tab is Pro, all three segments. One cover rather than a dozen
    /// small gates: a kitchen with a crown on every row would read as broken,
    /// and the point is to show what is behind the wall, not to litter it.
    @Environment(Entitlements.self) private var gate: Entitlements?
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
                kitchenContent
            }
            .contentMargins(.bottom, 56, for: .scrollContent)
            .background(Theme.Colors.background)
            .navigationBarHidden(true)
        }
    }

    /// Ingredients is free: a free cook can see what is in their kitchen and
    /// type more in. Tools and Groceries are Pro, but they still *open* —
    /// blurred, with the wall over them, because someone has to be able to see
    /// what they are missing before they will pay for it.
    @ViewBuilder
    private var kitchenContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            SegmentedTabs(
                titles: Segment.allCases.map(\.rawValue),
                selection: segmentIndex,
                crowned: gate.isPro ? [] : [1, 2]
            )
            .padding(.horizontal, 20)

            switch segment {
            case .inventory:
                InventoryView(isAddingItem: $isAddingPantryItem, scanEntry: $scanEntry)
            case .tools:
                ToolsView()
                    .premiumLockedSurface(
                        .kitchenTools,
                        isUnlocked: gate.isPro,
                        headline: "Tell Glutt what you cook with",
                        message: "Glutt \(PremiumFeature.tierName) knows your pans and your gadgets, and stops handing you recipes you cannot make.",
                        bottomInset: GluttTabBar.reservedHeight
                    )
            case .groceries:
                GroceriesView(isAddingItem: $isAddingGroceryItem)
                    .premiumLockedSurface(
                        .groceries,
                        isUnlocked: gate.isPro,
                        headline: "One list for the whole week",
                        message: "Missing ingredients go straight from a recipe to your shop. Glutt \(PremiumFeature.tierName) unlocks groceries.",
                        bottomInset: GluttTabBar.reservedHeight
                    )
            }
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
                        gate.perform(.groceries) { isAddingGroceryItem = true }
                    } label: { plusCircle }
                    .buttonStyle(.plain)
                    .premiumCrown(.groceries, offset: CGSize(width: 6, height: -6))
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
                    Button { gate.perform(.pantryScan) { scanEntry = .camera } } label: {
                        PremiumMenuLabel(title: "Scan with a photo", systemImage: "camera.fill",
                                         feature: .pantryScan, isPro: gate.isPro)
                    }
                }
                Button { gate.perform(.pantryScan) { scanEntry = .library } } label: {
                    PremiumMenuLabel(title: "Choose a photo", systemImage: "photo.on.rectangle",
                                     feature: .pantryScan, isPro: gate.isPro)
                }
                Button { gate.perform(.pantryDictation) { scanEntry = .voice } } label: {
                    PremiumMenuLabel(title: "Tell us what you have", systemImage: "mic.fill",
                                     feature: .pantryDictation, isPro: gate.isPro)
                }
            }
            // Always last, always present, and always **free**. The three above
            // are shortcuts worth paying for; typing a tin of chickpeas in is
            // how a free cook fills their kitchen, and gating that would leave
            // the tab with nothing in it to look at.
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
