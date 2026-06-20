import SwiftUI

/// A circular category thumbnail + label for the Browse category row.
/// Active: 66pt with a herb-green ring and a sparkle accent. Inactive: 50pt, dimmed.
/// The thumbnail is injected so callers can pass a static `Image` or a live
/// `RecipeImageView` (asset/photo/remote).
struct CategoryCircle<Thumb: View>: View {
    let label: String
    var isActive: Bool = false
    var action: () -> Void = {}
    @ViewBuilder var thumb: () -> Thumb

    private var diameter: CGFloat { isActive ? 66 : 50 }

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    thumb()
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.Colors.accent, lineWidth: isActive ? 3 : 0))
                        .opacity(isActive ? 1 : 0.78)
                    Ph.sparkle.fill
                        .resizable().scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundColor(Theme.Colors.warning)
                        .offset(x: 4, y: -4)
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .frame(width: 66, height: 66)            // reserve max slot → no sibling reflow on activate
                Text(label)
                    .font(.system(size: isActive ? 14 : 13, weight: isActive ? .heavy : .bold, design: .rounded))
                    .foregroundColor(isActive ? Theme.Colors.textPrimary : Theme.Colors.mutedLabel)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
    }
}

/// Convenience for a static image thumbnail.
extension CategoryCircle where Thumb == _CategoryImageThumb {
    init(image: Image, label: String, isActive: Bool = false, action: @escaping () -> Void = {}) {
        self.init(label: label, isActive: isActive, action: action) { _CategoryImageThumb(image: image) }
    }
}

struct _CategoryImageThumb: View {
    let image: Image
    var body: some View { image.resizable().scaledToFill() }
}

#Preview("CategoryCircle") {
    HStack(spacing: 16) {
        CategoryCircle(image: Image(systemName: "photo"), label: "Breakfast")
        CategoryCircle(image: Image(systemName: "photo"), label: "Lunch", isActive: true)
        CategoryCircle(image: Image(systemName: "photo"), label: "Dinner")
    }
    .padding().background(Theme.Colors.background)
}
