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

        static let live = Dependencies(
            daily: { try await PlatesService.live.daily() },
            search: { try await PlatesService.live.search(query: $0, pageToken: $1) },
            save: { try await PlatesSaver.save(card: $0, into: $1) },
            seed: { PlatesSeedDeck.load() },
            cachedDeck: { PlatesDeckCache.today() },
            storeDeck: { PlatesDeckCache.store($0) }
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
    private let deps: Dependencies

    init(deps: Dependencies = .live) { self.deps = deps }

    var current: PlateCard? { recipes.indices.contains(index) ? recipes[index] : nil }

    func loadDaily(rules: [DietaryRule], allergies: [String], savedSourceURLs: Set<String>) async {
        isExplore = false
        deckTitle = "Today's Plate"

        // 1. Today's cached deck (instant, offline-friendly).
        if let cached = deps.cachedDeck() {
            applyDeck(cached, rules: rules, allergies: allergies, savedSourceURLs: savedSourceURLs, store: false)
            return
        }

        // 2. Network deck → cache it.
        phase = .loading
        do {
            let page = try await deps.daily()
            applyDeck(page, rules: rules, allergies: allergies, savedSourceURLs: savedSourceURLs, store: true)
        } catch {
            // 3. Bundled seed fallback.
            let seed = deps.seed()
            applyDeck(seed, rules: rules, allergies: allergies, savedSourceURLs: savedSourceURLs, store: false)
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
        saveError = nil
        savingID = card.id
        do {
            _ = try await deps.save(card, context)
            savedIDs.insert(card.id)
            savingID = nil
            await showNext()
        } catch {
            savingID = nil
            saveError = error.localizedDescription
        }
    }

    func skip(_ card: PlateCard) {
        skippedIDs.insert(card.id)
        if index < recipes.count - 1 { index += 1 }
    }

    func clearSaveError() { saveError = nil }

    private func applyDeck(
        _ page: PlatesResponse,
        rules: [DietaryRule],
        allergies: [String],
        savedSourceURLs: Set<String>,
        store: Bool
    ) {
        if store { deps.storeDeck(page) }
        deckTitle = page.deckTitle ?? deckTitle
        recipes = PlatesDeckFilter.filter(page.recipes, rules: rules, allergies: allergies, savedSourceURLs: savedSourceURLs)
        index = 0
        nextPageToken = nil  // daily deck never paginates
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
