import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Native clip player for Polly. Uses AVPlayerLayer (not SwiftUI `VideoPlayer`)
/// so WebRTC's audio session doesn't deadlock the main thread on appear.
///
/// Critical: never drive parent view identity / `sessionUIEpoch` from playback
/// callbacks during setup — that recreates this view and freezes the sim.
struct NativeClipPlayerView: View {
    let clip: NativeStepClip
    var autoplay: Bool = true
    @Binding var muted: Bool
    var showsInlineMuteControl: Bool = true
    /// Full-bleed 9:16 canvas vs letterboxed landscape clip.
    var fillsCanvas: Bool = false
    var onStateChange: ((PollyMediaState) -> Void)?

    init(
        clip: NativeStepClip,
        autoplay: Bool = true,
        muted: Binding<Bool> = .constant(true),
        showsInlineMuteControl: Bool = true,
        fillsCanvas: Bool = false,
        onStateChange: ((PollyMediaState) -> Void)? = nil
    ) {
        self.clip = clip
        self.autoplay = autoplay
        self._muted = muted
        self.showsInlineMuteControl = showsInlineMuteControl
        self.fillsCanvas = fillsCanvas
        self.onStateChange = onStateChange
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NativeClipPlayerRepresentable(
                url: clip.playbackURL,
                autoplay: autoplay,
                muted: muted,
                fillsCanvas: fillsCanvas,
                segmentID: clip.segmentID,
                onStateChange: onStateChange
            )
            if showsInlineMuteControl {
                Button {
                    muted.toggle()
                    onStateChange?(.playing(segmentID: clip.segmentID, muted: muted))
                } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel(muted ? "Hear original audio" : "Mute original audio")
            }
        }
        .background(Color.black)
    }
}

// MARK: - UIKit player (stable across SwiftUI identity churn)

private final class PlayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct NativeClipPlayerRepresentable: UIViewRepresentable {
    let url: URL
    let autoplay: Bool
    let muted: Bool
    let fillsCanvas: Bool
    let segmentID: String
    var onStateChange: ((PollyMediaState) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(segmentID: segmentID, onStateChange: onStateChange)
    }

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = fillsCanvas ? .resizeAspectFill : .resizeAspect
        context.coordinator.attach(url: url, to: view, autoplay: autoplay, muted: muted)
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        context.coordinator.onStateChange = onStateChange
        context.coordinator.segmentID = segmentID
        context.coordinator.setMuted(muted)
        uiView.playerLayer.videoGravity = fillsCanvas ? .resizeAspectFill : .resizeAspect
        if context.coordinator.currentURL != url {
            context.coordinator.attach(url: url, to: uiView, autoplay: autoplay, muted: muted)
        } else if autoplay {
            context.coordinator.playIfNeeded()
        } else {
            context.coordinator.pause()
        }
    }

    static func dismantleUIView(_ uiView: PlayerHostView, coordinator: Coordinator) {
        coordinator.teardown()
        uiView.playerLayer.player = nil
    }

    final class Coordinator: NSObject {
        var segmentID: String
        var onStateChange: ((PollyMediaState) -> Void)?
        private(set) var currentURL: URL?
        private var player: AVPlayer?
        private var endObserver: NSObjectProtocol?
        private var statusObservation: NSKeyValueObservation?
        private var didReportPlaying = false

        init(segmentID: String, onStateChange: ((PollyMediaState) -> Void)?) {
            self.segmentID = segmentID
            self.onStateChange = onStateChange
        }

        func attach(url: URL, to host: PlayerHostView, autoplay: Bool, muted: Bool) {
            teardown(reportIdle: false)
            currentURL = url
            didReportPlaying = false

            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 2
            let p = AVPlayer(playerItem: item)
            p.isMuted = muted
            p.automaticallyWaitsToMinimizeStalling = true
            // Keep Polly's WebRTC audio session in charge — don't let AVPlayer
            // reconfigure the session category on the main thread.
            if #available(iOS 16.0, *) {
                p.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            }
            player = p
            host.playerLayer.player = p

            statusObservation = item.observe(\.status, options: [.new]) { [weak self, weak p] item, _ in
                guard let self, let p else { return }
                DispatchQueue.main.async {
                    guard item.status == .readyToPlay else {
                        if item.status == .failed {
                            PollyDebugLog.shared.log(
                                "media: item failed — \(item.error?.localizedDescription ?? "?")"
                            )
                            self.onStateChange?(.idle)
                        }
                        return
                    }
                    if autoplay { p.play() }
                    if !self.didReportPlaying {
                        self.didReportPlaying = true
                        self.onStateChange?(.playing(segmentID: self.segmentID, muted: p.isMuted))
                    }
                }
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.onStateChange?(.finished(segmentID: self.segmentID))
            }
        }

        func setMuted(_ muted: Bool) {
            player?.isMuted = muted
        }

        func play() {
            guard let player else { return }
            restartFromBeginningIfNeededThenPlay(player)
        }

        func playIfNeeded() {
            guard let player else { return }
            restartFromBeginningIfNeededThenPlay(player)
        }

        private func restartFromBeginningIfNeededThenPlay(_ player: AVPlayer) {
            guard let item = player.currentItem else {
                player.play()
                return
            }
            let duration = item.duration
            let t = player.currentTime().seconds
            let atEnd: Bool
            if duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0 {
                atEnd = t >= max(0, duration.seconds - 0.25)
            } else {
                atEnd = false
            }
            if atEnd {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak player] _ in
                    player?.play()
                }
            } else if player.rate == 0 {
                player.play()
            }
        }

        func pause() {
            player?.pause()
        }

        func teardown(reportIdle: Bool = true) {
            player?.pause()
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            statusObservation?.invalidate()
            statusObservation = nil
            player?.replaceCurrentItem(with: nil)
            player = nil
            currentURL = nil
            didReportPlaying = false
            if reportIdle {
                // Defer so dismantle/update doesn't re-enter SwiftUI mid-layout.
                DispatchQueue.main.async { [onStateChange] in
                    onStateChange?(.idle)
                }
            }
        }
    }
}
