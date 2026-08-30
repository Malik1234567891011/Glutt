import AVFoundation
import SwiftUI

/// Muted, seamlessly-looping video (the design's autoplay/loop/muted `<video>`).
/// `scale`/`yOffsetFraction` mirror the HTML crop transforms.
/// Uses .ambient + mixWithOthers so it never interrupts the user's audio.
///
/// Started life as onboarding wallpaper, which is why it fills its frame by
/// default. It is now also used for skill demonstrations, where cropping is not
/// an option: the knife grip clip carries burned-in captions right at the frame
/// edges, so filling would cut off the words that make it a lesson. Hence
/// `fills`.
struct LoopingVideoView: UIViewRepresentable {
    let resource: String
    var scale: CGFloat = 1
    var yOffsetFraction: CGFloat = 0

    /// `true` crops to fill the frame, `false` fits the whole video inside it.
    /// Wallpaper wants the first, anything with words in it wants the second.
    var fills: Bool = true

    /// Set false to hold the video still without tearing the player down.
    ///
    /// `didMoveToWindow` already handles the view leaving the hierarchy, and it
    /// is not enough on its own: a `fullScreenCover` presented over the lesson
    /// leaves the presenter in the window, so a demonstration loop would carry
    /// on playing underneath a live coaching session that has the camera and
    /// the microphone open.
    var isPlaying: Bool = true

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(
            resource: resource,
            scale: scale,
            yOffsetFraction: yOffsetFraction,
            fills: fills)
        view.setPlaying(isPlaying)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.stop()
    }

    final class PlayerContainerView: UIView {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private let playerLayer = AVPlayerLayer()
        private var scale: CGFloat = 1
        private var yOffsetFraction: CGFloat = 0

        /// Whether the caller wants it playing. Kept separate from whether it
        /// is on screen, so returning from a cover resumes only if both agree.
        private var wantsPlayback = true

        func configure(
            resource: String,
            scale: CGFloat,
            yOffsetFraction: CGFloat,
            fills: Bool
        ) {
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
            playerLayer.videoGravity = fills ? .resizeAspectFill : .resizeAspect
            layer.addSublayer(playerLayer)
            applyPlaybackState()
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
            applyPlaybackState()
        }

        func setPlaying(_ playing: Bool) {
            guard wantsPlayback != playing else { return }
            wantsPlayback = playing
            applyPlaybackState()
        }

        private func applyPlaybackState() {
            (window != nil && wantsPlayback) ? player?.play() : player?.pause()
        }

        func stop() {
            player?.pause()
            playerLayer.player = nil
            player = nil
            looper = nil
        }
    }
}
