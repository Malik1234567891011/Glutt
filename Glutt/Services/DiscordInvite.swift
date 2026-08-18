import Foundation

/// The Discord invite, and the latch in front of the sheet that offers it.
///
/// Two surfaces share this type: the Settings row, which is always available
/// and asks nothing of the latch, and the launch sheet, which does.
///
/// The sheet repeats on a seven day cycle rather than firing once, because the
/// server is where feature requests are meant to land and one missed sheet on
/// launch three would be the only ask a user ever got. What keeps that from
/// being a nag is that it is cheap to end: tapping Join retires it for good,
/// and from the third showing the second button stops saying "Not now" and
/// starts saying "Don't show this again".
///
/// Nothing here can tell whether somebody actually joined. Discord does not
/// report back, so a tap on Join *is* the join as far as the app is concerned.
///
/// State lives in `UserDefaults` for the same reason `ReviewPrompt`'s does:
/// it is install-local bookkeeping about an ask, not a preference the user set,
/// and it must survive a forced re-run of onboarding that leaves the SwiftData
/// record untouched.
enum DiscordInvite {

    /// Where the invite goes. Opens the Discord app when it is installed and
    /// Safari when it isn't, both of which land on the join screen.
    static let url = URL(string: "https://discord.gg/cKjD2qvFaG")!

    /// Which surface an open came from. Recorded on `discord_opened`.
    enum Source: String {
        case sheet
        case settings
    }

    /// Why the sheet went away without an open.
    enum Decline: String {
        case notNow = "not_now"
        case never
    }

    private static let launchCountKey = "discordInviteLaunchCount"
    private static let lastShownKey = "discordInviteLastShownAt"
    private static let showCountKey = "discordInviteShowCount"
    private static let retiredKey = "discordInviteRetired"

    /// The first launch that may see the sheet. Launches one and two are spent
    /// on onboarding, the paywall and sign in; a community ask on top of that
    /// stack would be the fourth thing asked of somebody who has not cooked yet.
    private static let firstEligibleLaunch = 3

    /// Seven days between showings.
    private static let interval: TimeInterval = 7 * 24 * 60 * 60

    /// From this showing on, the secondary button offers to stop for good.
    private static let finalOfferShowCount = 3

    private static var defaults: UserDefaults { .standard }

    /// `-discordSheet`: forces the sheet on the next launch so it is reachable
    /// in the simulator without waiting three launches. A staged run writes
    /// nothing and reports nothing, so it can be repeated and stays out of the
    /// funnel.
    static var isStaged: Bool {
        ProcessInfo.processInfo.arguments.contains("-discordSheet")
    }

    /// True once Join, or a "Don't show this again", has ended the cycle.
    static var isRetired: Bool { defaults.bool(forKey: retiredKey) }

    /// Which showing the sheet is on, counting from 1. Read while the sheet is
    /// up, after `markShown()`.
    static var showCount: Int { defaults.integer(forKey: showCountKey) }

    /// Whether this showing should offer to stop asking rather than "Not now".
    /// A staged run has no stored count, so `-discordSheetFinal` is how that
    /// variant is reached in the simulator.
    static var isFinalOffer: Bool {
        if isStaged {
            return ProcessInfo.processInfo.arguments.contains("-discordSheetFinal")
        }
        return showCount >= finalOfferShowCount
    }

    /// Counts a cold launch. Idempotent within a process, so the view that
    /// calls it may be rebuilt without inflating the count.
    private nonisolated(unsafe) static var didCountLaunch = false

    static func noteLaunch() {
        guard !didCountLaunch else { return }
        didCountLaunch = true
        defaults.set(defaults.integer(forKey: launchCountKey) + 1, forKey: launchCountKey)
    }

    /// Whether to present the sheet on this launch. Call after `noteLaunch()`,
    /// and only once the app is actually usable — the caller owns the rest of
    /// the eligibility (onboarding done, entitled, signed in, nothing else on
    /// screen), because only it can see those.
    static func shouldShow() -> Bool {
        if isStaged { return true }

        // Automated runs: the sheet would sit on top of whatever is being
        // captured and swallow taps. Same reasoning as `ReviewPrompt`.
        let args = ProcessInfo.processInfo.arguments
        guard !args.contains("-uiPreview"), !args.contains("-seed") else { return false }

        guard !isRetired else { return false }
        guard defaults.integer(forKey: launchCountKey) >= firstEligibleLaunch else { return false }

        let lastShown = defaults.double(forKey: lastShownKey)
        guard lastShown > 0 else { return true }
        return Date().timeIntervalSince1970 - lastShown >= interval
    }

    /// Starts the seven day clock and records the impression. Call as the sheet
    /// is presented, never after it is dismissed: a process that dies with the
    /// sheet up still showed it.
    static func markShown() {
        guard !isStaged else { return }
        defaults.set(defaults.integer(forKey: showCountKey) + 1, forKey: showCountKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastShownKey)
        Analytics.capture(.discordPromptShown, ["show_count": showCount])
    }

    /// Retires the cycle. Called when the invite is opened from the sheet.
    static func markJoined() {
        guard !isStaged else { return }
        defaults.set(true, forKey: retiredKey)
    }

    /// Records a dismissal. `.never` also retires the cycle; `.notNow` leaves
    /// the clock set by `markShown()` to bring it back in a week.
    static func markDeclined(_ decline: Decline) {
        guard !isStaged else { return }
        if decline == .never { defaults.set(true, forKey: retiredKey) }
        Analytics.capture(.discordPromptDismissed, [
            "action": decline.rawValue,
            "show_count": showCount,
        ])
    }

    /// The open itself, from either surface.
    static func noteOpened(from source: Source) {
        guard !isStaged else { return }
        Analytics.capture(.discordOpened, ["source": source.rawValue])
    }

    #if DEBUG
    /// Clears the latch so the cycle can be walked again from launch one.
    static func resetForTesting() {
        for key in [launchCountKey, lastShownKey, showCountKey, retiredKey] {
            defaults.removeObject(forKey: key)
        }
        didCountLaunch = false
    }
    #endif
}
