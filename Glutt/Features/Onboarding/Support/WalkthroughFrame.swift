import SwiftUI

/// Renders a tutorial screenshot fit-to-width and overlays a tappable, pulsing
/// hotspot over a real button. Tap inside → `onHotspotTap`; tap elsewhere →
/// `onMiss`; ~4s idle → `onIdle` (safety net). Idle timer resets on any tap.
struct WalkthroughFrame: View {
    let step: TutorialStep
    let nudgeToken: Int
    let onHotspotTap: () -> Void
    let onMiss: () -> Void
    let onIdle: () -> Void

    private static let idleSeconds: Double = 4

    @State private var idleResetToken = 0

    /// Aspect (w/h) read from the asset so the hotspot maps onto the real button.
    private var aspect: CGFloat {
        guard let image = UIImage(named: step.imageName), image.size.height > 0 else { return 0.46 }
        return image.size.width / image.size.height
    }

    var body: some View {
        Image(step.imageName)
            .resizable()
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let rect = hotspotRect(in: proxy.size)
                    ZStack {
                        CoachMark(pointer: step.pointer,
                                  showsLabel: step.showsLabel,
                                  nudgeToken: nudgeToken)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)

                        #if DEBUG
                        Rectangle()
                            .stroke(.red, lineWidth: 1)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                        #endif
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in handleTap(value.location, in: proxy.size) }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: Theme.Colors.textPrimary.opacity(0.12), radius: 14, y: 4)
            .task(id: "\(step.id)-\(idleResetToken)") {
                try? await Task.sleep(for: .seconds(Self.idleSeconds))
                guard !Task.isCancelled else { return }
                onIdle()
            }
    }

    private func hotspotRect(in size: CGSize) -> CGRect {
        CGRect(x: step.hotspot.minX * size.width,
               y: step.hotspot.minY * size.height,
               width: step.hotspot.width * size.width,
               height: step.hotspot.height * size.height)
    }

    private func handleTap(_ location: CGPoint, in size: CGSize) {
        idleResetToken += 1 // any tap restarts the idle countdown
        #if DEBUG
        print("CoachMark tap — normalized x=\(location.x / size.width), y=\(location.y / size.height)")
        #endif
        if hotspotRect(in: size).contains(location) {
            onHotspotTap()
        } else {
            onMiss()
        }
    }
}
