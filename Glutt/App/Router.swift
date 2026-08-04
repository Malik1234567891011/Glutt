import Foundation
import Observation
import SwiftData

enum AppTab: String, CaseIterable, Identifiable {
    case recipes, discover, kitchen
    var id: String { rawValue }

    var label: String {
        switch self {
        case .recipes: "Recipes"
        case .discover: "Discover"
        case .kitchen: "Kitchen"
        }
    }
}

/// A "Cook with Chef" request: the recipe plus the serving scale chosen on
/// the detail screen. Identifiable so RootView can present the session with
/// `.fullScreenCover(item:)` — a fresh `id` per tap means re-launching the
/// same recipe always starts a fresh session.
struct PollyLaunch: Identifiable, Equatable {
    let id = UUID()
    let recipe: Recipe
    let scale: Double
    /// True when the cook already heard the pre-cook trailer briefing, so
    /// Polly's live opening can stay short instead of re-narrating the dish.
    var heardBriefing: Bool = false
    /// True when the trailer finished and handed off automatically — Polly
    /// opens already listening and waits for a verbal "let's cook" / "I'm ready"
    /// instead of speaking first.
    var awaitVerbalGo: Bool = false
}

/// App-wide navigation state + deep link routing skeleton.
/// Deep links: glutt://recipes, glutt://discover, glutt://import?url=..., glutt://kitchen.
/// The share extension routes imports through here.
@Observable
final class Router {
    /// Instrumented here rather than in `GluttTabBar` so deep links and the
    /// share extension's jump to Recipes count too — the question is which
    /// screens people end up on, not which ones they tapped to get to.
    /// Observers do not fire during `init`, so the launch-argument hooks below
    /// stay out of the funnel.
    var selectedTab: AppTab = .recipes {
        didSet {
            guard oldValue != selectedTab else { return }
            Analytics.capture(.tabSwitched, ["tab": selectedTab.rawValue])
        }
    }
    /// URL waiting to be imported (from the share extension or glutt://import?url=...).
    /// When set, the Recipes tab opens the import sheet. This is the single signal
    /// for "start an import" now that the floating capture button is gone.
    var pendingImportURL: URL?
    /// SwiftData id of a freshly-imported recipe to open (set once the inbox is
    /// drained AND a `glutt://recipe?import=` link is handled — order-independent).
    var recipeToOpenID: PersistentIdentifier?
    /// Import-uuid → SwiftData id for recipes drained this session.
    private var importedThisSession: [UUID: PersistentIdentifier] = [:]
    /// Import uuid requested by a "View recipe" deep link, awaiting its drain.
    private var pendingOpenImportID: UUID?
    /// Set by the "Cook with Chef" button on recipe detail. RootView presents
    /// the live session (a fullScreenCover) whenever this is non-nil; carries the
    /// serving scale the user chose so Polly cooks the right amounts.
    var pollyLaunch: PollyLaunch?
    /// True while a live Polly session is on screen. GluttApp's notification
    /// delegate suppresses foreground banners while it's set — in-session
    /// timers already render natively over the camera.
    var isPollySessionActive = false
    /// Dev/testing hook (`-demoCook`): opens Cook Mode for the first recipe on launch.
    var demoCookOnLaunch = false
    /// Dev/testing hook (`-onboarding`): forces the first-run flow even when completed.
    var forceOnboarding = false
    /// Dev/testing hook (`-openRecipe`): pushes the first library recipe's detail on
    /// launch, so the detail screen can be captured without UI tapping.
    var openFirstRecipeOnLaunch = false
    /// Dev/testing hook (`-openChef <slug>`): pushes a chef page on launch. Slug is
    /// optional and defaults to the first chef in the rail.
    var chefToOpenOnLaunch: String?
    /// Dev/testing hook (`-openRestaurant <slug>`): pushes a restaurant page on
    /// launch. Slug is optional and defaults to the first in the rail.
    var restaurantToOpenOnLaunch: String?
    /// Dev/testing hook (`-pollyCook`): opens a live Polly session for the first
    /// library recipe on launch. Without this the cook screen's connecting,
    /// failed and mic-denied states could not be reached in the simulator at all,
    /// which is how they came to be drawn in the LIGHT app palette on a black
    /// canvas without anyone noticing.
    var pollyCookOnLaunch = false

    init() {
        // Launch-argument hooks for UI tests and tooling: `-tab recipes`, `-importURL https://...`
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "-tab"),
           arguments.indices.contains(flagIndex + 1),
           let tab = AppTab(rawValue: arguments[flagIndex + 1]) {
            selectedTab = tab
        }
        if let flagIndex = arguments.firstIndex(of: "-importURL"),
           arguments.indices.contains(flagIndex + 1),
           let url = URL(string: arguments[flagIndex + 1]) {
            pendingImportURL = url
            selectedTab = .recipes
        }
        demoCookOnLaunch = arguments.contains("-demoCook")
        pollyCookOnLaunch = arguments.contains("-pollyCook")
        forceOnboarding = arguments.contains("-onboarding")
        openFirstRecipeOnLaunch = arguments.contains("-openRecipe")
        if ChefContent.isEnabled, let flagIndex = arguments.firstIndex(of: "-openChef") {
            let next = arguments.indices.contains(flagIndex + 1) ? arguments[flagIndex + 1] : nil
            chefToOpenOnLaunch = (next?.hasPrefix("-") == false ? next : nil) ?? ChefContent.chefs.first?.id
        }
        if RestaurantContent.isEnabled, let flagIndex = arguments.firstIndex(of: "-openRestaurant") {
            let next = arguments.indices.contains(flagIndex + 1) ? arguments[flagIndex + 1] : nil
            restaurantToOpenOnLaunch =
                (next?.hasPrefix("-") == false ? next : nil) ?? RestaurantContent.restaurants.first?.id
        }
    }

    func handle(url: URL) {
        guard url.scheme == "glutt" else { return }
        switch url.host {
        case "recipes": selectedTab = .recipes
        case "discover", "plates": selectedTab = .discover
        case "kitchen": selectedTab = .kitchen
        // Legacy links kept working: Polly now launches from a recipe, and the
        // removed Today/Plan/Progress tabs fall back to the home (Recipes) tab so
        // any lingering notification/deep link still opens somewhere sensible.
        case "polly", "today", "plan", "progress": selectedTab = .recipes
        case "import":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let urlParameter = components?.queryItems?.first(where: { $0.name == "url" })?.value {
                pendingImportURL = URL(string: urlParameter)
            }
            selectedTab = .recipes
        case "recipe":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let raw = components?.queryItems?.first(where: { $0.name == "import" })?.value,
               let uuid = UUID(uuidString: raw) {
                requestOpenRecipe(importID: uuid)
            } else {
                selectedTab = .recipes
            }
        default: break
        }
    }

    /// Called when the app foregrounds: picks up URLs saved by the share extension.
    func checkForSharedImport() {
        if let url = PendingImportStore.consume() {
            pendingImportURL = url
            selectedTab = .recipes
        }
    }

    /// Called after the inbox is drained, mapping each draft's id to its new recipe.
    func noteImported(_ map: [UUID: PersistentIdentifier]) {
        importedThisSession.merge(map) { _, new in new }
        resolvePendingNavigation()
    }

    /// Called when a `glutt://recipe?import=<uuid>` link is handled.
    func requestOpenRecipe(importID: UUID) {
        pendingOpenImportID = importID
        selectedTab = .recipes
        resolvePendingNavigation()
    }

    private func resolvePendingNavigation() {
        guard let importID = pendingOpenImportID,
              let id = importedThisSession[importID] else { return }
        recipeToOpenID = id
        pendingOpenImportID = nil
    }
}
