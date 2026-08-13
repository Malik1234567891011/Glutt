import Combine
import Foundation
import SuperwallKit

/// The single source of truth for which tier the cook is on.
///
/// Glutt is **freemium**. The free tier is a real, usable recipe box: import as
/// much as you like, read any recipe you saved (ingredients, steps, macros), and
/// swipe a limited number of Discover cards a week. Everything that *does*
/// something — cooking, asking Polly, groceries, the kitchen, week planning — is
/// Pro, and is shown rather than hidden: the control stays on screen wearing a
/// crown, and tapping it opens the paywall (see `PremiumFeature`).
///
/// This replaces the old hard paywall, where no subscription meant no app at
/// all. What survives from it is the part worth keeping: entitlement is keyed to
/// the StoreKit entitlement Superwall reports, re-evaluated on every cold launch
/// (so a lapsed subscription drops to free on the next open), and it fails
/// **closed** — an entitlement we cannot resolve is free, never Pro.
@MainActor
@Observable
final class Entitlements {
    enum Tier: Equatable {
        /// Entitlement not yet known (the brief cold-launch window). The app
        /// waits on a neutral splash rather than rendering, so a paying customer
        /// never sees a screen full of crowns on their own features.
        case resolving
        /// No active subscription. The app works; the Pro features wear crowns.
        case free
        /// Active subscription (or a dev bypass). Nothing is gated.
        case pro
    }

    /// The placement registered to present the wall. Reuses `onboarding_complete`,
    /// which is ALREADY wired in the "Glutt" campaign (91288) → paywall 243875,
    /// so every gate presents a real, published paywall today. Per-feature
    /// placements are declared in `PremiumFeature` and currently route through
    /// here; see that type for how to cut them over.
    /// `nonisolated` so `PremiumFeature` — a plain enum with no actor of its
    /// own — can fall back to it while the per-feature placements are still
    /// unwired.
    nonisolated static let placement = "onboarding_complete"

    private(set) var status: SubscriptionStatus = .unknown
    /// If entitlement never resolves (SDK/network failure) we fall to `.free`
    /// rather than stranding the user on the splash forever.
    private var resolveTimedOut = false

    @ObservationIgnored private var cancellable: AnyCancellable?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isPresenting = false
    /// Clears `isPresenting` if no handler callback ever lands. See
    /// `finishPresenting`.
    @ObservationIgnored private var presentationWatchdog: Task<Void, Never>?
    /// `gate_resolved` is one event per launch, not one per status change —
    /// Superwall republishes the status more than once as it settles.
    @ObservationIgnored private var didReportTier = false
    /// The post-onboarding presentation happens once per launch. Without this it
    /// re-fires every time the host view reappears — which includes the moment
    /// the paywall itself is dismissed, so closing it reopened it instantly.
    @ObservationIgnored private var didAutoPresent = false

    /// Forces the free tier, overriding both a real subscription and the Debug
    /// unlock below. A Debug build unlocks everything by default (`DevBuild`),
    /// which would make the free tier the one configuration that cannot be
    /// tested on the machine it is being written on.
    static let freeTierArgument = "-freeTier"
    /// Cancels the above.
    static let proTierArgument = "-proTier"

    /// Where the choice is remembered between launches, in Debug builds.
    ///
    /// A launch argument only applies to a launch someone *triggers* — from
    /// Xcode, or from the build tooling. Tap the app icon on a phone and it is
    /// gone, so on-device testing of the free tier would last exactly one launch
    /// and then silently revert to a fully unlocked app, which looks like the
    /// gates having failed. Passing `-freeTier` once now latches it until
    /// `-proTier` clears it.
    private static let forcedFreeKey = "dev.forceFreeTier"

    /// Environment equivalents, for physical devices. See `DevBuild` for why:
    /// `devicectl` mangles any launch argument containing an "l".
    static let freeTierEnvironmentKey = "GLUTT_FREE_TIER"
    static let proTierEnvironmentKey = "GLUTT_PRO_TIER"

    private static func isSet(_ argument: String, _ environmentKey: String) -> Bool {
        if ProcessInfo.processInfo.arguments.contains(argument) { return true }
        return ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    /// Reads the launch arguments and latches the choice. Call once at startup,
    /// before any view reads `tier`.
    static func applyLaunchOverrides(store: UserDefaults = .standard) {
        #if DEBUG
        if isSet(freeTierArgument, freeTierEnvironmentKey) {
            store.set(true, forKey: forcedFreeKey)
        } else if isSet(proTierArgument, proTierEnvironmentKey) {
            store.set(false, forKey: forcedFreeKey)
        }
        #endif
    }

    static var forcedFree: Bool {
        // The argument alone still works in Release, on the same terms as
        // `-uiPreview` and `-seed`: launch arguments do not survive a TestFlight
        // or App Store install, so this can never affect a shipped build.
        if isSet(freeTierArgument, freeTierEnvironmentKey) { return true }
        #if DEBUG
        if isSet(proTierArgument, proTierEnvironmentKey) { return false }
        return UserDefaults.standard.bool(forKey: forcedFreeKey)
        #else
        return false
        #endif
    }

    /// Escape hatches for local dev / screenshots / the seeded demo scheme.
    /// Every flag here is Xcode-scheme-only — launch arguments do NOT survive a
    /// TestFlight/App Store upload, so none of them can unlock a shipped build.
    static var bypassEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        // `-uiPreview` skips `Superwall.configure` entirely; `-seed` is the
        // demo scheme. Both must land in the app with everything reachable.
        if arguments.contains("-uiPreview") || arguments.contains("-seed") { return true }
        #if DEBUG
        if arguments.contains("-unlockPremium") { return true }
        #endif
        // A Debug build with half its features crowned is an app you cannot use
        // to test the other half.
        if DevBuild.relaxGates { return true }
        return false
    }

    var tier: Tier {
        Self.tier(
            isActive: status.isActive,
            isUnknown: status == .unknown,
            timedOut: resolveTimedOut,
            bypass: Self.bypassEnabled,
            forcedFree: Self.forcedFree
        )
    }

    /// True only once entitlement has actually resolved to a subscription.
    /// Everything gated reads this, so `.resolving` is treated as "not yet Pro"
    /// by anyone who asks before the splash clears.
    var isPro: Bool { tier == .pro }

    /// The pure decision table behind `tier`, split out so it's testable without
    /// a live `Superwall` singleton. Keys off Superwall's own `isActive` (which
    /// requires a genuinely active entitlement) rather than pattern-matching
    /// `.active`, so an `.active` status with no live entitlement still falls to
    /// `.free`.
    nonisolated static func tier(
        isActive: Bool,
        isUnknown: Bool,
        timedOut: Bool,
        bypass: Bool,
        forcedFree: Bool = false
    ) -> Tier {
        // First, so `-freeTier` beats the Debug unlock it exists to defeat.
        if forcedFree { return .free }
        if bypass { return .pro }
        if isActive { return .pro }
        if isUnknown { return timedOut ? .free : .resolving }
        return .free
    }

    /// Begins observing entitlement. Idempotent; call from the host view's
    /// `.task`. Deliberately NOT done in `init` so we never touch
    /// `Superwall.shared` before `Superwall.configure()` has run.
    func start() {
        guard !isStarted, !Self.bypassEnabled else { return }
        isStarted = true

        status = Superwall.shared.subscriptionStatus
        reportTierIfSettled()
        cancellable = Superwall.shared.$subscriptionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                self?.status = newStatus
                self?.reportTierIfSettled()
            }

        // Safety net: don't trap the user on the splash if entitlement never
        // resolves. ~4s is far longer than a warm StoreKit/Superwall check;
        // a returning subscriber resolves from Superwall's on-disk cache well
        // before this fires.
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.status == .unknown else { return }
            self.resolveTimedOut = true
            self.reportTierIfSettled()
        }
    }

    /// The free/paid split of launches. Fires once, as soon as entitlement stops
    /// being `.resolving` (including via the fail-closed timeout above).
    /// Bypassed dev builds never reach here: `start()` returns early for them.
    ///
    /// The `access` property used to read "unlocked"/"locked", when locked meant
    /// a dead app. It now reads "pro"/"free" and means a tier, so the series
    /// deliberately changes value at the release that ships freemium.
    private func reportTierIfSettled() {
        let settled = tier
        guard !didReportTier, settled != .resolving else { return }
        didReportTier = true
        // Payer status as a super property, before the event that reports it —
        // otherwise `gate_resolved` is the one event of the launch that cannot
        // be split by the thing it measures. Every product event after this
        // carries it, so "do subscribers cook more" is a breakdown rather than
        // a cohort join on every insight.
        Analytics.setEntitled(settled == .pro)
        Analytics.capture(.gateResolved, [
            "access": settled == .pro ? "pro" : "free",
            "timed_out": resolveTimedOut,
        ])
    }

    /// Asks StoreKit to restore a subscription bought on another device or a
    /// previous install, and reports whether that left them entitled.
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
    /// So the SDK's own verdict is read first, and the status is then given a
    /// moment to catch up before anyone is told they have not paid. Telling a
    /// paying customer that is the expensive mistake here; a second of waiting
    /// is the cheap one.
    func restorePurchases() async -> Bool {
        guard !Self.forcedFree else { return false }
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

    /// Where "we have already spent the post-onboarding pitch" is remembered.
    private static let didPitchKey = "paywall.didPresentAfterOnboarding"

    /// Presents the paywall **once, ever**: the first time a free cook lands past
    /// onboarding. Finishing the tutorial is the strongest moment we get, so it
    /// is still spent on the wall, and closing it lands in a working app.
    ///
    /// Once ever, not once per launch. Under the hard paywall those were the
    /// same thing, because a locked app had nothing else to show. In freemium
    /// they are very different: the free tier is a product people are meant to
    /// live in, and throwing the paywall at them every time they open the app to
    /// look up their own recipe is how a free tier becomes an uninstall. After
    /// this, upgrading is prompted by the crowns, which are asked for.
    func presentPaywallOnce(store: UserDefaults = .standard) {
        guard !didAutoPresent, !store.bool(forKey: Self.didPitchKey) else { return }
        didAutoPresent = true
        store.set(true, forKey: Self.didPitchKey)
        presentPaywall()
    }

    /// Re-arms the post-onboarding pitch, for testing it more than once.
    static func resetPitchForTesting(store: UserDefaults = .standard) {
        store.removeObject(forKey: didPitchKey)
    }

    /// The one call a crowned control should make: run the feature when the cook
    /// owns it, otherwise open the paywall and count the attempt.
    ///
    /// Deliberately not built on Superwall's `register(placement:feature:)`
    /// closure. That closure *runs* when no campaign matches the placement, so
    /// an unwired or unpublished placement would silently hand the feature over
    /// for free. Checking `isPro` ourselves means the worst a broken placement
    /// can do is show no paywall.
    func perform(_ feature: PremiumFeature, action: () -> Void) {
        guard isPro else {
            presentPaywall(for: feature)
            return
        }
        action()
    }

    /// Opens the paywall for a specific feature, recording which one was wanted.
    func presentPaywall(for feature: PremiumFeature) {
        // Before presenting, not after: this counts *intent*, and it has to
        // survive a placement that resolves to nothing.
        Analytics.capture(.premiumGateTapped, ["feature": feature.rawValue])
        presentPaywall(placement: feature.placement)
    }

    /// Presents the paywall. Guarded so a flurry of taps can't stack
    /// presentations.
    ///
    /// Nothing here unlocks anything: the tier only ever changes when
    /// `subscriptionStatus` flips to `.active`. So an unwired placement means no
    /// paywall appears and the feature stays gated — it fails closed.
    func presentPaywall(placement: String = Entitlements.placement) {
        guard !Self.bypassEnabled, !isPresenting else { return }
        isPresenting = true
        // One event per presentation *attempt*, not per tap — the `isPresenting`
        // guard above already swallows a flurry of them.
        Analytics.capture(.paywallPresented)

        // If no handler callback ever lands, clear the flag anyway.
        //
        // `isPresenting` is shared by every crown in the app, so a stuck `true`
        // does not disable one gate, it disables all of them, silently and until
        // the app is relaunched. That is not hypothetical: on the simulator
        // Superwall cannot load StoreKit products, so a presentation can neither
        // show nor report, and the first tap kills the rest.
        presentationWatchdog?.cancel()
        presentationWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled, self.isPresenting else { return }
            self.isPresenting = false
            Analytics.capture(.paywallError, ["message": "presentation_never_resolved"])
        }

        let handler = PaywallPresentationHandler()
        handler.onDismiss { [weak self] info, result in
            self?.finishPresenting()
            Analytics.capture(.paywallDismissed, [
                "result": Self.label(for: result),
                "paywall": info.name,
            ])
        }
        handler.onError { [weak self] error in
            self?.finishPresenting()
            Analytics.capture(.paywallError, ["message": error.localizedDescription])
        }
        handler.onSkip { [weak self] reason in
            self?.finishPresenting()
            Analytics.capture(.paywallSkipped, ["reason": reason.description])
        }
        Superwall.shared.register(placement: placement, handler: handler) { [weak self] in
            // Runs when the user is entitled (already subscribed or just
            // purchased). The tier itself is driven by `subscriptionStatus`.
            self?.finishPresenting()
        }
    }

    /// One exit point for a presentation, so the watchdog is always cancelled
    /// alongside the flag it guards.
    private func finishPresenting() {
        presentationWatchdog?.cancel()
        presentationWatchdog = nil
        isPresenting = false
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

/// Read through the environment, `Entitlements` is optional — it is nil in
/// previews and anywhere the injection was forgotten. These let a gated call
/// site read `gate.isPro` and `gate.perform(…)` without unwrapping first, and
/// they treat a missing gate as **free**: a screen that forgets the injection
/// then shows crowns, which someone notices, rather than quietly giving the paid
/// features away, which nobody does.
extension Optional where Wrapped == Entitlements {
    @MainActor
    var isPro: Bool { self?.isPro ?? false }

    @MainActor
    func perform(_ feature: PremiumFeature, action: () -> Void) {
        guard let self else { return }
        self.perform(feature, action: action)
    }

    @MainActor
    func presentPaywall(for feature: PremiumFeature) {
        self?.presentPaywall(for: feature)
    }
}
