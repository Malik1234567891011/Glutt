import SwiftUI

/// Screen 8 — the one thing Glutt does that a recipe app does not: it watches
/// you cook and says how you are doing.
///
/// # Why the ladder rather than the map
///
/// The Skills tab has two faces. The map is the prettier one, but it is a map
/// of *content*, and a stranger who has never opened Glutt reads a row of
/// locked nodes as "there is a lot here", which is what every course app says.
/// The ladder says the thing only Glutt can say: a rating that moves on
/// cooking it has actually verified, and never on what you tell it. That is
/// also the claim the rest of onboarding is missing, since every other screen
/// asserts that Glutt is good rather than showing how it works.
///
/// # Why it is vertical
///
/// The first draft laid the nine ranks out left to right with one big toque
/// above them, and it was wrong in three ways that only showed up on a device.
/// The real Ranks sheet is a vertical list, so onboarding was teaching an axis
/// the app never uses again. A horizontal row of nine pips with the first one
/// filled reads as a progress bar, which the screen already has one of at the
/// top. And the row could only show one rank's name at a time, so it took nine
/// taps to learn what the real sheet says in a glance, inside a card that was
/// two thirds empty. Vertical fixes all three: it is the shape the app uses, it
/// makes "climb" literal, and every rank carries its own name and points.
///
/// # Nothing here touches real progress
///
/// This is a picture of the ladder, not a position on it. It writes nothing,
/// marks nothing learned and seeds no rating. It also deliberately does not
/// point at a rung and call it yours: a cook is Unranked until three verified
/// checks place them, and where they land then depends on how the cooking went,
/// so promising a starting rank here would be a lie the first real check
/// exposes.
struct SkillsScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    /// Top of the card down to the bottom, the way the Ranks sheet reads.
    private var ladder: [CookRank] { CookRank.ladder.reversed() }

    /// Read from the catalog rather than typed in, so the sentence cannot go
    /// stale the next time a region is written.
    ///
    /// Counts only what is **authored**. The map deliberately shows regions
    /// that are drawn but not written yet, because seeing how far the world
    /// goes is part of the point, and counting those here would be promising
    /// lessons that do not exist.
    private var scale: String {
        let authored = SkillCatalog.allSkills.filter(\.isAuthored)
        let regions = SkillCatalog.categories.filter(\.isAuthored)
        guard regions.count > 1 else { return "\(authored.count) skills feed your rating" }
        return "\(authored.count) skills across \(regions.count) regions feed your rating"
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("Earn your rank in the kitchen", size: 27, maxWidth: 300)
            // Lifted from the Ranks sheet itself ("they move on verified
                // cooking only"), so onboarding and the app say it the
                // same way. Short enough to hold one line.
                OnboardingSubhead("Ranks move on verified cooking only")
                .padding(.top, 8)

            card.padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .onAppear {
            guard !reduceMotion else { revealed = true; return }
            withAnimation(.easeOut(duration: 0.4)) { revealed = true }
        }
    }

    // MARK: - The card
    //
    // Same shell as the two video screens either side of it (cream ground,
    // 28pt radius, hairline warm border), so this lands as another page of the
    // same flow rather than a slide someone bolted on.

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(Array(ladder.enumerated()), id: \.offset) { index, rank in
                row(rank, index: index)
            }

            Divider()
                .background(OnboardingTheme.warmBlack(0.06))
                .padding(.horizontal, 18)
                .padding(.top, 6)

            // Inside the card, not floating above the Continue button, where a
            // muted line reads as button fine print. It also earns its place
            // here by joining the two halves of the tab: lessons are what move
            // the rating the ladder above is measuring.
            Text(scale)
                .font(OnboardingFonts.nunito(12.5, 700))
                .foregroundStyle(OnboardingTheme.mutedDeep)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .opacity(revealed ? 1 : 0)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingTheme.videoFrame)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28)
            .strokeBorder(OnboardingTheme.warmBlack(0.05), lineWidth: 1))
    }

    /// One rung: the toque at the height its rank earns, the brigade title, and
    /// the rating that reaches it. Same three pieces as the Ranks sheet, laid
    /// out to the same reading order.
    private func row(_ rank: CookRank, index: Int) -> some View {
        HStack(spacing: 13) {
            CookRankBadge(rank: rank, size: 30)
            Text(rank.title)
                .font(OnboardingFonts.nunito(14.5, 700))
                .foregroundStyle(OnboardingTheme.textHeading)
            Spacer(minLength: 8)
            Text(span(rank))
                .font(OnboardingFonts.nunito(12.5, 600))
                .foregroundStyle(OnboardingTheme.mutedDeep)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .opacity(revealed ? 1 : 0)
        // Bottom rung first, so the ladder builds upward and the motion says
        // the same thing the hats do.
        .animation(
            reduceMotion ? nil
                : .easeOut(duration: 0.3).delay(Double(ladder.count - 1 - index) * 0.04),
            value: revealed)
        .accessibilityElement(children: .combine)
    }

    /// Same wording the Ranks sheet uses, so the two never disagree.
    private func span(_ rank: CookRank) -> String {
        guard let ceiling = rank.ceiling else { return "\(formatted(rank.floor)) and up" }
        return "\(formatted(rank.floor)) to \(formatted(ceiling - 1))"
    }

    private func formatted(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}
