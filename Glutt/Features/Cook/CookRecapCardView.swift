import SwiftUI

/// Shareable "cook run" card — photo, soft score, time, Polly Saves, badge.
struct CookRecapCardView: View {
    let recap: CookRecap
    let plateImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let plateImage {
                        Image(uiImage: plateImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Theme.Colors.peachPanel
                        MS.restaurant.sized(48)
                            .foregroundStyle(Theme.Colors.accent.opacity(0.35))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()

                LinearGradient(
                    colors: [.clear, Theme.Colors.heading.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 110)
                .frame(maxHeight: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: 4) {
                    Text(recap.runTitle)
                        .font(BrandFont.bricolage(22, 600))
                        .foregroundStyle(Theme.Colors.creamText)
                        .lineLimit(2)
                    if let badge = recap.badge {
                        Text(badge.uppercased())
                            .font(BrandFont.nunito(11, 800))
                            .tracking(1.2)
                            .foregroundStyle(Theme.Colors.brightAccent)
                    }
                }
                .padding(16)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.1f", recap.overallScore))
                        .font(BrandFont.bricolage(40, 600))
                        .foregroundStyle(Theme.Colors.accent)
                    Text("overall")
                        .font(BrandFont.nunito(13, 700))
                        .foregroundStyle(Theme.Colors.muted)
                        .textCase(.uppercase)
                        .tracking(1)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(recap.timeLabel)
                            .font(BrandFont.nunito(18, 800))
                            .foregroundStyle(Theme.Colors.heading)
                        Text("cook time")
                            .font(BrandFont.nunito(11, 700))
                            .foregroundStyle(Theme.Colors.muted)
                            .textCase(.uppercase)
                    }
                }

                Text(recap.headline)
                    .font(BrandFont.nunito(14, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)

                HStack(spacing: 10) {
                    if let visual = recap.visualScore {
                        scoreChip("Visual", visual)
                    }
                    if let timing = recap.timingScore {
                        scoreChip("Timing", timing)
                    }
                    if let tech = recap.techniqueScore {
                        scoreChip("Technique", tech)
                    }
                }

                HStack(spacing: 8) {
                    Text("Polly Saves")
                        .font(BrandFont.nunito(12, 800))
                        .foregroundStyle(Theme.Colors.accent)
                        .textCase(.uppercase)
                        .tracking(1)
                    Text("\(recap.saves.count)")
                        .font(BrandFont.nunito(16, 800))
                        .foregroundStyle(Theme.Colors.heading)
                    Spacer()
                }

                if let improvement = recap.improvement {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next upgrade")
                            .font(BrandFont.nunito(11, 800))
                            .foregroundStyle(Theme.Colors.muted)
                            .textCase(.uppercase)
                            .tracking(1)
                        Text(improvement)
                            .font(BrandFont.nunito(14, 600))
                            .foregroundStyle(Theme.Colors.heading)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Text("Beat this run on Glutt")
                    .font(BrandFont.nunito(12, 700))
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(16)
            .background(Theme.Colors.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
        .shadow(color: Theme.Colors.textPrimary.opacity(0.08), radius: 18, y: 8)
    }

    private func scoreChip(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f", value))
                .font(BrandFont.nunito(15, 800))
                .foregroundStyle(Theme.Colors.heading)
            Text(label)
                .font(BrandFont.nunito(10, 700))
                .foregroundStyle(Theme.Colors.muted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.Colors.greenTint)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum CookRecapShareService {
    @MainActor
    static func renderCard(recap: CookRecap, plateImage: UIImage?, width: CGFloat = 390) -> UIImage? {
        let card = CookRecapCardView(recap: recap, plateImage: plateImage)
            .frame(width: width)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// UIKit share sheet for a rendered recap image (+ optional caption).
struct CookRecapActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onComplete?() }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
