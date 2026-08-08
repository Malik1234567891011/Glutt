import MWDATCamera
import MWDATCore
#if canImport(MWDATMockDevice)
import MWDATMockDevice
#endif
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
                // In the header because the INTERRUPT row keeps getting clipped
                // off the bottom, and a teardown you cannot reach is worse than
                // no teardown: it silently invalidates every experiment.
                Button("Stop") { model.teardown() }
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
        .task { model.start() }
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
            GridRow {
                Text("memory").foregroundStyle(.secondary)
                Text(model.memoryStatus)
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
                labelled("meta ai") {
                    button("Register") { model.registerWithMetaAI() }
                    button("Update glasses app") { model.openGlassesAppUpdate() }
                    button("Firmware") { model.openFirmwareUpdate() }
                    button("Unregister") { model.unregisterFromMetaAI() }
                }
#if canImport(MWDATMockDevice)
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
#endif
                labelled("permission") {
                    button("Check") { model.checkPermission() }
                    button("Request") { model.requestPermission() }
#if canImport(MWDATMockDevice)
                    button("Force deny") { model.forceDenyPermission() }
#endif
                }
                labelled("stream") {
                    ForEach(GlassesSpikeModel.ResolutionChoice.allCases) { choice in
                        toggleButton(
                            choice.label,
                            selected: model.resolutionChoice == choice
                        ) { model.resolutionChoice = choice }
                    }
                    Divider().frame(height: 16)
                    ForEach(GlassesSpikeModel.frameRates, id: \.self) { rate in
                        toggleButton("\(rate)", selected: model.frameRate == rate) {
                            model.frameRate = rate
                        }
                    }
                }
                labelled("isolate") {
                    ForEach(GlassesSpikeModel.FrameProbe.allCases) { probe in
                        toggleButton(probe.rawValue, selected: model.frameProbe == probe) {
                            model.frameProbe = probe
                        }
                    }
                    Divider().frame(height: 16)
                    toggleButton("hvc1", selected: model.useCompressedCodec) {
                        model.useCompressedCodec.toggle()
                    }
                }
                labelled("run") {
                    button("Start session") { model.startSession() }
                    button("Add camera") { model.addCameraAndStream() }
                    button("Photo") { model.capturePhoto() }
                }
                labelled("polly") {
                    button("Look x5") { model.runLookSeries() }
                    button("Long look") { model.runLongLook() }
                    button("Warm reopen") { model.runWarmReopen() }
                    button("Coordinator") { model.startCoordinator() }
                    button("Ask frame") { model.requestFrameLikePolly(highDetail: false) }
                    button("Ask detail") { model.requestFrameLikePolly(highDetail: true) }
                }
                labelled("interrupt") {
#if canImport(MWDATMockDevice)
                    button("Doff") { model.don(false) }
                    button("Fold") { model.fold(true) }
                    button("Power off") { model.power(on: false) }
#endif
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

    /// A one-of-many choice, spelled as a button rather than a `Picker`.
    ///
    /// Every row on this screen is its own horizontal `ScrollView`, and a
    /// segmented picker inside one is effectively dead: the scroll gesture wins
    /// the tap, so the control renders correctly, highlights the current value,
    /// and silently refuses to change it. That cost a test run — resolution and
    /// frame rate could not be moved off med/7 at all. Plain buttons in the same
    /// rows have always worked, so these are plain buttons.
    private func toggleButton(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.caption.weight(selected ? .bold : .regular))
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.15)
                )
            )
            .overlay(
                Capsule().stroke(selected ? Color.accentColor : .clear, lineWidth: 1)
            )
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
    enum ResolutionChoice: String, Hashable, CaseIterable, Identifiable {
        case low, medium, high

        var id: Self { self }

        var label: String {
            switch self {
            case .low: return "low"
            case .medium: return "med"
            case .high: return "high"
            }
        }

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

    /// Resolution and frame rate survive closing the screen.
    ///
    /// They did not, and it cost a hardware run: the sheet was reopened, the
    /// pickers silently reverted to med/7, and a measurement meant to test
    /// 2 fps was taken at 7 fps and looked like every run before it. A
    /// diagnostic screen whose settings reset between attempts will keep
    /// producing that mistake, and each one costs a full battery-warm run on a
    /// real pair of glasses.
    var resolutionChoice: ResolutionChoice = {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-res"), index + 1 < args.count {
            switch args[index + 1] {
            case "low": return .low
            case "high": return .high
            default: return .medium
            }
        }
        let stored = UserDefaults.standard.string(forKey: GlassesSpikeModel.resolutionKey) ?? ""
        return ResolutionChoice(rawValue: stored) ?? .medium
    }() {
        didSet { UserDefaults.standard.set(resolutionChoice.rawValue, forKey: GlassesSpikeModel.resolutionKey) }
    }

    /// 7, matching `MetaGlassesVisualSource`. 24 was only ever chosen to match
    /// the mock fixture's native rate, and on real glasses it is 3.4x the frame
    /// traffic for no benefit: cooking changes slowly and the gate only needs a
    /// few candidates a second.
    var frameRate: UInt = {
        let stored = UserDefaults.standard.integer(forKey: GlassesSpikeModel.frameRateKey)
        return GlassesSpikeModel.frameRates.contains(UInt(max(0, stored))) ? UInt(stored) : 7
    }() {
        didSet { UserDefaults.standard.set(Int(frameRate), forKey: GlassesSpikeModel.frameRateKey) }
    }

    private static let resolutionKey = "glassesSpike.resolution"
    private static let frameRateKey = "glassesSpike.frameRate"
    /// The isolation ladder. Each rung adds exactly one thing, so the rung where
    /// the memory slope appears names the culprit. Set before Add camera.
    enum FrameProbe: String, CaseIterable, Identifiable {
        /// Do not subscribe to videoFramePublisher AT ALL. If memory still
        /// climbs here, nothing in our code is responsible and the growth is
        /// inside the toolkit. This is the test that settles the argument.
        case noListener = "none"
        /// Subscribe, increment a counter on the delivery thread, return. No
        /// main-actor hop, no image, no Task.
        case countOnly = "count"
        /// Decode and throw it away immediately inside an autorelease pool.
        case decodeDiscard = "decode"
        /// Everything: decode, thumbnail, preview, main-actor hop.
        case fullPipeline = "full"

        var id: String { rawValue }
    }

    /// Driven by launch argument so an experiment is one launch, not a sequence
    /// of taps on a segmented control that may or may not register.
    /// `-probe none|count|decode|full`, `-res low|med|high`, `-hvc1`, `-autoStream`.
    var frameProbe: FrameProbe = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-probe"), index + 1 < args.count,
              let probe = FrameProbe(rawValue: args[index + 1]) else { return .fullPipeline }
        return probe
    }()
    /// `.raw` hands over decoded frames the toolkit owns; `.hvc1` hands over
    /// compressed samples, which is why Meta's sample ships a VideoFrameDecoder.
    var useCompressedCodec = ProcessInfo.processInfo.arguments.contains("-hvc1")

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

#if canImport(MWDATMockDevice)
    private var mockGlasses: (any MockGlasses)?
#endif
    /// Built lazily: the coordinator is the thing Polly holds, and starting it
    /// here proves the same path a cook session takes.
    private var coordinator: PollyVisualSourceCoordinator?
    private(set) var coordinatorStatus = "not started"
    private(set) var memoryStatus = MemoryProbe.summary
    /// Lowest headroom seen. Logged as it falls so the copied log shows the
    /// approach to the cliff even though the app cannot log its own death.
    private var lowestAvailableMB = Double.greatestFiniteMagnitude
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
    /// One frame in flight at a time. See `FrameAdmission`: without it this
    /// queued a main-actor Task per delivered frame, each holding a decoded
    /// 504x896 image, and the phone killed the app for memory.
    private let admission = FrameAdmission()
    private var memoryTimer: Task<Void, Never>?
    private var probeStartedAt: Date?
    private var probeStartFootprint: UInt64 = 0
    /// Counted on the delivery thread, so the count-only rung costs nothing.
    private let deliveredCounter = FrameCounter()
    private let startedAt = Date()

    init() {}

    private var hasStarted = false

    /// Everything that used to be in `init`, moved out of it.
    ///
    /// `@State private var model = GlassesSpikeModel()` re-evaluates
    /// `GlassesSpikeModel()` on **every** initialisation of the view struct and
    /// keeps only the first, so anything with a side effect in `init` runs a
    /// handful of times per appearance. That put eight run markers into the log
    /// inside two seconds, which left the newest marker holding two lines of
    /// boilerplate while the actual run sat under an older one, which is exactly
    /// why "Copy log" kept coming back with the wrong thing.
    ///
    /// Called from `.task`, which runs once, on the instance SwiftUI actually
    /// kept.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        toolkitStatus = GlassesSupport.shared.isAvailable
            ? "configured"
            : "unavailable: \(GlassesSupport.shared.configurationFailure ?? "not attempted")"
        registrationStatus = describe(Wearables.shared.registrationState)
        // Observed from the start: with real glasses nobody touches the mock kit,
        // and the registration listener used to be installed only by enabling it.
        observeRegistration()
        observeDevices()
        selector = AutoDeviceSelector(wearables: Wearables.shared)
        // Marks a boundary in the on-disk log. Everything above it is a previous
        // run, which is deliberately kept: after a memory kill the run we want
        // to read is the one before this launch.
        GlassesRunLog.shared.startRun("glasses spike run")
        append("spike ready. REAL glasses: tap Register, then Start session.")
        if ProcessInfo.processInfo.arguments.contains("-autoStream") {
            append("auto: probe=\(frameProbe.rawValue) res=\(resolutionChoice) hvc1=\(useCompressedCodec)")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.startSession()
                try? await Task.sleep(for: .seconds(6))
                self.addCameraAndStream()
            }
        }
        append("mock: Enable, Pair, On, Unfold, Don, Wok, then Coordinator.")
    }

    /// The toolkit ships deep links for the two "go update something" failures,
    /// which is faster and less error-prone than describing where the page is.
    func openGlassesAppUpdate() {
        Task {
            do {
                try await Wearables.shared.openDATGlassesAppUpdate()
                append("opened the glasses app update page in Meta AI")
            } catch {
                append("! could not open glasses app update: \(message(error))")
            }
        }
    }

    func openFirmwareUpdate() {
        Task {
            do {
                try await Wearables.shared.openFirmwareUpdate()
                append("opened the firmware update page in Meta AI")
            } catch {
                append("! could not open firmware update: \(message(error))")
            }
        }
    }

    // MARK: - Meta AI registration (real glasses)

    /// Opens Meta AI so the user can approve Glutt, then comes back through the
    /// `glutt-wearables://` callback that `GlassesSupport` claims.
    ///
    /// Required on real hardware. Developer Mode means the approval is always
    /// granted, not that it can be skipped.
    func registerWithMetaAI() {
        Task {
            do {
                append("registration: handing off to Meta AI…")
                try await Wearables.shared.startRegistration()
                append("registration: Meta AI handed back")
            } catch {
                append("! registration failed: \(message(error))")
            }
        }
    }

    /// For a second run, or when approval got into a bad state.
    func unregisterFromMetaAI() {
        Task {
            do {
                try await Wearables.shared.startUnregistration()
                append("registration: unregistered")
            } catch {
                append("! unregister failed: \(message(error))")
            }
        }
    }

#if canImport(MWDATMockDevice)
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

#endif

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

#if canImport(MWDATMockDevice)
    /// The failure we actually have to handle gracefully in the cook session.
    func forceDenyPermission() {
        MockDeviceKit.shared.permissions.set(.camera, .denied)
        MockDeviceKit.shared.permissions.setRequestResult(.camera, result: .denied)
        append("mock permissions forced to denied")
    }

#endif

    /// Three looks back to back through the real coordinator.
    ///
    /// The first is cold. Looks two and three are what actually matter: they say
    /// whether a warm restart is a glance or a wait, and whether each one repays
    /// the setup memory. Those two numbers decide if on-demand vision survives.
    /// One camera, held open for a minute, against five short ones.
    ///
    /// This is the experiment that decides the architecture. A look costs its
    /// Wi-Fi association plus its frames, and we have never separated those two.
    /// If this run costs about the same as a single short look, then the whole
    /// charge is in opening the camera and the cheapest possible design is to
    /// open it once and leave it running — the exact opposite of the on-demand
    /// looks we built. If it instead costs sixty seconds' worth of streaming,
    /// short looks were right all along.
    ///
    /// 300 frames at 7 fps, capped well above what a minute delivers, so the
    /// frame cap never ends the look early and the duration is what is measured.
    func runLongLook(seconds: TimeInterval = 60) {
        Task {
            let coordinator = self.coordinator ?? PollyVisualSourceCoordinator(
                phone: PhoneCameraVisualSource(camera: PollyCameraController())
            )
            self.coordinator = coordinator
            if coordinator.activeKind == nil {
                append("long look: starting coordinator")
                await coordinator.start()
                coordinatorStatus = coordinator.activeKind?.toolName ?? "nothing"
            }
            guard coordinator.activeKind == .metaGlasses else {
                return append("! long look needs the glasses, active source is \(coordinatorStatus)")
            }

            // Honour the STREAM pickers rather than the source's own defaults.
            //
            // Measured at 1.44 MB per delivered frame, resolution and frame rate
            // stop being cosmetic and become the entire vision budget: 2 fps
            // instead of 7 is three and a half times as long before the app is
            // in danger. Those two rows of buttons are now the experiment.
            coordinator.glasses.resolution = resolutionChoice.streaming
            coordinator.glasses.frameRate = frameRate

            let size = resolutionChoice.streaming.videoFrameSize
            append("long look: \(Int(size.width))x\(Int(size.height)) @ \(frameRate) fps for \(Int(seconds))s")
            let look = await coordinator.glasses.captureLook(maxFrames: 5000, timeout: seconds)
            append(String(
                format: "LONG LOOK: %@ · %d frames · %.1fs to first frame · %.1fs total · %+.0f MB (link %+.0f, frames %+.0f)",
                look.succeeded ? "ok \(look.jpeg?.count ?? 0)B" : "FAILED \(look.rejection?.rawValue ?? "?")",
                look.framesSeen, look.startLatency, look.totalDuration,
                look.memoryDeltaMB, look.linkMB, look.framesMB))
            append("memory now: \(MemoryProbe.summary)")
            // Then again after the camera has been shut for a while.
            //
            // This is the difference between a leak and a high-water mark, and
            // it decides whether glasses vision is rationed per app launch or
            // per watch window. The first long run ended at 780 MB and the
            // screen showed 66 MB a few minutes later, which says the memory
            // does come back — but that was read off a screenshot, not
            // measured, so it gets measured here.
            for delay in [5, 15, 30] {
                try? await Task.sleep(for: .seconds(delay == 5 ? 5 : 10))
                append("memory +\(delay)s after the look: \(MemoryProbe.summary)")
            }

            // Then stop the session outright and watch again.
            //
            // The first run showed memory still climbing thirty seconds after
            // the camera closed — 860 MB to 1057 MB with `stream` and `session`
            // both reading none on screen. `endLook()` deliberately keeps the
            // DeviceSession alive because re-establishing it is the slow part,
            // so if the climb stops here, that choice is what is paying for it
            // and holding a session between looks costs more than it saves.
            append("stopping the session outright")
            coordinator.glasses.stop()

            // Sampled out to three minutes, because the growth does not stop
            // when the session does. It was still climbing thirty seconds after
            // a full stop, and yet the screen reads normal again minutes later,
            // so the memory is clearly returned eventually and nothing so far
            // has caught the moment it turns around.
            //
            // That moment is the whole product question. A hard ceiling per app
            // launch means Chef can look a fixed number of times and then never
            // again; a cost that drains in a minute or two means she can look as
            // often as she likes, just not back to back.
            var elapsed = 0
            var peak = Double(MemoryProbe.footprintBytes) / 1_048_576
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(15))
                elapsed += 15
                let now = Double(MemoryProbe.footprintBytes) / 1_048_576
                peak = max(peak, now)
                let recovered = peak > 0 ? (peak - now) / peak * 100 : 0
                append(String(
                    format: "memory +%ds after session stop: %@ (peak %.0f MB, %.0f%% back)",
                    elapsed, MemoryProbe.summary, peak, recovered))
            }
        }
    }

    /// Does closing the camera give the phone its Wi-Fi back, and how long does
    /// it take to start watching again?
    ///
    /// Those two numbers decide the whole shape of glasses vision. Holding the
    /// stream for a cook means the phone is on the glasses' access point the
    /// entire time and Polly's voice runs on cellular, which is not a trade
    /// worth making in a kitchen with weak signal. The alternative is watch
    /// windows, and the alternative is only viable if closing the camera
    /// actually releases the network and reopening it is quick.
    ///
    /// Three cycles, because the first reopen after a cold start may not behave
    /// like the ones after it.
    func runWarmReopen(cycles: Int = 3) {
        Task {
            let coordinator = self.coordinator ?? PollyVisualSourceCoordinator(
                phone: PhoneCameraVisualSource(camera: PollyCameraController())
            )
            self.coordinator = coordinator
            if coordinator.activeKind == nil {
                append("warm reopen: starting coordinator (cold open)")
                let cold = Date()
                await coordinator.start()
                coordinatorStatus = coordinator.activeKind?.toolName ?? "nothing"
                append(String(format: "cold open took %.1fs", Date().timeIntervalSince(cold)))
            }
            guard coordinator.activeKind == .metaGlasses else {
                return append("! warm reopen needs the glasses, active source is \(coordinatorStatus)")
            }
            append("while watching → \(await NetworkProbe.describeCurrent())")

            for cycle in 1...cycles {
                coordinator.glasses.pauseWatching()
                append("cycle \(cycle): camera closed, session kept")
                // iOS does not hand the network back instantly, so give it a
                // moment before asking, and ask twice.
                for wait in [3, 8] {
                    try? await Task.sleep(for: .seconds(wait == 3 ? 3 : 5))
                    append("  +\(wait)s after closing → \(await NetworkProbe.describeCurrent())")
                }

                let latency = await coordinator.glasses.resumeWatching()
                if let latency {
                    append(String(format: "cycle %d: watching again after %.1fs", cycle, latency))
                } else {
                    append("cycle \(cycle): could NOT start watching again")
                }
                append("  now → \(await NetworkProbe.describeCurrent())")
                try? await Task.sleep(for: .seconds(3))
            }
            append("memory now: \(MemoryProbe.summary)")
        }
    }

    func runLookSeries(count: Int = 5, gap: TimeInterval = 8) {
        Task {
            let coordinator = self.coordinator ?? PollyVisualSourceCoordinator(
                phone: PhoneCameraVisualSource(camera: PollyCameraController())
            )
            self.coordinator = coordinator
            if coordinator.activeKind == nil {
                append("looks: starting coordinator")
                await coordinator.start()
                coordinatorStatus = coordinator.activeKind?.toolName ?? "nothing"
            }
            guard coordinator.activeKind == .metaGlasses else {
                return append("! looks need the glasses, active source is \(coordinatorStatus)")
            }

            for index in 1...count {
                let look = await coordinator.glasses.captureLook()
                append(String(
                    format: "look %d: %@ · %d frames · %.1fs to first frame · %.1fs total · %+.0f MB",
                    index,
                    look.succeeded ? "ok \(look.jpeg?.count ?? 0)B" : "FAILED \(look.rejection?.rawValue ?? "?")",
                    look.framesSeen, look.startLatency, look.totalDuration, look.memoryDeltaMB))
                if let jpeg = look.jpeg { capturedPhoto = UIImage(data: jpeg) }
                memoryStatus = MemoryProbe.summary
                // 8 seconds, not 3. Re-opening the camera ~3s after stopping it
                // produced a look that never reached streaming and then a fast
                // one right after, which reads as the toolkit needing time to
                // settle between camera cycles. A real cook would not take two
                // looks in the same breath either.
                if index < count { try? await Task.sleep(for: .seconds(gap)) }
            }
            append("looks done · \(MemoryProbe.summary)")
            // The stream state transitions and any stream error only reach
            // PollyDebugLog, and not seeing them is what made the last failure
            // unreadable.
            for line in PollyDebugLog.shared.dump().split(separator: "\n").suffix(12) {
                append("  polly| \(line)")
            }
        }
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
        // Built here when it does not exist yet: with real glasses nobody enables
        // the mock kit, and this used to send them off to do exactly that.
        let selector = self.selector ?? AutoDeviceSelector(wearables: Wearables.shared)
        self.selector = selector
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
                append("memory at session start: \(MemoryProbe.summary)")
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
            videoCodec: useCompressedCodec ? .hvc1 : .raw,
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
        append("memory after addCamera: \(MemoryProbe.summary)")
        startMemorySampling()
            observeStream(camera.stream)
            camera.stream.start()
            append("stream.start() called")
        } catch {
            append("! addCamera failed: \(message(error))")
        }
    }

    /// A stopped session is terminal: the toolkit needs a brand new one.
    private func clearDeadSession() {
        camera?.stop()
        camera = nil
        session = nil
        streamStatus = "none"
        append("session cleared, Start session will make a fresh one")
    }

    func capturePhoto() {
        guard let camera else { return append("! no camera") }
        let accepted = camera.stream.capturePhoto(format: .jpeg)
        append("capturePhoto(.jpeg) accepted=\(accepted)")
    }

    func teardown() {
        memoryTimer?.cancel()
        memoryTimer = nil
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
        append("torn down at \(MemoryProbe.summary)")
        // The question that decides whether any workaround exists: if stopping
        // the stream gives the memory back, a long cook can cycle it. If not,
        // the leak is permanent for the life of the process.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            self.append("3s after teardown: \(MemoryProbe.summary)")
            self.memoryStatus = MemoryProbe.summary
        }
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
            // Clear it, or the next Start session says "session already exists"
            // forever and the only way out is relaunching the app.
            self?.clearDeadSession()
        })
        streamTasks.append(Task { [weak self] in
            for await error in session.errorStream() {
                self?.append("! session error: \(error.description)")
            }
        })
    }

    // `MWDATCamera.Stream` in full: bare `Stream` collides with Foundation's.
    private func observeStream(_ stream: MWDATCamera.Stream) {
        // Snapshotted here rather than read inside the listener: the listener is
        // @Sendable and cannot touch main-actor state. Set the toggle before
        // starting the stream.
        let probe = frameProbe
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
        // The isolation ladder. `.noListener` deliberately subscribes to
        // nothing, which is the whole point: if memory climbs with no
        // subscriber, our code cannot be the cause.
        switch probe {
        case .noListener:
            append("probe: NO listener subscribed, memory sampled on a timer")

        case .countOnly:
            tokens.append(stream.videoFramePublisher.listen { [weak self] _ in
                self?.deliveredCounter.increment()
            })

        case .decodeDiscard:
            tokens.append(stream.videoFramePublisher.listen { [weak self] frame in
                guard let self else { return }
                self.deliveredCounter.increment()
                autoreleasepool { _ = VisualFramePipeline.image(from: frame.sampleBuffer) }
            })

        case .fullPipeline:
            tokens.append(stream.videoFramePublisher.listen { [weak self] frame in
                guard let self, self.admission.admit() else { return }
                self.deliveredCounter.increment()
                let image = autoreleasepool { VisualFramePipeline.image(from: frame.sampleBuffer) }
                Task { @MainActor in
                    defer { self.admission.release() }
                    self.ingest(image)
                }
            })
        }

        tokens.append(stream.photoDataPublisher.listen { [weak self] photo in
            let image = UIImage(data: photo.data)
            let byteCount = photo.data.count
            Task { @MainActor in
                self?.capturedPhoto = image
                self?.append("photo received — \(byteCount) bytes, \(image == nil ? "UNDECODABLE" : "decoded")")
            }
        })
    }

    /// The no-decode path: count, sample memory, touch nothing else.
    /// Samples memory once a second and reports MB per frame, which is the only
    /// number that compares across rungs and frame rates.
    private func startMemorySampling() {
        memoryTimer?.cancel()
        deliveredCounter.reset()
        probeStartedAt = Date()
        probeStartFootprint = MemoryProbe.footprintBytes
        append("probe \(frameProbe.rawValue): baseline \(MemoryProbe.summary)")

        memoryTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let started = self.probeStartedAt else { return }
                let elapsed = Date().timeIntervalSince(started)
                let frames = self.deliveredCounter.count
                let grownMB = (Double(MemoryProbe.footprintBytes) - Double(self.probeStartFootprint)) / 1_048_576
                let perFrame = frames > 0 ? grownMB / Double(frames) : 0
                self.memoryStatus = MemoryProbe.summary
                self.frameSummary = "\(frames) frames\nprobe: \(self.frameProbe.rawValue)"
                self.append(String(
                    format: "t+%.0fs  %d frames  +%.0f MB  %.2f MB/frame  %.1f MB/s",
                    elapsed, frames, grownMB, perFrame, grownMB / max(elapsed, 1)))
            }
        }
    }

    private func countUndecodedFrame() {
        frameCount += 1
        if firstFrameAt == nil {
            firstFrameAt = Date()
            append("first frame (DECODE OFF) — counting only")
        }
        memoryStatus = MemoryProbe.summary
        let availableMB = Double(MemoryProbe.availableBytes) / 1_048_576
        if availableMB < lowestAvailableMB - 25 {
            lowestAvailableMB = availableMB
            append(String(format: "memory: %@ (frame %d, decode off)", MemoryProbe.summary, frameCount))
        }
        frameSummary = "\(frameCount) frames\ndecode OFF"
    }

    private func ingest(_ image: UIImage?) {
        guard let image else {
            // Still sample: this path is taken for every frame under .hvc1, and
            // returning early here is why the hvc1 run measured nothing at all.
            frameCount += 1
            memoryStatus = MemoryProbe.summary
            if frameCount == 1 || frameCount % 50 == 0 {
                append("undecodable frame \(frameCount) — \(MemoryProbe.summary)")
            }
            return
        }
        // Hold a small copy, not the full frame. The full one is backed by the
        // toolkit's own buffer, and keeping it alive keeps that buffer alive too.
        let thumbnail = autoreleasepool { VisualFramePipeline.thumbnail(image, maxDimension: 320) } ?? image
        let now = Date()
        if firstFrameAt == nil {
            firstFrameAt = now
            append("first frame — \(Int(image.size.width))x\(Int(image.size.height))")
        }
        frameCount += 1
        lastFrameAt = now
        latestFrame = thumbnail

        memoryStatus = MemoryProbe.summary
        // Log each new low, but only in whole 25 MB steps: at frame rate an
        // unfiltered line would itself become the memory problem.
        let availableMB = Double(MemoryProbe.availableBytes) / 1_048_576
        if availableMB < lowestAvailableMB - 25 {
            lowestAvailableMB = availableMB
            append(String(format: "memory: %@ (frame %d)", MemoryProbe.summary, frameCount))
        }

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

    /// The current run only, read from disk.
    ///
    /// Disk rather than the in-memory log because the runs worth reading are the
    /// ones that end in a memory kill, which takes the in-memory copy with it.
    /// Current run only because the first version of this pasted the entire
    /// file — every run ever recorded — which is unreadable and buries the one
    /// line anybody wanted. Previous runs stay on disk and are still reachable
    /// with "Copy all runs" when a crash means the interesting run is the one
    /// before this launch.
    func copyLog() {
        let device = UIDevice.current
        let header = "Glasses spike — \(device.systemName) \(device.systemVersion) — \(Date().formatted())"
        UIPasteboard.general.string = header + "\n" + GlassesRunLog.shared.currentRun()
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justCopied = false
        }
    }

    private func append(_ line: String) {
        log.append(String(format: "%6.1f  %@", Date().timeIntervalSince(startedAt), line))
        if log.count > 500 { log.removeFirst(log.count - 500) }
        // Also to disk, flushed. A memory kill takes the on-screen log with it,
        // and the runs that get killed are the ones worth reading.
        GlassesRunLog.shared.log(line)
    }
}
