import SwiftUI

/// Small tag/filter chip ("High protein", "Quick", "TikTok").
struct Chip: View {
    let label: String
    var isSelected: Bool = false
    var tint: Color = Theme.Colors.accent

    var body: some View {
        Text(label)
            .font(.gluttCaption.weight(.medium))
            .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? tint : Theme.Colors.card)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(isSelected ? .clear : Theme.Colors.border, lineWidth: 1)
            )
    }
}

/// Horizontally scrolling row of filter chips.
struct ChipRow: View {
    let labels: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(labels, id: \.self) { label in
                    Button {
                        selection = selection == label ? nil : label
                    } label: {
                        Chip(label: label, isSelected: selection == label)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
}
