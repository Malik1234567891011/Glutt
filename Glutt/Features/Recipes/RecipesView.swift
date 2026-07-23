import SwiftData
import SwiftUI

/// The recipe library, "Feed" design: a cream home with a stat header, an
/// ask/search pill, a "ready to cook tonight" hero, quick filter chips, and big
/// single-column recipe cards. Source: `Glutt Main Page.dc.html`, direction B.
struct RecipesView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query(sort: \Recipe.createdAt, order: .reverse) private var allRecipes: [Recipe]
    @Query private var pantryItems: [PantryItem]
    @Query private var cookHistory: [CookSession]

    @State private var navPath: [Recipe] = []
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var filter: HomeFilter = .all
    @State private var isShowingEditor = false
    @State private var isShowingImport = false
    @State private var isShowingSettings = false
    @State private var isShowingBasics = false
    @State private var isShowingCollections = false
    @State private var isRequestingHowTo = false
    @State private var isNamingCollection = false
    @State private var newCollectionName = ""
    @State private var aiHeadline: String?
    @State private var aiResults: [AskGlutt.RankedResult]?
    @State private var aiQuery = ""
    @State private var isRanking = false

    /// The five fixed quick filters from the mock.
    enum HomeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case ready = "Ready now"
        case quick = "Under 30 min"
        case protein = "High protein"
        case recent = "Recent"
        var id: String { rawValue }
    }

    // MARK: - Derived data

    /// Top-level, non-lesson recipes (versions + Cooking Basics stay out of the feed).
    private var libraryRecipes: [Recipe] {
        allRecipes.filter { $0.parentRecipe == nil && !$0.isCookingBasic }
    }

    private var basicsLessons: [Recipe] {
        allRecipes.filter { $0.parentRecipe == nil && $0.isCookingBasic }
            .sorted { $0.title < $1.title }
    }

    /// Distinct recipes that have been cooked at least once.
    private var cookedCount: Int {
        Set(cookHistory.compactMap { $0.recipe?.persistentModelID }).count
    }

    private func match(_ recipe: Recipe) -> PantryMatcher.MatchResult {
        PantryMatcher.match(recipe: recipe, pantry: pantryItems)
    }

    /// "Ready to cook tonight": the best pantry coverage, ties broken by recency.
    private var heroRecipe: Recipe? {
        libraryRecipes.max { a, b in
            let ma = match(a), mb = match(b)
            if ma.coverage != mb.coverage { return ma.coverage < mb.coverage }
            return a.createdAt < b.createdAt
        }
    }

    private var visibleRecipes: [Recipe] {
        var recipes = libraryRecipes
        switch filter {
        case .all:
            break
        case .ready:
            recipes = recipes.sorted { match($0).coverage > match($1).coverage }
        case .quick:
            recipes = recipes.filter { $0.estimatedMinutes <= 30 }
        case .protein:
            recipes = recipes.sorted { proteinPerServing($0) > proteinPerServing($1) }
        case .recent:
            break // already sorted by createdAt desc
        }
        return recipes
    }

    private func proteinPerServing(_ recipe: Recipe) -> Int {
        recipe.proteinGrams ?? NutritionEstimator.estimate(for: recipe)?.proteinGrams ?? 0
    }

    private var searchResults: [RecipeSearchEngine.SearchResult] {
        RecipeSearchEngine.search(query: searchText, recipes: libraryRecipes, sessions: cookHistory)
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        searchPill
                            .padding(.horizontal, 20)
                            .padding(.top, 6)
                            .padding(.bottom, 16)

                        if trimmedQuery.isEmpty {
                            feedContent
                        } else {
                            searchContent
                        }
                    }
                    .padding(.bottom, GluttTabBar.reservedHeight + 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.Colors.background)
            .navigationBarHidden(true)
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .navigationDestination(for: RecipeCollection.self) { CollectionDetailView(collection: $0) }
            .onChange(of: searchText) {
                if trimmedQuery != aiQuery { aiResults = nil; aiHeadline = nil }
            }
            .sheet(isPresented: $isShowingEditor) { RecipeEditorView(recipe: nil) }
            .sheet(isPresented: $isShowingImport, onDismiss: { router.pendingImportURL = nil }) {
                ImportRecipeView(initialURL: router.pendingImportURL)
            }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .sheet(isPresented: $isShowingBasics) {
                NavigationStack {
                    CookingBasicsView { recipe in isShowingBasics = false; navPath = [recipe] }
                }
            }
            .sheet(isPresented: $isShowingCollections) {
                CollectionsListSheet()
            }
            .sheet(isPresented: $isRequestingHowTo) {
                RequestHowToSheet { recipe in navPath = [recipe] }
            }
            .onAppear(perform: handlePendingImport)
            .onChange(of: router.pendingImportURL) { handlePendingImport() }
            .onChange(of: router.recipeToOpenID) { openRequestedRecipe() }
            .onAppear(perform: openRequestedRecipe)
            .onAppear {
                if router.openFirstRecipeOnLaunch, let first = libraryRecipes.first {
                    router.openFirstRecipeOnLaunch = false
                    navPath = [first]
                }
            }
            .alert("New collection", isPresented: $isNamingCollection) {
                TextField("Name", text: $newCollectionName)
                Button("Create") {
                    let trimmed = newCollectionName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { context.insert(RecipeCollection(name: trimmed)) }
                    newCollectionName = ""
                }
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(libraryRecipes.count) saved · \(cookedCount) cooked")
                    .font(BrandFont.nunito(12, 800))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.accent)
                Text("Your recipes")
                    .font(BrandFont.bricolage(31, 700))
                    .foregroundStyle(Theme.Colors.heading)
            }
            Spacer()
            HStack(spacing: 9) {
                Button {
                    Haptics.impact(.light); isShowingSettings = true
                } label: {
                    circleButton(fill: Theme.Colors.card, bordered: true) {
                        MS.settings.sized(22).foregroundStyle(Color(hex: 0x3A342C))
                    }
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Import from link or screenshot", systemImage: "link") { isShowingImport = true }
                    Button("Create manually", systemImage: "square.and.pencil") { isShowingEditor = true }
                    Divider()
                    Button("Cooking basics", systemImage: "book") { isShowingBasics = true }
                    Button("Browse collections", systemImage: "folder") { isShowingCollections = true }
                    Button("New collection", systemImage: "folder.badge.plus") { isNamingCollection = true }
                } label: {
                    circleButton(fill: Theme.Colors.accent, bordered: false) {
                        MS.add.sized(24).foregroundStyle(Theme.Colors.creamText)
                    }
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func circleButton(fill: Color, bordered: Bool, @ViewBuilder _ glyph: () -> some View) -> some View {
        glyph()
            .frame(width: 42, height: 42)
            .background(Circle().fill(fill))
            .overlay(bordered ? Circle().strokeBorder(Theme.Colors.textPrimary.opacity(0.07), lineWidth: 1.5) : nil)
            .shadow(color: Theme.Colors.textPrimary.opacity(bordered ? 0.05 : 0.12), radius: bordered ? 10 : 18, y: bordered ? 3 : 8)
    }

    // MARK: - Search pill

    private var searchPill: some View {
        HStack(spacing: 11) {
            MS.search.sized(22).foregroundStyle(Theme.Colors.muted)
            TextField("that creamy chicken thing…", text: $searchText)
                .font(BrandFont.nunito(15, 600))
                .foregroundStyle(Theme.Colors.heading)
                .tint(Theme.Colors.accent)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit(runAIRanking)
            if trimmedQuery.isEmpty {
                MS.autoAwesomeFill.sized(21).foregroundStyle(Theme.Colors.accent)
            } else {
                Button { searchText = ""; searchFocused = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 50)
        .background(Capsule().fill(Theme.Colors.card))
        .overlay(Capsule().strokeBorder(Theme.Colors.textPrimary.opacity(0.07), lineWidth: 1.5))
        .shadow(color: Theme.Colors.textPrimary.opacity(0.05), radius: 16, y: 5)
    }

    // MARK: - Feed content

    @ViewBuilder
    private var feedContent: some View {
        if libraryRecipes.isEmpty {
            EmptyStateView(
                icon: "book",
                title: "No recipes yet",
                message: "Import your first recipe from TikTok, Instagram, or any website, or add one from the plus button.",
                actionLabel: "Add a recipe",
                action: { isShowingEditor = true }
            )
            .padding(.top, 40)
        } else {
            if let hero = heroRecipe {
                heroCard(hero)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }
            filterChips
                .padding(.top, 16)
            SectionLabel(text: "Saved this week")
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            LazyVStack(spacing: 16) {
                ForEach(visibleRecipes) { recipe in
                    NavigationLink(value: recipe) {
                        FeedRecipeCard(recipe: recipe, match: match(recipe))
                    }
                    .buttonStyle(.plain)
                    .hapticTap()
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Hero

    private func heroCard(_ recipe: Recipe) -> some View {
        let m = match(recipe)
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Ready to cook tonight")
            NavigationLink(value: recipe) {
                ZStack(alignment: .bottomLeading) {
                    RecipeImageView(recipe: recipe)
                        .frame(height: 230)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
                    LinearGradient(
                        colors: [Color(hex: 0x140F0A).opacity(0.86), Color(hex: 0x140F0A).opacity(0.30), .clear],
                        startPoint: .bottom, endPoint: .top
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
                    .allowsHitTesting(false)

                    heroHeart(recipe)

                    VStack(alignment: .leading, spacing: 9) {
                        heroPantryChip(m)
                        Text(recipe.title)
                            .font(BrandFont.bricolage(24, 700))
                            .foregroundStyle(Theme.Colors.creamText)
                            .lineLimit(2)
                        HStack(spacing: 10) {
                            HStack(spacing: 6) {
                                MS.skilletFill.sized(18).foregroundStyle(Theme.Colors.creamText)
                                Text("Cook").font(BrandFont.nunito(15, 800)).foregroundStyle(Theme.Colors.creamText)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(Capsule().fill(Theme.Colors.accent))
                            HStack(spacing: 5) {
                                MS.schedule.sized(16)
                                Text("\(recipe.timeLabel) · \(recipe.difficulty.label)")
                                    .font(BrandFont.nunito(13, 700))
                            }
                            .foregroundStyle(Color(hex: 0xEAE0D2))
                        }
                    }
                    .padding(16)
                }
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
                .shadow(color: Theme.Colors.textPrimary.opacity(0.16), radius: 20, y: 12)
            }
            .buttonStyle(.plain)
            .hapticTap()
        }
    }

    private func heroHeart(_ recipe: Recipe) -> some View {
        Button {
            Haptics.impact(.light); recipe.isFavorite.toggle()
        } label: {
            (recipe.isFavorite ? MS.favoriteFill : MS.favorite).sized(19)
                .foregroundStyle(Theme.Colors.tomato)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.Colors.card))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(12)
    }

    private func heroPantryChip(_ m: PantryMatcher.MatchResult) -> some View {
        let haveAll = m.totalCount > 0 && m.ownedCount >= m.totalCount
        return HStack(spacing: 5) {
            MS.checkCircleFill.sized(14).foregroundStyle(Theme.Colors.brightAccent)
            Text(haveAll ? "You have all ^[\(m.totalCount) ingredient](inflect: true)"
                         : "You have \(m.ownedCount) of \(m.totalCount) ingredients")
                .font(BrandFont.nunito(11, 800))
                .foregroundStyle(Theme.Colors.greenTint)
        }
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Capsule().fill(Theme.Colors.accent))
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeFilter.allCases) { f in
                    let active = filter == f
                    Button {
                        Haptics.selection(); filter = f
                    } label: {
                        Text(f.rawValue)
                            .font(BrandFont.nunito(13, active ? 800 : 700))
                            .foregroundStyle(active ? Theme.Colors.creamText : Color(hex: 0x3A342C))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Capsule().fill(active ? Theme.Colors.accent : Theme.Colors.card))
                            .overlay(active ? nil : Capsule().strokeBorder(Theme.Colors.textPrimary.opacity(0.08), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchContent: some View {
        let results = searchResults
        if results.isEmpty {
            EmptyStateView(
                icon: "sparkle.magnifyingglass",
                title: "Nothing like that in your kitchen yet",
                message: "You don't have a recipe for \"\(searchText)\", but Discover probably does.",
                actionLabel: "Go to Discover",
                action: { Haptics.impact(.light); router.selectedTab = .discover }
            )
            .padding(.top, 24)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if isRanking {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Glutt\u{2019}s thinking\u{2026}")
                            .font(.gluttCaption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal, 20)
                }
                if let aiResults, aiQuery == trimmedQuery {
                    if let aiHeadline, !aiHeadline.isEmpty {
                        Text(aiHeadline)
                            .font(.gluttHeadline).foregroundStyle(Theme.Colors.heading)
                            .padding(.horizontal, 20)
                    }
                    ForEach(aiResults, id: \.recipe.persistentModelID) { result in
                        NavigationLink(value: result.recipe) {
                            FeedRecipeCard(recipe: result.recipe, match: match(result.recipe))
                        }
                        .buttonStyle(.plain).hapticTap()
                    }
                } else {
                    ForEach(results, id: \.recipe.persistentModelID) { result in
                        NavigationLink(value: result.recipe) {
                            FeedRecipeCard(recipe: result.recipe, match: match(result.recipe))
                        }
                        .buttonStyle(.plain).hapticTap()
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func runAIRanking() {
        let query = trimmedQuery
        let results = searchResults
        guard !query.isEmpty, !results.isEmpty else { return }
        Haptics.impact(.light)
        isRanking = true; aiResults = nil; aiHeadline = nil
        Task {
            let outcome = await AskGlutt.rankSearch(query: query, results: results, pantry: pantryItems)
            if trimmedQuery == query {
                aiResults = outcome.results; aiHeadline = outcome.headline; aiQuery = query
            }
            isRanking = false
        }
    }

    // MARK: - Routing helpers

    private func handlePendingImport() {
        if router.pendingImportURL != nil { isShowingImport = true }
    }

    private func openRequestedRecipe() {
        guard let id = router.recipeToOpenID,
              let recipe = allRecipes.first(where: { $0.persistentModelID == id }) else { return }
        navPath = [recipe]
        router.recipeToOpenID = nil
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
