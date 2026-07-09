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

// MARK: - Orb

/// Polly's presence: a 64 pt herb-green orb. Swells with the mic level while
/// listening, breathes gently while Polly speaks, dims in a slow pulse while
/// she thinks, sits still when idle.
struct PollyOrb: View {
    let inputLevel: Float
    let isListening: Bool
    let isSpeaking: Bool
    let isThinking: Bool

    @State private var breathe = false
    @State private var thinkingPulse = false

    private var micScale: CGFloat {
        guard isListening else { return 1 }
        return 1 + 0.25 * CGFloat(min(max(inputLevel, 0), 1))
    }

    private var showsThinking: Bool { isThinking && !isSpeaking && !isListening }

    var body: some View {
        Circle()
            .fill(Theme.Colors.accent)
            .overlay(
                Ph.chefHat.fill
                    .resizable().scaledToFit()
                    .frame(width: 26, height: 26)
                    .foregroundStyle(Theme.Colors.creamText)
            )
            .frame(width: 64, height: 64)
            .scaleEffect(isSpeaking ? (breathe ? 1.12 : 1.0) : micScale)
            .opacity(showsThinking ? (thinkingPulse ? 0.55 : 1.0) : 1.0)
            .animation(.easeOut(duration: 0.1), value: micScale)
            .onChange(of: isSpeaking) { _, speaking in
                if speaking {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        breathe = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { breathe = false }
                }
            }
            .onChange(of: showsThinking) { _, thinking in
                if thinking {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        thinkingPulse = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { thinkingPulse = false }
                }
            }
            .accessibilityLabel(
                isSpeaking ? "Polly is speaking"
                    : isListening ? "Polly is listening"
                    : showsThinking ? "Polly is thinking"
                    : "Polly"
            )
    }
}

// MARK: - Step card

/// The current CookPlan step, floated above the camera near the controls.
/// Polly narrates out loud; this card is the glanceable "where are we" anchor.
struct PollyStepCard: View {
    let step: CookPlan.PlanStep
    let totalSteps: Int
    let onStartTimer: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel(text: "Step \(step.index + 1) of \(totalSteps)")
            Text(step.title)
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(step.instruction)
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let seconds = step.timerSeconds {
                Button {
                    Haptics.selection()
                    onStartTimer(seconds)
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Ph.timer.regular
                            .resizable().scaledToFit()
                            .frame(width: 15, height: 15)
                        Text("Start \(TimerManager.format(seconds: seconds)) timer")
                            .font(.gluttCaption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 9)
                    .background(Theme.Colors.warning)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.photo, style: .continuous))
    }
}

// MARK: - Step hero

/// The current CookPlan step, blown up big and centered for a voice-only
/// session — the one thing a cook needs to glance at across the kitchen. No
/// card chrome: just large, legible cream text on the dark backdrop, with the
/// step's timer one tap away.
struct PollyStepHero: View {
    let step: CookPlan.PlanStep
    let totalSteps: Int
    let onStartTimer: (Int) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("STEP \(step.index + 1) OF \(totalSteps)")
                .font(.system(size: 13, weight: .heavy))
                .tracking(2)
                .foregroundStyle(Theme.Colors.accent)
            Text(step.title)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Colors.creamText)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.instruction)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.Colors.creamText.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let seconds = step.timerSeconds {
                Button {
                    Haptics.selection()
                    onStartTimer(seconds)
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Ph.timer.regular
                            .resizable().scaledToFit()
                            .frame(width: 17, height: 17)
                        Text("Start \(TimerManager.format(seconds: seconds)) timer")
                            .font(.gluttBody.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, 12)
                    .background(Theme.Colors.warning)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preflight card

/// Missing-ingredients checklist shown while Polly talks through the
/// preflight conversationally. Dismissible — Polly and the cook may well
/// decide to press on with substitutions.
struct PreflightCard: View {
    let missing: [String]
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel(text: "Before you start")
            Text("You're missing:")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            ForEach(missing, id: \.self) { name in
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(Theme.Colors.tomato)
                        .frame(width: 6, height: 6)
                    Text(name)
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Button {
                Haptics.selection()
                onDismiss()
            } label: {
                Text("Got it")
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.photo, style: .continuous))
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
                            Ph.bellRinging.fill
                                .resizable().scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundStyle(.white)
                                .onAppear { Haptics.notify(.success) }
                        } else {
                            Ph.timer.regular
                                .resizable().scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundStyle(.white)
                        }
                        Text(remaining == 0 ? "Done!" : TimerManager.format(seconds: remaining))
                            .monospacedDigit()
                        Button {
                            Haptics.impact(.light)
                            manager.cancel(timer)
                        } label: {
                            Ph.xCircle.fill
                                .resizable().scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(remaining == 0 ? Theme.Colors.tomato : Theme.Colors.accent)
                    .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Control button

/// Circular glass control for the session bar. Every tap gives haptic feedback.
struct PollyControlButton: View {
    let icon: Image
    var tint: Color = .white
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            icon
                .resizable().scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(label)
    }
}
