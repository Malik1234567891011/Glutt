import MWDATCamera
import MWDATCore
import MWDATMockDevice
import SwiftUI
import UIKit

/// Isolated spike for Meta's Device Access Toolkit. Launch-arg gated
/// (`-glassesSpike`), touches no Polly code, and exists to answer one question
/// before we refactor anything: can we hold a camera session open and get usable
/// frames out of it?
///
/// It drives the REAL toolkit. MockDeviceKit only swaps the device underneath,
/// so every call here is the same call we will make against hardware — which is
/// the whole reason to build it this way rather than stubbing a fake camera.
///
/// Exit criteria:
/// 1. Session reaches `.started` and the stream reaches `.streaming`.
/// 2. Frames arrive continuously at roughly the configured rate.
/// 3. `capturePhoto` returns a still while the stream is live.
/// 4. `doff` / `fold` drive the session somewhere sane, and teardown is clean.
struct GlassesSpikeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = GlassesSpikeModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Glasses spike")
                    .font(.headline)
                Spacer()
                Button(model.justCopied ? "Copied ✓" : "Copy log") { model.copyLog() }
                Button("Close") {
                    model.teardown()
                    dismiss()
                }
            }

            statusGrid

            HStack(alignment: .top, spacing: 10) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.frameSummary)
                        .font(.caption.monospaced())
                    if let photo = model.capturedPhoto {
                        Text("capturePhoto:")
                            .font(.caption2)
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 150)

            controls

            log
        }
        .padding()
        .onDisappear { model.teardown() }
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
            GridRow {
                Text("toolkit").foregroundStyle(.secondary)
                Text(model.toolkitStatus)
            }
            GridRow {
                Text("registration").foregroundStyle(.secondary)
                Text(model.registrationStatus)
            }
            GridRow {
                Text("permission").foregroundStyle(.secondary)
                Text(model.permissionStatus)
            }
            GridRow {
                Text("session").foregroundStyle(.secondary)
                Text(model.sessionStatus)
            }
            GridRow {
                Text("stream").foregroundStyle(.secondary)
                Text(model.streamStatus)
            }
            GridRow {
                Text("polly source").foregroundStyle(.secondary)
                Text(model.coordinatorStatus)
            }
        }
        .font(.caption.monospaced())
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.15))
            if let frame = model.latestFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("no frames")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 84, height: 150)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                labelled("device") {
                    button("Enable") { model.enableMockKit() }
                    button("Pair") { model.pairGlasses() }
                    button("On") { model.power(on: true) }
                    button("Unfold") { model.fold(false) }
                    button("Don") { model.don(true) }
                }
                labelled("feed") {
                    button("Wok") { model.useFixtureFeed() }
                    button("Phone cam") { model.usePhoneCameraFeed() }
                }
                labelled("permission") {
                    button("Check") { model.checkPermission() }
                    button("Request") { model.requestPermission() }
                    button("Force deny") { model.forceDenyPermission() }
                }
                labelled("stream") {
                    Picker("", selection: $model.resolutionChoice) {
                        Text("low").tag(GlassesSpikeModel.ResolutionChoice.low)
                        Text("med").tag(GlassesSpikeModel.ResolutionChoice.medium)
                        Text("high").tag(GlassesSpikeModel.ResolutionChoice.high)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    Picker("", selection: $model.frameRate) {
                        ForEach(GlassesSpikeModel.frameRates, id: \.self) { rate in
                            Text("\(rate)").tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                labelled("run") {
                    button("Start session") { model.startSession() }
                    button("Add camera") { model.addCameraAndStream() }
                    button("Photo") { model.capturePhoto() }
                }
                labelled("polly") {
                    button("Coordinator") { model.startCoordinator() }
                    button("Ask frame") { model.requestFrameLikePolly(highDetail: false) }
                    button("Ask detail") { model.requestFrameLikePolly(highDetail: true) }
                }
                labelled("interrupt") {
                    button("Doff") { model.don(false) }
                    button("Fold") { model.fold(true) }
                    button("Power off") { model.power(on: false) }
                    button("Teardown") { model.teardown() }
                }
            }
        }
        // Takes whatever the log leaves. Fixed heights clipped the run and
        // interrupt rows off the bottom, where they were listed in the
        // accessibility tree but could not actually be tapped.
        .frame(maxHeight: .infinity)
    }

    /// Label sits inline rather than on its own line. Five stacked title rows
    /// cost about eighty points of height, which was enough to push the run and
    /// interrupt buttons off the bottom of a phone screen.
    private func labelled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)
                content()
            }
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(line.hasPrefix("!") ? .red : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .onChange(of: model.log.count) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .frame(height: 200)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
@Observable
final class GlassesSpikeModel {
    enum ResolutionChoice: Hashable {
        case low, medium, high

        var streaming: StreamingResolution {
            switch self {
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
            }
        }
    }

    /// Every rate the toolkit accepts. 24 matches the mock fixture's native rate,
    /// so nothing is invented or dropped when playing it back.
    static let frameRates: [UInt] = [2, 7, 15, 24, 30]

    var resolutionChoice: ResolutionChoice = .medium
    var frameRate: UInt = 24

    private(set) var toolkitStatus = "not configured"
    private(set) var registrationStatus = "unknown"
    private(set) var permissionStatus = "unknown"
    private(set) var sessionStatus = "none"
    private(set) var streamStatus = "none"
    private(set) var latestFrame: UIImage?
    private(set) var capturedPhoto: UIImage?
    private(set) var frameSummary = "0 frames"
    private(set) var log: [String] = []
    private(set) var justCopied = false

    private var mockGlasses: (any MockGlasses)?
    /// Built lazily: the coordinator is the thing Polly holds, and starting it
    /// here proves the same path a cook session takes.
    private var coordinator: PollyVisualSourceCoordinator?
    private(set) var coordinatorStatus = "not started"
    /// Long-lived on purpose. `AutoDeviceSelector` resolves its active device by
    /// observing, so one constructed and used in the same breath still has a nil
    /// device and `createSession` fails with `noEligibleDevice`.
    private var selector: AutoDeviceSelector?
    private var session: DeviceSession?
    private var camera: Camera?
    private var tokens: [any AnyListenerToken] = []
    private var streamTasks: [Task<Void, Never>] = []

    private var frameCount = 0
    private var firstFrameAt: Date?
    private var lastFrameAt: Date?
    private let startedAt = Date()

    init() {
        toolkitStatus = GlassesSupport.shared.isAvailable
            ? "configured"
            : "unavailable: \(GlassesSupport.shared.configurationFailure ?? "not attempted")"
        registrationStatus = describe(Wearables.shared.registrationState)
        append("spike ready. Enable mock kit, pair, power on, unfold, don, then start.")
    }

    // MARK: - Mock device

    /// `initiallyRegistered` is what lets this run with no Wearables Developer
    /// Center account: the mock device reports itself already approved, so the
    /// Meta AI round trip never has to happen.
    func enableMockKit() {
        MockDeviceKit.shared.enable(
            config: MockDeviceKitConfig(initiallyRegistered: true, initialPermissionsGranted: true)
        )
        append("mock kit enabled (registered=\(MockDeviceKit.shared.isEnabled))")
        registrationStatus = describe(Wearables.shared.registrationState)
        observeRegistration()
        observeDevices()
        selector = AutoDeviceSelector(wearables: Wearables.shared)
    }

    func pairGlasses() {
        do {
            let glasses = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
            mockGlasses = glasses
            append("paired mock Ray-Ban Meta — id \(glasses.deviceIdentifier)")
        } catch {
            append("! pairGlasses failed: \(message(error))")
        }
    }

    func power(on: Bool) {
        guard let mockGlasses else { return append("! no paired device") }
        on ? mockGlasses.powerOn() : mockGlasses.powerOff()
        append("device power \(on ? "on" : "off")")
    }

    func fold(_ folded: Bool) {
        guard let mockGlasses else { return append("! no paired device") }
        folded ? mockGlasses.fold() : mockGlasses.unfold()
        append("hinges \(folded ? "folded (expect the session to stop)" : "unfolded")")
    }

    func don(_ worn: Bool) {
        guard let mockGlasses else { return append("! no paired device") }
        worn ? mockGlasses.don() : mockGlasses.doff()
        append("glasses \(worn ? "donned" : "doffed")")
    }

    // MARK: - Feed

    func useFixtureFeed() {
        guard let mockGlasses else { return append("! no paired device") }
        guard let url = Bundle.main.url(forResource: "glasses-mock-wok", withExtension: "mov") else {
            return append("! glasses-mock-wok.mov missing from the bundle")
        }
        mockGlasses.services.camera.setCameraFeed(fileURL: url)
        if let still = Bundle.main.url(forResource: "glasses-mock-still", withExtension: "jpg") {
            mockGlasses.services.camera.setCapturedImage(fileURL: still)
        }
        append("feed: wok fixture (HEVC 504x896)")
    }

    /// On a real phone this points the back camera at the world and feeds it in
    /// as if it were the glasses. Closer to a real POV rehearsal than a file.
    func usePhoneCameraFeed() {
        guard let mockGlasses else { return append("! no paired device") }
        mockGlasses.services.camera.setCameraFeed(cameraFacing: .back)
        append("feed: phone back camera")
    }

    // MARK: - Permission

    func checkPermission() {
        Task {
            do {
                let status = try await Wearables.shared.checkPermissionStatus(.camera)
                permissionStatus = describe(status)
                append("permission status: \(describe(status))")
            } catch {
                permissionStatus = "error"
                append("! checkPermissionStatus: \(message(error))")
            }
        }
    }

    func requestPermission() {
        Task {
            do {
                let status = try await Wearables.shared.requestPermission(.camera)
                permissionStatus = describe(status)
                append("permission request returned: \(describe(status))")
            } catch {
                permissionStatus = "error"
                append("! requestPermission: \(message(error))")
            }
        }
    }

    /// The failure we actually have to handle gracefully in the cook session.
    func forceDenyPermission() {
        MockDeviceKit.shared.permissions.set(.camera, .denied)
        MockDeviceKit.shared.permissions.setRequestResult(.camera, result: .denied)
        append("mock permissions forced to denied")
    }

    // MARK: - The production path

    /// Everything above drives the toolkit directly. This drives what Polly
    /// actually uses: the coordinator picks a source, the gate picks a frame,
    /// and the result is shaped exactly as the `request_camera_frame` tool
    /// returns it. If this works, the cook session works.
    func startCoordinator() {
        Task {
            let coordinator = self.coordinator ?? PollyVisualSourceCoordinator(
                phone: PhoneCameraVisualSource(camera: PollyCameraController())
            )
            self.coordinator = coordinator
            append("coordinator: starting (prefers glasses)")
            await coordinator.start()
            let chosen = coordinator.activeKind?.toolName ?? "nothing"
            append("coordinator: active source is \(chosen)")
            append("coordinator: glasses state \(coordinator.glasses.state)")
            coordinatorStatus = chosen
            // The source reports its own failures to the Polly debug log, which
            // is where a real cook session's diagnostics live. Mirror the tail
            // here so the spike does not have to guess.
            for line in PollyDebugLog.shared.dump().split(separator: "\n").suffix(6) {
                append("  polly| \(line)")
            }
        }
    }

    func requestFrameLikePolly(highDetail: Bool) {
        guard let coordinator else { return append("! start the coordinator first") }
        Task {
            let started = Date()
            let capture = await coordinator.preparedFrame(
                maxAge: 1.5,
                highDetail: highDetail
            )
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            if let jpeg = capture.jpeg {
                append(String(
                    format: "%@ → captured from %@, %d bytes, age %@ms, took %dms",
                    highDetail ? "high_detail" : "fast",
                    capture.source?.toolName ?? "?",
                    jpeg.count,
                    capture.ageMillis.map(String.init) ?? "?",
                    elapsed
                ))
                capturedPhoto = UIImage(data: jpeg)
            } else {
                append("! \(highDetail ? "high_detail" : "fast") refused: \(capture.rejection?.rawValue ?? "unknown")")
                for line in PollyDebugLog.shared.dump().split(separator: "\n").suffix(2) {
                    append("  polly| \(line)")
                }
            }
        }
    }

    // MARK: - Session and stream

    func startSession() {
        guard session == nil else { return append("! session already exists") }
        guard let selector else { return append("! enable the mock kit first") }
        Task {
            guard await waitForEligibleDevice() else {
                sessionStatus = "no device"
                return append("! no eligible device appeared. Power on and unfold first.")
            }
            do {
                let session = try Wearables.shared.createSession(deviceSelector: selector)
                self.session = session
                sessionStatus = describe(session.state)
                observeSession(session)
                try session.start()
                append("session.start() accepted, waiting for .started")
            } catch {
                append("! session failed: \(message(error))")
                sessionStatus = "failed"
                session = nil
            }
        }
    }

    /// The selector resolves asynchronously. Poll rather than fire blind, so a
    /// slow device list reads as "waiting" instead of `noEligibleDevice`.
    private func waitForEligibleDevice(timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if selector?.activeDevice != nil { return true }
            if !Wearables.shared.devices.isEmpty, selector?.activeDevice == nil {
                append("devices present but selector has not chosen one yet")
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return selector?.activeDevice != nil
    }

    func addCameraAndStream() {
        guard let session else { return append("! no session") }
        guard camera == nil else { return append("! camera already added") }
        guard session.state == .started else {
            return append("! session is \(describe(session.state)), must be started before addCamera")
        }
        let config = StreamConfiguration(
            videoCodec: .raw,
            resolution: resolutionChoice.streaming,
            frameRate: frameRate
        )
        do {
            guard let camera = try session.addCamera(config: config) else {
                return append("! addCamera returned nil")
            }
            self.camera = camera
            let size = resolutionChoice.streaming.videoFrameSize
            append("camera added — \(size.width)x\(size.height) @ \(frameRate) fps")
            observeStream(camera.stream)
            camera.stream.start()
            append("stream.start() called")
        } catch {
            append("! addCamera failed: \(message(error))")
        }
    }

    func capturePhoto() {
        guard let camera else { return append("! no camera") }
        let accepted = camera.stream.capturePhoto(format: .jpeg)
        append("capturePhoto(.jpeg) accepted=\(accepted)")
    }

    func teardown() {
        streamTasks.forEach { $0.cancel() }
        streamTasks.removeAll()
        let tokens = self.tokens
        self.tokens.removeAll()
        Task { for token in tokens { await token.cancel() } }

        camera?.stop()
        camera = nil
        session?.stop()
        session = nil
        sessionStatus = "none"
        streamStatus = "none"
        append("torn down")
    }

    // MARK: - Observation

    private func observeRegistration() {
        let token = Wearables.shared.addRegistrationStateListener { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.registrationStatus = self.describe(state)
                self.append("registration → \(self.describe(state))")
            }
        }
        tokens.append(token)
    }

    private func observeDevices() {
        let token = Wearables.shared.addDevicesListener { [weak self] devices in
            Task { @MainActor in
                self?.append("devices → \(devices.count): \(devices.map { String($0.prefix(8)) }.joined(separator: ","))")
            }
        }
        tokens.append(token)
    }

    private func observeSession(_ session: DeviceSession) {
        streamTasks.append(Task { [weak self] in
            for await state in session.stateStream() {
                guard let self else { return }
                self.sessionStatus = self.describe(state)
                self.append("session → \(self.describe(state))")
            }
            self?.append("session state stream finished (terminal)")
        })
        streamTasks.append(Task { [weak self] in
            for await error in session.errorStream() {
                self?.append("! session error: \(error.description)")
            }
        })
    }

    // `MWDATCamera.Stream` in full: bare `Stream` collides with Foundation's.
    private func observeStream(_ stream: MWDATCamera.Stream) {
        tokens.append(stream.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.streamStatus = self.describe(state)
                self.append("stream → \(self.describe(state))")
            }
        })
        tokens.append(stream.errorPublisher.listen { [weak self] error in
            Task { @MainActor in
                self?.append("! stream error: \(error.description)")
            }
        })
        tokens.append(stream.videoFramePublisher.listen { [weak self] frame in
            // Decode off the main actor; only the finished image hops over.
            let image = frame.makeUIImage()
            Task { @MainActor in
                self?.ingest(image)
            }
        })
        tokens.append(stream.photoDataPublisher.listen { [weak self] photo in
            let image = UIImage(data: photo.data)
            let byteCount = photo.data.count
            Task { @MainActor in
                self?.capturedPhoto = image
                self?.append("photo received — \(byteCount) bytes, \(image == nil ? "UNDECODABLE" : "decoded")")
            }
        })
    }

    private func ingest(_ image: UIImage?) {
        guard let image else { return append("! frame arrived but makeUIImage returned nil") }
        let now = Date()
        if firstFrameAt == nil {
            firstFrameAt = now
            append("first frame — \(Int(image.size.width))x\(Int(image.size.height))")
        }
        frameCount += 1
        lastFrameAt = now
        latestFrame = image

        let elapsed = now.timeIntervalSince(firstFrameAt ?? now)
        let fps = elapsed > 0 ? Double(frameCount - 1) / elapsed : 0
        frameSummary = String(
            format: "%d frames\n%.1f fps measured\n%dx%d",
            frameCount, fps, Int(image.size.width), Int(image.size.height)
        )
    }

    // MARK: - Plumbing

    private func describe(_ state: DeviceSessionState) -> String { state.description }
    private func describe(_ state: RegistrationState) -> String { state.description }
    /// `StreamState` is the one state enum the toolkit ships without a
    /// `description`, so it gets the reflective spelling.
    private func describe(_ state: StreamState) -> String { String(describing: state) }
    private func describe(_ status: PermissionStatus) -> String {
        status == .granted ? "granted" : "denied"
    }

    /// The toolkit throws typed errors, but this target is still in Swift 5.10
    /// language mode, where `catch` widens them back to `any Error`. Recover the
    /// readable text rather than printing an opaque enum case.
    private func message(_ error: any Error) -> String {
        (error as? any DatError)?.description ?? String(describing: error)
    }

    func copyLog() {
        let device = UIDevice.current
        let header = "Glasses spike — \(device.systemName) \(device.systemVersion) — \(Date().formatted())"
        UIPasteboard.general.string = ([header] + log).joined(separator: "\n")
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justCopied = false
        }
    }

    private func append(_ line: String) {
        log.append(String(format: "%6.1f  %@", Date().timeIntervalSince(startedAt), line))
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}
