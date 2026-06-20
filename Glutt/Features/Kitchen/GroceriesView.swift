import PhosphorSwift
import SwiftData
import SwiftUI

/// The shopping list: grouped by aisle, checked items sink, and finishing
/// a shop offers to move bought items into the inventory.
struct GroceriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \GroceryItem.addedAt) private var items: [GroceryItem]
    @Binding var isAddingItem: Bool

    @State private var newItemName = ""
    @State private var isStoreMode = false
    @State private var isConfirmingShopDone = false

    private var uncheckedItems: [GroceryItem] { items.filter { !$0.isChecked } }
    private var checkedItems: [GroceryItem] { items.filter { $0.isChecked } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                quickAddField

                if items.isEmpty {
                    EmptyStateView(
                        icon: "cart",
                        title: "Grocery list is empty",
                        message: "Add items here, or tap \u{201C}Add missing to groceries\u{201D} on any recipe."
                    )
                } else {
                    ForEach(GroceryCategory.allCases) { category in
                        let categoryItems = uncheckedItems.filter { $0.category == category }
                        if !categoryItems.isEmpty {
                            categorySection(category, items: categoryItems)
                        }
                    }

                    if !checkedItems.isEmpty {
                        checkedSection
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !items.isEmpty {
                    Button {
                        Haptics.impact(.light)
                        isStoreMode = true
                    } label: {
                        Ph.basket.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isStoreMode) {
            StoreModeView()
        }
        .confirmationDialog(
            "Move \(checkedItems.count) bought items into your kitchen inventory?",
            isPresented: $isConfirmingShopDone,
            titleVisibility: .visible
        ) {
            Button("Add to inventory") {
                Haptics.notify(.success)
                moveCheckedToInventory()
            }
            Button("Just clear them", role: .destructive) {
                Haptics.notify(.warning)
                checkedItems.forEach { context.delete($0) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: isAddingItem) {
            // The capture sheet routes "Add grocery item" here.
            isAddingItem = false
        }
    }

    private var quickAddField: some View {
        HStack {
            TextField("Add an item…", text: $newItemName)
                .font(.gluttBody)
                .onSubmit(addItem)
            Button {
                addItem()
            } label: {
                Ph.plusCircle.fill
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Theme.Colors.accent)
            }
            .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
    }

    private func addItem() {
        let trimmed = newItemName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Haptics.notify(.success)
        let item = GroceryItem(
            name: trimmed,
            category: GroceryCategorizer.categorize(trimmed),
            substitutionHint: SubstitutionService.substitutions(for: trimmed).first?.name
        )
        context.insert(item)
        newItemName = ""
    }

    private func categorySection(_ category: GroceryCategory, items: [GroceryItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(category.label)
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(items) { item in
                GroceryItemRow(item: item)
            }
        }
    }

    private var checkedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("In the cart (\(checkedItems.count))")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Button("Done shopping") { isConfirmingShopDone = true }
                    .buttonStyle(.gluttPill)
            }
            ForEach(checkedItems) { item in
                GroceryItemRow(item: item)
                    .opacity(0.55)
            }
        }
    }

    private func moveCheckedToInventory() {
        for item in checkedItems {
            let location: StorageLocation = switch item.category {
            case .produce, .dairy, .meat: .fridge
            case .frozen: .freezer
            default: .pantry
            }
            context.insert(PantryItem(name: item.name, category: item.category, location: location))
            context.delete(item)
        }
    }
}

struct GroceryItemRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var item: GroceryItem

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Button {
                Haptics.impact(.light)
                withAnimation(.snappy) { item.isChecked.toggle() }
            } label: {
                (item.isChecked ? Ph.checkCircle.fill : Ph.circle.regular)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.name)
                        .font(.gluttBody)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .strikethrough(item.isChecked)
                    if item.isOptional {
                        Text("optional")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    if let quantity = item.displayQuantity {
                        Text(quantity)
                            .font(.gluttCaption.weight(.medium))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                if !item.sourceRecipeTitles.isEmpty {
                    Text("For: \(item.sourceRecipeTitles.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                if let hint = item.substitutionHint, !item.isChecked {
                    Text("Or swap: \(hint)")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.warning)
                }
            }
        }
        .cardStyle(padding: Theme.Spacing.sm)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                Haptics.notify(.warning)
                context.delete(item)
            }
        }
    }
}
