import SwiftUI

/// A pill segmented control (e.g. Ingredients | Steps). Active segment fills herb-green
/// with cream text; the track is a warm rounded rectangle.
struct SegmentedTabs: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { i in
                let isActive = i == selection
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = i
                    }
                } label: {
                    Text(titles[i])
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(isActive ? Theme.Colors.creamText : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                .fill(isActive ? Theme.Colors.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
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
