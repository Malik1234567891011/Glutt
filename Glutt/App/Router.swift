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

    func handle(url: URL) {
        guard url.scheme == "glutt" else { return }
        switch url.host {
        case "today": selectedTab = .today
        case "recipes": selectedTab = .recipes
        case "plan": selectedTab = .plan
        case "kitchen": selectedTab = .kitchen
        case "progress": selectedTab = .progress
        case "import":
            selectedTab = .recipes
            pendingAction = .importRecipe
        default: break
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
