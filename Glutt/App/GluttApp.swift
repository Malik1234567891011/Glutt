import SwiftData
import SwiftUI

@main
struct GluttApp: App {
    @State private var router = Router()

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
            #if DEBUG
            SeedData.seedIfNeeded(context: container.mainContext)
            #endif
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
        .modelContainer(container)
    }
}
