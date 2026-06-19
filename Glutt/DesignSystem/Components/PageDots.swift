import SwiftUI

/// Onboarding page indicator: the active page is a 24×8 herb-green bar,
/// inactive pages are 8×8 muted dots.
struct PageDots: View {
    let count: Int
    let index: Int
    var active: Color = Theme.Colors.accent
    var inactive: Color = Theme.Colors.dotInactive

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i == index ? active : inactive)
                    .frame(width: i == index ? 24 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: index)
    }
}

#Preview("PageDots") {
    VStack(spacing: 20) {
        PageDots(count: 3, index: 0)
        PageDots(count: 3, index: 1)
        PageDots(count: 6, index: 4)
    }
    .padding()
    .background(Theme.Colors.background)
}
