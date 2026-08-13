import Foundation

/// What a Debug build does differently, in one place.
///
/// A Debug build installed on a phone is a tool for testing whatever you are
/// actually working on. Making it walk onboarding, then bounce off the paywall,
/// then field an Apple Account dialog from Superwall's product fetch, means the
/// thing you wanted to test is unreachable — which is exactly what happened the
/// first time the bundle id changed and the install came up fresh.
///
/// This does not invent new behaviour. It turns on the same bypasses
/// `-uiPreview` and `-unlockPremium` already provide, so nothing here is a code
/// path that only ever runs in Debug.
///
/// Release builds are untouched: the whole thing compiles to `false`.
enum DevBuild {
    /// Pass `-realGates` to get onboarding, the paywall and Superwall back in a
    /// Debug build, for the times those are the thing under test.
    static let realGatesArgument = "-realGates"
    /// Cancels the above, back to the relaxed default.
    static let relaxGatesArgument = "-relaxGates"

    /// Where the choice is remembered between launches.
    ///
    /// Launch arguments only apply to a launch someone *triggers*, so on a phone
    /// they are gone the moment the app is opened from its icon. Testing the
    /// paywall on a device therefore lasted exactly one launch: after that,
    /// Superwall was no longer configured and every crown was a dead tap that
    /// looked like a broken gate. Latching it makes the phone hold the setting.
    private static let realGatesKey = "dev.realGates"

    /// Environment equivalents of the two arguments above, for physical devices.
    ///
    /// `devicectl` splits a launch argument into single-letter flags — it reads
    /// `-realGates` as `-r -e -a -l …` and then fails demanding a value for
    /// `-l` — so **any** flag containing an "l" is unusable on a phone.
    /// `-freeTier` happens to survive; `-realGates` cannot. Environment
    /// variables are passed through untouched, so they are the only reliable way
    /// to set this on device.
    static let realGatesEnvironmentKey = "GLUTT_REAL_GATES"
    static let relaxGatesEnvironmentKey = "GLUTT_RELAX_GATES"

    private static func isSet(_ argument: String, _ environmentKey: String) -> Bool {
        if ProcessInfo.processInfo.arguments.contains(argument) { return true }
        return ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    /// Reads the launch arguments and latches the choice. Call once at startup,
    /// before anything reads `relaxGates` — including `Superwall.configure`.
    static func applyLaunchOverrides(store: UserDefaults = .standard) {
        #if DEBUG
        if isSet(realGatesArgument, realGatesEnvironmentKey) {
            store.set(true, forKey: realGatesKey)
        } else if isSet(relaxGatesArgument, relaxGatesEnvironmentKey) {
            store.set(false, forKey: realGatesKey)
        }
        #endif
    }

    static var relaxGates: Bool {
        #if DEBUG
        if isSet(realGatesArgument, realGatesEnvironmentKey) { return false }
        if isSet(relaxGatesArgument, relaxGatesEnvironmentKey) { return true }
        return !UserDefaults.standard.bool(forKey: realGatesKey)
        #else
        return false
        #endif
    }
}
