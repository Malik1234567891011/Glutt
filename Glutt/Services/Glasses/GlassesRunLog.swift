import Foundation

/// A glasses diagnostic log that survives the app being killed.
///
/// Exists because the most expensive runs are the ones that tell us the most,
/// and those are exactly the runs we lose. A memory kill gives no crash report,
/// no jetsam event and no chance to tap "Copy log", so twice now the run that
/// finally reproduced the problem left nothing behind but a description from
/// memory. Every line here is written and flushed as it happens, so the next
/// launch can read back a log that ends at the instant the process died.
///
/// Deliberately separate from `PollyDebugLog`, which is an in-memory ring buffer
/// that never touches disk. That is the right design for a live cook session,
/// where the log is a convenience and the disk write is not worth it. It is the
/// wrong design for a diagnostic run whose whole purpose is to be read after a
/// crash.
final class GlassesRunLog: @unchecked Sendable {
    static let shared = GlassesRunLog()

    private let lock = NSLock()
    private let url: URL
    private var handle: FileHandle?
    private var runStart = Date()
    private var savedFrames = 0

    /// Roughly 400 KB of text, after which the file is truncated and started
    /// again. A diagnostic run is a few hundred lines; anything approaching this
    /// is a loop we would rather notice than store.
    private let maxBytes: UInt64 = 400_000

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = documents.appendingPathComponent("glasses-runs.log")
    }

    /// Mark the start of a run. Previous runs are kept above the marker, which is
    /// the point: the log that matters is usually the one before the crash.
    func startRun(_ title: String) {
        lock.lock()
        defer { lock.unlock() }
        runStart = Date()
        savedFrames = 0
        openIfNeeded()
        write("\n\n══════ \(title) — \(Self.stamp.string(from: runStart)) ══════\n")
    }

    func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        openIfNeeded()
        let elapsed = Date().timeIntervalSince(runStart)
        write(String(format: "%6.1f  %@\n", elapsed, message))
    }

    /// Keep the picture Chef was actually shown.
    ///
    /// A log can say a frame was sent, its sharpness and its age, and still
    /// leave the question that matters unanswered: is 504x896 over Bluetooth
    /// enough to tell a red onion from a yellow one, or 5mm dice from 15mm?
    /// Nobody has looked. These land next to the log so a run can be reviewed
    /// picture by picture afterwards rather than argued about.
    ///
    /// Capped per launch. Diagnostic frames are ~50 KB, so this is a couple of
    /// megabytes at worst, and it is the only copy that exists — the buffer
    /// holds eight and drops the rest.
    func saveFrame(_ jpeg: Data, reason: String) {
        lock.lock()
        defer { lock.unlock() }
        guard savedFrames < 60 else { return }
        savedFrames += 1

        let directory = url.deletingLastPathComponent().appendingPathComponent("glasses-frames")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Numbered by order and stamped with seconds into the run, so the file
        // name alone lines a picture up against the line in the log that sent it.
        let elapsed = Int(Date().timeIntervalSince(runStart))
        let slug = reason
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .prefix(50)
        let name = String(format: "%03d-t%04ds-%@.jpg", savedFrames, elapsed, String(slug))
        try? jpeg.write(to: directory.appendingPathComponent(name))

        // Remembered so what she says next can be written beside it.
        pendingLook = (folder: directory, imageName: name, reason: reason)
    }

    /// The look that has been sent and not yet answered.
    private var pendingLook: (folder: URL, imageName: String, reason: String)?

    /// What she actually said about the last picture she was sent.
    ///
    /// The half that was missing, and the half that makes the archive worth
    /// keeping. A folder of frames tells you what the camera saw. It cannot
    /// tell you whether she noticed that the pot she was asked about was not
    /// in the picture, which is the only question worth asking about most of
    /// these, and three frames pulled off a real cook show exactly that: a
    /// laptop playing football under "confirm the pot is at a rolling boil".
    ///
    /// Whether she answered anyway is unknowable from the image alone.
    func saveAnswer(_ spoken: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let look = pendingLook else { return }
        pendingLook = nil

        let text = """
        she was asked to: \(look.reason)

        what she said about it:
        \(spoken.isEmpty ? "(nothing, no spoken answer followed this look)" : spoken)

        open \(look.imageName) and ask the only question that matters here:
        is the thing she was asked about actually in that picture?
        """
        let name = (look.imageName as NSString).deletingPathExtension + ".txt"
        try? Data(text.utf8).write(to: look.folder.appendingPathComponent(name))
    }

    /// Everything on disk, including runs that ended in a kill.
    ///
    /// Rarely what you want directly: after a few runs this is hundreds of
    /// lines. `currentRun()` is the default for a reason.
    func dump() -> String {
        lock.lock()
        defer { lock.unlock() }
        handle?.synchronizeFile()
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "(no glasses run log yet)"
    }

    /// This run and nothing else, capped at `maxLines`.
    ///
    /// Two earlier versions of this were unusable. The first pasted the whole
    /// file; the second kept the previous run as well, which is fine right up
    /// until that previous run is a long one and the paste is hundreds of pages
    /// again. A run is a few dozen lines and the interesting one is always the
    /// most recent, so it is the only one copied, and it is truncated from the
    /// front if something ever does run away.
    func currentRun(maxLines: Int = 250) -> String {
        let whole = dump()
        let runs = whole.components(separatedBy: "\n\n══════ ")
        guard runs.count > 1 else { return whole }

        // Rebuild the marker the split consumed, so the paste still says which
        // run it is and when it started.
        func rendered(_ index: Int) -> String { "══════ " + runs[index] }

        // A run with almost nothing in it means the interesting one is above:
        // either the app was killed and relaunched, or a marker was written that
        // no measurement followed. Reach back one rather than hand over a header
        // and two lines of boilerplate, which is precisely the failure this
        // method exists to avoid.
        var latest = rendered(runs.count - 1)
        if latest.components(separatedBy: "\n").count < 6, runs.count > 2 {
            latest = rendered(runs.count - 2) + "\n\n" + latest
        }
        let lines = latest.components(separatedBy: "\n")
        guard lines.count > maxLines else { return latest }
        let kept = lines.suffix(maxLines)
        return "(… \(lines.count - maxLines) earlier lines trimmed)\n" + kept.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func openIfNeeded() {
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
        }
        if let handle, handle.offsetInFile > maxBytes {
            try? handle.truncate(atOffset: 0)
        }
    }

    /// Flushed on every line. The whole value of this file is that it is current
    /// at the moment the process stops existing, and buffered writes are not.
    private func write(_ text: String) {
        guard let handle, let data = text.data(using: .utf8) else { return }
        handle.write(data)
        handle.synchronizeFile()
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
