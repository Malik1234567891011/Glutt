import AVFoundation
import SwiftUI

/// Muted, seamlessly-looping, aspect-fill video (the design's autoplay/loop/muted
/// <video>). `scale`/`yOffsetFraction` mirror the HTML crop transforms.
/// Uses .ambient + mixWithOthers so onboarding never interrupts the user's audio.
struct LoopingVideoView: UIViewRepresentable {
    let resource: String
    var scale: CGFloat = 1
    var yOffsetFraction: CGFloat = 0

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(resource: resource, scale: scale, yOffsetFraction: yOffsetFraction)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.stop()
    }

    final class PlayerContainerView: UIView {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private let playerLayer = AVPlayerLayer()
        private var scale: CGFloat = 1
        private var yOffsetFraction: CGFloat = 0

        func configure(resource: String, scale: CGFloat, yOffsetFraction: CGFloat) {
            guard player == nil else { return }
            self.scale = scale
            self.yOffsetFraction = yOffsetFraction
            guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
                assertionFailure("Missing video \(resource).mp4")
                return // cream frame behind stays — graceful no-op
            }
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer(items: [item])
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: item)
            player = queue
            playerLayer.player = queue
            playerLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(playerLayer)
            queue.play()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            playerLayer.setAffineTransform(
                CGAffineTransform(translationX: 0, y: bounds.height * yOffsetFraction)
                    .scaledBy(x: scale, y: scale)
            )
            CATransaction.commit()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            window == nil ? player?.pause() : player?.play()
        }

        func stop() {
            player?.pause()
            playerLayer.player = nil
            player = nil
            looper = nil
        }
    }
}
