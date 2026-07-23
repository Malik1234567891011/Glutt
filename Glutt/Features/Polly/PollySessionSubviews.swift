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
