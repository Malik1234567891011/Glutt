import FBSDKCoreKit
import Foundation

/// Meta app events — a thin façade over the Facebook SDK so call sites never
/// import it, on the same terms as `Analytics`.
///
/// This is **not** product analytics and does not replace PostHog. It exists
/// for one reason: a Facebook or Instagram ad campaign can only optimize
/// delivery toward a conversion it can see. Meta's Events Manager is configured
/// for a single event, `StartTrial`, so that is the only thing sent by hand.
///
/// Everything else is automatic. Once `start()` runs, the SDK logs installs,
/// launches and sessions on its own (`FacebookAutoLogAppEventsEnabled` defaults
/// to true and is left that way — those are the events an install campaign is
/// measured on), and it owns the SKAdNetwork conversion values for the two
/// identifiers declared in `project.yml`. Only one SDK in an app may own those,
/// which is why there is no AppsFlyer or Adjust beside it.
///
/// **"Log in-app events automatically" must stay OFF** in the app's iOS
/// platform settings on developers.facebook.com. That toggle makes the SDK
/// watch StoreKit and log its own trials and purchases, which alongside
/// `logTrialStarted` below means Meta counts every trial twice and bids on the
/// doubled number. It is a dashboard setting with no representation in this
/// repo, so nothing here will catch it being switched back on: a sudden
/// doubling of `StartTrial` with no release behind it is that toggle.
///
/// **Attribution quality is capped by ATT.** With no `NSUserTrackingUsageDescription`
/// prompt the IDFA is never available, so Meta measures through SKAdNetwork and
/// Aggregated Event Measurement: real, delayed, and coarser (campaign-level, no
/// ad-set or creative split). Adding the prompt is a separate decision.
enum MetaAds {
    /// Boots the SDK. Call once, from `GluttApp.init`.
    static func start() {
        guard isReportingAllowed, isConfigured else { return }
        // The SwiftUI equivalent of the `application(_:didFinishLaunchingWithOptions:)`
        // call in Meta's docs. Glutt has no `UIApplicationDelegate` and does not
        // need one for this.
        ApplicationDelegate.shared.initializeSDK()

        // Prints every event and its full parameter dictionary to the console,
        // including `advertiser_id` and the ATE flag. Nothing else in this
        // integration is inspectable from here: the events go to Meta and come
        // back as a number in Ads Manager three days later. When the question is
        // "is this actually wired up", this is the answer.
        #if DEBUG
        Settings.shared.loggingBehaviors = [.appEvents]
        #endif
    }

    /// The conversion the ad sets bid on: someone started the free trial.
    ///
    /// `price` is the price of the subscription the trial converts into, not
    /// the price of the trial itself (which is zero). Meta sums `valueToSum`
    /// into the campaign's reported value, so sending zero would leave every
    /// value-based bid strategy with nothing to work with. The trade is that
    /// reported ROAS counts trials that never convert, so read it as reach,
    /// not revenue. Revenue lives in App Store Connect.
    static func logTrialStarted(productID: String, price: Decimal, currencyCode: String?) {
        log(.startTrial, productID: productID, price: price, currencyCode: currencyCode)
    }

    /// Someone subscribed without a trial, because they had already used theirs.
    /// Reinstalls and lapsed subscribers, mostly.
    ///
    /// A separate Meta standard event rather than a second `StartTrial`, so the
    /// two never merge into one inflated number. Without it these conversions
    /// were invisible: an ad could buy a resubscribe and hear nothing back, and
    /// a quiet week read exactly the same as a broken integration.
    ///
    /// Confirmed against Superwall's own record of a 2026-08-16 purchase, which
    /// carried `is_free_trial_available: false` and raised `subscriptionStart`
    /// rather than `freeTrialStart`. Meta's Events Manager needs `Subscribe`
    /// added alongside `StartTrial` for this to be usable as a campaign goal.
    static func logSubscribed(productID: String, price: Decimal, currencyCode: String?) {
        log(.subscribe, productID: productID, price: price, currencyCode: currencyCode)
    }

    private static func log(
        _ event: AppEvents.Name,
        productID: String,
        price: Decimal,
        currencyCode: String?
    ) {
        guard isReportingAllowed, isConfigured else { return }

        var parameters: [AppEvents.ParameterName: Any] = [.contentID: productID]
        // Absent only if StoreKit handed back a product with no locale, which
        // it does not in practice. Meta reads an unlabelled value as USD.
        if let currencyCode { parameters[.currency] = currencyCode }

        AppEvents.shared.logEvent(
            event,
            valueToSum: NSDecimalNumber(decimal: price).doubleValue,
            parameters: parameters
        )
    }

    /// Debug builds *do* report, deliberately: Meta's App Event Tester is the
    /// only way to confirm the wiring before it goes near a live campaign.
    ///
    /// The two exclusions are the ones that would corrupt the campaign rather
    /// than verify it. `XCTestConfigurationFilePath` is the important one: the
    /// suite runs inside this app, so `@main` runs, and a single test pass
    /// would otherwise file an install and a run of launches against the ad
    /// account. `Analytics` learned that the expensive way.
    private static var isReportingAllowed: Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return false }
        return !ProcessInfo.processInfo.arguments.contains("-uiPreview")
    }

    /// False while `project.yml` still carries a placeholder, so the app builds
    /// and runs before the Meta app exists. `initializeSDK` on a bogus id is not
    /// a no-op — it boots a reporting pipeline that talks to nothing, which
    /// looks identical to a wiring bug once the campaign is spending.
    ///
    /// Both values are required, not just the id: the SDK has refused to send
    /// app events without a client token since v13.
    private static var isConfigured: Bool {
        ["FacebookAppID", "FacebookClientToken"].allSatisfy { key in
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return false }
            return !value.isEmpty && !value.hasPrefix("REPLACE_WITH_")
        }
    }
}
