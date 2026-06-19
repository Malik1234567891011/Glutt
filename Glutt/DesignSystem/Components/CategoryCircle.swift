import SwiftUI
import PhosphorSwift

/// A circular category thumbnail (recipe photo) + label for the Browse category row.
/// Active: 66pt with a herb-green ring and a sparkle accent. Inactive: 50pt, dimmed.
struct CategoryCircle: View {
    let image: Image
    let label: String
    var isActive: Bool = false
    var action: () -> Void = {}

    private var diameter: CGFloat { isActive ? 66 : 50 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                        .overlay(
                            Circle().strokeBorder(Theme.Colors.accent, lineWidth: isActive ? 3 : 0)
                        )
                        .opacity(isActive ? 1 : 0.78)

                    if isActive {
                        Ph.sparkle.fill
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundColor(Theme.Colors.warning)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(label)
                    .font(.system(size: isActive ? 14 : 13,
                                  weight: isActive ? .heavy : .bold,
                                  design: .rounded))
                    .foregroundColor(isActive ? Theme.Colors.textPrimary : Theme.Colors.mutedLabel)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }
}

#Preview("CategoryCircle") {
    HStack(spacing: 16) {
        CategoryCircle(image: Image(systemName: "photo"), label: "Breakfast")
        CategoryCircle(image: Image(systemName: "photo"), label: "Lunch", isActive: true)
        CategoryCircle(image: Image(systemName: "photo"), label: "Dinner")
    }
    .padding()
    .background(Theme.Colors.background)
}
