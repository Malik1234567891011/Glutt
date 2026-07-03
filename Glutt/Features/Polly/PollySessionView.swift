import AVFAudio
import SwiftData
import SwiftUI

/// Live "Cook with Polly" session: full-bleed camera preview behind a
/// voice-first overlay — orb, rolling caption, current step, timers, controls.
/// Presented as a fullScreenCover from RootView via `router.pollyLaunch`.
/// The screen stays awake for the whole cook (wet hands, no taps needed).
struct PollySessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router

    let recipe: Recipe
    /// Serving scale carried over from the detail screen.
    var scale: Double = 1

    @State private var controller: PollySessionController?
    @State private var startedAt = Date.now
    @State private var isConfirmingExit = false
    @State private var isShowingFinish = false
    @State private var isEndingWithoutSaving = false
    @State private var micDenied = false
    @State private var didDismissPreflight = false
    /// Set by "Cook without Polly": swaps the session for classic Cook Mode
    /// inside the same cover, so the user never loses their place.
    @State private var isCookingWithoutPolly = false

    var body: some View {
        Group {
            if isCookingWithoutPolly {
                CookModeView(recipe: recipe, scale: scale)
            } else {
                sessionContent
            }
        }
        .task {
            guard controller == nil else { return }
            await startSession()
        }
        .onAppear {
            router.isPollySessionActive = true
            router.floatingButtonSuppressors += 1
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            router.isPollySessionActive = false
            router.floatingButtonSuppressors -= 1
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: controller?.phase) { _, phase in
            // Controller-initiated end that already ran end() (e.g. the
            // session-cap hard stop): route into the same finish-and-log flow.
            guard phase == .ended, !isShowingFinish, !isEndingWithoutSaving,
                  !isCookingWithoutPolly else { return }
            isShowingFinish = true
        }
        .onChange(of: controller?.wantsEnd) { _, wants in
            // Polly-initiated end (the end_session tool): the tool only sets
            // the flag — this view owns the teardown + finish-and-log flow.
            guard wants == true, !isShowingFinish, !isEndingWithoutSaving,
                  !isCookingWithoutPolly else { return }
            isShowingFinish = true
            Task { await controller?.end(context: context, endedEarly: false) }
        }
        .sheet(isPresented: $isShowingFinish) {
            CookFinishView(recipe: recipe, scale: scale) {
                dismiss()
            }
            .interactiveDismissDisabled()
        }
        .confirmationDialog(
            "End cooking with Polly?", isPresented: $isConfirmingExit, titleVisibility: .visible
        ) {
            Button("Keep cooking", role: .cancel) {}
            Button("Finish & log") {
                isShowingFinish = true
                Task { await controller?.end(context: context, endedEarly: false) }
            }
            Button("End without saving", role: .destructive) {
                isEndingWithoutSaving = true
                Task {
                    await controller?.end(context: context, endedEarly: true)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Session startup

    /// Mic permission is requested HERE, before the controller exists — the
    /// engine itself never prompts. Denied mic means no session (spec), so
    /// the user gets a clear card instead of a silently deaf Polly. Also the
    /// "Try again" path: a fresh controller every time, because start() runs
    /// once per instance.
    private func startSession() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            micDenied = true
            return
        }
        let session = PollySessionController(recipe: recipe, scale: scale)
        controller = session
        await session.start(context: context)
    }

    // MARK: - Layers

    private var sessionContent: some View {
        ZStack {
            background
            if micDenied {
                micDeniedCard
            } else if let controller {
                overlayChrome(for: controller)
                phaseOverlay(for: controller)
            }
        }
    }

    /// Camera preview when running; otherwise a calm dark backdrop with a
    /// chef-hat watermark (voice-only sessions, permission denied, simulator).
    @ViewBuilder
    private var background: some View {
        if let controller, controller.camera.isRunning {
            CameraPreviewView(previewLayer: controller.camera.previewLayer)
                .ignoresSafeArea()
        } else {
            ZStack {
                Theme.Colors.textPrimary.ignoresSafeArea()
                Ph.chefHat.fill
                    .resizable().scaledToFit()
                    .frame(width: 180, height: 180)
                    .foregroundStyle(Theme.Colors.creamText.opacity(0.08))
            }
        }
    }

    private func overlayChrome(for controller: PollySessionController) -> some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomStack(for: controller)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                Haptics.impact(.light)
                isConfirmingExit = true
            } label: {
                Ph.x.regular
                    .resizable().scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            VStack(spacing: 1) {
                Text(recipe.title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                    Text(elapsedLabel(at: timeline.date))
                        .font(.system(size: 11.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            Spacer()
            // Invisible twin of the X button so the title stays centered.
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func elapsedLabel(at date: Date) -> String {
        TimerManager.format(seconds: max(0, Int(date.timeIntervalSince(startedAt))))
    }

    // MARK: - Bottom stack

    private func bottomStack(for controller: PollySessionController) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            PollyOrb(
                inputLevel: controller.audio.inputLevel,
                isListening: controller.isListening,
                isSpeaking: controller.isPollySpeaking,
                isThinking: controller.isThinking
            )
            if !controller.captionText.isEmpty {
                captionLine(controller.captionText)
            }
            if controller.phase == .live, !controller.missingIngredients.isEmpty,
               !didDismissPreflight {
                PreflightCard(missing: controller.missingIngredients) {
                    didDismissPreflight = true
                }
            }
            if let step = currentStep(of: controller) {
                PollyStepCard(step: step, totalSteps: controller.plan?.steps.count ?? 0) { seconds in
                    controller.timers.start(
                        label: "Step \(step.index + 1): \(String(step.title.prefix(40)))",
                        seconds: seconds
                    )
                }
            }
            if !controller.timers.timers.isEmpty {
                PollyTimersRow(manager: controller.timers)
            }
            controlsRow(for: controller)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.md)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [Theme.Colors.textPrimary.opacity(0), Theme.Colors.textPrimary.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
            .padding(.top, -Theme.Spacing.xl)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    private func captionLine(_ text: String) -> some View {
        Text(text)
            .font(.gluttCaption.weight(.semibold))
            .foregroundStyle(Theme.Colors.creamText)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.Colors.textPrimary.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
    }

    private func currentStep(of controller: PollySessionController) -> CookPlan.PlanStep? {
        guard let plan = controller.plan,
              plan.steps.indices.contains(controller.stepIndex) else { return nil }
        return plan.steps[controller.stepIndex]
    }

    private func controlsRow(for controller: PollySessionController) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            PollyControlButton(
                icon: controller.audio.isMuted ? Ph.microphoneSlash.regular : Ph.microphone.fill,
                label: controller.audio.isMuted ? "Unmute" : "Mute"
            ) {
                controller.toggleMute()
            }
            PollyControlButton(
                icon: controller.isWatching ? Ph.eye.fill : Ph.eyeSlash.regular,
                label: "Polly watches while you cook"
            ) {
                controller.isWatching.toggle()
            }
            PollyControlButton(icon: Ph.camera.regular, label: "Show Polly") {
                Task { await controller.sendShowPolly() }
            }
            // Privacy control: turning the camera OFF is as important as flip.
            PollyControlButton(
                icon: controller.camera.isRunning ? Ph.videoCamera.fill : Ph.videoCameraSlash.regular,
                label: "Camera on or off"
            ) {
                if controller.camera.isRunning {
                    controller.camera.stop()
                } else {
                    Task { await controller.camera.start() }
                }
            }
            PollyControlButton(icon: Ph.cameraRotate.regular, label: "Flip camera") {
                controller.flipCamera()
            }
            PollyControlButton(icon: Ph.x.regular, tint: Theme.Colors.tomato, label: "End session") {
                isConfirmingExit = true
            }
        }
    }

    // MARK: - Phase overlays

    @ViewBuilder
    private func phaseOverlay(for controller: PollySessionController) -> some View {
        switch controller.phase {
        case .idle, .compiling:
            statusCard("Polly is reading the recipe…")
        case .connecting:
            statusCard("Calling Polly…")
        case .reconnecting:
            VStack {
                Text("One sec — reconnecting…")
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.creamText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.Colors.textPrimary.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.top, 60)
                Spacer()
            }
        case .failed(let message):
            failedCard(message: message, controller: controller)
        case .live, .ended:
            EmptyView()
        }
    }

    private func statusCard(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.accent)
            Text(message)
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: 300)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
    }

    private func failedCard(message: String, controller: PollySessionController) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Ph.chefHat.regular
                .resizable().scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(Theme.Colors.accent)
            Text("Polly couldn't pick up")
                .font(.gluttTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Haptics.impact(.medium)
                // start() runs once per controller instance — retry means a
                // fresh controller (startSession builds one). `self.` targets
                // the @State property, not the shadowing `controller` param.
                self.controller = nil
                Task { await startSession() }
            }
            .buttonStyle(.gluttPrimary)
            Button("Cook without Polly") {
                Haptics.impact(.light)
                isCookingWithoutPolly = true
                router.isPollySessionActive = false
                Task { await controller.end(context: context, endedEarly: true) }
            }
            .buttonStyle(.gluttSecondary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: 320)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
    }

    private var micDeniedCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            Ph.microphoneSlash.regular
                .resizable().scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(Theme.Colors.accent)
            Text("Polly can't hear you")
                .font(.gluttTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Polly needs the microphone to cook with you. You can enable it in Settings, or cook without her.")
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Cook without Polly") {
                Haptics.impact(.light)
                isCookingWithoutPolly = true
                router.isPollySessionActive = false
            }
            .buttonStyle(.gluttPrimary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: 320)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
    }
}
