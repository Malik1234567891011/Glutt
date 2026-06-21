import Foundation
import SwiftData

/// Downloads imported recipe images once and stores the bytes in `imageData`
/// so they survive `/Library/Caches` purges and source-URL rot. Display
/// (`RecipeImageView`) already prefers `imageData`, so once bytes exist the
/// durable copy is shown — no display changes needed.
enum RecipeImageBackfill {

    /// Network seam — injected in tests, real `URLSession` in the app.
    typealias Fetch = (URL) async throws -> Data

    static let defaultFetch: Fetch = { url in
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    /// Max images cached per sweep, so a large library heals over several
    /// foregrounds instead of spiking on one.
    static let perSweepLimit = 20

    /// URLs that failed this app run — not retried until next launch.
    @MainActor private static var failedURLs: Set<String> = []

    /// Needs caching iff it has a remote URL, no local bytes, and no bundled asset.
    static func needsCaching(_ recipe: Recipe) -> Bool {
        guard recipe.imageData == nil, recipe.imageAssetName == nil else { return false }
        guard let url = recipe.imageURL else { return false }
        return !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Download + downscale via `ImagePrep` (1280 / q0.65). `nil` on any failure.
    static func downloadAndPrepare(from urlString: String, fetch: Fetch = defaultFetch) async -> Data? {
        guard let url = URL(string: urlString),
              !urlString.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let raw = try? await fetch(url) else { return nil }
        return ImagePrep.prepareForVision(raw, maxDimension: 1280)
    }

    /// Cache one recipe's image if needed. Model mutation on the main actor;
    /// the `await`ed download runs off-main via `URLSession`.
    @MainActor
    static func ensure(for recipe: Recipe, in context: ModelContext, fetch: Fetch = defaultFetch) async {
        guard needsCaching(recipe), let urlString = recipe.imageURL else { return }
        guard !failedURLs.contains(urlString) else { return }
        guard let bytes = await downloadAndPrepare(from: urlString, fetch: fetch) else {
            failedURLs.insert(urlString)
            return
        }
        recipe.imageData = bytes
        try? context.save()
    }

    /// Heal up to `perSweepLimit` URL-only recipes, sequentially.
    @MainActor
    static func sweep(in context: ModelContext, fetch: Fetch = defaultFetch) async {
        guard let all = try? context.fetch(FetchDescriptor<Recipe>()) else { return }
        let pending = all.filter { needsCaching($0) && !failedURLs.contains($0.imageURL ?? "") }
            .prefix(perSweepLimit)
        for recipe in pending {
            await ensure(for: recipe, in: context, fetch: fetch)
        }
    }

    /// Test seam: clear the session failed-set between tests.
    @MainActor static func resetFailedURLsForTesting() { failedURLs.removeAll() }
}
