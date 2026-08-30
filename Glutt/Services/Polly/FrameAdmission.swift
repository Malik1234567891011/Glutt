import Foundation

/// Lets one frame through at a time, and drops the rest on the floor.
///
/// The toolkit delivers frames on its own thread as fast as a wearable camera send
/// them. Handing every one of them to the main actor means a `Task` per frame,
/// each retaining a decoded `UIImage`: at 24 fps and 504x896 that is roughly
/// 43 MB per second of images queued behind whatever the main actor is already
/// doing. It only has to fall behind for a moment before the backlog is the
/// whole memory budget, and the app dies with no crash report because it was
/// killed rather than crashed.
///
/// Dropping is correct here, not a compromise. Nothing downstream wants every
/// frame: the preview only shows the newest, and the gate picks the sharpest of
/// the last handful. A frame skipped while the previous one is still being
/// handled would have been thrown away anyway.
final class FrameAdmission: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false

    /// True when the caller may process this frame. Balance every `true` with
    /// exactly one `release()`.
    func admit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if busy { return false }
        busy = true
        return true
    }

    func release() {
        lock.lock()
        busy = false
        lock.unlock()
    }
}
