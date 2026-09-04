import SuperwallKit
import SwiftData
import SwiftUI
import UserNotifications

/// Routes notification taps (e.g. "time to start cooking") to the right tab,
/// and keeps banners visible while the app is foregrounded.
final class NotificationRoutingDelegate: NSObject, UNUserNotificationCenterDelegate {
    var router: Router?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let destination = response.notification.request.content.userInfo["destination"] as? String
        if destination == "plates" {
            router?.selectedTab = .discover
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // A live Polly session renders its timers natively over the camera —
        // a banner on top would announce the same thing twice. Stay quiet
        // until the session ends.
        if router?.isPollySessionActive == true { return [] }
        return [.banner, .sound]
    }
}

@main
struct GluttApp: App {
    @State private var router = Router()
    private let notificationDelegate = NotificationRoutingDelegate()
    /// Held here because `Superwall.shared.delegate` is weak. See the type.
    private let paywallEventBridge = PaywallEventBridge()

    /// Superwall publishable key — safe to embed in the app binary.
    /// Dashboard → Settings → API Keys.
    private static let superwallPublicAPIKey = "pk_WahaBcbECKEDins7Lio-Q"

    init() {
        // Before the Superwall configure below, which is the thing it decides.
        // `-realGates` latches in Debug so a phone holds the setting rather than
        // reverting the moment the app is opened from its icon.
        DevBuild.applyLaunchOverrides()
        // `-uiPreview`: dev/screenshot hook — skip Superwall so its test-mode
        // sheet (shown when the running bundle id differs from the dashboard's)
        // doesn't cover the UI during local iteration.
        // `-realGates` brings it back when the paywall is the thing being tested.
        if !ProcessInfo.processInfo.arguments.contains("-uiPreview"), !DevBuild.relaxGates {
            Superwall.configure(apiKey: Self.superwallPublicAPIKey)
            // Inside this branch, never outside it: reading `Superwall.shared`
            // before `configure` is the one ordering mistake this file has to
            // avoid.
            Superwall.shared.delegate = paywallEventBridge
        }
        // Before any view exists, so the onboarding funnel's first screen and
        // PostHog's own launch events are captured under the install id.
        Analytics.start()
        // Meta app events for the Facebook and Instagram campaigns. Separate
        // from PostHog on purpose: this one reports to an ad account, not to
        // us, and sends exactly one hand-written event (`StartTrial`).
        MetaAds.start()
        notificationDelegate.router = router
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    let container: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            RecipeIngredient.self,
            RecipeStep.self,
            RecipeCollection.self,
            MealPlan.self,
            MealPlanLine.self,
            PantryItem.self,
            GroceryItem.self,
            KitchenTool.self,
            CookSession.self,
            UserPrefs.self,
            PollyMemory.self,
            PollyCookLog.self,
            RecipeChatMessage.self,
            SkillProgress.self,
            SkillAttempt.self,
            TrialResult.self,
            SyncTombstone.self,
        ])
        do {
            let container = try ModelContainer(for: schema)
            // Seed demo recipes only when launched with `-seed` (the "Glutt Beta"
            // scheme passes it). Works when you run the scheme from Xcode; launch
            // arguments do NOT survive a TestFlight/App Store upload, so distributed
            // builds stay empty.
            if ProcessInfo.processInfo.arguments.contains("-seed") {
                SeedData.seedIfNeeded(context: container.mainContext)
            }
            // Technique lessons (fry an egg, etc.) for every user — not Beta-only.
            CookingBasics.install(context: container.mainContext)
            // Guest chefs and their signature dishes. Bundled, free, and kept out
            // of the personal library feed until the user hearts one. Gated here
            // rather than inside `install` so the tests can still seed them.
            if ChefContent.isEnabled {
                ChefContent.install(context: container.mainContext)
            }
            // Restaurant packs, on the same terms as the chefs above.
            if RestaurantContent.isEnabled {
                RestaurantContent.install(context: container.mainContext)
            }
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                // Light-only by design (cream/green identity); also enforced
                // via UIUserInterfaceStyle in Info.plist. Dark theme: backlog.
                .preferredColorScheme(.light)
                .onOpenURL { url in router.handle(url: url) }
        }
        .modelContainer(container)
    }
}
