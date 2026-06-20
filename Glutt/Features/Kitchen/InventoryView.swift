import PhosphorSwift
import SwiftData
import SwiftUI

/// What's actually in the kitchen. Fast over precise: tap an item to cycle
/// its rough quantity, swipe to remove, use-soon items pinned on top.
struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PantryItem.name) private var items: [PantryItem]
    @Binding var isAddingItem: Bool
    @State private var searchText = ""
    @State private var isScanning = false

    private var visibleItems: [PantryItem] {
        guard !searchText.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter { $0.name.lowercased().contains(query) }
    }

    private var useSoonItems: [PantryItem] {
        visibleItems.filter { $0.isUseSoon && $0.roughQuantity != .out }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                searchField

                if items.isEmpty {
                    EmptyStateView(
                        icon: "refrigerator",
                        title: "Your kitchen is a mystery",
                        message: "Add what you have and recipes will show what you can already cook.",
                        actionLabel: LLMClient.isConfigured ? "Scan it with a photo" : "Add items",
                        action: {
                            if LLMClient.isConfigured {
                                isScanning = true
                            } else {
                                isAddingItem = true
                            }
                        }
                    )
                } else {
                    if !useSoonItems.isEmpty {
                        useSoonSection
                    }
                    ForEach(GroceryCategory.allCases) { category in
                        let categoryItems = visibleItems.filter { $0.category == category && !$0.isUseSoon }
                        if !categoryItems.isEmpty {
                            categorySection(category, items: categoryItems)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .toolbar {
            if LLMClient.isConfigured {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.impact(.light)
                        isScanning = true
                    } label: {
                        Ph.camera.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.impact(.light)
                    isAddingItem = true
                } label: {
                    Ph.plus.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
            }
        }
        .sheet(isPresented: $isAddingItem) {
            PantryItemEditorView()
        }
        .sheet(isPresented: $isScanning) {
            PantryScanView()
        }
    }

    private var searchField: some View {
        HStack {
            Ph.magnifyingGlass.regular
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField("Search your kitchen", text: $searchText)
                .font(.gluttBody)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
    }

    private var useSoonSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label {
                Text("Use soon")
            } icon: {
                Ph.warningCircle.fill
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
            .font(.gluttHeadline)
            .foregroundStyle(Theme.Colors.warning)
            ForEach(useSoonItems) { item in
                itemRow(item)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.warningTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func categorySection(_ category: GroceryCategory, items: [PantryItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(category.label)
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(items) { item in
                itemRow(item)
                    .cardStyle(padding: Theme.Spacing.sm)
            }
        }
    }

    private func itemRow(_ item: PantryItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.gluttBody)
                    .foregroundStyle(item.roughQuantity == .out ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                    .strikethrough(item.roughQuantity == .out)
                Text(item.location.label)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            // Tap to cycle: full -> half -> low -> out -> full
            Button {
                Haptics.impact(.light)
                item.roughQuantity = item.roughQuantity.next
                item.updatedAt = .now
            } label: {
                Chip(
                    label: item.roughQuantity.label,
                    isSelected: item.roughQuantity == .full,
                    tint: item.roughQuantity == .low || item.roughQuantity == .out
                        ? Theme.Colors.warning
                        : Theme.Colors.accent
                )
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button(item.useSoonDate == nil ? "Flag as use soon" : "Remove use-soon flag", systemImage: "exclamationmark.circle") {
                Haptics.impact(.light)
                item.useSoonDate = item.useSoonDate == nil
                    ? Calendar.current.date(byAdding: .day, value: 2, to: .now)
                    : nil
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Haptics.notify(.warning)
                context.delete(item)
            }
        }
    }
}

/// Add pantry items: single item with details, or bulk comma-separated.
struct PantryItemEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: GroceryCategory = .other
    @State private var quantity: RoughQuantity = .full
    @State private var location: StorageLocation = .fridge
    @State private var flagUseSoon = false
    @State private var bulkText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Add one item") {
                    TextField("Name (e.g. Chicken thighs)", text: $name)
                        .onChange(of: name) {
                            category = GroceryCategorizer.categorize(name)
                        }
                    Picker("Category", selection: $category) {
                        ForEach(GroceryCategory.allCases) { category in
                            Text(category.label).tag(category)
                        }
                    }
                    Picker("Where", selection: $location) {
                        ForEach(StorageLocation.allCases, id: \.self) { location in
                            Text(location.label).tag(location)
                        }
                    }
                    Picker("How much", selection: $quantity) {
                        ForEach(RoughQuantity.allCases, id: \.self) { quantity in
                            Text(quantity.label).tag(quantity)
                        }
                    }
                    Toggle("Use soon", isOn: $flagUseSoon)
                    Button("Add") {
                        Haptics.notify(.success)
                        addSingle()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Or add many at once") {
                    TextField("rice, eggs, spinach, honey…", text: $bulkText, axis: .vertical)
                        .lineLimit(2...4)
                    Button("Add all") {
                        Haptics.notify(.success)
                        addBulk()
                    }
                    .disabled(bulkText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Add to kitchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addSingle() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let item = PantryItem(
            name: trimmed,
            category: category,
            roughQuantity: quantity,
            location: location,
            useSoonDate: flagUseSoon ? Calendar.current.date(byAdding: .day, value: 2, to: .now) : nil
        )
        context.insert(item)
        name = ""
        flagUseSoon = false
    }

    private func addBulk() {
        let names = bulkText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for itemName in names {
            let category = GroceryCategorizer.categorize(itemName)
            let location: StorageLocation = category == .produce || category == .dairy || category == .meat
                ? .fridge
                : .pantry
            context.insert(PantryItem(name: itemName, category: category, location: location))
        }
        bulkText = ""
    }
}
