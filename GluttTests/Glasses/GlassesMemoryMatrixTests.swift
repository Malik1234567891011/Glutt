#if canImport(MWDATMockDevice)
import MWDATCamera
import MWDATCore
import MWDATMockDevice
import XCTest
@testable import Glutt

/// Measures what a glasses camera actually costs, without a pair of glasses.
///
/// Every memory number we had before this file cost Malik five minutes: put the
/// glasses on, tap through the spike screen, copy a log out of a dying app,
/// paste it. One variable per run, one run per interruption. At that rate the
/// question "is the cost per frame or per second" takes days to answer and the
/// glasses get memory-killed into the stuck-broadcast state of issue #231 on the
/// way, which quietly poisons the numbers that do come back.
///
/// So the matrix runs here instead. `MWDATMockDevice` is the real toolkit with a
/// fake device underneath: the same `DeviceSession`, the same `Camera`, the same
/// `videoFramePublisher`, fed from an H.265 file rather than a radio. It already
/// reproduced the growth that was killing the app on device, which is what makes
/// it worth trusting for the shape of the answer even though it cannot speak to
/// the Wi-Fi transport.
///
/// # The question this exists to settle
///
/// Every measurement we have, on device and on the simulator, lands between 19
/// and 42 MB per **second** of camera uptime, and the per-frame figures move
/// around a lot more than the per-second ones. If the cost is per second, then
/// frame rate, resolution and our frame gate are all irrelevant and the only
/// lever that matters is how long the camera stays open. If it is per frame,
/// they are the only levers there are. We have been tuning the wrong set for
/// weeks on the strength of a guess.
///
/// Group A holds the clock still and moves the frame rate 15-fold. That single
/// comparison decides it.
///
/// # Running it
///
/// Off by default: it takes minutes and would distort the suite baseline.
///
/// ```
/// GLUTT_GLASSES_MATRIX=1 xcodebuild test -scheme Glutt \
///   -destination 'platform=iOS Simulator,name=iPhone 17' \
///   -only-testing:GluttTests/GlassesMemoryMatrixTests \
///   CODE_SIGN_IDENTITY="-"
/// ```
///
/// `CODE_SIGN_IDENTITY="-"` is not optional and not cosmetic. With
/// `CODE_SIGNING_ALLOWED=NO` the SDK's keychain lookup fails, `configure()`
/// throws, and the host app fatals on first access to `Wearables.shared` with a
/// message that blames the caller. Meta confirmed this on issue #197.
@MainActor
final class GlassesMemoryMatrixTests: XCTestCase {

    // MARK: - One row of the table

    private struct Row {
        let label: String
        let seconds: Double
        let frames: Int
        let deltaMB: Double

        var mbPerSecond: Double { seconds > 0 ? deltaMB / seconds : 0 }
        var mbPerFrame: Double { frames > 0 ? deltaMB / Double(frames) : 0 }
        var fps: Double { seconds > 0 ? Double(frames) / seconds : 0 }
    }

    private var rows: [Row] = []

    /// The toolkit is a process-global singleton and the mock device is paired
    /// into it once. Rows differ by camera configuration, not by device, which
    /// also matches how we use it: one long-lived session, many short cameras.
    private static var deviceReady = false
    private static var mockGlasses: (any MockGlasses)?

    /// Static, because XCTest builds a fresh instance per test method while the
    /// toolkit keeps the session it was handed. An instance-owned session leaves
    /// the next method unable to create its own ("A session already exists for
    /// this device") — and holding one session across many cameras is the shape
    /// of the design under test anyway.
    private static var selector: AutoDeviceSelector?
    private static var session: DeviceSession?

    // MARK: - Gate

    private var matrixEnabled: Bool {
        ProcessInfo.processInfo.environment["GLUTT_GLASSES_MATRIX"] == "1"
    }

    override func setUp() async throws {
        try XCTSkipUnless(
            matrixEnabled,
            "Set GLUTT_GLASSES_MATRIX=1 to run the glasses memory matrix. It takes minutes."
        )
        try Self.prepareDevice()
    }

    // MARK: - Device bring-up

    private static func prepareDevice() throws {
        guard !deviceReady else { return }

        try? Wearables.configure()
        MockDeviceKit.shared.enable(
            config: MockDeviceKitConfig(initiallyRegistered: true, initialPermissionsGranted: true)
        )

        let glasses = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
        glasses.powerOn()
        glasses.unfold()
        // Donned or the device never becomes eligible and every session throws
        // `noEligibleDevice`. Meta's answer on issue #171.
        glasses.don()

        // MUST be H.265. `setCameraFeed` extracts frames with a decoder that
        // accepts nothing else, and an H.264 file fails *silently*: the stream
        // still reaches `.streaming` because the control handshake completes
        // before frame extraction is ever attempted, so the symptom is a
        // publisher that simply never fires. That mismatch is the whole content
        // of issue #197.
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "glasses-mock-wok", withExtension: "mov"),
            "glasses-mock-wok.mov is missing from the app bundle"
        )
        glasses.services.camera.setCameraFeed(fileURL: url)

        mockGlasses = glasses
        deviceReady = true
    }

    /// One session, held across every row, because that is the shape of the
    /// design under test: establishing a session is the slow part and we keep it
    /// alive between looks, so a per-row session would measure something we
    /// never do.
    private func liveSession() async throws -> DeviceSession {
        if let session = Self.session, session.state == .started { return session }
        Self.session?.stop()
        Self.session = nil

        let selector = Self.selector ?? AutoDeviceSelector(wearables: Wearables.shared)
        Self.selector = selector
        // The selector resolves by observing rather than on demand, so a session
        // created in the same breath as the selector throws `noEligibleDevice`.
        try await waitUntil(timeout: 6) { selector.activeDevice != nil }

        let session = try Wearables.shared.createSession(deviceSelector: selector)
        try session.start()
        try await waitUntil(timeout: 10) { session.state == .started }
        Self.session = session
        return session
    }

    // MARK: - The measurement

    /// Open a camera, hold it open for `seconds`, close it, and report what the
    /// process footprint did.
    ///
    /// `subscribe: false` is the control that made the earlier device numbers
    /// mean something: with nothing listening to `videoFramePublisher`, any
    /// growth that still happens cannot be ours.
    @discardableResult
    private func measureCamera(
        label: String,
        codec: VideoCodec = .raw,
        resolution: StreamingResolution = .medium,
        frameRate: UInt = 7,
        seconds: Double,
        subscribe: Bool = true,
        decode: Bool = false
    ) async throws -> Row {
        let session = try await liveSession()
        let counter = FrameTally()

        // Settle before the baseline so the previous row's teardown is not
        // charged to this one.
        try? await Task.sleep(for: .milliseconds(600))
        let before = MemoryProbe.footprintBytes
        let startedAt = Date()

        let config = StreamConfiguration(videoCodec: codec, resolution: resolution, frameRate: frameRate)
        let camera = try XCTUnwrap(try session.addStream(config: config), "addStream returned nil for \(label)")

        var token: (any AnyListenerToken)?
        if subscribe {
            token = camera.videoFramePublisher.listen { frame in
                counter.increment()
                guard decode else { return }
                // The toolkit's delivery thread has no autorelease pool of its
                // own, so a decode without one accumulates megabytes of CGImage
                // temporaries for the life of the stream.
                autoreleasepool {
                    _ = VisualFramePipeline.image(from: frame.sampleBuffer)
                }
            }
        }

        camera.start()
        try? await Task.sleep(for: .seconds(seconds))

        camera.stop()
        if let token { await token.cancel() }
        // Let teardown actually finish before reading the footprint, or a row
        // gets credited with memory the next one will release.
        try? await Task.sleep(for: .milliseconds(800))

        let row = Row(
            label: label,
            seconds: Date().timeIntervalSince(startedAt),
            frames: counter.value,
            deltaMB: (Double(MemoryProbe.footprintBytes) - Double(before)) / 1_048_576
        )
        rows.append(row)
        return row
    }

    private func waitUntil(
        timeout: TimeInterval,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard condition() else { throw XCTSkip("Timed out waiting for the mock device to settle") }
    }

    // MARK: - Group A: is the cost per second or per frame?

    /// Same wall clock, frame rate moved 15-fold.
    ///
    /// Reports the frame count as well as the request, because the mock is under
    /// no obligation to honour `frameRate` — it plays a file at the file's own
    /// cadence. If the counts come back identical across the column then this
    /// group has not varied what it set out to vary, and only
    /// `testA2_duration` can speak to the question.
    func testA_timeVersusFrames() async throws {
        let seconds = 12.0
        for rate in [UInt(2), 7, 15, 30] {
            try await measureCamera(label: "A · raw/medium @ \(rate)fps", frameRate: rate, seconds: seconds)
        }
        report("A · TIME vs FRAMES (constant \(Int(seconds))s, frame rate requested 2→30)")
    }

    /// Hold everything still and stretch the clock instead.
    ///
    /// This is the honest version of group A on a mock that pins the frame rate:
    /// duration and frame count rise together, so it cannot separate the two
    /// causes, but it does separate a **steady leak** from a **fixed setup
    /// charge**. A steady leak keeps MB/s constant as the runs get longer; a
    /// one-off cost per camera cycle shows MB/s falling away as the fixed charge
    /// is spread over more seconds.
    ///
    /// That distinction is the one that decides whether looks are viable at all,
    /// because a fixed charge per look can be budgeted and a leak cannot.
    func testA2_duration() async throws {
        for seconds in [6.0, 12.0, 24.0, 48.0] {
            try await measureCamera(label: "A2 · raw/medium @ 7fps for \(Int(seconds))s", seconds: seconds)
        }
        report("A2 · DURATION SWEEP (leak shows as flat MB/s, setup cost shows as falling MB/s)")
    }

    /// One camera held open far longer than any look, to catch slow growth that
    /// a twelve-second window would round to nothing.
    ///
    /// At the 42 MB/s we measured on device this would end the process. If it
    /// comes back in single-digit MB, whatever we saw there is not in this path.
    func testA3_soak() async throws {
        try await measureCamera(label: "A3 · raw/medium @ 7fps for 120s", seconds: 120)
        report("A3 · SOAK")
    }

    // MARK: - Group B: does resolution change the slope?

    /// Distinguishes "one image buffer per frame is retained" from "a fixed-size
    /// wrapper per frame is retained". Those point at different causes and only
    /// one of them can be dodged by asking for less.
    func testB_resolution() async throws {
        for resolution in [StreamingResolution.low, .medium, .high] {
            try await measureCamera(
                label: "B · raw/\(resolution) @ 7fps",
                resolution: resolution,
                seconds: 12
            )
        }
        report("B · RESOLUTION (constant 12s @ 7fps)")
    }

    // MARK: - Group C: codec, subscriber, and our own decode

    /// `.hvc1` is Meta's own recommendation over `.raw` (issue #254), and `.raw`
    /// is the path where their decoder is known-defective. If passthrough is
    /// flat, it is worth the cost of decoding ourselves.
    ///
    /// The no-subscriber row is the control: growth with nothing listening
    /// cannot be attributed to our handler.
    func testC_codecAndSubscriber() async throws {
        try await measureCamera(label: "C · raw/medium  @ 7fps, listening", seconds: 12)
        try await measureCamera(label: "C · raw/medium  @ 7fps, NO listener", seconds: 12, subscribe: false)
        try await measureCamera(label: "C · raw/medium  @ 7fps, + our decode", seconds: 12, decode: true)
        try await measureCamera(label: "C · hvc1/medium @ 7fps, listening", codec: .hvc1, seconds: 12)
        report("C · CODEC / SUBSCRIBER / DECODE (constant 12s)")
    }

    // MARK: - Group D: the design we actually shipped

    /// Five short looks on one held session, which is what `captureLook` does.
    ///
    /// The interesting number is not the total but whether each look costs the
    /// same. A fixed per-camera-cycle charge is survivable and bounds a cook
    /// session; a charge that grows look over look means the design has a
    /// ceiling on how many times Chef can glance before the app dies, and the
    /// device numbers so far (419 → 603 → 839 MB) look uncomfortably like the
    /// second.
    func testD_repeatedLooks() async throws {
        for index in 1...5 {
            try await measureCamera(label: "D · look \(index) (2s camera)", seconds: 2)
            try? await Task.sleep(for: .seconds(1))
        }
        report("D · REPEATED LOOKS on one held session")
    }

    // MARK: - Output

    private func report(_ title: String) {
        var out = "\n\n╔══ \(title)\n"
        out += String(
            format: "║ %-38@ %7@ %7@ %9@ %9@ %9@\n",
            "row" as NSString, "secs" as NSString, "frames" as NSString,
            "ΔMB" as NSString, "MB/s" as NSString, "MB/frame" as NSString
        )
        for row in rows {
            out += String(
                format: "║ %-38@ %7.1f %7d %9.1f %9.1f %9.2f\n",
                row.label as NSString, row.seconds, row.frames,
                row.deltaMB, row.mbPerSecond, row.mbPerFrame
            )
        }
        out += "╚══ footprint now \(MemoryProbe.summary)\n"
        print(out)
        rows.removeAll()
    }
}

/// Counts frames from the toolkit's delivery thread without retaining any.
private final class FrameTally: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
#endif
