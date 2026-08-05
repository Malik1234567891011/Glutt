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
    private var observationTasks: [Task<Void, Never>] = []
    private var photoContinuation: CheckedContinuation<Data?, Never>?
    private var frameSequence = 0

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
            try await attachCamera(to: session)
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
            state = .unavailable(reason: "The glasses camera did not start.")
            PollyDebugLog.shared.log("glasses: stream never reached streaming")
            teardown()
            return
        }
    }

    private func waitForStreaming(timeout: TimeInterval = 6) async -> Bool {
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
        tokens.append(stream.statePublisher.listen { [weak self] streamState in
            Task { @MainActor in self?.apply(streamState) }
        })
        tokens.append(stream.errorPublisher.listen { [weak self] error in
            Task { @MainActor in self?.applyStreamError(error) }
        })
        tokens.append(stream.photoDataPublisher.listen { [weak self] photo in
            let data = photo.data
            Task { @MainActor in self?.resumePhoto(data) }
        })
        tokens.append(stream.videoFramePublisher.listen { [weak self] frame in
            // Decode and measure off the main actor: this runs several times a
            // second and the cook session's UI is on the other side of it.
            guard let image = frame.makeUIImage() else { return }
            let gate = VisualFrameGate()
            guard let quality = gate.measure(image) else { return }
            let captured = Date()
            Task { @MainActor in
                guard let self else { return }
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
