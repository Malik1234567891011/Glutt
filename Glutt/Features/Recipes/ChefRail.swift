import SwiftUI

/// Circular chef portrait. Falls back to initials on a tinted circle until
/// licensed headshots land (`Chef.portraitAsset`).
struct ChefPortrait: View {
    let chef: Chef
    var size: CGFloat = 64
    var shadowOpacity: Double = 0.1

    var body: some View {
        Group {
            if let asset = chef.portraitAsset, UIImage(named: asset) != nil {
                Image(asset).resizable().scaledToFill()
            } else {
                Theme.Colors.surface3.overlay(
                    Text(chef.initials)
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

/// "Cook with the pros": the horizontal rail of chef portraits on the Recipes
/// home. Each item pushes `ChefDetailView` on the feed's own navigation stack.
struct ChefRail: View {
    var chefs: [Chef] = ChefContent.chefs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Cook with the pros")
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(chefs) { chef in
                        NavigationLink(value: chef) { item(chef) }
                            .buttonStyle(.plain)
                            .hapticTap()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 2)
            }
        }
    }

    private func item(_ chef: Chef) -> some View {
        VStack(spacing: 7) {
            ChefPortrait(chef: chef)
            Text(chef.name)
                .font(BrandFont.nunito(12, 800))
                .foregroundStyle(Theme.Colors.heading)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 74)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chef.name), \(chef.credit)")
    }
}

#Preview("Chef rail") {
    NavigationStack {
        ChefRail()
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.Colors.background)
    }
}
