import SwiftUI

struct DiscoverCardView: View {
    let video: DiscoverVideo
    let isSaving: Bool
    let isSaved: Bool
    let onSave: () -> Void
    let onNext: () -> Void

    /// Ceiling on the player, so Save and Show me next stay on screen.
    ///
    /// These clips are vertical, and a 9:16 player told only to fit the width is
    /// taller than the phone — 430pt wide becomes 764pt tall — which pushed both
    /// buttons below the fold. Capping the height makes the player narrow instead
    /// of overflowing, and the whole card fits in the viewport.
    var playerMaxHeight: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            YouTubePlayerView(videoId: video.videoId)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: playerMaxHeight)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.segment, style: .continuous))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(video.title)
                    .font(BrandFont.bricolage(20, 700))
                    .lineLimit(2)
                if let creator = video.creator {
                    Text(creator)
                        .font(BrandFont.nunito(14, 600))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            // Saving is the point of the feed; moving on is the way out of it.
            //
            // These were `.bordered` and `.borderedProminent`, which drew two
            // filled capsules of near equal weight, and the stock `.bordered`
            // tint read as a disabled button rather than a secondary one. Glutt
            // already owns the pair of styles this needs.
            HStack(spacing: Theme.Spacing.sm) {
                Button(action: onNext) {
                    Text("Show me next")
                }
                .buttonStyle(.gluttSecondary)
                .frame(maxWidth: .infinity)

                Button(action: onSave) {
                    Group {
                        if isSaving { ProgressView().tint(Theme.Colors.creamText) }
                        else { Text(isSaved ? "Saved" : "Save") }
                    }
                }
                .buttonStyle(.gluttPrimary)
                .frame(maxWidth: .infinity)
                .disabled(isSaving || isSaved)
                .opacity(isSaved ? 0.55 : 1)
            }
        }
    }
}
