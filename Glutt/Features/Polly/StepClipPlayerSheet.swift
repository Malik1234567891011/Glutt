import SwiftUI

/// On-demand YouTube demonstration window for the current Polly step.
/// Muted by default so Polly's voice stays primary; user can unmute in-player.
struct StepClipPlayerSheet: View {
    let clip: StepClip
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                YouTubePlayerView(
                    videoId: clip.youtubeVideoID,
                    startSeconds: clip.startSeconds,
                    endSeconds: clip.endSeconds,
                    mute: true
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .background(Color.black)

                Text(clip.watchLabel)
                    .font(BrandFont.bricolage(20, 600))
                    .foregroundStyle(Theme.Colors.heading)

                if !clip.notice.isEmpty {
                    Text(clip.notice)
                        .font(BrandFont.nunito(14, 600))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Playing on YouTube · \(clip.durationSeconds)s demo")
                    .font(BrandFont.nunito(12, 700))
                    .foregroundStyle(Theme.Colors.muted)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Theme.Colors.background)
            .navigationTitle("Technique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClose() }
                        .font(BrandFont.nunito(15, 800))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Compact CTA used on Polly step cards / guide panels.
struct StepClipWatchButton: View {
    let clip: StepClip
    let action: () -> Void
    var dark: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(clip.watchLabel.isEmpty
                      ? "Watch technique · \(clip.durationSeconds)s"
                      : clip.watchLabel)
                    .font(BrandFont.nunito(13, 800))
                    .lineLimit(1)
            }
            .foregroundStyle(dark ? Theme.Colors.creamText : Theme.Colors.creamText)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(dark ? Theme.Colors.brightAccent.opacity(0.9) : Theme.Colors.amber)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Watch \(clip.durationSeconds) second technique clip")
    }
}
