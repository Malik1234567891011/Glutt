import SwiftUI

/// A pill segmented control (e.g. Ingredients | Steps). Active segment is a raised
/// cream pill with dark text; the track is a warm rounded rectangle.
/// Source: `Glutt Screens.dc.html` (detail + Kitchen segmented controls).
struct SegmentedTabs: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(titles.indices, id: \.self) { i in
                let isActive = i == selection
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = i
                    }
                } label: {
                    Text(titles[i])
                        .font(BrandFont.nunito(14, isActive ? 800 : 700))
                        .foregroundColor(isActive ? Theme.Colors.heading : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                .fill(isActive ? Theme.Colors.card : Color.clear)
                                .shadow(color: isActive ? Theme.Colors.textPrimary.opacity(0.09) : .clear,
                                        radius: 6, y: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.segment, style: .continuous)
                .fill(Theme.Colors.segmentTrack)
        )
    }
}

#Preview("SegmentedTabs") {
    struct Demo: View {
        @State private var sel = 1
        var body: some View {
            SegmentedTabs(titles: ["Ingredients", "Steps"], selection: $sel)
                .padding()
                .background(Theme.Colors.background)
        }
    }
    return Demo()
}
