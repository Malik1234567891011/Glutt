import SwiftData
import SwiftUI

/// The recipe library: search, filters, collections, and the recipe list.
struct RecipesView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query(sort: \Recipe.createdAt, order: .reverse) private var allRecipes: [Recipe]
    @Query(sort: \RecipeCollection.createdAt) private var collections: [RecipeCollection]
    @Query private var pantryItems: [PantryItem]

    @State private var searchText = ""
    @State private var selectedFilter: String?
    @State private var sortOrder: SortOrder = .recentlySaved
    @State private var isShowingEditor = false
    @State private var isShowingImport = false
    @State private var isNamingCollection = false
    @State private var newCollectionName = ""

    enum SortOrder: String, CaseIterable {
        case recentlySaved = "Recently saved"
        case alphabetical = "A to Z"
        case quickest = "Quickest first"
    }

    /// Special chips that aren't tags.
    private static let cookedBeforeFilter = "Cooked before"
    private static let needsCleanupFilter = "Needs cleanup"

    /// Version children stay hidden; they're reachable from their parent's detail screen.
    private var libraryRecipes: [Recipe] {
        allRecipes.filter { $0.parentRecipe == nil }
    }

    private var filterChips: [String] {
        var chips: [String] = []
        if libraryRecipes.contains(where: { !$0.cookSessions(in: context).isEmpty }) {
            chips.append(Self.cookedBeforeFilter)
        }
        if libraryRecipes.contains(where: { ($0.importConfidence ?? 1) < 0.8 }) {
            chips.append(Self.needsCleanupFilter)
        }
        let tags = libraryRecipes.flatMap(\.tags)
        let counted = Dictionary(grouping: tags, by: { $0 }).mapValues(\.count)
        chips += counted.sorted { $0.value > $1.value }.map(\.key)
        return chips
    }

    private var visibleRecipes: [Recipe] {
        var recipes = libraryRecipes

        if let filter = selectedFilter {
            switch filter {
            case Self.cookedBeforeFilter:
                recipes = recipes.filter { !$0.cookSessions(in: context).isEmpty }
            case Self.needsCleanupFilter:
                recipes = recipes.filter { ($0.importConfidence ?? 1) < 0.8 }
            default:
                recipes = recipes.filter { $0.tags.contains(filter) }
            }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            recipes = recipes.filter { recipe in
                recipe.title.lowercased().contains(query)
                    || recipe.tags.contains { $0.lowercased().contains(query) }
                    || recipe.ingredients.contains { $0.name.lowercased().contains(query) }
            }
        }

        switch sortOrder {
        case .recentlySaved: return recipes
        case .alphabetical: return recipes.sorted { $0.title < $1.title }
        case .quickest: return recipes.sorted { $0.totalMinutes < $1.totalMinutes }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if !collections.isEmpty {
                        collectionsRow
                    }
                    ChipRow(labels: filterChips, selection: $selectedFilter)

                    if visibleRecipes.isEmpty {
                        EmptyStateView(
                            icon: "book",
                            title: searchText.isEmpty ? "No recipes yet" : "Nothing matches",
                            message: searchText.isEmpty
                                ? "Import your first recipe from TikTok, Instagram, or any website — or add one yourself."
                                : "Try a different search or clear the filter.",
                            actionLabel: searchText.isEmpty ? "Add a recipe" : nil,
                            action: searchText.isEmpty ? { isShowingEditor = true } : nil
                        )
                    } else {
                        LazyVStack(spacing: Theme.Spacing.md) {
                            ForEach(visibleRecipes) { recipe in
                                NavigationLink(value: recipe) {
                                    let match = PantryMatcher.match(recipe: recipe, pantry: pantryItems)
                                    RecipeCard(
                                        recipe: recipe,
                                        pantryMatch: (match.ownedCount, match.totalCount)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                    }
                }
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Recipes")
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .navigationDestination(for: RecipeCollection.self) { collection in
                CollectionDetailView(collection: collection)
            }
            .searchable(text: $searchText, prompt: "creamy chicken thing with lemon…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        Divider()
                        Button("New collection", systemImage: "folder.badge.plus") {
                            isNamingCollection = true
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Import from link or screenshot", systemImage: "link") {
                            isShowingImport = true
                        }
                        Button("Create manually", systemImage: "square.and.pencil") {
                            isShowingEditor = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingEditor) {
                RecipeEditorView(recipe: nil)
            }
            .sheet(isPresented: $isShowingImport, onDismiss: { router.pendingImportURL = nil }) {
                ImportRecipeView(initialURL: router.pendingImportURL)
            }
            .onAppear(perform: handlePendingImport)
            .onChange(of: router.pendingAction) { handlePendingImport() }
            .alert("New collection", isPresented: $isNamingCollection) {
                TextField("Name", text: $newCollectionName)
                Button("Create") {
                    let trimmed = newCollectionName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        context.insert(RecipeCollection(name: trimmed))
                    }
                    newCollectionName = ""
                }
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
        }
    }

    private func handlePendingImport() {
        if router.pendingAction == .importRecipe {
            router.pendingAction = nil
            isShowingImport = true
        }
    }

    private var collectionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(collections) { collection in
                    NavigationLink(value: collection) {
                        VStack(alignment: .leading, spacing: 2) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Theme.Colors.accent)
                            Text(collection.name)
                                .font(.gluttCaption.weight(.semibold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            Text("^[\(collection.recipes.count) recipe](inflect: true)")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(Theme.Spacing.sm)
                        .frame(width: 120, alignment: .leading)
                        .background(Theme.Colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
}

extension Recipe {
    /// Cook sessions for this recipe, newest first.
    func cookSessions(in context: ModelContext) -> [CookSession] {
        let descriptor = FetchDescriptor<CookSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let sessions = (try? context.fetch(descriptor)) ?? []
        return sessions.filter { $0.recipe === self }
    }
}
