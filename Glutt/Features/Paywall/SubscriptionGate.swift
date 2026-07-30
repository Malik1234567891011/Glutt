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

    /// The placement registered to present the wall. Reuses `onboarding_complete`,
    /// which is ALREADY wired in the "Glutt" campaign (91288) → paywall 243875,
    /// so the gate presents without any campaign change (and App Review never
    /// hits a locked app with no paywall). A dedicated `premium_gate` placement
    /// would give cleaner funnel analytics — deferred as a future cleanup.
    static let placement = "onboarding_complete"

    private(set) var status: SubscriptionStatus = .unknown
    /// If entitlement never resolves (SDK/network failure) we fail *closed* to
    /// `.locked` rather than stranding the user on the splash forever.
    private var resolveTimedOut = false

    @ObservationIgnored private var cancellable: AnyCancellable?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isPresenting = false
    /// `gate_resolved` is one event per launch, not one per status change —
    /// Superwall republishes the status more than once as it settles.
    @ObservationIgnored private var didReportAccess = false
    /// The automatic presentation happens once per launch. Without this it
    /// re-fires every time the host view reappears — which includes the moment
    /// the paywall itself is dismissed, so closing it reopened it instantly and
    /// the user could never get out.
    @ObservationIgnored private var didAutoPresent = false

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
        reportAccessIfSettled()
        cancellable = Superwall.shared.$subscriptionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                self?.status = newStatus
                self?.reportAccessIfSettled()
            }

        // Safety net: don't trap the user on the splash if entitlement never
        // resolves. ~4s is far longer than a warm StoreKit/Superwall check;
        // a returning subscriber resolves from Superwall's on-disk cache well
        // before this fires.
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.status == .unknown else { return }
            self.resolveTimedOut = true
            self.reportAccessIfSettled()
        }
    }

    /// The lock rate — what share of launches land on the paywall rather than
    /// the app. Fires once, as soon as entitlement stops being `.resolving`
    /// (including via the fail-closed timeout above). Bypassed dev builds never
    /// reach here: `start()` returns early for them.
    private func reportAccessIfSettled() {
        let settled = access
        guard !didReportAccess, settled != .resolving else { return }
        didReportAccess = true
        // Payer status as a super property, before the event that reports it —
        // otherwise `gate_resolved` is the one event of the launch that cannot
        // be split by the thing it measures. Every product event after this
        // carries it, so "do subscribers cook more" is a breakdown rather than
        // a cohort join on every insight.
        Analytics.setEntitled(settled == .unlocked)
        Analytics.capture(.gateResolved, [
            "access": settled == .unlocked ? "unlocked" : "locked",
            "timed_out": resolveTimedOut,
        ])
    }

    /// Asks StoreKit to restore a subscription bought on another device or a
    /// previous install, and reports whether that left them entitled.
    ///
    /// This is what "Already have an account? Log in" actually needs: the
    /// subscription lives on the Apple ID, so restoring it is the real work.
    /// The account is looked up afterwards, and only if this succeeds.
    ///
    /// In Superwall's automatic mode the SDK raises its own alert when there is
    /// nothing to restore, so callers should not add a second one.
    /// Reading `subscriptionStatus` the instant the restore call returns is a
    /// race, and it lost: a real subscriber got "nothing to restore", then had
    /// the login screen open normally after a relaunch. `subscriptionStatus` is
    /// published asynchronously as StoreKit transactions are processed, so it
    /// is routinely still `.unknown` or stale at the moment `restorePurchases()`
    /// hands back.
    ///
    /// So the SDK's own verdict is read first — it was previously discarded
    /// with `_ =` — and the status is then given a moment to catch up before
    /// anyone is told they have not paid. Telling a paying customer that is the
    /// expensive mistake here; a second of waiting is the cheap one.
    func restorePurchases() async -> Bool {
        guard !Self.bypassEnabled else { return true }

        let result = await Superwall.shared.restorePurchases()
        if Superwall.shared.subscriptionStatus.isActive { return true }

        // Nothing to restore is an answer, not a race: don't stall on it.
        guard case .restored = result else { return false }

        // Poll rather than await the publisher: `status` is already driven by
        // that subscription in `start()`, and a second sink here would need
        // unwinding on every exit path.
        for _ in 0 ..< 20 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Superwall.shared.subscriptionStatus.isActive { return true }
        }
        return false
    }

    /// Presents the paywall on its own, the first time a locked user lands past
    /// onboarding. Pressing Continue at the end of the tutorial should open the
    /// paywall, not the app.
    ///
    /// Once per launch, deliberately: re-presenting on every dismissal would be
    /// a modal with no way out, which App Review reads as a trap. Closing it
    /// leaves them on the blurred cover, and a tap there reopens it.
    func presentPaywallOnce() {
        guard !didAutoPresent else { return }
        didAutoPresent = true
        presentPaywall()
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
        // One event per presentation *attempt*, not per bounce tap — the
        // `isPresenting` guard above already swallows a flurry of taps.
        Analytics.capture(.paywallPresented)

        let handler = PaywallPresentationHandler()
        handler.onDismiss { [weak self] info, result in
            self?.isPresenting = false
            Analytics.capture(.paywallDismissed, [
                "result": Self.label(for: result),
                "paywall": info.name,
            ])
        }
        handler.onError { [weak self] error in
            self?.isPresenting = false
            Analytics.capture(.paywallError, ["message": error.localizedDescription])
        }
        handler.onSkip { [weak self] reason in
            self?.isPresenting = false
            Analytics.capture(.paywallSkipped, ["reason": reason.description])
        }
        Superwall.shared.register(placement: Self.placement, handler: handler) { [weak self] in
            // Runs when the user is entitled (already subscribed or just
            // purchased). Unlocking itself is driven by `subscriptionStatus`.
            self?.isPresenting = false
        }
    }

    /// Stable analytics labels — `String(describing:)` on the enum would carry
    /// the associated product into the property value and fragment the funnel.
    private static func label(for result: PaywallResult) -> String {
        switch result {
        case .purchased: "purchased"
        case .declined: "declined"
        case .restored: "restored"
        }
    }
}
