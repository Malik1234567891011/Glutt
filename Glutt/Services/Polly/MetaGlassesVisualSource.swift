import Foundation
import MWDATCamera
import MWDATCore
import Observation
import UIKit

/// Ray-Ban Meta glasses as a visual source for Polly.
///
/// Talks to the real Device Access Toolkit. `MWDATMockDevice` swaps the device
/// underneath during development, which is the whole point: nothing in here
/// knows or cares whether the frames came from glasses on a face or an H.265
/// fixture, so going to hardware is a configuration change rather than a rewrite.
///
/// Failure is never fatal. Every path that cannot deliver a picture leaves the
/// cook session running and reports why, because losing the camera must not lose
/// the cook their place in the recipe.
enum GlassesLookError: Error {
    case cameraDidNotStart
}

@MainActor
@Observable
final class MetaGlassesVisualSource: PollyVisualSource {
    nonisolated let kind: PollyVisualSourceKind = .metaGlasses

    private(set) var state: PollyVisualSourceState = .off
    /// The most recent decoded frame, for the canvas. Separate from the buffer
    /// the gate chooses from: the preview wants the newest, Polly wants the best.
    private(set) var previewImage: UIImage?

    var preview: PollyVisualPreview {
        guard state == .streaming, let previewImage else { return .none }
        return .image(previewImage)
    }

    /// One camera, pointed where the cook is looking.
    var canFlip: Bool { false }

    /// `.medium` at 7 fps by default. Meta's own guidance is that lower
    /// resolution and frame rate produce better individual frames, because there
    /// is less compression in the way, and cooking changes slowly enough that
    /// seven chances a second to find a sharp one is plenty.
    var resolution: StreamingResolution = .medium
    var frameRate: UInt = 7

    /// How stale a frame may be before Polly is told the view has gone.
    var defaultMaxFrameAge: TimeInterval = 1.5

    private var gate = VisualFrameGate()
    /// Small image window, long sharpness memory. See `VisualFrameBuffer`: a
    /// second of frames is plenty to choose from, and holding more decoded
    /// 504x896 images than that is megabytes the toolkit wants back.
    private var buffer = VisualFrameBuffer(capacity: 8, historyCapacity: 64)

    private var selector: AutoDeviceSelector?
    private var session: DeviceSession?
    private var camera: Camera?
    private var tokens: [any AnyListenerToken] = []
    /// Cancelled at the end of every look, unlike `tokens`, which belong to the
    /// long-lived session.
    private var streamTokens: [any AnyListenerToken] = []
    private var observationTasks: [Task<Void, Never>] = []
    private var photoContinuation: CheckedContinuation<Data?, Never>?
    private var frameSequence = 0
    /// One frame in flight at a time. Without this every delivered frame queues
    /// a main-actor Task holding a decoded image, and the backlog is unbounded.
    private let admission = FrameAdmission()
    /// Frames the toolkit actually handed us during this look.
    ///
    /// Distinct from `buffer.frames.count`, which was what a look reported until
    /// a 73-second run came back claiming "8 frames": the buffer holds 8 images
    /// by design and drops the oldest, so its count saturates and stops being a
    /// frame count at all. That made every long run look identical to every
    /// short one and made MB-per-frame impossible to compute.
    private let delivered = FrameCounter()

    init() {}

    // MARK: - Lifecycle

    func start() async {
        guard state == .off || isUnavailable else { return }
        guard GlassesSupport.shared.isAvailable else {
            state = .unavailable(reason: "Glasses support is not set up on this phone.")
            return
        }
        state = .starting
        PollyDebugLog.shared.log("glasses: starting visual source")

        let selector = self.selector ?? AutoDeviceSelector(wearables: Wearables.shared)
        self.selector = selector

        // The selector resolves by observing, so a session created in the same
        // breath throws `noEligibleDevice`. Give it a moment to settle.
        guard await waitForDevice(selector: selector) else {
            state = .unavailable(reason: "No glasses are connected.")
            PollyDebugLog.shared.log("glasses: no eligible device")
            return
        }

        do {
            let session = try Wearables.shared.createSession(deviceSelector: selector)
            self.session = session
            observeSession(session)
            try session.start()
            guard await waitForStarted(session) else {
                state = .unavailable(reason: "The glasses did not connect.")
                teardown()
                return
            }
            // Open the camera here and leave it open for the cook.
            //
            // This used to stop at the session and open the camera per look,
            // to spend as few frames as possible. That was built for a leak
            // that turned out to be ours, and with it fixed the frames are
            // nearly free: 0.16 MB/s at 2 fps, so a 45 minute cook watching
            // continuously costs a few hundred MB.
            //
            // What is expensive is *opening* the camera. Every open stands up a
            // Wi-Fi link to the glasses and that takes 14 to 20 seconds,
            // measured, against Meta's stated ~5s. Paying that per glance made
            // five looks cost a minute and a half of waiting; paying it once
            // makes it a single wait at the start of the cook, after which Chef
            // answers immediately. That inverts the old design and is the whole
            // reason this is here rather than in `captureLook`.
            do {
                try await attachCamera(to: session)
                PollyDebugLog.shared.log("glasses: watching")
            } catch {
                // The connection is worth keeping even with no picture: the cook
                // is told, and a retry does not have to re-establish the session.
                state = .ready
                PollyDebugLog.shared.log("glasses: connected, but the camera did not start")
            }
        } catch {
            let text = (error as? any DatError)?.description ?? String(describing: error)
            state = .unavailable(reason: text)
            PollyDebugLog.shared.log("glasses: start failed — \(text)")
            teardown()
        }
    }

    func stop() {
        teardown()
        state = .off
        previewImage = nil
        buffer.removeAll()
        PollyDebugLog.shared.log("glasses: visual source stopped")
    }

    /// Nothing to flip. Present so the canvas does not have to special-case.
    func flip() {}

    private var isUnavailable: Bool {
        if case .unavailable = state { return true }
        return false
    }

    // MARK: - Looks

    /// Take one look: open the camera, gather a few frames, close it, return the
    /// best.
    ///
    /// Reports its own timings because whether a look reads as a glance or a
    /// hang is the number that decides whether this design survives.
    ///
    /// The design was originally forced by a per-frame leak that has since been
    /// retracted — see `docs/glasses-transport-and-memory.md`, and
    /// `GluttTests/Glasses/GlassesMemoryMatrixTests.swift` for the measurements
    /// that retracted it. What still argues for looks over a live stream is the
    /// transport: since 0.8 the camera runs over a Wi-Fi network hosted by the
    /// glasses, so opening one costs an association and drops the phone to
    /// cellular for the duration. That cost is per look, which is a reason to
    /// take few of them, not short ones.
    func captureLook(maxFrames: Int = 8, timeout: TimeInterval = 30) async -> GlassesLook {
        var look = GlassesLook()
        let startedAt = Date()
        let footprintBefore = MemoryProbe.footprintBytes

        guard let session, session.state == .started else {
            look.rejection = .noFrames
            // Say which, because a look that returns in 0.0s having spent 0 MB
            // looks identical to a look that was never attempted, and the
            // difference is the whole diagnosis: a dead session means the
            // previous look took the connection down with it.
            let detail = session.map { "session is \($0.state)" } ?? "no session at all"
            PollyDebugLog.shared.log("glasses: look refused, \(detail)")
            GlassesRunLog.shared.log("look refused before it started: \(detail)")
            return look
        }
        // A camera that is already open is the normal case now that the stream
        // is held for the whole cook, so a look samples the live stream rather
        // than refusing. Only a look that opened the camera itself closes it
        // again; closing one it found open would take the cook's vision away as
        // a side effect of answering a question.
        let openedCamera = camera == nil

        buffer.removeAll()
        frameSequence = 0
        delivered.reset()

        // Sample while the look runs. A look that ends in a memory kill reports
        // nothing at all, and those are the looks worth reading; this way the
        // last flushed line says how far it got and what it had spent.
        let sampler = Task { [startedAt] in
            var lastMB = Double(footprintBefore) / 1_048_576
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                let nowMB = Double(MemoryProbe.footprintBytes) / 1_048_576
                GlassesRunLog.shared.log(String(
                    format: "  look t+%.0fs · %.0f MB used (%+.0f) · %.0f MB free",
                    Date().timeIntervalSince(startedAt), nowMB, nowMB - lastMB,
                    Double(MemoryProbe.availableBytes) / 1_048_576))
                lastMB = nowMB
            }
        }
        defer { sampler.cancel() }

        if openedCamera {
            do {
                try await attachCamera(to: session)
            } catch {
                look.rejection = .noFrames
                PollyDebugLog.shared.log("glasses: look failed to open camera — \(message(error))")
                endLook()
                return look
            }
        }

        // Wait for enough frames, or give up. `maxFrames` is usually reached long
        // before the timeout once frames start; the timeout covers the case where
        // they never do.
        let deadline = Date().addingTimeInterval(timeout)
        var firstFrameAt: Date?
        var footprintAtFirstFrame: UInt64?
        while Date() < deadline {
            if firstFrameAt == nil, buffer.newest != nil {
                firstFrameAt = Date()
                footprintAtFirstFrame = MemoryProbe.footprintBytes
                look.startLatency = firstFrameAt!.timeIntervalSince(startedAt)
            }
            if buffer.frames.count >= maxFrames { break }
            if isUnavailable { break }
            try? await Task.sleep(for: .milliseconds(80))
        }

        // Everything before the first frame is the toolkit reaching the camera,
        // which since 0.8 means standing up a Wi-Fi link to the glasses.
        // Everything after is delivering pictures over a link that already
        // exists. Splitting there is what separates "opening the camera is
        // expensive" from "streaming is expensive".
        if let atFirstFrame = footprintAtFirstFrame {
            look.linkMB = (Double(atFirstFrame) - Double(footprintBefore)) / 1_048_576
            look.framesMB = (Double(MemoryProbe.footprintBytes) - Double(atFirstFrame)) / 1_048_576
        }

        look.framesSeen = delivered.count
        let selected = buffer.best(maxAge: timeout, now: Date(), gate: gate)
        if openedCamera { endLook() }

        switch selected {
        case .failure(let rejection):
            look.rejection = rejection
        case .success(let frame):
            look.frameID = frame.id
            let image = frame.image
            look.jpeg = await Task.detached { VisualFramePipeline.prepare(image) }.value
            if look.jpeg == nil { look.rejection = .noFrames }
        }

        look.totalDuration = Date().timeIntervalSince(startedAt)
        look.memoryDeltaMB = (Double(MemoryProbe.footprintBytes) - Double(footprintBefore)) / 1_048_576
        let summary = String(
            format: "glasses: look %@ — %d frames, %.1fs to first frame, %.1fs total, +%.0f MB (link %+.0f, frames %+.0f)",
            look.succeeded ? "ok" : "failed (\(look.rejection?.rawValue ?? "?"))",
            look.framesSeen, look.startLatency, look.totalDuration,
            look.memoryDeltaMB, look.linkMB, look.framesMB)
        PollyDebugLog.shared.log(summary)
        GlassesRunLog.shared.log(summary)
        return look
    }

    /// Stop watching without disconnecting.
    ///
    /// The camera closes and the session stays. This is what gives the cook
    /// their Wi-Fi back: the toolkit joins an access point hosted by the glasses
    /// to carry frames, so while the camera is open the phone is off the home
    /// network and everything else, Polly's voice included, is on cellular. In a
    /// kitchen with poor signal that is a worse trade than losing vision.
    func pauseWatching() {
        guard camera != nil else { return }
        endLook()
        PollyDebugLog.shared.log("glasses: stopped watching, connection kept")
    }

    /// Start watching again on the connection we already have.
    ///
    /// Returns seconds to the first frame, which is the number that decides
    /// whether vision can be something Chef opens when she needs it. A cold open
    /// measured 14 to 20 seconds; if a warm one is a second or two, watch
    /// windows work and the phone spends most of a cook on Wi-Fi.
    @discardableResult
    func resumeWatching(timeout: TimeInterval = 30) async -> TimeInterval? {
        guard let session, session.state == .started, camera == nil else { return nil }
        let startedAt = Date()
        do {
            try await attachCamera(to: session)
        } catch {
            PollyDebugLog.shared.log("glasses: could not start watching again — \(message(error))")
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if buffer.newest != nil { return Date().timeIntervalSince(startedAt) }
            if isUnavailable { return nil }
            try? await Task.sleep(for: .milliseconds(80))
        }
        return nil
    }

    /// Close the camera but keep the session. Re-establishing the session is the
    /// slow part, so it is deliberately left alive between looks.
    private func endLook() {
        let tokens = streamTokens
        streamTokens.removeAll()
        Task { for token in tokens { await token.cancel() } }
        camera?.stop()
        camera = nil
        previewImage = nil
        if !isUnavailable { state = .ready }
    }

    private func message(_ error: any Error) -> String {
        (error as? any DatError)?.description ?? String(describing: error)
    }

    private func attachCamera(to session: DeviceSession) async throws {
        let config = StreamConfiguration(videoCodec: .raw, resolution: resolution, frameRate: frameRate)
        guard let camera = try session.addCamera(config: config) else {
            state = .unavailable(reason: "The glasses camera is not available.")
            return
        }
        self.camera = camera
        observeStream(camera.stream)
        camera.stream.start()
        let size = resolution.videoFrameSize
        PollyDebugLog.shared.log("glasses: camera \(size.width)x\(size.height) @ \(frameRate) fps")

        // `stream.start()` returns before the stream is running: the state
        // arrives on the publisher a moment later, through
        // `waitingForDevice → starting → streaming`. Returning here would hand
        // the caller a source that says it is not streaming and invite it to
        // tear the whole thing down, which is exactly what happened.
        guard await waitForStreaming() else {
            // Deliberately NOT teardown(): that destroys the DeviceSession,
            // which is the expensive thing we keep alive between looks. One
            // camera failing must not cost the connection, or every later look
            // fails instantly with nothing to look through.
            PollyDebugLog.shared.log("glasses: camera did not reach streaming, session kept")
            throw GlassesLookError.cameraDidNotStart
        }
    }

    /// 25s, not 6. Measured on device, `waitingForDevice -> starting -> streaming`
    /// takes 12 to 19 seconds on a cold camera, so the old 6s timeout gave up on
    /// a camera that was still legitimately coming up.
    private func waitForStreaming(timeout: TimeInterval = 25) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if state == .streaming { return true }
            if isUnavailable { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return state == .streaming
    }

    private func waitForDevice(selector: AutoDeviceSelector, timeout: TimeInterval = 4) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if selector.activeDevice != nil { return true }
            try? await Task.sleep(for: .milliseconds(120))
        }
        return selector.activeDevice != nil
    }

    private func waitForStarted(_ session: DeviceSession, timeout: TimeInterval = 8) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch session.state {
            case .started: return true
            case .stopped, .stopping: return false
            default: try? await Task.sleep(for: .milliseconds(120))
            }
        }
        return session.state == .started
    }

    private func teardown() {
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
        let tokens = self.tokens
        self.tokens.removeAll()
        Task { for token in tokens { await token.cancel() } }

        resumePhoto(nil)
        camera?.stop()
        camera = nil
        session?.stop()
        session = nil
    }

    // MARK: - Frames

    func captureFrame() async -> Data? {
        await prepared(maxAge: defaultMaxFrameAge).jpeg
    }

    /// A real still from the glasses rather than a stream frame, for the times
    /// Polly needs to read a thermometer or judge pastry colour. Falls back to
    /// the best stream frame whenever the photo path cannot deliver, so a
    /// detailed request never comes back empty-handed just because it was greedy.
    func captureHighDetailFrame() async -> Data? {
        guard let camera, state == .streaming, photoContinuation == nil else {
            return await captureFrame()
        }
        guard camera.stream.capturePhoto(format: .jpeg) else {
            PollyDebugLog.shared.log("glasses: capturePhoto refused, using stream frame")
            return await captureFrame()
        }

        let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            photoContinuation = continuation
            // A photo that never arrives must not hang a live cook session.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.resumePhoto(nil)
            }
        }

        guard let data, let image = UIImage(data: data) else {
            PollyDebugLog.shared.log("glasses: photo did not arrive, using stream frame")
            return await captureFrame()
        }
        return await Task.detached { VisualFramePipeline.prepare(image) }.value
    }

    /// The selected frame plus everything the tool layer needs to explain itself.
    func prepared(maxAge: TimeInterval) async -> (jpeg: Data?, frameID: String?, ageMillis: Int?, rejection: VisualFrameRejection?) {
        guard state == .streaming else { return (nil, nil, nil, .noFrames) }
        switch buffer.best(maxAge: maxAge, now: Date(), gate: gate) {
        case .failure(let rejection):
            if let newest = buffer.newest {
                PollyDebugLog.shared.log(String(
                    format: "glasses: refused %@ (sharp %.4f, bright %.3f, %d buffered)",
                    rejection.rawValue, newest.quality.sharpness, newest.quality.brightness, buffer.frames.count))
            } else {
                PollyDebugLog.shared.log("glasses: refused \(rejection.rawValue) (buffer empty)")
            }
            return (nil, nil, nil, rejection)
        case .success(let frame):
            let age = Int(Date().timeIntervalSince(frame.capturedAt) * 1000)
            let image = frame.image
            let jpeg = await Task.detached { VisualFramePipeline.prepare(image) }.value
            return (jpeg, frame.id, age, jpeg == nil ? .noFrames : nil)
        }
    }

    private func ingest(_ frame: BufferedVisualFrame) {
        buffer.insert(frame)
        previewImage = frame.image
    }

    private func resumePhoto(_ data: Data?) {
        guard let continuation = photoContinuation else { return }
        photoContinuation = nil
        continuation.resume(returning: data)
    }

    // MARK: - Observation

    private func observeSession(_ session: DeviceSession) {
        observationTasks.append(Task { [weak self] in
            for await sessionState in session.stateStream() {
                guard let self else { return }
                self.apply(sessionState)
            }
            // The stream finishes once the session is terminal, which is how a
            // folded pair of glasses reaches us.
            guard let self, self.session === session else { return }
            self.handleSessionEnded()
        })
        observationTasks.append(Task { [weak self] in
            for await error in session.errorStream() {
                PollyDebugLog.shared.log("glasses: session error — \(error.description)")
                _ = self
            }
        })
    }

    private func apply(_ sessionState: DeviceSessionState) {
        switch sessionState {
        case .paused:
            // Do not restart. The device resumes or stops on its own, and
            // fighting it just churns sessions.
            state = .paused
        case .stopped:
            handleSessionEnded()
        default:
            break
        }
    }

    private func handleSessionEnded() {
        guard state != .off else { return }
        state = .unavailable(reason: "The glasses disconnected.")
        previewImage = nil
        buffer.removeAll()
        teardown()
        PollyDebugLog.shared.log("glasses: session ended by device")
    }

    private func observeStream(_ stream: MWDATCamera.Stream) {
        streamTokens.append(stream.statePublisher.listen { [weak self] streamState in
            Task { @MainActor in self?.apply(streamState) }
        })
        streamTokens.append(stream.errorPublisher.listen { [weak self] error in
            Task { @MainActor in self?.applyStreamError(error) }
        })
        streamTokens.append(stream.photoDataPublisher.listen { [weak self] photo in
            let data = photo.data
            Task { @MainActor in self?.resumePhoto(data) }
        })
        streamTokens.append(stream.videoFramePublisher.listen { [weak self] frame in
            // Decode and measure off the main actor: this runs several times a
            // second and the cook session's UI is on the other side of it.
            guard let self else { return }
            // Counted before admission, so the number reflects what the toolkit
            // delivered rather than what we chose to decode.
            self.delivered.increment()
            guard self.admission.admit() else { return }
            // The toolkit calls this on its own thread, which has no autorelease
            // pool of its own. Decoding a frame and measuring it produces several
            // megabytes of autoreleased CGImage and UIImage temporaries, and
            // without a pool to drain they accumulate for the life of the
            // stream: about 5 MB per frame, which ate 2 GB in a minute.
            let decoded: (UIImage, VisualFrameQuality)? = autoreleasepool {
                // NOT frame.makeUIImage(): measured at ~5.8 MB per call that
                // never comes back. See VisualFramePipeline.image(from:).
                guard let image = VisualFramePipeline.image(from: frame.sampleBuffer),
                      let quality = VisualFrameGate().measure(image) else { return nil }
                return (image, quality)
            }
            guard let (image, quality) = decoded else {
                self.admission.release()
                return
            }
            let captured = Date()
            Task { @MainActor in
                defer { self.admission.release() }
                self.frameSequence += 1
                self.ingest(
                    BufferedVisualFrame(
                        id: "g\(self.frameSequence)",
                        image: image,
                        quality: quality,
                        capturedAt: captured
                    )
                )
            }
        })
    }

    private func apply(_ streamState: StreamState) {
        switch streamState {
        case .streaming:
            state = .streaming
        case .paused:
            state = .paused
        case .starting, .waitingForDevice:
            state = .starting
        case .stopped, .stopping:
            if state == .streaming || state == .paused { state = .off }
        @unknown default:
            break
        }
    }

    private func applyStreamError(_ error: StreamError) {
        PollyDebugLog.shared.log("glasses: stream error — \(error.description)")
        switch error {
        case .permissionDenied:
            state = .unavailable(reason: "Camera access for the glasses was denied.")
        case .hingesClosed:
            state = .unavailable(reason: "The glasses were folded shut.")
        case .thermalCritical, .thermalEmergency, .peakPowerShutdown:
            state = .unavailable(reason: "The glasses got too hot and stopped the camera.")
        case .batteryCritical:
            state = .unavailable(reason: "The glasses are out of battery.")
        case .deviceNotConnected, .deviceNotFound:
            state = .unavailable(reason: "The glasses disconnected.")
        default:
            break
        }
    }
}
