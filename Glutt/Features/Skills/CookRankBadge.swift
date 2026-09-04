import SwiftUI

/// The toque, drawn at the height its rank earns.
///
/// # Why a hat and not a badge
///
/// Escoffier, whose brigade this ladder is named from, set the height of the
/// toque by station, so anyone walking into the kitchen could read the
/// hierarchy off the room. Carême wore one eighteen inches tall, propped up
/// with cardboard. The pleats carried meaning too: the traditional hundred
/// stood for a hundred ways to cook an egg, a count of technique rather than
/// of seniority.
///
/// So the rank insignia is not invented. It is the thing kitchens already used
/// to say exactly what this ladder says, and it means the badge for Head Chef
/// is different from the badge for Prep Cook III in the way a real toque is:
/// taller, with more pleats. A row of medals or stars would have been a
/// decision about styling. This is a decision about the subject.
///
/// # Read the ladder, not the badge
///
/// Every toque is drawn bottom aligned inside a fixed frame, so a column of
/// them in the ladder sheet climbs. That is the whole reason to draw them
/// rather than pick nine icons: the shape carries the progression, and a cook
/// can see where they are without reading a number.
struct CookRankBadge: View {
    let rank: CookRank
    var size: CGFloat = 34
    /// The rank the cook actually holds, so this badge knows whether it is
    /// behind them, under them, or still ahead.
    var heldRank: CookRank?

    /// Convenience for the single-badge cases, where there is no ladder to
    /// place this against and the badge simply IS the cook's rank.
    var isCurrent: Bool = false

    private enum Standing { case climbed, current, ahead }

    /// Where this rank sits relative to the cook.
    ///
    /// The ladder used to draw eight identical outlined hats and one filled
    /// one, which threw away the most interesting thing on the screen: how far
    /// up somebody has come. A column that fills in behind you tells that
    /// story without a word, the same way the map's trail colours itself in.
    private var standing: Standing {
        if isCurrent { return .current }
        guard let heldRank else { return .ahead }
        if rank.floor == heldRank.floor { return .current }
        return rank.floor < heldRank.floor ? .climbed : .ahead
    }

    private var index: Int {
        CookRank.ladder.firstIndex(where: { $0.floor == rank.floor }) ?? 0
    }

    /// How tall this toque stands, as a fraction of the frame.
    ///
    /// The bottom of the range is deliberately not tiny. A Prep Cook III toque
    /// that read as a stub would make the first rank look like a failure state,
    /// and the first rank is an achievement: it means Glutt has actually
    /// watched you cook three times.
    private var heightRatio: CGFloat {
        let steps = max(1, CookRank.ladder.count - 1)
        // 0.50 rather than 0.58, because at the narrower range two adjacent
        // ranks differed by about two points and read as one hat drawn twice.
        return 0.50 + (0.50 * CGFloat(index) / CGFloat(steps))
    }

    /// Exposed so a test can prove the ladder actually climbs.
    func badgeHeight(in size: CGFloat) -> CGFloat { size * heightRatio }

    /// The chef hat the app already uses, at the height the rank earns.
    ///
    /// # Why not a drawn toque
    ///
    /// This started as a hand drawn `ToqueShape` whose pleat count also grew
    /// with rank, because the traditional hundred pleats counted technique.
    /// Three drafts in it still did not read as a hat at 38 points: straight
    /// sides drew a tumbler, quadratic bumps drew a rectangle with teeth, and
    /// overlapping lobes drew a rounded square. At this size a filled
    /// silhouette has almost no room to say "hat", and the pleats were asking
    /// for detail the size cannot carry.
    ///
    /// The app already owns a chef hat that reads instantly: the Phosphor
    /// glyph in the Skills tab. Using it keeps the badge consistent with the
    /// tab the ladder lives under, and keeps the half of the idea that
    /// actually survives at this scale, which is the important half:
    /// **Escoffier set toque height by station**, so the hat grows with rank
    /// and a column of them climbs.
    ///
    /// Three states, not two. Solid green for where you are, a quieter green
    /// for every rank you came through, and an outline for what is still
    /// ahead. The column then reads as a climb rather than a list.
    private var fill: Color {
        switch standing {
        case .current: Theme.Colors.accent
        case .climbed: Theme.Colors.accent.opacity(0.34)
        case .ahead: Theme.Colors.muted.opacity(0.5)
        }
    }

    var body: some View {
        (standing == .ahead ? Ph.chefHat.regular : Ph.chefHat.fill)
            .resizable()
            .scaledToFit()
            .foregroundStyle(fill)
            .frame(width: size * heightRatio, height: size * heightRatio)
            // Bottom aligned so a column of these climbs. Centre alignment
            // would throw away the one thing the size is carrying.
            .frame(width: size, height: size, alignment: .bottom)
            .accessibilityHidden(true)
    }
}
