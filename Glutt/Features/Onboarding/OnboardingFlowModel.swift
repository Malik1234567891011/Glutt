import Observation

/// The prototype's `Component` state machine, verbatim: `screen` 0–10 clamped,
/// `tutPhase` 0–4. Pure of SwiftUI/SwiftData so it is unit-testable.
@Observable
final class OnboardingFlowModel {
    private(set) var screen = 0
    private(set) var tutPhase = 0

    private static let chromeScreens: Set<Int> = [1, 2, 3, 4, 5, 7, 8, 9]

    var progress: Double { Double(screen) / 10 }
    var showsChrome: Bool { Self.chromeScreens.contains(screen) }

    func go(_ n: Int) {
        let clamped = min(10, max(0, n))
        if clamped == 10 { tutPhase = 0 }
        screen = clamped
    }

    func advance() { go(screen + 1) }
    func back() { go(screen - 1) }
    func toPermission() { go(9) }
    func skipToTutorial() { go(10) }

    /// Tap anywhere on the mini-phone. Returns true exactly when the tap
    /// enters phase 3 (importing) — the caller starts the 1800ms timer.
    func tutorialTap() -> Bool {
        guard screen == 10, tutPhase < 3 else { return false }
        tutPhase += 1
        return tutPhase == 3
    }

    /// 1800ms after entering phase 3 (or timer re-arm on foreground).
    func completeImport() {
        guard tutPhase == 3 else { return }
        tutPhase = 4
    }
}
