import SwiftData
import SwiftUI

/// What's actually in the kitchen. Fast over precise: tap an item to cycle
/// its rough quantity, swipe to remove, use-soon items flagged with an inline badge.
struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PantryItem.name) private var items: [PantryItem]
    @Binding var isAddingItem: Bool
    @State private var searchText = ""
    @State private var isScanning = false
    @State private var editingQuantityItem: PantryItem?
    @State private var exactQuantityText = ""

    private var visibleItems: [PantryItem] {
        guard !searchText.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter { $0.name.lowercased().contains(query) }
    }

    /// A use-soon item still worth flagging: not fully out of stock.
    private func showsUseSoonBadge(_ item: PantryItem) -> Bool {
        item.isUseSoon && item.roughQuantity != .out
    }

    /// Staples surfaced in their own section, so they don't clutter the
    /// regular category lists (and their opt-out markers stay tidy).
    private func isAssumedStaple(_ item: PantryItem) -> Bool {
        PantryMatcher.assumedStapleCanonicals.contains(item.canonicalName)
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
                    // Use-soon items surface inline (via per-row badge) inside their
                    // category sections rather than in a separate pinned section.
                    ForEach(GroceryCategory.allCases) { category in
                        let categoryItems = visibleItems.filter {
                            $0.category == category && !isAssumedStaple($0)
                        }
                        if !categoryItems.isEmpty {
                            categorySection(category, items: categoryItems)
                        }
                    }
                }

                if searchText.isEmpty {
                    assumedStaplesSection
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
                        // Outlined herb-green circle — pantry scan.
                        Ph.camera.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle().strokeBorder(Theme.Colors.accent, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.impact(.light)
                    isAddingItem = true
                } label: {
                    // Filled herb-green circle — add item.
                    Ph.plus.bold
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Theme.Colors.creamText)
                        .frame(width: 38, height: 38)
                        .background(Theme.Colors.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $isAddingItem) {
            PantryItemEditorView()
        }
        .sheet(isPresented: $isScanning) {
            PantryScanView()
        }
        .alert("Exact amount", isPresented: Binding(
            get: { editingQuantityItem != nil },
            set: { if !$0 { editingQuantityItem = nil } }
        )) {
            TextField("e.g. 1 lb, 2 bell peppers, 24 eggs", text: $exactQuantityText)
            Button("Save") {
                editingQuantityItem?.exactQuantity = exactQuantityText
                    .trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil
                        : exactQuantityText.trimmingCharacters(in: .whitespaces)
                editingQuantityItem?.updatedAt = .now
                editingQuantityItem = nil
            }
            Button("Cancel", role: .cancel) { editingQuantityItem = nil }
        } message: {
            Text("Optional. Add a precise amount if the rough level isn't enough.")
        }
    }

    // MARK: - Assumed staples

    /// Salt, pepper, oil, water — assumed present when matching recipes. Listed
    /// here so the assumption is visible and the user can switch off anything
    /// they don't actually keep (which then counts as missing).
    private var assumedStaplesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Assumed you have")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Glutt treats these basics as on-hand when checking recipes. Turn off anything you don't keep and it'll count as missing.")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(PantryMatcher.assumedStapleCanonicals, id: \.self) { canonical in
                stapleToggleRow(canonical)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func stapleToggleRow(_ canonical: String) -> some View {
        let optOut = items.first { $0.canonicalName == canonical && $0.roughQuantity == .out }
        return Toggle(canonical.capitalized, isOn: Binding(
            get: { optOut == nil },
            set: { assumed in setStaple(canonical, assumed: assumed) }
        ))
        .font(.gluttBody)
        .tint(Theme.Colors.accent)
        .hapticOnChange(of: optOut == nil)
    }

    /// Toggling off creates/marks an "out" row so the matcher stops assuming it;
    /// toggling back on restores it. Non-destructive either way.
    private func setStaple(_ canonical: String, assumed: Bool) {
        let existing = items.first { $0.canonicalName == canonical }
        if assumed {
            existing?.roughQuantity = .full
            existing?.updatedAt = .now
        } else if let existing {
            existing.roughQuantity = .out
            existing.updatedAt = .now
        } else {
            context.insert(PantryItem(
                name: canonical.capitalized,
                category: .spices,
                roughQuantity: .out,
                location: .pantry
            ))
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

    private func categorySection(_ category: GroceryCategory, items: [PantryItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel(text: category.label)
                .padding(.leading, Theme.Spacing.xs)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    itemRow(item)
                        .padding(.vertical, Theme.Spacing.sm)
                        .padding(.horizontal, Theme.Spacing.md)
                    if index < items.count - 1 {
                        Divider()
                            .overlay(Theme.Colors.border)
                            .padding(.leading, Theme.Spacing.md)
                    }
                }
            }
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
            )
        }
    }

    /// Section-tinted 36pt icon chip keyed off the item's grocery category.
    /// Tints mirror the handoff: produce → green, protein → tomato, dairy → amber.
    @ViewBuilder
    private func categoryChip(for category: GroceryCategory) -> some View {
        IngredientCategoryStyle.chip(for: category)
    }

    /// Peach pill with tomato text for items flagged use-soon.
    private var useSoonBadge: some View {
        Text("Use soon")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.Colors.tomato)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .background(Theme.Colors.peachPanel)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func itemRow(_ item: PantryItem) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            categoryChip(for: item.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.gluttBody.weight(.bold))
                    .foregroundStyle(item.roughQuantity == .out ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                    .strikethrough(item.roughQuantity == .out)
                Text([item.exactQuantity, item.location.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(item.exactQuantity == nil ? Theme.Colors.textSecondary : Theme.Colors.accent)
            }
            Spacer(minLength: Theme.Spacing.sm)
            // Right-side status: inline use-soon badge, else an "In stock" caption.
            if showsUseSoonBadge(item) {
                useSoonBadge
            } else {
                Text("In stock")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
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
            Button("Set exact amount…", systemImage: "scalemass") {
                exactQuantityText = item.exactQuantity ?? ""
                editingQuantityItem = item
            }
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
    @State private var exactQuantity = ""
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
                    TextField("Exact amount (optional): 1 lb, 24 eggs…", text: $exactQuantity)
                    Toggle("Use soon", isOn: $flagUseSoon)
                        .hapticOnChange(of: flagUseSoon)
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
            useSoonDate: flagUseSoon ? Calendar.current.date(byAdding: .day, value: 2, to: .now) : nil,
            exactQuantity: exactQuantity.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : exactQuantity.trimmingCharacters(in: .whitespaces)
        )
        context.insert(item)
        name = ""
        exactQuantity = ""
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
