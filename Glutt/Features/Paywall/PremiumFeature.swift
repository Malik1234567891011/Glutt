import Foundation

/// Everything behind the subscription, in one enumerable list.
///
/// Glutt's free tier is a real recipe box: import as much as you like, read any
/// recipe you saved (ingredients, steps, macros, tags), and swipe a capped
/// number of Discover cards a week. This type is the other side of that line.
/// Nothing here is hidden from a free cook — the control stays exactly where it
/// was, wearing a crown, and tapping it opens the paywall.
///
/// Keeping the list in one enum rather than as string literals at call sites
/// means the gated surface is auditable ("what exactly do you get for $49.99?"
/// has a single answer), the copy can't drift between two spellings of the same
/// feature, and every gate reports under a stable analytics name.
enum PremiumFeature: String, CaseIterable {

    // MARK: Recipe detail
    //
    // Reading a recipe is free. Doing anything with it is not.

    case cookWithChef
    case cookStepByStep
    case askPolly
    case useWhatIHave
    case substitutions
    case editRecipe
    case recipeVersions
    case collections
    case shareRecipe
    case recipeExtras
    case unitConversion

    // MARK: Recipes tab

    case weekPlan
    case cookingBasics
    // Search, including its AI re-ranking, is deliberately NOT here. Searching
    // your own library is free.

    // MARK: Discover

    case discoverVideos
    case unlimitedSwipes

    // MARK: Kitchen
    //
    // The tab itself opens, and a free cook can see their ingredients and type
    // new ones in. What is gated is every *shortcut* into it (the camera, the
    // microphone), what it can make for you, and the other two segments.
    // Seeing what you are missing is the point; that is what sells the rest.

    /// Reading the camera, both "Scan with a photo" and "Choose a photo".
    case pantryScan
    /// "Tell us what you have", the voice route.
    case pantryDictation
    /// Invent a dish from what is on hand.
    case inventDish
    case kitchenTools
    /// The grocery list, and adding to it from a recipe.
    case groceries

    /// What the tier is called in user-facing copy, in one place because it is
    /// currently spelled two ways in the shipped app: "Glutt Pro" in the old
    /// paywall cover, "Glutt Premium" in Settings, and `premium` in the StoreKit
    /// product ids. Every new string reads this, so settling the name later is
    /// one edit rather than a sweep.
    static let tierName = "Pro"

    /// Short label for this feature, used in the crown's accessibility label and
    /// in the notice banners. Reads naturally after "…is part of Glutt Pro".
    var title: String {
        switch self {
        case .cookWithChef: "Cooking with Chef"
        case .cookStepByStep: "Step by step cooking"
        case .askPolly: "Ask Polly"
        case .useWhatIHave: "Use what I have"
        case .substitutions: "Ingredient swaps"
        case .editRecipe: "Editing recipes"
        case .recipeVersions: "Recipe versions"
        case .collections: "Collections"
        case .shareRecipe: "Sharing recipes"
        case .recipeExtras: "Notes, ratings and cook history"
        case .unitConversion: "Unit conversion"
        case .weekPlan: "Planning a week of dinners"
        case .cookingBasics: "Cooking basics"
        case .discoverVideos: "Recipe videos"
        case .unlimitedSwipes: "Unlimited swipes"
        case .pantryScan: "Scanning your kitchen"
        case .pantryDictation: "Adding by voice"
        case .inventDish: "Making something from what you have"
        case .kitchenTools: "Your tools"
        case .groceries: "Groceries"
        }
    }

    /// The Superwall placement this feature *will* register once campaign 91288
    /// carries it. Snake case, matching the existing `onboarding_complete`.
    var placementName: String {
        switch self {
        case .cookWithChef: "premium_cook_with_chef"
        case .cookStepByStep: "premium_cook_step_by_step"
        case .askPolly: "premium_ask_polly"
        case .useWhatIHave: "premium_use_what_i_have"
        case .substitutions: "premium_substitutions"
        case .editRecipe: "premium_edit_recipe"
        case .recipeVersions: "premium_recipe_versions"
        case .collections: "premium_collections"
        case .shareRecipe: "premium_share_recipe"
        case .recipeExtras: "premium_recipe_extras"
        case .unitConversion: "premium_unit_conversion"
        case .weekPlan: "premium_week_plan"
        case .cookingBasics: "premium_cooking_basics"
        case .discoverVideos: "premium_discover_videos"
        case .unlimitedSwipes: "premium_unlimited_swipes"
        case .pantryScan: "premium_pantry_scan"
        case .pantryDictation: "premium_pantry_dictation"
        case .inventDish: "premium_invent_dish"
        case .kitchenTools: "premium_kitchen_tools"
        case .groceries: "premium_groceries"
        }
    }

    /// Whether to register `placementName` or fall back to the one placement we
    /// know is live.
    ///
    /// **Leave this false until every name above exists in campaign 91288, under
    /// the "no active entitlements" audience, and the campaign is published.**
    /// A placement Superwall has never heard of presents nothing at all, which
    /// turns every crown in the app into a dead tap — the failure is silent and
    /// it looks exactly like a broken build. `onboarding_complete` is already
    /// wired to paywall 243875, so the gates present a real, published paywall
    /// in the meantime and cutting over is this one line.
    static let usesPerFeaturePlacements = false

    /// The placement actually registered today.
    var placement: String {
        Self.usesPerFeaturePlacements ? placementName : Entitlements.placement
    }
}
