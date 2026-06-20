import PhosphorSwift
import SwiftData
import SwiftUI

/// Simplified in-store shopping UI: big rows, giant tap targets,
/// nothing but the list. Screen stays awake.
struct StoreModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GroceryItem.addedAt) private var items: [GroceryItem]

    private var remaining: [GroceryItem] { items.filter { !$0.isChecked } }

    var body: some View {
        VStack(spacing: 0) {
            header

            if remaining.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "All done!",
                    message: "Everything's in the cart.",
                    actionLabel: "Finish",
                    action: {
                        Haptics.impact(.light)
                        dismiss()
                    }
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(GroceryCategory.allCases) { category in
                            let categoryItems = remaining.filter { $0.category == category }
                            if !categoryItems.isEmpty {
                                Text(category.label.uppercased())
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, Theme.Spacing.sm)
                                ForEach(categoryItems) { item in
                                    bigRow(item)
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
        .background(Theme.Colors.background)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var header: some View {
        HStack {
            Button("Exit") {
                Haptics.impact(.light)
                dismiss()
            }
            .font(.gluttHeadline)
            .foregroundStyle(Theme.Colors.accent)
            Spacer()
            Text("\(items.count - remaining.count) of \(items.count)")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
        .padding(Theme.Spacing.md)
    }

    private func bigRow(_ item: GroceryItem) -> some View {
        Button {
            Haptics.notify(.success)
            withAnimation(.snappy) { item.isChecked = true }
        } label: {
            HStack {
                Ph.circle.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let quantity = item.displayQuantity {
                        Text(quantity)
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
