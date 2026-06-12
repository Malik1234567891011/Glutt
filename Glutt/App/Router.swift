import Foundation
import Observation

enum AppTab: String, CaseIterable, Identifiable {
    case today, recipes, plan, kitchen, progress
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .recipes: "Recipes"
        case .plan: "Plan"
        case .kitchen: "Kitchen"
        case .progress: "Progress"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .recipes: "book"
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
        case .askWhatToCook: "What should I cook?"
        }
    }

    var subtitle: String {
        switch self {
        case .importRecipe: "Paste a link or share from TikTok, Instagram, YouTube"
        case .scanPantry: "Point the camera, confirm what you have"
        case .logFood: "Photo, search, or quick-add"
        case .addGroceryItem: "Add something to the shopping list"
        case .askWhatToCook: "Get ideas based on your kitchen and time"
        }
    }

    var icon: String {
        switch self {
        case .importRecipe: "link"
        case .scanPantry: "camera.viewfinder"
        case .logFood: "fork.knife.circle"
        case .addGroceryItem: "cart.badge.plus"
        case .askWhatToCook: "sparkles"
        }
    }
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
    /// Screens with their own bottom action bar (e.g. recipe detail's Cook button)
    /// bump this to hide the floating + button while they're visible.
    var floatingButtonSuppressors = 0
    /// Dev/testing hook (`-demoCook`): opens Cook Mode for the first recipe on launch.
    var demoCookOnLaunch = false
    /// Dev/testing hook (`-demoWizard`): opens the week planner wizard on launch.
    var demoWizardOnLaunch = false

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
    }

    func handle(url: URL) {
        guard url.scheme == "glutt" else { return }
        switch url.host {
        case "today": selectedTab = .today
        case "recipes": selectedTab = .recipes
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
