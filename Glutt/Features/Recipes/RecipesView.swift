import SwiftData
import SwiftUI

/// The recipe library, "Feed" design: a cream home with a stat header, sort
/// menu (protein ratio, pantry coverage, …), ask/search pill, filter chips,
/// a "ready to cook tonight" hero, and big single-column recipe cards.
struct RecipesView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query(sort: \Recipe.createdAt, order: .reverse) private var allRecipes: [Recipe]
    @Query private var pantryItems: [PantryItem]
    @Query private var cookHistory: [CookSession]
    @Query private var mealPlans: [MealPlan]
    /// Every collection that still exists, so a plan's link can be checked
    /// against reality before it is followed. See `plannedRecipeIDs`.
    @Query private var collections: [RecipeCollection]

    // Heterogeneous on purpose: the feed pushes recipes, the chef rail pushes chefs.
    @State private var navPath = NavigationPath()
    /// Cards in this stack grow into their detail screen instead of sliding.
    @Namespace private var zoomNamespace
    @State private var zoomSource = ZoomSource()
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var filter: HomeFilter = .all
    @State private var sort: HomeSort = .newest
    @State private var isShowingEditor = false
    @State private var isShowingImport = false
    @State private var isShowingSettings = false
    @State private var isShowingBasics = false
    @State private var isShowingCollections = false
    @State private var isPlanningWeek = false
    @State private var isRequestingHowTo = false
    @State private var isNamingCollection = false
    @State private var newCollectionName = ""
    @State private var aiHeadline: String?
    @State private var aiResults: [AskGlutt.RankedResult]?
    @State private var aiQuery = ""
    @State private var isRanking = false

    /// Quick filters — narrow the list. Sorting lives in the header menu.
    enum HomeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case ready = "Ready now"
        case quick = "Under 30 min"
        case favorites = "Favorites"
        var id: String { rawValue }
    }

    /// Library sort. Nutrition sorts use per-serving cal/protein (stored, caption, or estimate).
    enum HomeSort: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case ready = "Ready to cook"
        case proteinRatio = "Best protein ratio"
        case mostProtein = "Most protein"
        case fewestCalories = "Fewest calories"
        case quickest = "Quickest"
        case alphabetical = "A–Z"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .newest: "clock"
            case .ready: "refrigerator"
            case .proteinRatio: "chart.bar.fill"
            case .mostProtein: "bolt.fill"
            case .fewestCalories: "flame"
            case .quickest: "timer"
            case .alphabetical: "textformat"
            }
        }
    }

    // MARK: - Derived data

    /// Top-level, non-lesson recipes (versions + Cooking Basics stay out of the
    /// feed). Bundled chef and restaurant dishes stay out too until you favorite
    /// one from its detail screen, which is what saves it to your library.
    private var libraryRecipes: [Recipe] {
        allRecipes.filter {
            $0.parentRecipe == nil && !$0.isCookingBasic && (!$0.isCuratedRecipe || $0.isFavorite)
        }
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

    /// Dinners that belong to a planned week.
    ///
    /// They stay in `libraryRecipes`, so search still finds them and the "ready
    /// tonight" hero can still pick one, and they are held out of the flat list
    /// below, where the week rail already shows them as the set they are. Listing
    /// them twice would be worse than either.
    private var plannedRecipeIDs: Set<PersistentIdentifier> {
        // Only collections that genuinely still exist.
        //
        // This is the line that crashed the app on launch after somebody
        // deleted a planned week's collection. `MealPlan.collection` has no
        // inverse and so no delete rule, which leaves the plan pointing at a
        // deleted row, and reading `.recipes` through it takes the process
        // down. `WeekPlanRail` was given the same guard when this first
        // happened and this second reader was missed, which is the argument for
        // the guard living in one place rather than at each call site.
        let live = Set(collections.map(\.persistentModelID))
        return Set(
            mealPlans
                .compactMap { plan -> RecipeCollection? in
                    guard let collection = plan.collection,
                          live.contains(collection.persistentModelID) else { return nil }
                    return collection
                }
                .flatMap { $0.recipes }
                .map(\.persistentModelID))
    }

    private var visibleRecipes: [Recipe] {
        var recipes = libraryRecipes
        if filter != .favorites {
            // Favourites is the exception: someone who deliberately starred a
            // planned dinner is asking to see it in a list of starred things.
            let planned = plannedRecipeIDs
            recipes = recipes.filter { !planned.contains($0.persistentModelID) }
        }
        switch filter {
        case .all:
            break
        case .ready:
            // Keep dishes you can mostly cook tonight (≥70% pantry coverage).
            recipes = recipes.filter { match($0).coverage >= 0.7 || match($0).totalCount == 0 }
        case .quick:
            recipes = recipes.filter { $0.estimatedMinutes <= 30 }
        case .favorites:
            recipes = recipes.filter(\.isFavorite)
        }
        return sorted(recipes)
    }

    private func sorted(_ recipes: [Recipe]) -> [Recipe] {
        switch sort {
        case .newest:
            return recipes.sorted { $0.createdAt > $1.createdAt }
        case .ready:
            return recipes.sorted {
                let a = match($0).coverage, b = match($1).coverage
                if a != b { return a > b }
                return $0.createdAt > $1.createdAt
            }
        case .proteinRatio:
            return recipes.sorted {
                let a = proteinPerCalorie($0), b = proteinPerCalorie($1)
                if a != b { return a > b }
                return proteinPerServing($0) > proteinPerServing($1)
            }
        case .mostProtein:
            return recipes.sorted { proteinPerServing($0) > proteinPerServing($1) }
        case .fewestCalories:
            return recipes.sorted {
                let a = caloriesPerServing($0), b = caloriesPerServing($1)
                // Unknown nutrition sinks to the bottom.
                switch (a, b) {
                case (nil, nil): return $0.createdAt > $1.createdAt
                case (nil, _): return false
                case (_, nil): return true
                case let (x?, y?): return x < y
                }
            }
        case .quickest:
            return recipes.sorted {
                let a = $0.estimatedMinutes, b = $1.estimatedMinutes
                if a == 0 && b == 0 { return $0.createdAt > $1.createdAt }
                if a == 0 { return false }
                if b == 0 { return true }
                return a < b
            }
        case .alphabetical:
            return recipes.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    private func nutrition(for recipe: Recipe) -> RecipeNutrition? {
        RecipeNutrition.resolve(for: recipe, servings: 1)
    }

    private func proteinPerServing(_ recipe: Recipe) -> Int {
        nutrition(for: recipe)?.perServingProtein ?? 0
    }

    private func caloriesPerServing(_ recipe: Recipe) -> Int? {
        nutrition(for: recipe)?.perServingCalories
    }

    /// Grams of protein per calorie — higher is leaner / better ratio. Missing → -1.
    private func proteinPerCalorie(_ recipe: Recipe) -> Double {
        guard let n = nutrition(for: recipe), n.perServingCalories > 0 else { return -1 }
        return Double(n.perServingProtein) / Double(n.perServingCalories)
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
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
                    .zoomedFrom(zoomSource.card(for: recipe.persistentModelID))
            }
            .navigationDestination(for: Chef.self) { ChefDetailView(chef: $0) }
            .navigationDestination(for: Restaurant.self) { RestaurantDetailView(restaurant: $0) }
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
                    CookingBasicsView { recipe in isShowingBasics = false; open(recipe) }
                }
            }
            .sheet(isPresented: $isShowingCollections) {
                CollectionsListSheet()
            }
            .sheet(isPresented: $isPlanningWeek) {
                WeekPlanView { collection in
                    // Straight into the week you just saved, which is where the
                    // five recipes and the reason for them live.
                    zoomSource.card = nil
                    navPath = NavigationPath([collection])
                }
            }
            .sheet(isPresented: $isRequestingHowTo) {
                RequestHowToSheet { recipe in open(recipe) }
            }
            .onAppear(perform: handlePendingImport)
            .onChange(of: router.pendingImportURL) { handlePendingImport() }
            .onChange(of: router.recipeToOpenID) { openRequestedRecipe() }
            .onAppear(perform: openRequestedRecipe)
            .onAppear {
                if router.openFirstRecipeOnLaunch, let first = libraryRecipes.first {
                    router.openFirstRecipeOnLaunch = false
                    open(first)
                }
                // Deferred a runloop turn: a path set while the stack is still
                // laying itself out gets discarded, which is why these hooks
                // silently did nothing.
                if let slug = router.chefToOpenOnLaunch, let chef = ChefContent.chef(id: slug) {
                    router.chefToOpenOnLaunch = nil
                    Task { @MainActor in navPath = NavigationPath([chef]) }
                }
                if let slug = router.restaurantToOpenOnLaunch,
                   let restaurant = RestaurantContent.restaurant(id: slug) {
                    router.restaurantToOpenOnLaunch = nil
                    Task { @MainActor in navPath = NavigationPath([restaurant]) }
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
        // On the stack itself, so pushed screens inherit it too — a card inside
        // a chef page has to share the namespace its destination reads.
        .zoomTransitions(zoomNamespace, source: zoomSource)
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
                Menu {
                    ForEach(HomeSort.allCases) { option in
                        Button {
                            Haptics.selection()
                            sort = option
                        } label: {
                            if sort == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Label(option.rawValue, systemImage: option.systemImage)
                            }
                        }
                    }
                } label: {
                    circleButton(
                        fill: sort == .newest ? Theme.Colors.card : Theme.Colors.accent.opacity(0.12),
                        bordered: true
                    ) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(sort == .newest ? Color(hex: 0x3A342C) : Theme.Colors.accent)
                    }
                }

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
                    // The five dinners land here as ordinary recipes, so the
                    // way in sits with everything else that adds to the shelf.
                    Button("Plan a week of dinners", systemImage: "calendar") { isPlanningWeek = true }
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
            // Chips sit under search — above the hero — so filter/sort isn't
            // buried below a tall "ready tonight" card.
            filterChips
                .padding(.top, 4)
                .padding(.bottom, 14)
            if let hero = heroRecipe {
                heroCard(hero)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }
            // Above the chef and restaurant rails: a week the cook planned
            // themselves, with a shop still open against it, outranks browsing.
            WeekPlanRail()
            if RestaurantContent.isEnabled {
                RestaurantRail()
            }
            if ChefContent.isEnabled {
                ChefRail()
            }
            SectionLabel(text: listSectionTitle)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            LazyVStack(spacing: 16) {
                ForEach(visibleRecipes) { recipe in
                    NavigationLink(value: recipe) {
                        FeedRecipeCard(recipe: recipe, match: match(recipe))
                    }
                    .zoomCard(ZoomCardID(recipe.persistentModelID, slot: "feed"))
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
            // Its own slot: this dish is usually also a row in the list below,
            // and the zoom has to start from whichever one you pressed.
            .zoomCard(ZoomCardID(recipe.persistentModelID, slot: "hero"))
            .hapticTap()
        }
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

    private var listSectionTitle: String {
        if sort != .newest { return sort.rawValue }
        switch filter {
        case .all: return "Your recipes"
        case .ready: return "Ready now"
        case .quick: return "Under 30 min"
        case .favorites: return "Favorites"
        }
    }

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
                        .zoomCard(ZoomCardID(result.recipe.persistentModelID, slot: "search"))
                        .hapticTap()
                    }
                } else {
                    ForEach(results, id: \.recipe.persistentModelID) { result in
                        NavigationLink(value: result.recipe) {
                            FeedRecipeCard(recipe: result.recipe, match: match(result.recipe))
                        }
                        .zoomCard(ZoomCardID(result.recipe.persistentModelID, slot: "search"))
                        .hapticTap()
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
        open(recipe)
        router.recipeToOpenID = nil
    }

    /// Opens a recipe with no card behind it (deep link, launch hook, a sheet
    /// handing one over). Forgetting the last pressed card keeps these as plain
    /// pushes instead of growing out of something unrelated.
    private func open(_ recipe: Recipe) {
        zoomSource.card = nil
        navPath = NavigationPath([recipe])
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
