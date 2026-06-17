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
        if response.notification.request.content.userInfo["destination"] as? String == "plan" {
            router?.selectedTab = .plan
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct GluttApp: App {
    @State private var router = Router()
    private let notificationDelegate = NotificationRoutingDelegate()

    init() {
        notificationDelegate.router = router
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    let container: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            RecipeIngredient.self,
            RecipeStep.self,
            RecipeCollection.self,
            PantryItem.self,
            GroceryItem.self,
            Leftover.self,
            PlannedMeal.self,
            FoodLog.self,
            CookSession.self,
            UserPrefs.self,
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
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
        .modelContainer(container)
    }
}
