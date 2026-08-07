import Foundation

/// Counts frames on whatever thread delivers them, with no actor hop.
///
/// The point of the count-only rung of the isolation ladder is to prove that
/// merely *receiving* frames costs nothing. A counter that hopped to the main
/// actor would reintroduce the very thing being ruled out.
final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock(); value += 1; lock.unlock()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func reset() {
        lock.lock(); value = 0; lock.unlock()
    }
}
