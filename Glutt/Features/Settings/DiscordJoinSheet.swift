import SwiftUI

/// The launch invitation to the Discord server.
///
/// Deliberately small: it slides up over the app somebody just opened, so it
/// has to say what the server is for and get out of the way in one glance. The
/// height is fitted rather than a fixed detent, which keeps it under half the
/// screen at every Dynamic Type size a phone can reach.
///
/// The secondary button changes its mind from the third showing on. Until then
/// it is "Not now" and the sheet returns in a week; after that it offers to
/// stop asking, because a third decline is an answer. See `DiscordInvite`.
struct DiscordJoinSheet: View {
    /// Whether this showing offers to stop asking rather than "Not now".
    let isFinalOffer: Bool
    var onJoin: () -> Void
    var onDecline: (DiscordInvite.Decline) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.greenTint)
                Ph.discordLogo.fill
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Theme.Colors.accent)
            }
            .frame(width: 68, height: 68)
            .padding(.top, 28)

            Text("Come cook with us")
                .font(BrandFont.bricolage(22, 600))
                .foregroundStyle(Theme.Colors.heading)
                .padding(.top, 18)

            Text("Tell us what Glutt should build next, and get help from cooks who use it every day.")
                .font(BrandFont.nunito(15, 500))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 8)

            Button {
                Haptics.impact(.medium)
                onJoin()
            } label: {
                Text("Join the Discord")
            }
            .buttonStyle(.gluttPrimary)
            .padding(.top, 24)

            Button {
                Haptics.impact(.light)
                onDecline(isFinalOffer ? .never : .notNow)
            } label: {
                Text(isFinalOffer ? "Don't show this again" : "Not now")
                    .font(BrandFont.nunito(15, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.background)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    /// Fitted rather than `.medium`: at the default text size the content is
    /// well under half the screen, and a medium detent would leave a third of
    /// the sheet empty.
    private var sheetHeight: CGFloat { 340 }
}

#Preview("First showing") {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            DiscordJoinSheet(isFinalOffer: false, onJoin: {}, onDecline: { _ in })
        }
}

#Preview("Third showing") {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            DiscordJoinSheet(isFinalOffer: true, onJoin: {}, onDecline: { _ in })
        }
}
