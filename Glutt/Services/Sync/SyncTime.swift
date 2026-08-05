import Foundation

/// Timestamps on the wire.
///
/// Sync documents carry dates as **strings, never as `Date`**, and this is the
/// only place that converts. Two reasons, both of which bite silently:
///
/// - The Postgrest client brings its own `JSONEncoder`/`JSONDecoder` with their
///   own date strategies. A `Date` property would be written with fractional
///   seconds by one and rejected by the other, and the failure would look like
///   a corrupt recipe rather than a formatting mismatch.
/// - The push sweep decides what to send by hashing the document. Whole seconds
///   in a fixed format hash identically on every launch; a strategy chosen by
///   somebody else's default does not.
enum SyncTime {
    private static let writer: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let fractionalReader: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Whole seconds, UTC. `2026-07-31T09:14:05Z`.
    static func string(from date: Date) -> String {
        writer.string(from: date)
    }

    /// Reads what we write, and what Postgres emits — which carries microseconds
    /// and is what a value read back from a `timestamptz` looks like.
    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return writer.date(from: string) ?? fractionalReader.date(from: string)
    }
}
