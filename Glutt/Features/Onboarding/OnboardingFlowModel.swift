import Observation

/// The onboarding state machine: `screen` 0–9 clamped, `tutPhase` 0–4. (The
/// design's separate OS-permission page was folded into the soft-ask, so the
/// import tutorial is now screen 9.) Pure of SwiftUI/SwiftData so it is testable.
@Observable
final class OnboardingFlowModel {
    private(set) var screen = 0
    private(set) var tutPhase = 0

    private static let chromeScreens: Set<Int> = [1, 2, 3, 4, 5, 7, 8]

    var progress: Double { Double(screen) / 9 }
    var showsChrome: Bool { Self.chromeScreens.contains(screen) }

    func go(_ n: Int) {
        let clamped = min(9, max(0, n))
        if clamped == 9 { tutPhase = 0 }
        screen = clamped
    }

    func advance() { go(screen + 1) }
    func back() { go(screen - 1) }
    func skipToTutorial() { go(9) }

    /// Tap anywhere on the mini-phone. Returns true exactly when the tap
    /// enters phase 3 (importing) — the caller starts the 1800ms timer.
    func tutorialTap() -> Bool {
        guard screen == 9, tutPhase < 3 else { return false }
        tutPhase += 1
        return tutPhase == 3
    }

    /// 1800ms after entering phase 3 (or timer re-arm on foreground).
    func completeImport() {
        guard tutPhase == 3 else { return }
        tutPhase = 4
    }
}
