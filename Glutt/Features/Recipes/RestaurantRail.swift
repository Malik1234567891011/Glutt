import SwiftUI

/// Circular restaurant logo, the visual twin of `ChefPortrait`. Falls back to
/// initials on a tinted circle when there's no logo asset.
struct RestaurantLogo: View {
    let restaurant: Restaurant
    var size: CGFloat = 64
    var shadowOpacity: Double = 0.1

    var body: some View {
        Group {
            if let asset = restaurant.logoAsset, UIImage(named: asset) != nil {
                // Fill, not fit: these logos are square with the mark inset from
                // the edges, so the circle crops only background and a fitted
                // version would float small inside a ring of dead space.
                Image(asset).resizable().scaledToFill()
            } else {
                Theme.Colors.surface3.overlay(
                    Text(restaurant.initials)
                        .font(BrandFont.bricolage(size * 0.3125, 700))
                        .foregroundStyle(Theme.Colors.muted)
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.Colors.card, lineWidth: 2.5))
        .shadow(color: Theme.Colors.textPrimary.opacity(shadowOpacity), radius: 13, y: 5)
    }
}

/// "Cook like the restaurants": the horizontal rail of restaurant logos, sitting
/// directly above the chef rail on the Recipes home. Each item pushes
/// `RestaurantDetailView` on the feed's own navigation stack.
struct RestaurantRail: View {
    var restaurants: [Restaurant] = RestaurantContent.restaurants

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Cook like the restaurants")
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(restaurants) { restaurant in
                        NavigationLink(value: restaurant) { item(restaurant) }
                            .buttonStyle(.plain)
                            .hapticTap()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 2)
            }
        }
    }

    private func item(_ restaurant: Restaurant) -> some View {
        VStack(spacing: 7) {
            RestaurantLogo(restaurant: restaurant)
            Text(restaurant.name)
                .font(BrandFont.nunito(12, 800))
                .foregroundStyle(Theme.Colors.heading)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 74)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(restaurant.name), \(restaurant.credit)")
    }
}

#Preview("Restaurant rail") {
    NavigationStack {
        RestaurantRail()
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.Colors.background)
    }
}
