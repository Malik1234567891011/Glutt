import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class DiscoverFeedViewModel {
    enum Phase: Equatable {
        case idle, loading, loaded, empty
        case failed(String)
    }

    struct Dependencies {
        var search: (_ query: String, _ pageToken: String?) async throws -> DiscoverResponse
        var suggested: (_ tags: [String]) async throws -> DiscoverResponse
        var save: (_ video: DiscoverVideo, _ context: ModelContext) async throws -> Recipe

        static let live = Dependencies(
            search: { try await DiscoverService.live.search(query: $0, pageToken: $1) },
            suggested: { try await DiscoverService.live.suggested(tags: $0) },
            save: { try await DiscoverSaver.save(video: $0, into: $1) }
        )
    }

    private(set) var phase: Phase = .idle
    private(set) var videos: [DiscoverVideo] = []
    private(set) var currentIndex = 0
    private(set) var savedVideoIDs: Set<String> = []
    private(set) var savingVideoID: String?

    private var nextPageToken: String?
    private var query: String = ""
    private var isSuggested = false
    private let deps: Dependencies

    init(deps: Dependencies = .live) { self.deps = deps }

    var current: DiscoverVideo? {
        videos.indices.contains(currentIndex) ? videos[currentIndex] : nil
    }

    func loadSuggested(tags: [String]) async {
        isSuggested = true
        query = ""
        phase = .loading
        do {
            let page = try await deps.suggested(tags)
            apply(firstPage: page)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSuggested = false
        self.query = trimmed
        phase = .loading
        do {
            let page = try await deps.search(trimmed, nil)
            apply(firstPage: page)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func showNext() async {
        guard !videos.isEmpty else { return }
        if currentIndex < videos.count - 1 { currentIndex += 1 }
        await prefetchIfNeeded()
    }

    func save(_ video: DiscoverVideo, into context: ModelContext) async {
        savingVideoID = video.videoId
        do {
            _ = try await deps.save(video, context)
            savedVideoIDs.insert(video.videoId)
            savingVideoID = nil
            await showNext()
        } catch {
            savingVideoID = nil
            phase = .failed(error.localizedDescription)
        }
    }

    private func apply(firstPage page: DiscoverResponse) {
        videos = page.videos
        currentIndex = 0
        nextPageToken = page.nextPageToken
        phase = page.videos.isEmpty ? .empty : .loaded
    }

    private func prefetchIfNeeded() async {
        guard let token = nextPageToken, currentIndex >= videos.count - 2 else { return }
        do {
            let page = isSuggested
                ? try await deps.suggested([])   // suggested paging falls back to refresh; tokenized below
                : try await deps.search(query, token)
            videos.append(contentsOf: page.videos)
            nextPageToken = page.nextPageToken
        } catch {
            // Soft-fail: keep the current queue; the user can still browse what loaded.
            nextPageToken = nil
        }
    }
}
