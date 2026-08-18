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
/// **`distinct_id` is always the Supabase user id, never the email.** An email
/// is mutable — Apple's Hide My Email can be switched off, an Apple ID address
/// can change — and a `distinct_id` that changes forks one person into two,
/// permanently. The UUID also keeps one join key between here and
/// `ai_spend_by_user` in Supabase.
///
/// The email rides along as a **person property** instead, which is what
/// PostHog actually displays: with `person_display_name_properties` resolving
/// `email` first, every persons list, breakdown and cohort shows the address
/// rather than a UUID. Deliberate reversal of this file's original stance that
/// PostHog would hold nothing but random UUIDs — it now holds customer emails
/// in a US installation, which is a privacy-policy commitment, not just a
/// technical one.
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
        /// The App Tracking Transparency answer, with `status`. This is the
        /// opt-in rate the Meta ad reporting rests on: everyone who is not
        /// `authorized` is measured through SKAdNetwork alone, so a low number
        /// here explains a campaign that looks blind before the ads do.
        case trackingPermission = "tracking_permission"
        /// The native App Store rating card was asked for, with the `moment` it
        /// fired at. Counts *asks*, not ratings: iOS never reports whether the
        /// card actually appeared (it is throttled to 3 a year and users can
        /// switch it off) or what was tapped. Compare against App Store Connect
        /// review counts, never against this alone.
        case reviewPrompted = "review_prompted"
        /// Once per cold launch, when entitlement settles: locked or unlocked.
        case gateResolved = "gate_resolved"
        case paywallPresented = "paywall_presented"
        case paywallDismissed = "paywall_dismissed"
        case paywallSkipped = "paywall_skipped"
        case paywallError = "paywall_error"
        /// Tapped "Already have an account? Log in" with no subscription to
        /// restore. These are people who believe they are customers and aren't.
        case loginNoSubscription = "login_no_subscription"
        /// Logged in, was entitled, and had no account — so one was created by
        /// the OIDC exchange and immediately deleted again. They get sent back
        /// to onboarding to sign up properly.
        case loginWithoutAccount = "login_without_account"
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

        // MARK: - Product
        //
        // Everything above is acquisition: it stops the moment someone gets
        // into the app. These answer what they actually do once they are in.
        //
        // *How often* needs no event of its own — the SDK's own
        // `Application Opened` already drives DAU/WAU, retention and
        // stickiness. What was missing is what happened in between.

        /// The one recipe-creation event, with a `source`. Deliberately not one
        /// event per path: a `plates_recipe_saved` alongside this would double
        /// count every "recipes created" number the moment someone forgets.
        /// Sources: `import_<platform>` (the draft already knows whether it came
        /// from instagram, reddit, youtube or a plain website), `import_share`
        /// for the share extension, `discover`, `plates`, `ai_howto`, `manual`.
        /// Seeded starter recipes and cooking basics are not creations and do
        /// not fire.
        case recipeCreated = "recipe_created"
        case recipeViewed = "recipe_viewed"
        case recipeDeleted = "recipe_deleted"

        /// Both cooking flows fire these, separated by `with_polly` rather than
        /// by having their own events. A live Polly cook *is* a cook, so a
        /// separate `polly_session_started` would either double count every
        /// cook or leave "how many cooks" needing two events added together.
        ///
        /// `cook_started` with `with_polly: true` is also the PostHog half of
        /// `ai_usage.polly_session`: this says who and how often, that says
        /// what the minutes cost. The two counts diverging is real signal —
        /// sessions that die before teardown, or mid-session token re-mints.
        case cookStarted = "cook_started"
        /// `ended_early` is true when they walked away, so drop-off is a filter
        /// on one event rather than a funnel across two.
        case cookFinished = "cook_finished"
        case pollyWakeWord = "polly_wake_word"

        /// The AI features that are not Polly and not an import: `invent`,
        /// `pantry_scan`, `substitute`, `optimize`, `adjust`, and the recipe
        /// chat (`recipe_chat_opened` / `recipe_chat` / `recipe_chat_pantry` /
        /// `recipe_chat_applied`). Most are a `feature = chat` row in
        /// `ai_usage`, which knows what they cost in total but not which button
        /// produced them. Recipe chat is the exception: it sends
        /// `x-glutt-feature: recipe_chat`, so its spend is readable on its own.
        ///
        /// Not to be confused with `KitchenTool`, which is a whisk.
        case aiToolUsed = "ai_tool_used"
        /// `method`: manual / bulk / scan / voice.
        case pantryItemAdded = "pantry_item_added"

        /// No matching "video opened" event: Discover autoplays the card that
        /// is on screen, so an open is just an impression, and impressions at
        /// swipe volume would drown everything else in this list. Search to
        /// `recipe_created{source: discover}` is the funnel that matters.
        case discoverSearched = "discover_searched"
        case platesDeckViewed = "plates_deck_viewed"
        case platesSwiped = "plates_swiped"

        /// A started import that never reaches `recipe_created` is a failure,
        /// so success needs no event of its own.
        case importStarted = "import_started"
        case importFailed = "import_failed"

        /// The Discord invite. `discord_opened` is the only one that can be
        /// trusted as a join: the app never learns who is actually in the
        /// server, so a tap is the whole signal. The other two exist to answer
        /// whether the repeating prompt is earning its interruption, or whether
        /// people are just declining it every week.
        ///
        /// `show_count`: which showing this was, from 1.
        case discordPromptShown = "discord_prompt_shown"
        /// `action`: not_now / never. `show_count` as above.
        case discordPromptDismissed = "discord_prompt_dismissed"
        /// `source`: sheet / settings.
        case discordOpened = "discord_opened"

        /// Navigation. Needed because `captureScreenViews` is off, and it is
        /// off because every SwiftUI screen is the same hosting controller.
        case tabSwitched = "tab_switched"
    }

    /// Configures the SDK. Call once, from `GluttApp.init`.
    static func start() {
        // `-uiPreview` (screenshots / local UI iteration) already skips
        // Superwall; keep those runs out of the funnel entirely.
        guard !ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return }

        // The unit tests run *inside* this app, so `@main` runs and every
        // service the suite exercises reports for real. One `test_sim` put 17
        // `cook_started`, 6 `recipe_created` and 7 `plates_deck_viewed` into
        // production — a full suite outnumbers a real user by an order of
        // magnitude, which is how a product metric quietly becomes a count of
        // how often the tests ran.
        //
        // Skipping `setup` is enough: every `capture` after this is a no-op
        // against an unconfigured SDK.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

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

    /// Properties must be enums, counts and booleans. **No free text** — search
    /// queries, recipe titles and transcripts stay out, because a property
    /// value is a filterable dimension, not a log line.
    static func capture(_ event: Event, _ properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
    }

    /// Links the install's pre-account history to the account at sign-in, and
    /// puts a readable name on the person.
    ///
    /// `userID` is the **Supabase user id** and nothing else — see the note at
    /// the top of this file for why the email must not be the `distinct_id`.
    ///
    /// `email` and `name` go to `userProperties` (overwritten on every restore,
    /// so a changed address follows the person). `first_seen_at` is
    /// set-once — later sign-ins must not overwrite the day they arrived.
    static func identify(userID: String, email: String? = nil, name: String? = nil) {
        var person: [String: Any] = [:]
        // Apple only ever returns a name on first authorization, so a nil here
        // is normal and must not blank out one we already stored.
        if let email, !email.isEmpty { person["email"] = email }
        if let name, !name.isEmpty { person["name"] = name }

        PostHogSDK.shared.identify(
            userID,
            userProperties: person.isEmpty ? nil : person,
            userPropertiesSetOnce: ["first_seen_at": ISO8601DateFormatter().string(from: Date())]
        )
    }

    /// Person properties for cohorting — "do people cooking for macros come
    /// back more" is a question about the person, not about one event.
    ///
    /// Sent as a `$set` on a lightweight event because PostHog has no
    /// person-update call outside `identify`, and re-identifying to change a
    /// property would be a lie about when they signed in.
    static func setPerson(_ properties: [String: Any]) {
        guard !properties.isEmpty else { return }
        PostHogSDK.shared.capture("$set", userProperties: properties)
    }

    /// Registers payer status as a super property, so **every** event can be
    /// split by it. Without this, "do subscribers cook more" needs a cohort
    /// join on every single insight.
    static func setEntitled(_ entitled: Bool) {
        PostHogSDK.shared.register(["entitled": entitled])
    }

    /// Detaches this device from the person. Called on account **deletion**
    /// only, never on sign out.
    ///
    /// Deleting an account and then continuing to file that device's events
    /// under the deleted person is the one behaviour that would make the
    /// in-app deletion path dishonest. The cost is real though: `reset()`
    /// mints a fresh anonymous id, so this device's `distinct_id` stops
    /// matching its `InstallID` and its future events no longer join to
    /// `ai_usage.install_id`. Correct trade for a rare, deliberate action.
    static func resetPerson() {
        PostHogSDK.shared.reset()
    }

    private static var buildKind: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }
}
