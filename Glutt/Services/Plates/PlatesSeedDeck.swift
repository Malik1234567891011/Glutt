import Foundation

/// Loads the bundled fallback deck so Plates works on first run, offline, or
/// before the backend is deployed.
enum PlatesSeedDeck {
    static func decode(_ data: Data) -> PlatesResponse? {
        try? JSONDecoder().decode(PlatesResponse.self, from: data)
    }

    static func load(from bundle: Bundle = .main) -> PlatesResponse {
        guard let url = bundle.url(forResource: "PlatesSeedDeck", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let resp = decode(data) else {
            return PlatesResponse(deckTitle: "Today's Plate", recipes: [], nextPageToken: nil)
        }
        return resp
    }
}

/// Persists the daily deck keyed by local calendar date, so reopening is
/// instant and the feed works briefly offline. Refreshes when the local day
/// rolls over (which is how "07:00 local" freshness is realized client-side:
/// the first open on a new local day fetches a fresh deck).
enum PlatesDeckCache {
    private static let dayKey = "plates.deck.day"
    private static let dataKey = "plates.deck.data"

    private static func todayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    static func today() -> PlatesResponse? {
        let d = UserDefaults.standard
        guard d.string(forKey: dayKey) == todayString(),
              let data = d.data(forKey: dataKey) else { return nil }
        return PlatesSeedDeck.decode(data)
    }

    static func store(_ response: PlatesResponse) {
        guard let data = try? JSONEncoder().encode(EncodablePlates(response)) else { return }
        let d = UserDefaults.standard
        d.set(todayString(), forKey: dayKey)
        d.set(data, forKey: dataKey)
    }
}
