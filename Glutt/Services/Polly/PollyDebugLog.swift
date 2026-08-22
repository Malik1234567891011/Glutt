import Foundation

/// In-memory session diagnostics for live Polly debugging. Lightweight,
/// lock-guarded, capped ring buffer — never touches disk, never logs
/// secrets (no tokens, no raw audio). The session screen exposes a
/// copy-to-clipboard button so a whole call's timeline can be pasted
/// into a bug report.
final class PollyDebugLog: @unchecked Sendable {
    static let shared = PollyDebugLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private var start = Date()
    private let cap = 800

    private let clock: () -> Date

    init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
        start = clock()
    }

    /// Wipe and restart the timeline (called at session start).
    func reset() {
        lock.lock(); defer { lock.unlock() }
        lines.removeAll()
        start = clock()
    }

    /// Append one timestamped line ("+12.34s message"). Oldest lines drop
    /// past the cap so a runaway session can't balloon memory.
    func log(_ message: String) {
        let stamp = String(format: "+%.2fs", clock().timeIntervalSince(startLocked()))
        #if DEBUG
        // Mirrored to stdout so a session can be diagnosed from the runtime log
        // without tapping through the app to copy it out.
        print("POLLY \(stamp) \(message)")
        #endif
        lock.lock(); defer { lock.unlock() }
        lines.append("\(stamp) \(message)")
        if lines.count > cap {
            lines.removeFirst(lines.count - cap)
        }
    }

    /// The full timeline as one pasteable string.
    func dump() -> String {
        lock.lock(); defer { lock.unlock() }
        return (["=== Polly session debug log (\(lines.count) lines) ==="] + lines)
            .joined(separator: "\n")
    }

    var lineCount: Int {
        lock.lock(); defer { lock.unlock() }
        return lines.count
    }

    private func startLocked() -> Date {
        lock.lock(); defer { lock.unlock() }
        return start
    }
}
