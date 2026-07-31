import SwiftUI

/// Adaptive Video Canvas cook session UI (`docs/newDesign.md`).
/// Layers: full-bleed visual canvas → floating step sheet → Polly dock.
struct PollyAdaptiveCanvasView: View {
    @Bindable var controller: PollySessionController
    let recipe: Recipe
    let onMinimize: () -> Void
    let onRequestEnd: () -> Void
    let onStartTimer: (CookPlan.PlanStep, Int) -> Void

    @State private var sheetExpanded = false
    @State private var clipPlaying = false
    @State private var replayNonce = 0
    @State private var showAttribution = false
    @State private var showOverflow = false
    @State private var showIngredients = false
    @State private var showStepDetail = false

    private var plan: CookPlan? { controller.plan }
    private var step: CookPlan.PlanStep? {
        guard let plan, plan.steps.indices.contains(controller.stepIndex) else { return nil }
        return plan.steps[controller.stepIndex]
    }
    private var nativeClip: NativeStepClip? { controller.nativeClipForCurrentStep() }
    private var hasClip: Bool { nativeClip != nil }
    private var isCamera: Bool { controller.camera.isRunning }
    /// Shrink the step card only while a real clip is playing — never on Tools/Prep.
    private var sheetMini: Bool { hasClip && clipPlaying && !isCamera }
    /// Missing-ingredients screen Polly talks through before Tools.
    private var showingPreflight: Bool {
        !controller.preflightDismissed && !controller.missingIngredients.isEmpty
    }

    var body: some View {
        ZStack {
            canvas
            topScrim
            VStack(spacing: 0) {
                topNav
                progressLine
                Spacer(minLength: 0)
                if controller.isPollySpeaking || controller.isThinking {
                    pollyBubble
                        .padding(.horizontal, CookCanvasTheme.margin)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                stepSheet
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                pollyDock
                    .padding(.horizontal, CookCanvasTheme.margin)
                    .padding(.bottom, 8)
            }
            .padding(.top, 8)
        }
        .animation(.easeInOut(duration: 0.22), value: clipPlaying)
        .animation(.easeInOut(duration: 0.22), value: controller.isPollySpeaking)
        .animation(.easeInOut(duration: 0.22), value: sheetExpanded)
        .animation(.easeInOut(duration: 0.22), value: showingPreflight)
        .confirmationDialog("Video source", isPresented: $showAttribution, titleVisibility: .visible) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attributionMessage)
        }
        .confirmationDialog("Cooking", isPresented: $showOverflow, titleVisibility: .hidden) {
            Button("View full recipe") { showIngredients = true }
            Button("Ingredients") { showIngredients = true }
            if !controller.timers.timers.isEmpty {
                Button("Timers (\(controller.timers.timers.count))") {}
            }
            Button("End cooking session", role: .destructive, action: onRequestEnd)
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showIngredients) {
            NavigationStack {
                List {
                    Section("Ingredients") {
                        ForEach(recipe.ingredients.sorted(by: { $0.sortIndex < $1.sortIndex })) { ing in
                            Text(ingredientLine(ing))
                        }
                    }
                    Section("Steps") {
                        ForEach(recipe.steps.sorted(by: { $0.index < $1.index })) { s in
                            Text("\(s.index + 1). \(s.text)")
                                .font(.body)
                        }
                    }
                }
                .navigationTitle(recipe.title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showIngredients = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: controller.mediaState) { _, state in
            guard let currentID = nativeClip?.segmentID else { return }
            switch state {
            case .playing(let id, _):
                guard id == currentID else { return }
                clipPlaying = true
            case .finished(let id), .paused(let id):
                guard id == currentID else { return }
                clipPlaying = false
            case .idle, .preparing:
                break
            }
        }
        .onChange(of: controller.clipRestartToken) { _, _ in
            guard hasClip else { return }
            clipPlaying = true
            replayNonce += 1
        }
        .onChange(of: controller.clipPlaybackDesired) { _, want in
            guard hasClip else { return }
            if !want { clipPlaying = false }
        }
        .onChange(of: controller.stepIndex) { _, _ in
            sheetExpanded = false
            showStepDetail = false
            controller.syncClipPlaybackForCurrentStep()
            // Local mirror — restart token also bumps nonce when a clip exists.
            if controller.nativeClipForCurrentStep() == nil {
                clipPlaying = false
                replayNonce += 1
            }
        }
        .sheet(isPresented: $showStepDetail) {
            if let step {
                stepDetailSheet(step)
            }
        }
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvas: some View {
        ZStack {
            CookCanvasTheme.mainBlack.ignoresSafeArea()
            if isCamera {
                CameraPreviewView(previewLayer: controller.camera.previewLayer)
                    .ignoresSafeArea()
            } else if let clip = nativeClip {
                canvasClip(clip)
            } else {
                recipeFallbackPoster
            }
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.45),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func canvasClip(_ clip: NativeStepClip) -> some View {
        ZStack {
            // Blur-fill 9:16 derivative autoplays — no grey material play CTA.
            NativeClipPlayerView(
                clip: clip,
                autoplay: clipPlaying,
                muted: clipMutedBinding,
                showsInlineMuteControl: false,
                fillsCanvas: true
            ) { state in
                controller.updateMediaState(state)
                if case .finished = state { clipPlaying = false }
            }
            .ignoresSafeArea()

            if !clipPlaying {
                Button {
                    Haptics.impact(.light)
                    _ = controller.controlStepVideo(action: "play")
                } label: {
                    Label("Play example", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        controller.setClipMuted(!controller.clipMuted)
                    } label: {
                        Image(systemName: controller.clipMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(controller.clipMuted ? "Hear original audio" : "Mute original audio")
                    .padding(.trailing, 16)
                    .padding(.top, 56)
                }
                Spacer()
                HStack {
                    Button { showAttribution = true } label: {
                        Text(attributionShort)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(clip.displayLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .allowsHitTesting(true)
        }
        .id("\(clip.segmentID)-\(replayNonce)")
    }

    private func poster(for clip: NativeStepClip) -> some View {
        Group {
            if let url = clip.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        CookCanvasTheme.elevated
                    }
                }
            } else {
                CookCanvasTheme.elevated
            }
        }
        .ignoresSafeArea()
    }

    private var recipeFallbackPoster: some View {
        Group {
            if let data = recipe.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                CookCanvasTheme.elevated
            }
        }
        .ignoresSafeArea()
        .overlay(Color.black.opacity(0.35))
    }

    private var topScrim: some View {
        LinearGradient(colors: [Color.black.opacity(0.5), .clear], startPoint: .top, endPoint: .center)
            .frame(height: 140)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: - Top nav

    private var topNav: some View {
        HStack(spacing: 12) {
            circleButton(system: "chevron.down", action: onMinimize)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(recipe.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CookCanvasTheme.primaryText)
                    .lineLimit(1)
                if showingPreflight {
                    Text("Before you start")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CookCanvasTheme.secondaryText)
                } else if let plan {
                    Text("Step \(controller.stepIndex + 1) of \(plan.steps.count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CookCanvasTheme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            circleButton(system: "ellipsis", action: { showOverflow = true })
        }
        .padding(.horizontal, CookCanvasTheme.margin)
    }

    private func circleButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CookCanvasTheme.primaryText)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }

    private var progressLine: some View {
        GeometryReader { geo in
            let total = max(plan?.steps.count ?? 1, 1)
            let done = showingPreflight ? 0 : min(controller.stepIndex + 1, total)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(CookCanvasTheme.green)
                    .frame(width: geo.size.width * CGFloat(done) / CGFloat(total))
            }
        }
        .frame(height: 3)
        .padding(.horizontal, CookCanvasTheme.margin)
        .padding(.top, 10)
    }

    // MARK: - Step sheet

    private var stepSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showingPreflight {
                preflightSheet
            } else if sheetMini, let step {
                miniSheet(step)
            } else if sheetExpanded, let step {
                expandedSheet(for: step)
            } else if let step {
                defaultSheet(step)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .frame(minHeight: sheetMini && !showingPreflight ? 96 : (sheetExpanded || showingPreflight ? 320 : 210))
        .background(
            RoundedRectangle(cornerRadius: CookCanvasTheme.sheetRadius, style: .continuous)
                .fill(CookCanvasTheme.stepSheet.opacity(0.96))
        )
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard !showingPreflight else { return }
                    if value.translation.height < -40 { sheetExpanded = true }
                    if value.translation.height > 40 { sheetExpanded = false }
                }
        )
    }

    private var preflightSheet: some View {
        let missing = controller.missingIngredients
        return VStack(alignment: .leading, spacing: 14) {
            Text("BEFORE YOU START")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(CookCanvasTheme.green)

            Text(missing.count == 1
                 ? "You're missing 1 thing"
                 : "You're missing \(missing.count) things")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(CookCanvasTheme.primaryText)

            Text("Polly’s walking through these with you. Sub out what you can, or grab what’s easy.")
                .font(.system(size: 16))
                .foregroundStyle(CookCanvasTheme.secondaryText)
                .lineSpacing(4)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(missing, id: \.self) { name in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(CookCanvasTheme.warning)
                                .frame(width: 7, height: 7)
                            Text(name)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(CookCanvasTheme.primaryText)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(maxHeight: missing.count > 6 ? 200 : nil)

            Button {
                Haptics.impact(.medium)
                controller.dismissPreflight()
            } label: {
                Text("Got it, let’s cook")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CookCanvasTheme.mainBlack)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(CookCanvasTheme.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func defaultSheet(_ step: CookPlan.PlanStep) -> some View {
        let isSetup = CookPlan.isSetupStep(step)
        let items = checklist(for: step)
        let done = items.filter { controller.checkedActionIDs.contains($0.id) }.count

        return VStack(alignment: .leading, spacing: 12) {
            Button {
                sheetExpanded = true
            } label: {
                HStack(spacing: 6) {
                    Text(eyebrow(step: step, done: done, total: items.count, isSetup: isSetup))
                    if isSetup, items.count > 1 {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(CookCanvasTheme.green)
            }
            .buttonStyle(.plain)

            Text(displayTitle(step))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(CookCanvasTheme.primaryText)
                .lineLimit(2)

            if isSetup {
                // Tools / Prep: the checklist IS the content.
                setupChecklistPreview(items)
            } else {
                Text(displayInstruction(step))
                    .font(.system(size: 18))
                    .foregroundStyle(CookCanvasTheme.secondaryText)
                    .lineSpacing(5)
                    .lineLimit(showStepDetail ? nil : 3)

                Button {
                    Haptics.selection()
                    showStepDetail = true
                } label: {
                    Text("Tap to view more")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CookCanvasTheme.green)
                }
                .buttonStyle(.plain)
            }

            if !controller.timers.timers.isEmpty {
                PollyTimersRow(manager: controller.timers)
            }

            if let seconds = step.timerSeconds, seconds > 0 {
                Button {
                    Haptics.impact(.light)
                    onStartTimer(step, seconds)
                } label: {
                    Text("Start \(TimerManager.format(seconds: seconds)) timer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CookCanvasTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                Haptics.impact(.medium)
                markStepDone(step: step, items: items)
            } label: {
                Label(isSetup ? "All set — next" : "Mark done", systemImage: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CookCanvasTheme.mainBlack)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(CookCanvasTheme.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if let next = nextStepTitle {
                Text("UP NEXT  ·  \(next)")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(CookCanvasTheme.mutedText)
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func setupChecklistPreview(_ items: [StepActionChecklist.Item]) -> some View {
        let preview = Array(items.prefix(4))
        VStack(alignment: .leading, spacing: 8) {
            ForEach(preview) { item in
                checklistRow(item)
            }
            if items.count > preview.count {
                Button {
                    sheetExpanded = true
                } label: {
                    Text("View all \(items.count) · swipe up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CookCanvasTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func checklistRow(_ item: StepActionChecklist.Item) -> some View {
        let checked = controller.checkedActionIDs.contains(item.id)
        return Button {
            Haptics.impact(.light)
            controller.toggleChecklistItem(item.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(checked ? CookCanvasTheme.green : CookCanvasTheme.mutedText)
                Text(item.text)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(checked ? CookCanvasTheme.mutedText : CookCanvasTheme.primaryText)
                    .strikethrough(checked, color: CookCanvasTheme.mutedText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func miniSheet(_ step: CookPlan.PlanStep) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STEP \(displayStepNumber(step))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CookCanvasTheme.green)
                Text(displayTitle(step))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CookCanvasTheme.primaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                if clipPlaying {
                    _ = controller.controlStepVideo(action: "pause")
                } else {
                    _ = controller.controlStepVideo(action: "play")
                }
            } label: {
                Text(clipPlaying ? "Pause video" : "Play video")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CookCanvasTheme.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func expandedSheet(for step: CookPlan.PlanStep) -> some View {
        if CookPlan.isSetupStep(step) {
            setupExpandedSheet(step)
        } else if let plan {
            stepsOverviewSheet(plan)
        }
    }

    private func setupExpandedSheet(_ step: CookPlan.PlanStep) -> some View {
        let items = checklist(for: step)
        let label = step.id == CookPlan.toolsStepID ? "TOOLS" : "PREP"
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CookCanvasTheme.green)
                Spacer()
                Button("Done") { sheetExpanded = false }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CookCanvasTheme.secondaryText)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        checklistRow(item)
                    }
                }
            }
        }
    }

    private func stepsOverviewSheet(_ plan: CookPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("STEPS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CookCanvasTheme.green)
                Spacer()
                Button("Done") { sheetExpanded = false }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CookCanvasTheme.secondaryText)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, s in
                        let active = index == controller.stepIndex
                        Button {
                            controller.goToStep(index)
                            sheetExpanded = false
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: index < controller.stepIndex ? "checkmark.circle.fill" : (active ? "circle.inset.filled" : "circle"))
                                    .foregroundStyle(index < controller.stepIndex || active ? CookCanvasTheme.green : CookCanvasTheme.mutedText)
                                Text(displayTitle(s))
                                    .font(.system(size: active ? 18 : 16, weight: active ? .semibold : .regular))
                                    .foregroundStyle(active ? CookCanvasTheme.primaryText : CookCanvasTheme.mutedText)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Polly dock

    private var pollyDock: some View {
        HStack(spacing: 12) {
            waveform
            Button {
                Haptics.impact(.medium)
                controller.forceListen()
            } label: {
                Text(dockCopy)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CookCanvasTheme.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.selection()
                Task {
                    if controller.camera.isRunning {
                        controller.camera.stop()
                        clipPlaying = false
                    } else {
                        clipPlaying = false
                        _ = await controller.camera.start()
                    }
                }
            } label: {
                Image(systemName: isCamera ? "video.fill" : "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isCamera ? CookCanvasTheme.mainBlack : CookCanvasTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(isCamera ? CookCanvasTheme.green : Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCamera ? "Back to step video" : "Show Polly your pan")
        }
        .padding(.horizontal, 14)
        .frame(height: CookCanvasTheme.dockHeight)
        .background(
            Capsule()
                .fill(CookCanvasTheme.elevated.opacity(0.96))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        )
    }

    private var waveform: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(CookCanvasTheme.green)
                        .frame(width: 3, height: barHeight(index: i, t: t))
                }
            }
            .frame(width: 28, height: 28)
        }
    }

    private func barHeight(index: Int, t: Double) -> CGFloat {
        let base: CGFloat
        switch controller.listeningMode {
        case .listening, .followUp: base = 10 + CGFloat((sin(t * 8 + Double(index)) + 1) * 8)
        default:
            if controller.isPollySpeaking { base = 8 + CGFloat((sin(t * 6 + Double(index)) + 1) * 7) }
            else if controller.isThinking { base = 6 + CGFloat((sin(t * 3 + Double(index)) + 1) * 4) }
            else if hasClip && clipPlaying { base = 5 }
            else { base = 4 + (index == 2 ? 4 : 0) }
        }
        return max(4, min(24, base))
    }

    private var dockCopy: String {
        if hasClip && clipPlaying { return "Playing example" }
        if controller.isHardMuted { return "Mic muted — tap to talk" }
        if controller.isThinking { return "Thinking…" }
        if controller.isPollySpeaking { return "Polly is helping" }
        switch controller.listeningMode {
        case .listening: return "Listening…"
        case .followUp: return "Listening…"
        case .dormant: return controller.wakeWordAvailable ? "Say “Polly” or tap to talk" : "Tap to talk"
        }
    }

    private var pollyBubble: some View {
        Text(controller.captionText.isEmpty ? (controller.isThinking ? "…" : "") : controller.captionText)
            .font(.system(size: 17))
            .foregroundStyle(CookCanvasTheme.primaryText)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CookCanvasTheme.elevated.opacity(0.92))
            )
    }

    private func stepDetailSheet(_ step: CookPlan.PlanStep) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(displayTitle(step))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(CookCanvasTheme.primaryText)

                    detailBlock(title: "What to do", body: detailInstruction(step))

                    if let cue = nativeClip?.visualCue.trimmingCharacters(in: .whitespacesAndNewlines),
                       !cue.isEmpty,
                       cue != step.instruction.trimmingCharacters(in: .whitespacesAndNewlines) {
                        detailBlock(title: "From the video", body: cue)
                    }

                    if let check = step.visualCheck?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !check.isEmpty {
                        detailBlock(title: "Done when", body: check)
                    }

                    if let recovery = step.recovery?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !recovery.isEmpty {
                        detailBlock(title: "If it goes wrong", body: recovery)
                    }

                    if !step.ingredientNames.isEmpty {
                        detailBlock(
                            title: "Ingredients for this step",
                            body: step.ingredientNames.joined(separator: "\n")
                        )
                    }

                    if let seconds = step.timerSeconds, seconds > 0 {
                        detailBlock(title: "Timer", body: TimerManager.format(seconds: seconds))
                    } else if let seconds = step.estimatedSeconds, seconds > 0 {
                        detailBlock(title: "About", body: TimerManager.format(seconds: seconds))
                    }

                    if let notice = nativeClip?.notice.trimmingCharacters(in: .whitespacesAndNewlines),
                       !notice.isEmpty {
                        detailBlock(title: "Clip tip", body: notice)
                    }
                }
                .padding(20)
            }
            .background(CookCanvasTheme.mainBlack.ignoresSafeArea())
            .navigationTitle("Step detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showStepDetail = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func detailBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(CookCanvasTheme.green)
            Text(body)
                .font(.system(size: 17))
                .foregroundStyle(CookCanvasTheme.primaryText)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CookCanvasTheme.stepSheet)
        )
    }

    private func detailInstruction(_ step: CookPlan.PlanStep) -> String {
        let planText = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cue = nativeClip?.visualCue.trimmingCharacters(in: .whitespacesAndNewlines),
           !cue.isEmpty {
            // Full detail: video method first, then original plan wording if different.
            if !planText.isEmpty, planText.caseInsensitiveCompare(cue) != .orderedSame {
                return "\(cue)\n\nRecipe note: \(planText)"
            }
            return cue
        }
        return planText
    }

    // MARK: - Helpers

    private var clipMutedBinding: Binding<Bool> {
        Binding(
            get: { controller.clipMuted },
            set: { controller.setClipMuted($0) }
        )
    }

    private var attributionShort: String {
        if let name = nativeClip?.creatorAttribution, !name.isEmpty {
            return "From \(name)"
        }
        return "Original recipe video"
    }

    private var attributionMessage: String {
        let title = recipe.title
        let creator = nativeClip?.creatorAttribution ?? recipe.sourceCreator ?? "Creator"
        return "\(title)\n\(creator)"
    }

    private var nextStepTitle: String? {
        guard let plan, controller.stepIndex + 1 < plan.steps.count else { return nil }
        return displayTitle(plan.steps[controller.stepIndex + 1])
    }

    private func displayTitle(_ step: CookPlan.PlanStep) -> String {
        if step.id == CookPlan.toolsStepID {
            let t = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Grab your tools" : t
        }
        if step.id == CookPlan.prepStepID || step.kind == .prep {
            let t = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Mise en place" : t
        }
        let t = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return String(step.instruction.prefix(42))
    }

    private func displayInstruction(_ step: CookPlan.PlanStep) -> String {
        // Prefer what the technique clip actually shows so UI and Polly match.
        if let cue = nativeClip?.visualCue.trimmingCharacters(in: .whitespacesAndNewlines),
           !cue.isEmpty {
            return cue
        }
        let raw = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.count <= 140 { return raw }
        return String(raw.prefix(137)) + "…"
    }

    private func displayStepNumber(_ step: CookPlan.PlanStep) -> String {
        guard let plan else { return "\(controller.stepIndex + 1)" }
        if CookPlan.isSetupStep(step) {
            return step.id == CookPlan.toolsStepID ? "TOOLS" : "PREP"
        }
        let setup = plan.leadingSetupCount
        return "\(max(1, controller.stepIndex + 1 - setup))"
    }

    private func eyebrow(step: CookPlan.PlanStep, done: Int, total: Int, isSetup: Bool) -> String {
        if step.id == CookPlan.toolsStepID {
            return total > 0 ? "TOOLS  ·  \(done)/\(total)" : "TOOLS"
        }
        if step.id == CookPlan.prepStepID || step.kind == .prep {
            return total > 0 ? "PREP  ·  \(done)/\(total)" : "PREP"
        }
        // Cook steps are already bite-sized — no fake "action 1 of 2".
        return "STEP \(displayStepNumber(step))"
    }

    private func checklist(for step: CookPlan.PlanStep) -> [StepActionChecklist.Item] {
        guard let plan else { return [] }
        return StepActionChecklist.items(for: step, plan: plan)
    }

    /// One tap finishes the step. Setup lists can still be checked off one-by-one;
    /// the green button means "I'm done with this step."
    private func markStepDone(step: CookPlan.PlanStep, items: [StepActionChecklist.Item]) {
        for item in items where !controller.checkedActionIDs.contains(item.id) {
            controller.toggleChecklistItem(item.id)
        }
        controller.goToNextStep()
    }

    private func ingredientLine(_ ingredient: RecipeIngredient) -> String {
        if let display = UnitConverter.display(
            quantity: ingredient.quantity,
            unit: ingredient.unit,
            scale: 1,
            system: .original,
            ingredientName: ingredient.name
        ) {
            let amount = ingredient.isEstimated ? "~\(display)" : display
            return "\(amount) \(ingredient.name)"
        }
        return ingredient.name
    }
}
