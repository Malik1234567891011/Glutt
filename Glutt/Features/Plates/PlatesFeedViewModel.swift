import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class PlatesFeedViewModel {
    enum Phase: Equatable { case idle, loading, loaded, empty, failed(String) }

    struct Dependencies {
        var daily: () async throws -> PlatesResponse
        var search: (_ query: String, _ pageToken: String?) async throws -> PlatesResponse
        var save: (_ card: PlateCard, _ context: ModelContext) async throws -> Recipe
        var seed: () -> PlatesResponse
        /// Today's cached deck, or nil if none/stale (keyed by local date in `.live`).
        var cachedDeck: () -> PlatesResponse?
        var storeDeck: (PlatesResponse) -> Void
        /// One more page of the endless feed. Defaulted so existing callers
        /// (and tests) that don't paginate keep compiling unchanged.
        var feed: (_ pageToken: String?) async throws -> PlatesResponse = { _ in
            PlatesResponse(deckTitle: nil, recipes: [], nextPageToken: nil)
        }
        /// Cards judged in an earlier session. Defaulted to empty so tests get a
        /// deterministic deck without touching real user defaults.
        var seenIDs: () -> Set<String> = { [] }
        var recordSeen: (String) -> Void = { _ in }
        var forgetSeen: (String) -> Void = { _ in }
        /// Seam for the shuffle, so tests can assert on a stable order.
        var shuffle: ([PlateCard]) -> [PlateCard] = { $0.shuffled() }

        static let live = Dependencies(
            daily: { try await PlatesService.live.daily() },
            search: { try await PlatesService.live.search(query: $0, pageToken: $1) },
            save: { try await PlatesSaver.save(card: $0, into: $1) },
            seed: { PlatesSeedDeck.load() },
            cachedDeck: { PlatesDeckCache.today() },
            storeDeck: { PlatesDeckCache.store($0) },
            feed: { try await PlatesService.live.feed(pageToken: $0) },
            seenIDs: { PlatesSeenStore.ids() },
            recordSeen: { PlatesSeenStore.record($0) },
            forgetSeen: { PlatesSeenStore.forget($0) }
        )
    }

    private(set) var phase: Phase = .idle
    private(set) var recipes: [PlateCard] = []
    private(set) var index = 0
    private(set) var savedIDs: Set<String> = []
    private(set) var skippedIDs: Set<String> = []
    private(set) var savingID: String?
    private(set) var saveError: String?
    var deckTitle: String?

    private var nextPageToken: String?
    private var query = ""
    private var isExplore = false
    private var isLoadingMore = false
    /// True when the current deck is the bundled seed (network unavailable at
    /// load). Seed has no page cursor, so we keep trying to go live rather than
    /// dead-ending on ~9 offline cards. See `recoverToLiveIfNeeded`.
    private var isFallback = false
    private var isRecovering = false
    /// Filter context captured on the initial load, reused when appending pages.
    private var filterRules: [DietaryRule] = []
    private var filterAllergies: [String] = []
    private var filterSavedURLs: Set<String> = []
    /// Read once per load rather than per page: a card judged during THIS
    /// session is already gone from the deck, and re-reading would let the
    /// pagination filter fight the undo button.
    private var filterSeenIDs: Set<String> = []
    private let deps: Dependencies

    init(deps: Dependencies = .live) { self.deps = deps }

    var current: PlateCard? { recipes.indices.contains(index) ? recipes[index] : nil }

    func loadDaily(rules: [DietaryRule], allergies: [String], savedSourceURLs: Set<String>) async {
        isExplore = false
        deckTitle = "Discover"
        // Before the cache check below, so an offline open still counts as an
        // open — this measures the feature being used, not the network.
        Analytics.capture(.platesDeckViewed)
        filterRules = rules
        filterAllergies = allergies
        filterSavedURLs = savedSourceURLs
        filterSeenIDs = deps.seenIDs()

        // 1. Today's cached deck (instant, offline-friendly first page).
        if let cached = deps.cachedDeck() {
            applyDeck(cached, rules: rules, allergies: allergies, savedSourceURLs: savedSourceURLs, store: false)
            // Everything on the cached page may already have been judged in an
            // earlier session — that is the normal state for a cook who swipes
            // daily, not an edge case — so page forward rather than showing the
            // empty state over a deck that has plenty left in it.
            if phase == .empty { await fillUntilNonEmpty() }
            return
        }

        // 2. Network deck → cache the first page. Retry once on a cold-start
        // failure before falling back (the first request after launch often
        // loses a DNS/TLS race the retry then wins).
        phase = .loading
        do {
            let page = try await fetchDailyWithRetry()
            isFallback = false
            applyDeck(page, rules: rules, allergies: allergies, savedSourceURLs: savedSourceURLs, store: true)
            // If everything on page 1 was filtered out (all seen/saved/diet-
            // excluded) but more pages exist, pull more so we don't dead-end.
            if phase == .empty { await fillUntilNonEmpty() }
        } catch {
            // 3. Bundled seed fallback — but flag it so we keep trying to go live
            // instead of stranding the user on the offline cards.
            isFallback = true
            let seed = deps.seed()
            applyDeck(seed, rules: rules, allergies: allergies, savedSourceURLs: savedSourceURLs, store: false)
        }
    }

    /// Walks the cursor forward until a page survives filtering. Bounded, because
    /// a cook deep into the deck could otherwise chain fetches on a cold open
    /// while staring at a spinner — better to show the empty state and let the
    /// next open continue than to hang.
    private func fillUntilNonEmpty(maxPages: Int = 4) async {
        var pulled = 0
        while phase == .empty, pulled < maxPages, nextPageToken != nil {
            await loadMoreIfNeeded(currentIndex: 0)
            pulled += 1
        }
    }

    private func fetchDailyWithRetry() async throws -> PlatesResponse {
        do {
            return try await deps.daily()
        } catch {
            try? await Task.sleep(for: .milliseconds(600))
            return try await deps.daily()
        }
    }

    /// When we're stuck on the offline seed deck, quietly attempt to swap in the
    /// live feed as the user nears the end — so a transient launch-time network
    /// blip doesn't permanently cap Discover at ~9 cards.
    func recoverToLiveIfNeeded() async {
        guard isFallback, !isRecovering, !isLoadingMore else { return }
        isRecovering = true
        defer { isRecovering = false }
        guard let page = try? await deps.daily() else { return }
        isFallback = false
        deps.storeDeck(page)
        let fresh = freshCards(from: page)
        recipes.append(contentsOf: fresh)
        nextPageToken = page.nextPageToken
        if phase == .empty, !recipes.isEmpty { phase = .loaded }
    }

    /// Endless scroll: pulls the next page as the cook nears the end of what's
    /// loaded. Safe to call on every card appearance — it self-guards on the
    /// cursor, an in-flight fetch, and how close to the end we are.
    func loadMoreIfNeeded(currentIndex: Int) async {
        guard !isExplore, currentIndex >= recipes.count - 3 else { return }
        // On the offline seed deck there's no cursor — try to go live instead.
        if isFallback { await recoverToLiveIfNeeded(); return }
        guard !isLoadingMore, let token = nextPageToken else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await deps.feed(token)
            let fresh = freshCards(from: page)
            recipes.append(contentsOf: fresh)
            nextPageToken = page.nextPageToken
            if phase == .empty, !recipes.isEmpty { phase = .loaded }
        } catch {
            // Leave the cursor so a later appearance retries; never surfaces an
            // error mid-scroll.
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isExplore = true
        self.query = trimmed
        deckTitle = nil
        phase = .loading
        do {
            let page = try await deps.search(trimmed, nil)
            recipes = page.recipes
            index = 0
            nextPageToken = page.nextPageToken
            phase = page.recipes.isEmpty ? .empty : .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func showNext() async {
        guard !recipes.isEmpty else { return }
        if index < recipes.count - 1 { index += 1 }
        await prefetchIfNeeded()
    }

    func save(_ card: PlateCard, into context: ModelContext) async {
        acceptSavedCard(card)
        await persistSave(card, into: context)
    }

    /// Marks a card saved and moves the deck on, WITHOUT waiting for the write.
    ///
    /// Split from `persistSave` so the view can advance and re-centre the deck in
    /// a single transaction. Awaiting SwiftData first meant the index moved on a
    /// later frame than the swipe offset reset, so the incoming card was painted
    /// once at the outgoing card's position — the flicker after a swipe.
    func acceptSavedCard(_ card: PlateCard) {
        saveError = nil
        savedIDs.insert(card.id)
        // Saved cards are normally excluded by source URL on the next load, but
        // Spoonacular does not always give one — recording the id too means a
        // saved recipe can never be dealt back as a suggestion.
        deps.recordSeen(card.id)
        if index < recipes.count - 1 { index += 1 }
    }

    /// Writes an accepted card to the cookbook. On failure the card is un-marked
    /// so undo can find it again, but the deck does not jump backwards: yanking
    /// someone's position out from under them is worse than the failed save,
    /// which the alert already tells them about.
    func persistSave(_ card: PlateCard, into context: ModelContext) async {
        savingID = card.id
        do {
            _ = try await deps.save(card, context)
            savingID = nil
        } catch {
            savingID = nil
            savedIDs.remove(card.id)
            deps.forgetSeen(card.id)
            saveError = error.localizedDescription
        }
    }

    func skip(_ card: PlateCard) {
        skippedIDs.insert(card.id)
        deps.recordSeen(card.id)
        if index < recipes.count - 1 { index += 1 }
        // The save side is `recipe_created` with `source: plates`, so the two
        // together give the deck's save rate without a second save event.
        Analytics.capture(.platesSwiped, ["direction": "skip"])
    }

    /// Rewinds to the previous card and clears its saved/skipped mark, backing the
    /// deck's "undo" button. A saved recipe stays in the cookbook (undo is a visual
    /// rewind of the deck, not a delete).
    func undo() {
        guard index > 0 else { return }
        index -= 1
        if let card = current {
            savedIDs.remove(card.id)
            skippedIDs.remove(card.id)
            deps.forgetSeen(card.id)
        }
    }

    func clearSaveError() { saveError = nil }

    /// A page minus everything the cook has already judged, already has, cannot
    /// eat, or is holding right now. `sort=random` upstream can repeat a recipe
    /// across pages, so the de-dupe against what's loaded matters more than it
    /// used to.
    private func freshCards(from page: PlatesResponse) -> [PlateCard] {
        let existing = Set(recipes.map(\.id))
        let filtered = PlatesDeckFilter
            .filter(
                page.recipes,
                rules: filterRules,
                allergies: filterAllergies,
                savedSourceURLs: filterSavedURLs,
                seenIDs: filterSeenIDs)
            .filter { !existing.contains($0.id) }
        return deps.shuffle(filtered)
    }

    private func applyDeck(
        _ page: PlatesResponse,
        rules: [DietaryRule],
        allergies: [String],
        savedSourceURLs: Set<String>,
        store: Bool
    ) {
        // Stored BEFORE filtering: the cache is this page as the server sent it,
        // so a cook whose taste or pantry changes later still gets the whole page.
        if store { deps.storeDeck(page) }
        deckTitle = page.deckTitle ?? deckTitle
        // Shuffled because the response is edge-cached for 12h and the local copy
        // for a whole day, so without this every open in that window deals the
        // identical hand in the identical order.
        recipes = deps.shuffle(
            PlatesDeckFilter.filter(
                page.recipes,
                rules: rules,
                allergies: allergies,
                savedSourceURLs: savedSourceURLs,
                seenIDs: filterSeenIDs))
        index = 0
        // Carry the cursor so the feed can page endlessly (nil in tests / seed).
        nextPageToken = page.nextPageToken
        phase = recipes.isEmpty ? .empty : .loaded
    }

    private func prefetchIfNeeded() async {
        guard isExplore, let token = nextPageToken, index >= recipes.count - 2 else { return }
        do {
            let page = try await deps.search(query, token)
            recipes.append(contentsOf: page.recipes)
            nextPageToken = page.nextPageToken
        } catch {
            nextPageToken = nil
        }
    }
}
