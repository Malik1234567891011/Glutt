import SwiftUI

/// The celebratory end of the daily deck: "that's today's plate", with a streak
/// and a come-back-tomorrow hook.
struct DeckEndCardView: View {
    let explored: Int
    let saved: Int
    var onDone: () -> Void

    @State private var streak = PlatesStreak.current

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Ph.forkKnife.fill.resizable().scaledToFit().frame(width: 56, height: 56)
                .foregroundStyle(.white)
            Text("That's today's plate")
                .font(.gluttLargeTitle).foregroundStyle(.white)
            Text("You explored \(explored) and saved \(saved).")
                .font(.gluttBody).foregroundStyle(.white.opacity(0.85))
            if streak > 1 {
                Text("🔥 \(streak)-day streak")
                    .font(.gluttHeadline).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial).clipShape(Capsule())
            }
            Text("Come back tomorrow for a fresh plate.")
                .font(.gluttCaption).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button { onDone() } label: { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(.gluttPrimary)
                .padding(.horizontal, Theme.Spacing.lg)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.textPrimary)
        .onAppear { streak = PlatesStreak.current }
    }
}
