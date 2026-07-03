import Foundation
import Observation
import SwiftData

enum AppTab: String, CaseIterable, Identifiable {
    case today, recipes, polly, plan, kitchen, progress
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .recipes: "Recipes"
        case .polly: "Polly"
        case .plan: "Plan"
        case .kitchen: "Kitchen"
        case .progress: "Progress"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .recipes: "book"
        case .polly: "chef-hat" // placeholder — GluttTabBar draws Ph.chefHat
        case .plan: "calendar"
        case .kitchen: "refrigerator"
        case .progress: "chart.line.uptrend.xyaxis"
        }
    }
}

/// The 5 universal capture actions behind the floating + button.
enum CaptureAction: String, CaseIterable, Identifiable {
    case importRecipe
    case scanPantry
    case logFood
    case addGroceryItem
    case askWhatToCook

    var id: String { rawValue }

    var label: String {
        switch self {
        case .importRecipe: "Import recipe"
        case .scanPantry: "Scan pantry or fridge"
        case .logFood: "Log food"
        case .addGroceryItem: "Add grocery item"
        case .askWhatToCook: "Invent a dish"
        }
    }

    var subtitle: String {
        switch self {
        case .importRecipe: "TikTok, Instagram, or any link"
        case .scanPantry: "Point the camera, confirm"
        case .logFood: "Photo, search, or quick add"
        case .addGroceryItem: "Straight to your list"
        case .askWhatToCook: "A new recipe from what you have"
        }
    }

    var icon: String {
        switch self {
        case .importRecipe: "link"
        case .scanPantry: "camera.viewfinder"
        case .logFood: "fork.knife.circle"
        case .addGroceryItem: "cart.badge.plus"
        case .askWhatToCook: "wand.and.stars"
        }
    }
}

/// A "Cook with Polly" request: the recipe plus the serving scale chosen on
/// the detail screen. Identifiable so RootView can present the session with
/// `.fullScreenCover(item:)` — a fresh `id` per tap means re-launching the
/// same recipe always starts a fresh session.
struct PollyLaunch: Identifiable, Equatable {
    let id = UUID()
    let recipe: Recipe
    let scale: Double
}

/// App-wide navigation state + deep link routing skeleton.
/// Deep links: glutt://today, glutt://recipes, glutt://import?url=..., etc.
/// The share extension (Phase 2) will route imports through here.
@Observable
final class Router {
    var selectedTab: AppTab = .today
    var isCaptureSheetPresented = false
    /// Set when a deep link or capture action requests a flow that isn't built yet.
    var pendingAction: CaptureAction?
    /// URL waiting to be imported (from share extension or glutt://import?url=...).
    var pendingImportURL: URL?
    /// SwiftData id of a freshly-imported recipe to open (set once the inbox is
    /// drained AND a `glutt://recipe?import=` link is handled — order-independent).
    var recipeToOpenID: PersistentIdentifier?
    /// Import-uuid → SwiftData id for recipes drained this session.
    private var importedThisSession: [UUID: PersistentIdentifier] = [:]
    /// Import uuid requested by a "View recipe" deep link, awaiting its drain.
    private var pendingOpenImportID: UUID?
    /// Screens with their own bottom action bar (e.g. recipe detail's Cook button)
    /// bump this to hide the floating + button while they're visible.
    var floatingButtonSuppressors = 0
    /// Set by the Today launcher card, the glutt://plates deep link, or the
    /// daily "Today's Plate" notification. RootView presents the Plates feed
    /// (a fullScreenCover, not a tab) whenever this is true.
    var pendingPresentPlates = false
    /// Set by the "Cook with Polly" button on recipe detail (and, in Task 16,
    /// the Polly tab's recipe picker). RootView presents the live session
    /// (a fullScreenCover) whenever this is non-nil; carries the serving
    /// scale the user chose so Polly cooks the right amounts.
    var pollyLaunch: PollyLaunch?
    /// True while a live Polly session is on screen. GluttApp's notification
    /// delegate suppresses foreground banners while it's set — in-session
    /// timers already render natively over the camera.
    var isPollySessionActive = false
    /// Dev/testing hook (`-demoCook`): opens Cook Mode for the first recipe on launch.
    var demoCookOnLaunch = false
    /// Dev/testing hook (`-demoWizard`): opens the week planner wizard on launch.
    var demoWizardOnLaunch = false
    /// Dev/testing hook (`-onboarding`): forces the first-run flow even when completed.
    var forceOnboarding = false

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
            pendingAction = .importRecipe
        }
        demoCookOnLaunch = arguments.contains("-demoCook")
        if arguments.contains("-ask") {
            selectedTab = .today
            pendingAction = .askWhatToCook
        }
        if arguments.contains("-demoWizard") {
            demoWizardOnLaunch = true
            selectedTab = .plan
        }
        forceOnboarding = arguments.contains("-onboarding")
    }

    func handle(url: URL) {
        guard url.scheme == "glutt" else { return }
        switch url.host {
        case "today": selectedTab = .today
        case "recipes": selectedTab = .recipes
        case "polly": selectedTab = .polly
        case "plan": selectedTab = .plan
        case "kitchen": selectedTab = .kitchen
        case "progress": selectedTab = .progress
        case "import":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let urlParameter = components?.queryItems?.first(where: { $0.name == "url" })?.value {
                pendingImportURL = URL(string: urlParameter)
            }
            selectedTab = .recipes
            pendingAction = .importRecipe
        case "recipe":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let raw = components?.queryItems?.first(where: { $0.name == "import" })?.value,
               let uuid = UUID(uuidString: raw) {
                requestOpenRecipe(importID: uuid)
            } else {
                selectedTab = .recipes
            }
        case "plates": pendingPresentPlates = true
        default: break
        }
    }

    /// Called when the app foregrounds: picks up URLs saved by the share extension.
    func checkForSharedImport() {
        if let url = PendingImportStore.consume() {
            pendingImportURL = url
            selectedTab = .recipes
            pendingAction = .importRecipe
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

    func perform(_ action: CaptureAction) {
        isCaptureSheetPresented = false
        pendingAction = action
        switch action {
        case .importRecipe: selectedTab = .recipes
        case .scanPantry, .addGroceryItem: selectedTab = .kitchen
        case .logFood, .askWhatToCook: selectedTab = .today
        }
    }
}
