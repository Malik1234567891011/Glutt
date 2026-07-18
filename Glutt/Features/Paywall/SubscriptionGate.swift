import Combine
import Foundation
import SuperwallKit

/// The single source of truth for whether Glutt is unlocked.
///
/// Glutt is a **hard paywall**: with no active subscription the app is inert.
/// The user lands on the real tabs (the app "looks real"), but any touch
/// re-presents the paywall — "land-then-bounce" (see `RootView`). Enforcement
/// lives HERE, keyed to the StoreKit entitlement Superwall reports, and is
/// re-evaluated on every cold launch — so a lapsed/expired subscription
/// re-locks the app the next time it opens.
///
/// This is the only gate. The old per-feature paywall hooks (onboarding,
/// invention, Polly) are retired: nothing behind the wall is reachable without
/// an active subscription, so the checks are redundant.
@MainActor
@Observable
final class SubscriptionGate {
    enum Access: Equatable {
        /// Entitlement not yet known (the brief cold-launch window). Show a
        /// neutral splash so we never flash the paywall at a real subscriber
        /// or the app at a freeloader.
        case resolving
        /// No active subscription — the app is inert; taps bounce to the paywall.
        case locked
        /// Active subscription (or a dev bypass) — the full app.
        case unlocked
    }

    /// The placement registered to present the wall. Wired in the "Glutt"
    /// campaign (91288) → paywall 243875. Distinct from `onboarding_complete`
    /// so the gate's re-presentations don't pollute the onboarding funnel.
    static let placement = "premium_gate"

    private(set) var status: SubscriptionStatus = .unknown
    /// If entitlement never resolves (SDK/network failure) we fail *closed* to
    /// `.locked` rather than stranding the user on the splash forever.
    private var resolveTimedOut = false

    @ObservationIgnored private var cancellable: AnyCancellable?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isPresenting = false

    /// Escape hatches for local dev / screenshots / the seeded demo scheme.
    /// Every flag here is Xcode-scheme-only — launch arguments do NOT survive a
    /// TestFlight/App Store upload, so none of them can unlock a shipped build.
    static var bypassEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        // `-uiPreview` skips `Superwall.configure` entirely; `-seed` is the
        // demo scheme. Both must land in the app so the UI is usable locally.
        if arguments.contains("-uiPreview") || arguments.contains("-seed") { return true }
        #if DEBUG
        if arguments.contains("-unlockPremium") { return true }
        #endif
        return false
    }

    var access: Access {
        Self.access(
            isActive: status.isActive,
            isUnknown: status == .unknown,
            timedOut: resolveTimedOut,
            bypass: Self.bypassEnabled
        )
    }

    /// The pure decision table behind `access`, split out so it's testable
    /// without a live `Superwall` singleton. Keys off Superwall's own
    /// `isActive` (which requires a genuinely active entitlement) rather than
    /// pattern-matching `.active`, so an `.active` status with no live
    /// entitlement still fails closed to `.locked`.
    nonisolated static func access(isActive: Bool, isUnknown: Bool, timedOut: Bool, bypass: Bool) -> Access {
        if bypass { return .unlocked }
        if isActive { return .unlocked }
        if isUnknown { return timedOut ? .locked : .resolving }
        return .locked
    }

    /// Begins observing entitlement. Idempotent; call from the host view's
    /// `.task`. Deliberately NOT done in `init` so we never touch
    /// `Superwall.shared` before `Superwall.configure()` has run.
    func start() {
        guard !isStarted, !Self.bypassEnabled else { return }
        isStarted = true

        status = Superwall.shared.subscriptionStatus
        cancellable = Superwall.shared.$subscriptionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                self?.status = newStatus
            }

        // Safety net: don't trap the user on the splash if entitlement never
        // resolves. ~4s is far longer than a warm StoreKit/Superwall check;
        // a returning subscriber resolves from Superwall's on-disk cache well
        // before this fires.
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.status == .unknown else { return }
            self.resolveTimedOut = true
        }
    }

    /// Re-presents the paywall (campaign → paywall 243875). Guarded so a flurry
    /// of taps can't stack presentations.
    ///
    /// The app only ever unlocks when `subscriptionStatus` flips to `.active` —
    /// never as a side effect of this call. So even if the placement is
    /// unwired (no paywall shown), the app stays locked: it fails closed.
    func presentPaywall() {
        guard !Self.bypassEnabled, !isPresenting else { return }
        isPresenting = true

        let handler = PaywallPresentationHandler()
        handler.onDismiss { [weak self] _, _ in self?.isPresenting = false }
        handler.onError { [weak self] _ in self?.isPresenting = false }
        handler.onSkip { [weak self] _ in self?.isPresenting = false }
        Superwall.shared.register(placement: Self.placement, handler: handler) { [weak self] in
            // Runs when the user is entitled (already subscribed or just
            // purchased). Unlocking itself is driven by `subscriptionStatus`.
            self?.isPresenting = false
        }
    }
}
