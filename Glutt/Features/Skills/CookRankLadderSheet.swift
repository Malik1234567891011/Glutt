import SwiftUI

/// Every rank, what it costs, and where the cook is standing.
///
/// Opened from the rank in the Cook Rating sheet, because that is the moment
/// somebody wants it: they have just read "Prep Cook I" and want to know what
/// is above it. A permanent tab or a dashboard tile would be answering a
/// question nobody asked yet.
///
/// Deliberately one column of rows on cream, in the same language as the sheet
/// behind it. The toques do the work a table of numbers would do badly: the
/// silhouette climbs, so a cook can see the distance before reading a single
/// figure.
struct CookRankLadderSheet: View {
    /// Nil while unranked, which is a real state and reads as one here.
    let rating: Int?
    @Environment(\.dismiss) private var dismiss

    private var current: CookRank? { rating.map(CookRank.rank(for:)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    intro
                    // Top of the kitchen first. A ladder drawn bottom up reads
                    // as a list of things you have already done; drawn top down
                    // it reads as where you are going, which is the question
                    // that opened this sheet.
                    ForEach(Array(CookRank.ladder.reversed()), id: \.floor) { rank in
                        row(rank)
                    }
                    provenance
                }
                .padding(.horizontal, 20)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Ranks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
    }

    @ViewBuilder private var intro: some View {
        Text("Ranks come from the kitchen brigade, and they move on verified cooking only. Lessons build your Level instead.")
            .font(BrandFont.nunito(14, 600))
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, Theme.Spacing.md)
    }

    private func row(_ rank: CookRank) -> some View {
        let isCurrent = current?.floor == rank.floor
        return HStack(alignment: .center, spacing: 14) {
            CookRankBadge(rank: rank, size: 40, heldRank: current)

            VStack(alignment: .leading, spacing: 1) {
                Text(rank.title)
                    .font(BrandFont.nunito(16.5, isCurrent ? 800 : 700))
                    .foregroundStyle(isCurrent ? Theme.Colors.accent : Theme.Colors.heading)
                Text(span(rank))
                    .font(BrandFont.nunito(13, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
            }

            Spacer(minLength: Theme.Spacing.sm)

            if isCurrent {
                // A word, not a pill. The filled toque and the accent title
                // have already said it; this is for anyone who reads rather
                // than scans, and for VoiceOver.
                Text("You")
                    .font(BrandFont.nunito(13, 800))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank.title), \(span(rank))\(isCurrent ? ", your rank" : "")")
    }

    /// The points a rank covers, with the top one left open because it is.
    private func span(_ rank: CookRank) -> String {
        guard let ceiling = rank.ceiling else { return "\(rank.floor.formatted()) and up" }
        return "\(rank.floor.formatted()) to \((ceiling - 1).formatted())"
    }

    /// Where the hats come from.
    ///
    /// Worth the four lines. It is the difference between nine invented badges
    /// and a system a cook can go and read about, and it explains why the hat
    /// grows rather than just changing colour.
    @ViewBuilder private var provenance: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Why the hats")
                .font(BrandFont.nunito(12, 800)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Escoffier set the height of the toque by station, so anyone walking into a kitchen could read the hierarchy off the room. Carême wore one eighteen inches tall. Yours grows the same way, on cooking Glutt has actually watched.")
                .font(BrandFont.nunito(13.5, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Spacing.lg)
    }
}
