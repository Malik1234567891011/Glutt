import SwiftUI

struct DiscoverCardView: View {
    let video: DiscoverVideo
    let isSaving: Bool
    let isSaved: Bool
    let onSave: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            YouTubePlayerView(videoId: video.videoId)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
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

            HStack(spacing: Theme.Spacing.sm) {
                Button(action: onNext) {
                    Text("Show me next")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onSave) {
                    Group {
                        if isSaving { ProgressView() }
                        else { Text(isSaved ? "Saved ✓" : "Save") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || isSaved)
            }
            .tint(Theme.Colors.accent)
        }
    }
}
