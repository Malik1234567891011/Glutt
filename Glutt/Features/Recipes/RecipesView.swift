import SwiftData
import SwiftUI

/// The recipe library: search, filters, collections, and the recipe list.
struct RecipesView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query(sort: \Recipe.createdAt, order: .reverse) private var allRecipes: [Recipe]
    @Query(sort: \RecipeCollection.createdAt) private var collections: [RecipeCollection]
    @Query private var pantryItems: [PantryItem]
    @Query private var cookHistory: [CookSession]

    @State private var navPath: [Recipe] = []
    @State private var searchText = ""
    @State private var selectedFilter: String?
    @State private var sortOrder: SortOrder = .recentlySaved
    @State private var isGrid = false
    @State private var isShowingEditor = false
    @State private var isShowingImport = false
    @State private var isNamingCollection = false
    @State private var newCollectionName = ""
    @State private var segment: RecipeSegment = .myRecipes
    @State private var discoverModel = DiscoverFeedViewModel()
    @State private var aiHeadline: String?
    @State private var aiResults: [AskGlutt.RankedResult]?
    /// The trimmed query the AI answer corresponds to (for staleness checks).
    @State private var aiQuery = ""
    @State private var isRanking = false

    enum RecipeSegment: Int, CaseIterable { case myRecipes, discover }

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
        if !cookHistory.isEmpty {
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

    /// Tag-driven categories: the most-used real tags, each with a representative recipe.
    private var categoryTags: [(tag: String, recipe: Recipe)] {
        let special: Set = [Self.cookedBeforeFilter, Self.needsCleanupFilter]
        return filterChips
            .filter { !special.contains($0) }
            .prefix(8)
            .compactMap { tag in
                libraryRecipes.first(where: { $0.tags.contains(tag) }).map { (tag, $0) }
            }
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

        switch sortOrder {
        case .recentlySaved: return recipes
        case .alphabetical: return recipes.sorted { $0.title < $1.title }
        case .quickest: return recipes.sorted { $0.estimatedMinutes < $1.estimatedMinutes }
        }
    }

    /// Simple taste hint for the suggested feed: the most common tags across saved recipes.
    private var tasteTags: [String] {
        let counts = libraryRecipes.flatMap { $0.tags }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
    }

    /// Semantic search: "that creamy lemon chicken thing" works.
    /// Results carry "why it matched" reasons shown under each card.
    private var searchResults: [RecipeSearchEngine.SearchResult] {
        RecipeSearchEngine.search(query: searchText, recipes: visibleRecipes, sessions: cookHistory)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if segment == .myRecipes {
                        if !collections.isEmpty {
                            collectionsRow
                        }
                        if !categoryTags.isEmpty {
                            categoryRow
                        }
                        ChipRow(labels: filterChips, selection: $selectedFilter)
                    }
                    SegmentedTabs(
                        titles: ["My Recipes", "Discover"],
                        selection: Binding(
                            get: { segment.rawValue },
                            set: { segment = RecipeSegment(rawValue: $0) ?? .myRecipes }
                        )
                    )
                    .padding(.horizontal, Theme.Spacing.md)

                    if segment == .discover {
                        DiscoverView(model: discoverModel, tasteTags: tasteTags)
                    } else if searchText.isEmpty {
                        if visibleRecipes.isEmpty {
                            EmptyStateView(
                                icon: "book",
                                title: "No recipes yet",
                                message: "Import your first recipe from TikTok, Instagram, or any website — or add one yourself.",
                                actionLabel: "Add a recipe",
                                action: { isShowingEditor = true }
                            )
                        } else {
                            countHeader
                            if isGrid {
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.md),
                                                    GridItem(.flexible(), spacing: Theme.Spacing.md)],
                                          spacing: Theme.Spacing.md) {
                                    ForEach(visibleRecipes) { recipe in
                                        recipeLink(recipe, reasons: [], compact: true)
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                            } else {
                                LazyVStack(spacing: Theme.Spacing.md) {
                                    ForEach(visibleRecipes) { recipe in
                                        recipeLink(recipe, reasons: [])
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                    } else {
                        let results = searchResults
                        if results.isEmpty {
                            discoverHandoff
                        } else {
                            if isRanking {
                                rankingIndicator
                            }
                            if let aiResults, aiQuery == searchText.trimmingCharacters(in: .whitespaces) {
                                if let aiHeadline, !aiHeadline.isEmpty {
                                    searchHeadlineBanner(aiHeadline)
                                }
                                LazyVStack(spacing: Theme.Spacing.md) {
                                    ForEach(aiResults, id: \.recipe.persistentModelID) { result in
                                        recipeLink(result.recipe, reasons: aiReasons(for: result))
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                            } else {
                                LazyVStack(spacing: Theme.Spacing.md) {
                                    ForEach(results, id: \.recipe.persistentModelID) { result in
                                        recipeLink(result.recipe, reasons: result.reasons)
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.md)
            }
            .contentMargins(.bottom, GluttTabBar.reservedHeight, for: .scrollContent)
            .background(Theme.Colors.background)
            .navigationTitle("Recipes")
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .navigationDestination(for: RecipeCollection.self) { collection in
                CollectionDetailView(collection: collection)
            }
            .searchable(text: $searchText, prompt: "creamy chicken thing with lemon…")
            .onSubmit(of: .search) {
                if segment == .discover {
                    Task { await discoverModel.search(searchText) }
                } else {
                    runAIRanking()
                }
            }
            .onChange(of: searchText) {
                // Editing the query invalidates a stale AI answer.
                if searchText.trimmingCharacters(in: .whitespaces) != aiQuery {
                    aiResults = nil
                    aiHeadline = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
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
                        Divider()
                        Button("New collection", systemImage: "folder.badge.plus") {
                            isNamingCollection = true
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
            .onChange(of: router.recipeToOpenID) { openRequestedRecipe() }
            .onAppear(perform: openRequestedRecipe)
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

    /// Shown when the library has nothing matching the query — points the user to Discover,
    /// carrying the same query into the Discover feed.
    private var discoverHandoff: some View {
        EmptyStateView(
            icon: "sparkle.magnifyingglass",
            title: "Nothing like that in your kitchen yet",
            message: "You don't have a recipe for \"\(searchText)\" — but Discover probably does. Want me to go look?",
            actionLabel: "Find it in Discover",
            action: {
                Haptics.impact(.light)
                segment = .discover
                Task { await discoverModel.search(searchText) }
            }
        )
    }

    private func runAIRanking() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let results = searchResults
        guard !query.isEmpty, !results.isEmpty else { return }
        Haptics.impact(.light)
        isRanking = true
        aiResults = nil
        aiHeadline = nil
        Task {
            let outcome = await AskGlutt.rankSearch(query: query, results: results, pantry: pantryItems)
            // Only apply if the query hasn't changed since we fired.
            if searchText.trimmingCharacters(in: .whitespaces) == query {
                aiResults = outcome.results
                aiHeadline = outcome.headline
                aiQuery = query
            }
            isRanking = false
        }
    }

    private func aiReasons(for result: AskGlutt.RankedResult) -> [String] {
        var chips: [String] = []
        if let badge = result.badge, !badge.isEmpty { chips.append(badge) }
        chips.append(contentsOf: result.reasons)
        return Array(chips.prefix(3))
    }

    private var rankingIndicator: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView()
            Text("Glutt\u{2019}s thinking\u{2026}")
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func searchHeadlineBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Ph.sparkle.regular
                .resizable().scaledToFit().frame(width: 18, height: 18)
                .foregroundStyle(Theme.Colors.accent)
            Text(text)
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func recipeLink(_ recipe: Recipe, reasons: [String], compact: Bool = false) -> some View {
        NavigationLink(value: recipe) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                let match = PantryMatcher.match(recipe: recipe, pantry: pantryItems)
                RecipeCard(
                    recipe: recipe,
                    pantryMatch: (match.ownedCount, match.totalCount),
                    compact: compact
                )
                if !reasons.isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.accent)
                        ForEach(reasons, id: \.self) { reason in
                            Chip(label: reason)
                                .fixedSize()
                        }
                    }
                    .padding(.leading, Theme.Spacing.xs)
                }
            }
        }
        .buttonStyle(.plain)
        .hapticTap()
    }

    private func handlePendingImport() {
        if router.pendingAction == .importRecipe {
            router.pendingAction = nil
            isShowingImport = true
        }
    }

    private func openRequestedRecipe() {
        guard let id = router.recipeToOpenID,
              let recipe = allRecipes.first(where: { $0.persistentModelID == id }) else { return }
        navPath = [recipe]
        router.recipeToOpenID = nil
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
                    .hapticTap()
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(categoryTags, id: \.tag) { item in
                    CategoryCircle(
                        label: item.tag,
                        isActive: selectedFilter == item.tag,
                        action: { selectedFilter = (selectedFilter == item.tag) ? nil : item.tag }
                    ) {
                        RecipeImageView(recipe: item.recipe)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }

    private var countHeader: some View {
        HStack {
            Text("^[\(visibleRecipes.count) recipe](inflect: true)")
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Button { Haptics.impact(.light); isGrid.toggle() } label: {
                Ph.squaresFour.fill.resizable().scaledToFit().frame(width: 18, height: 18)
                    .foregroundStyle(isGrid ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
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
