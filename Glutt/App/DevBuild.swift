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

    static var relaxGates: Bool {
        #if DEBUG
        return !ProcessInfo.processInfo.arguments.contains(realGatesArgument)
        #else
        return false
        #endif
    }
}
