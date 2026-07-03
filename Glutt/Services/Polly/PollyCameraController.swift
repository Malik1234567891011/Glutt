import AVFoundation
import CoreImage
import Observation
import UIKit

/// Sliding-gate policy for watch mode: at most one frame per `interval` while
/// enabled. Pure and synchronous — the session controller drives it with its
/// injected clock, and tests drive it with fixed dates. No timers in here.
struct WatchModeScheduler: Equatable {
    var isEnabled: Bool
    var interval: TimeInterval
    private(set) var lastSent: Date?

    init(isEnabled: Bool = false, interval: TimeInterval = PollyConfig.watchFrameInterval) {
        self.isEnabled = isEnabled
        self.interval = interval
    }

    /// True when a frame is due right now; records `now` as the send time on
    /// true. Toggling `isEnabled` never resets `lastSent` — re-enabling watch
    /// mode mid-interval must not burst an extra frame (cost control).
    mutating func shouldSendFrame(now: Date) -> Bool {
        guard isEnabled else { return false }
        if let last = lastSent, now.timeIntervalSince(last) < interval { return false }
        lastSent = now
        return true
    }
}

/// Live camera for Polly sessions: 720p capture, back wide camera by default,
/// flippable, keeps only the latest frame for on-demand JPEG snapshots.
/// Every hardware touch is guarded so the simulator (no camera) just leaves
/// `isRunning == false` and `captureFrame()` returning nil.
@MainActor
@Observable
final class PollyCameraController: NSObject {
    private(set) var isRunning = false
    private(set) var isAuthorized = false
    let previewLayer: AVCaptureVideoPreviewLayer

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let frameSink = LatestFrameSink()
    private let sampleQueue = DispatchQueue(label: "com.omarlahmimi.glutt.polly.camera")
    private var position: AVCaptureDevice.Position = .back

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    /// Requests camera permission if needed, then configures and starts the
    /// session off-main (`startRunning` blocks). On simulator or when denied,
    /// returns with `isRunning == false`.
    func start() async {
        guard !isRunning else { return }
        isAuthorized = await requestAuthorization()
        guard isAuthorized, configureSession(position: position) else { return }

        let session = self.session
        await Task.detached { session.startRunning() }.value
        isRunning = session.isRunning
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let session = self.session
        Task.detached { session.stopRunning() }
    }

    /// Swaps to the opposite camera. Reconfiguration happens inside
    /// beginConfiguration/commitConfiguration so the session never tears down.
    /// `position` only advances when the hardware swap actually succeeded, so
    /// stored state can't diverge from the live device (e.g. no front camera).
    func flip() {
        guard isRunning else { return }
        let flipped: AVCaptureDevice.Position = (position == .back) ? .front : .back
        if configureSession(position: flipped) {
            position = flipped
        } else {
            configureSession(position: position)
        }
    }

    /// Latest frame as a JPEG, downscaled to `PollyConfig.frameMaxDimension`
    /// at `PollyConfig.frameJPEGQuality` — same UIGraphicsImageRenderer
    /// approach as `ImagePrep.prepareForVision`. Nil when not running or no
    /// frame has arrived yet. Only the pixel-buffer handoff happens on the
    /// main actor; CIContext rendering + resize + JPEG all run detached so a
    /// capture never janks the session UI.
    func captureFrame() async -> Data? {
        guard isRunning, let buffer = frameSink.latestPixelBuffer() else { return nil }
        let sink = frameSink
        let maxDimension = PollyConfig.frameMaxDimension
        let quality = PollyConfig.frameJPEGQuality

        return await Task.detached { () -> Data? in
            guard let image = sink.image(from: buffer) else { return nil }
            let largestSide = max(image.size.width, image.size.height)
            guard largestSide > 0 else { return nil }

            let scale = min(1, maxDimension / largestSide)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            return resized.jpegData(compressionQuality: quality)
        }.value
    }

    // MARK: - Session plumbing

    private func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Installs the input for `position` (replacing any existing input) and
    /// the shared data output. Returns false when no camera device exists
    /// (simulator) or the session rejects the input.
    @discardableResult
    private func configureSession(position: AVCaptureDevice.Position) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720
        for input in session.inputs { session.removeInput(input) }
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return false }
        session.addInput(input)

        if !session.outputs.contains(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(frameSink, queue: sampleQueue)
            guard session.canAddOutput(output) else { return false }
            session.addOutput(output)
        }

        // Portrait-only app: keep frames upright so Polly isn't judging
        // sideways pancakes.
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return true
    }

    /// Sample-buffer delegate that retains only the most recent pixel buffer.
    /// Callbacks land on the capture serial queue; the lock makes reads safe
    /// from the main actor. Explicitly nonisolated — it must never hop to the
    /// main actor the enclosing controller lives on.
    private final class LatestFrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private nonisolated(unsafe) var latestBuffer: CVPixelBuffer?
        /// One shared context — allocating a CIContext per frame is the
        /// expensive part of rendering.
        private let context = CIContext()

        nonisolated func captureOutput(_ output: AVCaptureOutput,
                                       didOutput sampleBuffer: CMSampleBuffer,
                                       from connection: AVCaptureConnection) {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            lock.lock()
            latestBuffer = buffer
            lock.unlock()
        }

        /// Cheap main-actor-safe handoff: just the locked pointer read.
        nonisolated func latestPixelBuffer() -> CVPixelBuffer? {
            lock.lock()
            defer { lock.unlock() }
            return latestBuffer
        }

        /// Full render (CIContext -> CGImage -> UIImage). Call off-main.
        nonisolated func image(from buffer: CVPixelBuffer) -> UIImage? {
            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return UIImage(cgImage: cgImage)
        }
    }
}
