import Foundation

// MARK: - Recipe-related

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case beginner, intermediate, advanced
    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    /// Compact label for tight layouts (grid cards).
    var shortLabel: String {
        switch self {
        case .beginner: return "Easy"
        case .intermediate: return "Med"
        case .advanced: return "Hard"
        }
    }
}

enum SourcePlatform: String, Codable, CaseIterable {
    case manual
    case website
    case instagram
    case tiktok
    case youtube
    case reddit
    case pinterest
    case screenshot

    var label: String {
        switch self {
        case .manual: "Manual"
        case .website: "Website"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .reddit: "Reddit"
        case .pinterest: "Pinterest"
        case .screenshot: "Screenshot"
        }
    }

    /// Best guess straight from the shared link, so the import screen can name
    /// the source ("SAVING FROM INSTAGRAM") before the page has been fetched.
    init(urlString: String) {
        let host = URLComponents(string: urlString)?.host?.lowercased() ?? ""
        switch true {
        case host.contains("instagram."):            self = .instagram
        case host.contains("tiktok."):               self = .tiktok
        case host.contains("youtube."), host.contains("youtu.be"): self = .youtube
        case host.contains("reddit."), host.contains("redd.it"):   self = .reddit
        default:                                     self = .website
        }
    }
}

/// Culinary role of an ingredient. Nullable on ingredients; AI fills this in later phases.
enum IngredientRole: String, Codable, CaseIterable {
    case protein, starch, fat, acid, binder, aromatic, garnish, sweetener, spice, liquid, vegetable, dairy
}

// MARK: - Kitchen-related

enum GroceryCategory: String, Codable, CaseIterable, Identifiable {
    case produce, meat, dairy, pantry, frozen, spices, other
    var id: String { rawValue }

    var label: String { rawValue.capitalized }
}

enum RoughQuantity: String, Codable, CaseIterable {
    case full
    case half
    case low
    case out

    var label: String {
        switch self {
        case .full: "Full"
        case .half: "Half left"
        case .low: "Almost empty"
        case .out: "Out"
        }
    }

    /// Tap-to-cycle order used by inventory quick adjust.
    var next: RoughQuantity {
        switch self {
        case .full: .half
        case .half: .low
        case .low: .out
        case .out: .full
        }
    }
}

enum StorageLocation: String, Codable, CaseIterable {
    case fridge, pantry, freezer

    var label: String { rawValue.capitalized }
}

// MARK: - Planning & logging

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var sortOrder: Int {
        switch self {
        case .breakfast: 0
        case .lunch: 1
        case .dinner: 2
        case .snack: 3
        }
    }
}

enum MealStatus: String, Codable, CaseIterable {
    case planned
    case cooked
    case eaten
    case skipped
    case replaced
}

enum FoodLogSource: String, Codable, CaseIterable {
    case cookedMeal
    case leftover
    case restaurant
    case quickAdd
    case photo
    case barcode
    case manual
}

// MARK: - User preferences

enum NutritionMode: String, Codable, CaseIterable {
    case cookingOnly
    case lightTracking
    case gymMode

    var label: String {
        switch self {
        case .cookingOnly: "Just cooking"
        case .lightTracking: "Light tracking"
        case .gymMode: "Gym mode"
        }
    }

    var showsNutrition: Bool { self != .cookingOnly }
}

enum DietaryRule: String, Codable, CaseIterable, Identifiable {
    case halal
    case kosher
    case noPork
    case pescatarian
    case vegetarian
    case vegan
    case glutenFree
    case dairyFree
    case nutFree
    case keto
    var id: String { rawValue }

    var label: String {
        switch self {
        case .halal: "Halal"
        case .kosher: "Kosher"
        case .noPork: "No pork"
        case .pescatarian: "Pescatarian"
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .glutenFree: "Gluten-free"
        case .dairyFree: "Dairy-free"
        case .nutFree: "Nut-free"
        case .keto: "Keto"
        }
    }
}
