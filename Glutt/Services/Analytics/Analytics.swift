import Foundation
import PostHog

/// Product analytics — a thin façade over PostHog so call sites never import
/// the SDK, and swapping or removing it stays a one-file job.
///
/// Answers *are people using the app*, including the anonymous non-payers the
/// Supabase schema deliberately excludes. Cost-per-user is the other half and
/// lives in `ai_usage` (written by the proxy). See
/// docs/plan-accounts-and-ai-usage.md.
///
/// **Region is US** (`us.i.posthog.com`). US and EU are separate installations
/// and data cannot be moved between them, so this is effectively permanent.
///
/// **Identity:** `distinct_id` is `InstallID.current`, seeded as PostHog's
/// *anonymous* id. Two reasons it is the anonymous id rather than an identified
/// one: anonymous events don't create a person profile (cheaper, and there is
/// no person to profile before an account exists), and `identify(userID:)` at
/// sign-in then merges the whole pre-account history into the account.
///
/// **Never pass an email or an Apple-supplied name to `identify(userID:)`** —
/// use the Supabase user id. PostHog holds a random install UUID and nothing
/// else; that is what makes the US region a non-issue. Emails live in Supabase.
enum Analytics {
    /// Project API key for PostHog project "Glutt" (533977). Publishable and
    /// write-only — same class of value as the Superwall key in `GluttApp`.
    private static let projectToken = "phc_xzRDos4MXFVeHrRL9NeKFpKN8fidjUZwjnGPiPGq5NDD"
    private static let host = "https://us.i.posthog.com"

    /// The event catalog. Kept here rather than as literals at call sites so a
    /// rename can't silently fork one funnel into two.
    enum Event: String {
        /// Every onboarding page, `screen` 0–9 plus its `name`. Screen 0 is the
        /// top of the funnel; the paywall events below are its bottom.
        case onboardingScreenViewed = "onboarding_screen_viewed"
        /// The soft-ask outcome: granted / denied / skipped.
        case onboardingNotifications = "onboarding_notifications"
        case onboardingCompleted = "onboarding_completed"
        /// Once per cold launch, when entitlement settles: locked or unlocked.
        case gateResolved = "gate_resolved"
        case paywallPresented = "paywall_presented"
        case paywallDismissed = "paywall_dismissed"
        case paywallSkipped = "paywall_skipped"
        case paywallError = "paywall_error"
        /// Tapped "Already have an account? Log in" with no subscription to
        /// restore. These are people who believe they are customers and aren't.
        case loginNoSubscription = "login_no_subscription"
        case signInSucceeded = "sign_in_succeeded"
        case signInFailed = "sign_in_failed"
        /// Someone let through after a failed sign-in — see `SignInView`. A
        /// rising count here means the auth backend is broken, not that people
        /// dislike signing in: the link only appears after an error.
        case signInDeferred = "sign_in_deferred"
        /// Signed in, but writing the display name / install id onto the
        /// profile failed. Costs the name and per-user cost attribution.
        case profileLinkFailed = "profile_link_failed"
        /// Someone asked to delete their account and we couldn't. Worth an
        /// alert on: Apple treats a broken deletion path as a rejection.
        case accountDeleteFailed = "account_delete_failed"
    }

    /// Configures the SDK. Call once, from `GluttApp.init`.
    static func start() {
        // `-uiPreview` (screenshots / local UI iteration) already skips
        // Superwall; keep those runs out of the funnel entirely.
        guard !ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return }

        let config = PostHogConfig(projectToken: projectToken, host: host)

        // Seeds the install id as the anonymous `distinct_id` *before* setup, so
        // even the lifecycle events PostHog captures during initialization
        // (`Application Installed`/`Opened`) carry it rather than an SDK-minted
        // UUID. Applied once, on the first launch with no stored id.
        let bootstrap = PostHogBootstrapConfig()
        bootstrap.distinctId = InstallID.current
        config.bootstrap = bootstrap

        // Swizzled UIKit screen views are noise in a SwiftUI app — every screen
        // is the same hosting controller. We send our own.
        config.captureScreenViews = false

        #if DEBUG
        config.debug = true
        #endif

        PostHogSDK.shared.setup(config)

        // Rides on every event so funnels can exclude simulator/Xcode traffic
        // with `build_config = release`. Debug runs are still captured —
        // otherwise there'd be no way to verify instrumentation before
        // shipping it. NOT named `build`: PostHog ships a core definition for
        // that key typed as a *number* (the app build number), which silently
        // reads back as null for a string value.
        PostHogSDK.shared.register(["build_config": buildKind])
    }

    static func capture(_ event: Event, _ properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
    }

    /// Links the install's pre-account history to the account at sign-in.
    ///
    /// Pass the **Supabase user id** (a UUID) — never an email or the name
    /// Apple returns on first authorization. Unused until Sign in with Apple
    /// lands (step 4 of the plan).
    static func identify(userID: String) {
        PostHogSDK.shared.identify(userID)
    }

    private static var buildKind: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }
}
