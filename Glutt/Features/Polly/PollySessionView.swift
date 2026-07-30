import AVFAudio
import SwiftData
import SwiftUI
import UIKit

/// Live "Cook with Polly" session, redesigned to `Glutt Polly.dc.html`: a
/// full-bleed camera feed under a top→bottom scrim, a top bar, a centered state
/// pill ("Say Polly to talk" ↔ "Listening"), a big spoken caption, and a bottom
/// cluster with the current-step card and call-style controls (mute · red hang-up
/// · camera). Saying "Polly" un-gates the mic (Listening); an animated edge border
/// and live transcription show she's hearing you. Presented as a fullScreenCover.
struct PollySessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router

    let recipe: Recipe
    var scale: Double = 1
    /// True when the cook trailer briefing already covered the dish overview.
    var heardBriefing: Bool = false
    /// True when Polly should open already listening for a verbal "let's cook".
    var awaitVerbalGo: Bool = false

    @State private var controller: PollySessionController?
    @State private var startedAt = Date.now
    @State private var isConfirmingExit = false
    @State private var isShowingFinish = false
    @State private var isEndingWithoutSaving = false
    @State private var micDenied = false
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
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            router.isPollySessionActive = false
            UIApplication.shared.isIdleTimerDisabled = false
            controller?.leaveCookScreen()
            if let controller, controller.phase == .live || controller.phase == .reconnecting {
                Task { await controller.end(context: context, endedEarly: true) }
            }
        }
        .onChange(of: controller?.phase) { _, phase in
            guard phase == .ended, !isShowingFinish, !isEndingWithoutSaving, !isCookingWithoutPolly else { return }
            isShowingFinish = true
        }
        .onChange(of: controller?.wantsEnd) { _, wants in
            guard wants == true, !isShowingFinish, !isEndingWithoutSaving, !isCookingWithoutPolly else { return }
            isShowingFinish = true
            Task { await controller?.end(context: context, endedEarly: false) }
        }
        .onChange(of: controller?.listeningMode) { old, new in
            // A crisp "I'm hearing you" tap the moment she wakes (voice or pill tap).
            if new == .listening, old != .listening { Haptics.impact(.medium) }
            // Soft close cue when the follow-up session ends (no beep).
            if new == .dormant, old != .dormant, old != nil { Haptics.impact(.light) }
        }
        .sheet(isPresented: $isShowingFinish) {
            cookRecapSheet
                .interactiveDismissDisabled()
        }
        .confirmationDialog("End cooking with Polly?", isPresented: $isConfirmingExit, titleVisibility: .visible) {
            Button("Keep cooking", role: .cancel) {}
            Button("Finish") {
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

    @ViewBuilder
    private var cookRecapSheet: some View {
        let controller = controller
        let started = controller?.sessionStartedAt ?? startedAt
        let ended = Date.now
        let duration = max(0, Int(ended.timeIntervalSince(started)))
        let log = controller?.lastCookLog
        let previousBest = recipe.cookSessions(in: context)
            .compactMap(\.overallScore)
            .max()

        CookRecapView(
            recipe: recipe,
            scale: scale,
            durationSeconds: duration,
            stepsCompleted: log?.stepsCompleted ?? controller?.registry?.state.completedStepIDs.count ?? 0,
            stepsTotal: log?.stepsTotal ?? controller?.plan?.steps.count ?? recipe.sortedSteps.count,
            endedEarly: log?.endedEarly ?? false,
            pollySaves: log?.pollySaves ?? controller?.sessionSaves ?? [],
            substitutions: log?.substitutions ?? controller?.registry?.state.substitutions ?? [],
            summary: log?.summary,
            initialPlateJPEG: controller?.plateJPEG,
            previousBestOverall: previousBest,
            cookName: nil
        ) {
            dismiss()
        }
    }

    // MARK: - Session startup

    private func startSession() async {
        PollyDebugLog.shared.reset()
        PollyDebugLog.shared.log("session: starting (scale \(scale))")
        let granted = await AVAudioApplication.requestRecordPermission()
        PollyDebugLog.shared.log("session: mic permission \(granted ? "granted" : "DENIED")")
        guard granted else { micDenied = true; return }
        let session = PollySessionController(
            recipe: recipe,
            scale: scale,
            heardBriefing: heardBriefing,
            awaitVerbalGo: awaitVerbalGo
        )
        controller = session
        // On-device wake word ("Polly") needs Speech auth. Requested here so the
        // controller can decide whether to arm voice waking or fall back to
        // tap-to-talk. A denial never blocks the session.
        _ = await session.wakeWord.requestAuthorization()
        await session.start(context: context)
    }

    // MARK: - Layers

    private var sessionContent: some View {
        ZStack {
            CookCanvasTheme.mainBlack.ignoresSafeArea()
            if micDenied {
                micDeniedCard
            } else if let controller {
                PollyAdaptiveCanvasView(
                    controller: controller,
                    recipe: recipe,
                    onMinimize: { isConfirmingExit = true },
                    onRequestEnd: { isConfirmingExit = true },
                    onStartTimer: { step, seconds in
                        startTimer(for: step, seconds: seconds, controller: controller)
                    }
                )
                if isActivelyListening(controller) { ListeningEdge() }
                phaseOverlay(for: controller)
                if controller.listeningMode == .listening { ListeningSweep() }
            } else {
                ProgressView()
                    .tint(CookCanvasTheme.green)
            }
        }
    }

    /// Engaged mic visuals while Polly is waiting on you (initial listen or
    /// follow-up window) — not while she's thinking or talking.
    private func isActivelyListening(_ controller: PollySessionController) -> Bool {
        controller.isEngaged && !controller.isPollySpeaking && !controller.isThinking
    }

    @ViewBuilder
    private var background: some View {
        ZStack {
            Color(hex: 0x141310).ignoresSafeArea()
            if let controller, controller.camera.isRunning {
                CameraPreviewView(previewLayer: controller.camera.previewLayer)
                    .ignoresSafeArea()
            }
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x140F0A).opacity(0.5), location: 0),
                    .init(color: Color(hex: 0x140F0A).opacity(0.04), location: 0.22),
                    .init(color: Color(hex: 0x140F0A).opacity(0.10), location: 0.48),
                    .init(color: Color(hex: 0x140F0A).opacity(0.70), location: 0.80),
                    .init(color: Color(hex: 0x140F0A).opacity(0.94), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func overlayChrome(for controller: PollySessionController) -> some View {
        VStack(spacing: 0) {
            topBar(for: controller)
            statePill(for: controller).padding(.top, 14)
            if let plan = controller.plan, !plan.steps.isEmpty, !controller.camera.isRunning {
                // Camera off: the guide IS the step UI (cream card is hidden).
                PollyStepGuidePanel(
                    plan: plan,
                    stepIndex: controller.stepIndex,
                    checkedActionIDs: controller.checkedActionIDs,
                    isPollySpeaking: controller.isPollySpeaking,
                    onSelectStep: { controller.goToStep($0) },
                    onToggleItem: { controller.toggleChecklistItem($0) },
                    onStartTimer: { step, seconds in
                        startTimer(for: step, seconds: seconds, controller: controller)
                    },
                    currentNativeClip: controller.nativeClipForCurrentStep(),
                    onNativeMediaState: { controller.updateMediaState($0) },
                    currentStepClip: controller.clipForCurrentStep()
                )
                .id(controller.sessionUIEpoch)
                .padding(.top, 14)
                .frame(maxHeight: .infinity)
                Spacer(minLength: 8)
            } else {
                Spacer(minLength: 0)
            }
            speechLine(for: controller).padding(.horizontal, 22).padding(.top, 10)
            bottomCluster(for: controller)
        }
        .animation(.easeInOut(duration: 0.25), value: controller.camera.isRunning)
    }

    // MARK: - Top bar

    private func topBar(for controller: PollySessionController) -> some View {
        HStack {
            topCircle(MS.menuBook)
            Spacer()
            VStack(spacing: 2) {
                Text(recipe.title)
                    .font(BrandFont.nunito(14, 800))
                    .foregroundStyle(Theme.Colors.creamText)
                    .lineLimit(1)
                TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                    Text(elapsedLabel(at: timeline.date))
                        .font(BrandFont.nunito(12, 700))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.creamText.opacity(0.72))
                }
            }
            .onLongPressGesture(minimumDuration: 0.6) {
                UIPasteboard.general.string = PollyDebugLog.shared.dump()
                Haptics.notify(.success)
            }
            Spacer()
            Menu {
                Button("Finish and save", systemImage: "checkmark") {
                    isShowingFinish = true
                    Task { await controller.end(context: context, endedEarly: false) }
                }
                Button("Copy debug log", systemImage: "doc.on.clipboard") {
                    UIPasteboard.general.string = PollyDebugLog.shared.dump()
                    Haptics.notify(.success)
                }
                Button("End without saving", systemImage: "xmark", role: .destructive) {
                    isEndingWithoutSaving = true
                    Task { await controller.end(context: context, endedEarly: true); dismiss() }
                }
            } label: {
                topCircleLabel(MS.moreHoriz)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 56)
    }

    private func topCircle(_ icon: MS) -> some View { topCircleLabel(icon) }

    private func topCircleLabel(_ icon: MS) -> some View {
        icon.sized(21).foregroundStyle(Theme.Colors.tabLabel)
            .frame(width: 42, height: 42)
            .background(Circle().fill(Theme.Colors.tabBar))
            .overlay(Circle().strokeBorder(Theme.Colors.tabLabel.opacity(0.16), lineWidth: 1))
    }

    private func elapsedLabel(at date: Date) -> String {
        TimerManager.format(seconds: max(0, Int(date.timeIntervalSince(startedAt))))
    }

    // MARK: - State pill

    @ViewBuilder
    private func statePill(for controller: PollySessionController) -> some View {
        if controller.phase == .live {
            if isActivelyListening(controller) {
                HStack(spacing: 9) {
                    WaveformBars()
                    Text(engagedPillLabel(for: controller))
                        .font(BrandFont.nunito(13, 800)).tracking(0.2)
                        .foregroundStyle(Color(hex: 0xDFF3DC))
                }
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(Capsule().fill(
                    controller.listeningMode == .followUp
                        ? Theme.Colors.accent.opacity(0.82)
                        : Theme.Colors.accent
                ))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                Button {
                    controller.forceListen()
                } label: {
                    HStack(spacing: 7) {
                        (controller.isHardMuted ? MS.micOffFill : MS.graphicEqFill)
                            .sized(15)
                            .foregroundStyle(controller.isHardMuted ? Theme.Colors.tomato : Theme.Colors.brightAccent)
                        Text(pillText(for: controller))
                            .font(BrandFont.nunito(12.5, 700))
                            .foregroundStyle(Theme.Colors.tabLabel.opacity(0.85))
                    }
                    .padding(.horizontal, 15).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.Colors.tabBar.opacity(0.62)))
                    .overlay(Capsule().strokeBorder(Theme.Colors.tabLabel.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pillText(for controller: PollySessionController) -> String {
        if controller.isHardMuted { return "Muted, tap the mic to turn on" }
        if controller.isThinking { return "Thinking…" }
        if controller.isPollySpeaking { return "Polly is talking" }
        return controller.wakeWordAvailable ? "Say \u{201C}Polly\u{201D} to talk" : "Tap to talk"
    }

    private func engagedPillLabel(for controller: PollySessionController) -> String {
        if controller.expectsAnswer { return "Your turn…" }
        if controller.listeningMode == .followUp { return "Still with you…" }
        if let ack = controller.lastAcknowledgedAt,
           Date().timeIntervalSince(ack) < 1.5 {
            return "Got it"
        }
        return "Listening"
    }

    // MARK: - Speech line

    @ViewBuilder
    private func speechLine(for controller: PollySessionController) -> some View {
        // The big live quote shows only while there ARE live words — with the
        // hybrid window the listening state now persists after her answer,
        // and an empty/stale quote here read as "the captions are buggy".
        if isActivelyListening(controller), !controller.liveTranscript.isEmpty {
            Text("\u{201C}\(controller.liveTranscript)\u{2026}\u{201D}")
                .font(BrandFont.nunito(18, 700))
                .foregroundStyle(Theme.Colors.creamText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .lineLimit(3)
        } else if !controller.pollyCaption.isEmpty {
            Text(controller.pollyCaption)
                .font(BrandFont.nunito(15, 600))
                .foregroundStyle(Theme.Colors.creamText.opacity(0.94))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 330)
                .lineLimit(4)
        }
    }

    // MARK: - Bottom cluster

    private func bottomCluster(for controller: PollySessionController) -> some View {
        VStack(spacing: 16) {
            if controller.phase == .live, !controller.missingIngredients.isEmpty, !controller.preflightDismissed {
                PreflightCard(missing: controller.missingIngredients) {
                    controller.dismissPreflight()
                }
            }
            if !controller.timers.timers.isEmpty {
                PollyTimersRow(manager: controller.timers)
            }
            // Cream step card only when the camera is on (feed is the hero and
            // the guide panel is hidden). With camera off the dark checklist
            // owns step UI — a second cream card was just dead weight.
            if controller.camera.isRunning, let step = currentStep(of: controller) {
                stepCard(step: step, controller: controller)
            }
            controlsRow(for: controller)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 40)
    }

    /// Cream step card for camera-on mode (guide panel is hidden so the feed
    /// stays hero). Mirrors the original Polly mock bottom card.
    private func stepCard(step: CookPlan.PlanStep, controller: PollySessionController) -> some View {
        let total = controller.plan?.steps.count ?? 0
        let isSetup = CookPlan.isSetupStep(step)
        let setupCount = controller.plan?.leadingSetupCount ?? 0
        let cookTotal = max(0, total - setupCount)
        let cookNumber = isSetup ? 0 : max(1, step.index + 1 - setupCount)
        let phaseLabel: String = {
            if step.id == CookPlan.toolsStepID { return "Tools" }
            if step.id == CookPlan.prepStepID || step.kind == .prep { return "Prep" }
            return "Step \(cookNumber) of \(cookTotal)"
        }()
        let headline: String = {
            if step.id == CookPlan.toolsStepID {
                return step.title.isEmpty ? "Grab your tools" : step.title
            }
            if step.id == CookPlan.prepStepID || step.kind == .prep {
                return step.title.isEmpty ? "Mise en place" : step.title
            }
            return step.title
        }()
        return VStack(alignment: .leading, spacing: 0) {
            progressBar(done: step.index + 1, total: total)
            HStack(alignment: .firstTextBaseline) {
                Text(phaseLabel)
                    .font(BrandFont.nunito(11.5, 800)).tracking(1.5).textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.accent)
                Spacer()
                if let next = nextStepTitle(of: controller) {
                    Text(isSetup ? "Then, \(next)" : "Up next, \(next)")
                        .font(BrandFont.nunito(11.5, 700)).foregroundStyle(Theme.Colors.muted)
                        .lineLimit(1)
                }
            }
            .padding(.top, 12)
            Text(headline)
                .font(BrandFont.bricolage(22, 600))
                .foregroundStyle(Theme.Colors.heading)
                .padding(.top, 4)
            Text(step.instruction)
                .font(BrandFont.nunito(13.5, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(2)
                .lineLimit(3)
                .padding(.top, 5)
            if let native = controller.nativeClipForCurrentStep() {
                NativeClipPlayerView(clip: native) { state in
                    controller.updateMediaState(state)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 12)
                Text("\(native.watchLabel) · \(clipClock(Int(native.startSeconds)))–\(clipClock(Int(native.endSeconds)))")
                    .font(BrandFont.nunito(11, 700))
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.top, 4)
            } else if let clip = controller.clipForCurrentStep() {
                YouTubePlayerView(
                    videoId: clip.youtubeVideoID,
                    startSeconds: clip.startSeconds,
                    endSeconds: clip.endSeconds,
                    mute: true
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 12)
                Text("\(clip.watchLabel) · \(clipClock(clip.startSeconds))–\(clipClock(clip.endSeconds))")
                    .font(BrandFont.nunito(11, 700))
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.top, 4)
            } else if controller.isIndexingStepClips {
                Text("Finding a technique clip…")
                    .font(BrandFont.nunito(12, 700))
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.top, 10)
            }
            if let seconds = step.timerSeconds {
                Button {
                    Haptics.selection()
                    startTimer(for: step, seconds: seconds, controller: controller)
                } label: {
                    HStack(spacing: 6) {
                        MS.timerFill.sized(16)
                        Text("Start \(TimerManager.format(seconds: seconds)) timer")
                            .font(BrandFont.nunito(13, 800))
                    }
                    .foregroundStyle(Theme.Colors.creamText)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.Colors.amber))
                }
                .buttonStyle(.plain)
                .padding(.top, 13)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.3), radius: 20, y: 12)
    }

    private func clipClock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func progressBar(done: Int, total: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule()
                    .fill(i < done ? Theme.Colors.accent : Color(hex: 0xE4DAC6))
                    .frame(height: 4)
            }
        }
    }

    private func controlsRow(for controller: PollySessionController) -> some View {
        HStack(spacing: 20) {
            Button {
                Haptics.impact(.light); controller.toggleHardMute()
            } label: {
                controlCircle(controller.isHardMuted ? MS.micOffFill : MS.micFill,
                              glyph: controller.isHardMuted ? Theme.Colors.tomato : Theme.Colors.tabLabel,
                              size: 52, bg: Theme.Colors.tabBar, bordered: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isHardMuted ? "Unmute Polly" : "Mute Polly")

            Button {
                Haptics.impact(.medium); isConfirmingExit = true
            } label: {
                MS.callEndFill.sized(29).foregroundStyle(Theme.Colors.creamText)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Theme.Colors.tomato))
                    .shadow(color: Color.black.opacity(0.28), radius: 12, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End the call")

            Button {
                Haptics.impact(.light)
                if controller.camera.isRunning {
                    controller.camera.stop()
                } else {
                    Task { await controller.camera.start() }
                }
            } label: {
                controlCircle(MS.videocamFill, glyph: Theme.Colors.brightAccent,
                              size: 52, bg: Theme.Colors.tabBar, bordered: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.camera.isRunning ? "Turn camera off" : "Turn camera on")
        }
    }

    private func controlCircle(_ icon: MS, glyph: Color, size: CGFloat, bg: Color, bordered: Bool) -> some View {
        icon.sized(size * 0.44).foregroundStyle(glyph)
            .frame(width: size, height: size)
            .background(Circle().fill(bg))
            .overlay(bordered ? Circle().strokeBorder(Theme.Colors.tabLabel.opacity(0.18), lineWidth: 1) : nil)
    }

    // MARK: - Step helpers

    private func currentStep(of controller: PollySessionController) -> CookPlan.PlanStep? {
        guard let plan = controller.plan, plan.steps.indices.contains(controller.stepIndex) else { return nil }
        return plan.steps[controller.stepIndex]
    }

    private func nextStepTitle(of controller: PollySessionController) -> String? {
        guard let plan = controller.plan else { return nil }
        let next = controller.stepIndex + 1
        guard plan.steps.indices.contains(next) else { return nil }
        return plan.steps[next].title.lowercased()
    }

    private func startTimer(for step: CookPlan.PlanStep, seconds: Int, controller: PollySessionController) {
        controller.timers.start(label: "Step \(step.index + 1): \(String(step.title.prefix(40)))", seconds: seconds)
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
                Text("One sec, reconnecting…")
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.creamText)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.Colors.textPrimary.opacity(0.55)).clipShape(Capsule())
                    .padding(.top, 110)
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
            ProgressView().tint(Theme.Colors.accent)
            Text(message).font(.gluttHeadline).foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: 300)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
    }

    private func failedCard(message: String, controller: PollySessionController) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            MS.graphicEqFill.sized(30).foregroundStyle(Theme.Colors.accent)
            Text("Polly couldn't pick up").font(.gluttTitle).foregroundStyle(Theme.Colors.textPrimary)
            Text(message).font(.gluttBody).foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Haptics.impact(.medium)
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
            MS.micOffFill.sized(30).foregroundStyle(Theme.Colors.accent)
            Text("Polly can't hear you").font(.gluttTitle).foregroundStyle(Theme.Colors.textPrimary)
            Text("Polly needs the microphone to cook with you. You can enable it in Settings, or cook without her.")
                .font(.gluttBody).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(.center)
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

// MARK: - Listening edge border

/// The crisp gradient border that animates in while Polly is listening — a solid
/// color edge (green → green → amber → tomato), pulsing subtly, that reads as
/// "the phone is hearing you." Source: `Glutt Polly.dc.html`, state "Listening".
private struct ListeningEdge: View {
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 44, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Theme.Colors.brightAccent, Theme.Colors.accent, Theme.Colors.amber, Theme.Colors.coralBright],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 6
            )
            .padding(3)
            .opacity(pulse ? 1 : 0.88)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { pulse = true }
            }
            .transition(.opacity)
    }
}

// MARK: - Listening wake sweep

/// A one-shot diagonal light "slash" that glides across the whole screen the
/// instant Polly starts listening — a quick, celebratory "I heard you" flourish.
/// Mounts only while listening, so it replays on each wake and never loops.
private struct ListeningSweep: View {
    @State private var x: CGFloat = -1

    var body: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear,
                         Theme.Colors.brightAccent.opacity(0.55),
                         Color.white.opacity(0.35),
                         Theme.Colors.brightAccent.opacity(0.55),
                         .clear],
                startPoint: .leading, endPoint: .trailing))
            .frame(width: 240)
            .blur(radius: 16)
            .rotationEffect(.degrees(22))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: x * 620)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .blendMode(.plusLighter)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { x = 1 }
            }
    }
}

// MARK: - Listening waveform

/// Four staggered bars that bounce while Polly is listening.
private struct WaveformBars: View {
    @State private var animate = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Theme.Colors.brightAccent)
                    .frame(width: 3, height: 14)
                    .scaleEffect(y: animate ? 1 : 0.3, anchor: .bottom)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .frame(height: 14)
        .onAppear { animate = true }
    }
}
