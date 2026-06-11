import SwiftData
import SwiftUI

/// Phase 0 placeholder for the Kitchen tab with its three segments.
/// Full inventory, groceries, and leftovers flows arrive in Phase 4.
struct KitchenView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case inventory = "Inventory"
        case groceries = "Groceries"
        case leftovers = "Leftovers"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .inventory
    @Query private var pantryItems: [PantryItem]
    @Query private var groceryItems: [GroceryItem]
    @Query private var leftovers: [Leftover]

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

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        switch segment {
                        case .inventory: inventoryList
                        case .groceries: groceriesList
                        case .leftovers: leftoversList
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle("Kitchen")
        }
    }

    @ViewBuilder
    private var inventoryList: some View {
        if pantryItems.isEmpty {
            EmptyStateView(
                icon: "refrigerator",
                title: "Your kitchen is a mystery",
                message: "Add what you have at home and Glutt will match recipes to your real kitchen."
            )
        } else {
            ForEach(GroceryCategory.allCases) { category in
                let items = pantryItems.filter { $0.category == category }
                if !items.isEmpty {
                    Text(category.label)
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    ForEach(items) { item in
                        HStack {
                            Text(item.name)
                                .font(.gluttBody)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Chip(label: item.roughQuantity.label)
                        }
                        .cardStyle(padding: Theme.Spacing.sm)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var groceriesList: some View {
        if groceryItems.isEmpty {
            EmptyStateView(
                icon: "cart",
                title: "Grocery list is empty",
                message: "Lists build themselves from your recipes and meal plan."
            )
        } else {
            ForEach(groceryItems) { item in
                HStack {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Theme.Colors.accent)
                    Text(item.name)
                        .font(.gluttBody)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if let quantity = item.quantityText {
                        Text(quantity)
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .cardStyle(padding: Theme.Spacing.sm)
            }
        }
    }

    @ViewBuilder
    private var leftoversList: some View {
        if leftovers.isEmpty {
            EmptyStateView(
                icon: "takeoutbag.and.cup.and.straw",
                title: "No leftovers",
                message: "When you cook, Glutt tracks the servings you didn't eat."
            )
        } else {
            ForEach(leftovers) { leftover in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leftover.title)
                            .font(.gluttHeadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("\(leftover.servingsRemaining.formatted()) servings · cooked \(leftover.ageInDays)d ago")
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    if leftover.isFrozen {
                        Image(systemName: "snowflake")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .cardStyle(padding: Theme.Spacing.sm)
            }
        }
    }
}
