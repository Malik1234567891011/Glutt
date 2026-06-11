import SwiftData
import SwiftUI

/// Phase 0 placeholder for the recipe library. Full CRUD, collections,
/// filtering, and search arrive in Phase 1; import in Phase 2.
struct RecipesView: View {
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var selectedFilter: String?

    private let filters = ["Dinner", "Quick", "High protein", "Chicken", "Pasta", "Dessert"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ChipRow(labels: filters, selection: $selectedFilter)

                    if recipes.isEmpty {
                        EmptyStateView(
                            icon: "book",
                            title: "No recipes yet",
                            message: "Import your first recipe from TikTok, Instagram, or any website."
                        )
                    } else {
                        LazyVStack(spacing: Theme.Spacing.md) {
                            ForEach(recipes) { recipe in
                                RecipeCard(recipe: recipe)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                    }
                }
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Recipes")
            .searchable(text: .constant(""), prompt: "creamy chicken thing with lemon…")
        }
    }
}
