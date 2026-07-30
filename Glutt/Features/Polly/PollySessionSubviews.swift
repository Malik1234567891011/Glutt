import AVFoundation
import SwiftUI

// MARK: - Camera preview

/// Hosts the session camera's AVCaptureVideoPreviewLayer full-bleed behind
/// the overlay chrome. The UIKit hop is unavoidable: preview layers are CALayers.
struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    final class LayerHostView: UIView {
        var hostedLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                guard hostedLayer !== oldValue else { return }
                oldValue?.removeFromSuperlayer()
                if let hostedLayer {
                    hostedLayer.videoGravity = .resizeAspectFill
                    layer.addSublayer(hostedLayer)
                    setNeedsLayout()
                }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            hostedLayer?.frame = bounds
        }
    }

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.hostedLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {
        uiView.hostedLayer = previewLayer
    }
}

// MARK: - Preflight card

/// Missing-ingredients checklist shown while Polly talks through the preflight
/// conversationally. Dismissible — Polly and the cook may well decide to press on
/// with substitutions. Sits in the Polly bottom cluster above the step card.
struct PreflightCard: View {
    let missing: [String]
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel(text: "Before you start")
            Text("You're missing \(missing.count):")
                .font(BrandFont.bricolage(17, 600))
                .foregroundStyle(Theme.Colors.heading)
            // Cap the list height and let it scroll: a long missing list used to
            // push the "Got it" button off-screen and strand the cook. Now the
            // button stays pinned below the scroll.
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(missing, id: \.self) { name in
                        HStack(spacing: Theme.Spacing.xs) {
                            Circle().fill(Theme.Colors.tomato).frame(width: 6, height: 6)
                            Text(name).font(.gluttCaption).foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: missing.count > 5 ? 128 : nil)
            Button {
                Haptics.selection()
                onDismiss()
            } label: {
                Text("Got it")
                    .font(BrandFont.nunito(14, 800))
                    .foregroundStyle(Theme.Colors.creamText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.Colors.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.3), radius: 20, y: 12)
    }
}

// MARK: - Timers row

/// Compact mirror of CookModeView's activeTimersBar, driven by the
/// session-owned TimerManager.
struct PollyTimersRow: View {
    let manager: TimerManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(manager.timers) { timer in
                    let remaining = timer.remainingSeconds(at: manager.now)
                    HStack(spacing: 6) {
                        if remaining == 0 {
                            MS.timerFill.sized(14).foregroundStyle(Theme.Colors.creamText)
                                .onAppear { Haptics.notify(.success) }
                        } else {
                            MS.timerFill.sized(14).foregroundStyle(Theme.Colors.creamText)
                        }
                        Text(remaining == 0 ? "Done!" : TimerManager.format(seconds: remaining))
                            .monospacedDigit()
                        Button {
                            Haptics.impact(.light)
                            manager.cancel(timer)
                        } label: {
                            MS.closeIcon.sized(13).foregroundStyle(Theme.Colors.creamText.opacity(0.7))
                        }
                    }
                    .font(BrandFont.nunito(13, 700))
                    .foregroundStyle(Theme.Colors.creamText)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(remaining == 0 ? Theme.Colors.tomato : Theme.Colors.accent)
                    .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Live step guide (camera-off / glanceable)

/// Dark glass checklist that fills the empty middle of a Polly call when the
/// camera is off. Swipe between steps; tap rows to check them off. Polly can
/// also check rows via `check_step_actions` when the cook says they finished
/// something. Stays in the cinematic Polly palette (not a cream card).
struct PollyStepGuidePanel: View {
    let plan: CookPlan
    let stepIndex: Int
    let checkedActionIDs: Set<String>
    let isPollySpeaking: Bool
    let onSelectStep: (Int) -> Void
    let onToggleItem: (String) -> Void
    var onStartTimer: ((CookPlan.PlanStep, Int) -> Void)? = nil
    /// Preferred: native downloaded clip (media-worker / Stream).
    var currentNativeClip: NativeStepClip? = nil
    var onNativeMediaState: ((PollyMediaState) -> Void)? = nil
    /// Fallback: Gemini-indexed YouTube window.
    var currentStepClip: StepClip? = nil
    var onWatchClip: ((StepClip) -> Void)? = nil

    @State private var appearedStepID: String?
    @State private var revealCount = 0

    private var steps: [CookPlan.PlanStep] { plan.steps }
    private var currentStep: CookPlan.PlanStep? {
        steps.indices.contains(stepIndex) ? steps[stepIndex] : nil
    }

    var body: some View {
        VStack(spacing: 10) {
            // Whole-cook progress (replaces the old cream card’s bar).
            progressBar

            TabView(selection: selectionBinding) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    stepPage(step, index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.22), value: stepIndex)

            if let native = currentNativeClip {
                VStack(alignment: .leading, spacing: 6) {
                    NativeClipPlayerView(clip: native) { state in
                        onNativeMediaState?(state)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .background(Color.black)
                    .padding(.horizontal, 18)

                    Text("\(native.watchLabel) · \(formatClock(Int(native.startSeconds)))–\(formatClock(Int(native.endSeconds)))")
                        .font(BrandFont.nunito(11, 700))
                        .foregroundStyle(Theme.Colors.tabLabel.opacity(0.55))
                        .padding(.horizontal, 22)
                }
            } else if let clip = currentStepClip {
                VStack(alignment: .leading, spacing: 6) {
                    YouTubePlayerView(
                        videoId: clip.youtubeVideoID,
                        startSeconds: clip.startSeconds,
                        endSeconds: clip.endSeconds,
                        mute: true
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .background(Color.black)
                    .padding(.horizontal, 18)

                    Text("\(clip.watchLabel) · \(formatClock(clip.startSeconds))–\(formatClock(clip.endSeconds))")
                        .font(BrandFont.nunito(11, 700))
                        .foregroundStyle(Theme.Colors.tabLabel.opacity(0.55))
                        .padding(.horizontal, 22)
                }
            }

            if let step = currentStep, let seconds = step.timerSeconds {
                Button {
                    Haptics.selection()
                    onStartTimer?(step, seconds)
                } label: {
                    HStack(spacing: 6) {
                        MS.timerFill.sized(16)
                        Text("Start \(TimerManager.format(seconds: seconds)) timer")
                            .font(BrandFont.nunito(13, 800))
                    }
                    .foregroundStyle(Theme.Colors.creamText)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(Theme.Colors.amber))
                }
                .buttonStyle(.plain)
            }

            if steps.count > 1 {
                pageDots
                Text("Swipe for steps · tap to check off")
                    .font(BrandFont.nunito(11, 700))
                    .foregroundStyle(Theme.Colors.tabLabel.opacity(0.4))
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(steps.count, 1), id: \.self) { i in
                Capsule()
                    .fill(i <= stepIndex ? Theme.Colors.brightAccent : Theme.Colors.tabLabel.opacity(0.22))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 22)
    }

    private var selectionBinding: Binding<Int> {
        Binding(
            get: { stepIndex },
            set: { newValue in
                guard newValue != stepIndex else { return }
                Haptics.selection()
                onSelectStep(newValue)
            }
        )
    }

    private func stepPage(_ step: CookPlan.PlanStep, index: Int) -> some View {
        let items = StepActionChecklist.items(for: step, plan: plan)
        let doneCount = items.filter { checkedActionIDs.contains($0.id) }.count
        let isSetup = CookPlan.isSetupStep(step)
        let setupCount = plan.leadingSetupCount
        let cookTotal = max(0, steps.count - setupCount)
        let cookNumber = isSetup ? 0 : max(1, index + 1 - setupCount)
        let eyebrow: String = {
            if step.id == CookPlan.toolsStepID { return "TOOLS" }
            if step.id == CookPlan.prepStepID || step.kind == .prep { return "PREP" }
            return "STEP \(cookNumber) ACTIONS"
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

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow)
                    .font(BrandFont.nunito(11, 800))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Colors.brightAccent)
                Spacer()
                Text(items.isEmpty
                     ? (isSetup ? (step.id == CookPlan.toolsStepID ? "Tools" : "Prep") : "\(cookNumber)/\(cookTotal)")
                     : "\(doneCount)/\(items.count) done")
                    .font(BrandFont.nunito(11, 700))
                    .foregroundStyle(Theme.Colors.tabLabel.opacity(0.55))
            }

            Text(headline)
                .font(BrandFont.bricolage(20, 600))
                .foregroundStyle(Theme.Colors.creamText)
                .lineLimit(2)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        checklistRow(
                            item,
                            isChecked: checkedActionIDs.contains(item.id),
                            visible: index != stepIndex || offset < revealCount
                        ) {
                            Haptics.impact(.light)
                            onToggleItem(item.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let next = nextTitle(after: index) {
                Text("Up next · \(next)")
                    .font(BrandFont.nunito(11, 700))
                    .foregroundStyle(Theme.Colors.tabLabel.opacity(0.45))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.Colors.tabBar.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.Colors.tabLabel.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .onAppear { playReveal(for: step, itemCount: items.count) }
        .onChange(of: stepIndex) { _, _ in
            if index == stepIndex {
                playReveal(for: step, itemCount: items.count)
            }
        }
        .onChange(of: isPollySpeaking) { _, speaking in
            if speaking, index == stepIndex {
                playReveal(for: step, itemCount: items.count, force: true)
            }
        }
        .onChange(of: checkedActionIDs) { _, _ in
            // Polly just checked something — keep rows fully visible.
            if index == stepIndex { revealCount = items.count }
        }
    }

    private func nextTitle(after index: Int) -> String? {
        let next = index + 1
        guard steps.indices.contains(next) else { return nil }
        return steps[next].title
    }

    private func checklistRow(
        _ item: StepActionChecklist.Item,
        isChecked: Bool,
        visible: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isChecked ? Theme.Colors.accent : Theme.Colors.tabLabel.opacity(0.35),
                            lineWidth: 2
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isChecked ? Theme.Colors.accent : Color.clear)
                        )
                        .frame(width: 26, height: 26)
                    if isChecked {
                        MS.checkFill.sized(14)
                            .foregroundStyle(Theme.Colors.creamText)
                    }
                }
                .padding(.top, 1)

                Text(item.text)
                    .font(BrandFont.nunito(15, item.isVisualCheck ? 700 : 600))
                    .foregroundStyle(
                        isChecked
                            ? Theme.Colors.tabLabel.opacity(0.45)
                            : (item.isVisualCheck ? Theme.Colors.brightAccent.opacity(0.95) : Theme.Colors.creamText.opacity(0.92))
                    )
                    .strikethrough(isChecked, color: Theme.Colors.tabLabel.opacity(0.35))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(item.isVisualCheck && !isChecked ? 0.06 : 0.03))
            )
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 8)
        .accessibilityLabel(item.text)
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<steps.count, id: \.self) { i in
                Capsule()
                    .fill(i == stepIndex ? Theme.Colors.brightAccent : Theme.Colors.tabLabel.opacity(0.28))
                    .frame(width: i == stepIndex ? 16 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: stepIndex)
    }

    /// Stagger checklist rows in when the step opens or Polly starts talking —
    /// feels like the actions "pop up" with her guidance.
    private func playReveal(for step: CookPlan.PlanStep, itemCount: Int, force: Bool = false) {
        guard force || appearedStepID != step.id else {
            revealCount = itemCount
            return
        }
        appearedStepID = step.id
        revealCount = 0
        for i in 0..<itemCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(i)) {
                guard appearedStepID == step.id else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    revealCount = i + 1
                }
            }
        }
    }

    private func formatClock(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
