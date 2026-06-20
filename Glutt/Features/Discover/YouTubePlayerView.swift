import SwiftUI
import WebKit

/// Pure builder for the YouTube IFrame player page. Separated so it is unit-testable.
enum YouTubeEmbed {
    static func videoId(from urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString) else { return nil }
        if comps.host?.contains("youtu.be") == true {
            return comps.path.split(separator: "/").last.map(String.init)
        }
        if comps.host?.contains("youtube.com") == true {
            return comps.queryItems?.first { $0.name == "v" }?.value
        }
        return nil
    }

    static func html(videoId: String) -> String {
        // Use the official IFrame Player API (not a bare <iframe>). A bare iframe
        // loaded via WKWebView.loadHTMLString sends no valid Referer/origin, so
        // YouTube rejects even embeddable videos with "This video is unavailable"
        // (error 150/152/153). The IFrame API supplies `origin` explicitly via
        // postMessage, which YouTube accepts. Load with baseURL https://www.youtube.com.
        """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;background:#000;height:100%;overflow:hidden}
        #player{position:absolute;top:0;left:0;width:100%;height:100%}</style>
        </head><body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            videoId: '\(videoId)',
            playerVars: { playsinline: 1, autoplay: 1, mute: 1, controls: 1, rel: 0, modestbranding: 1, origin: 'https://www.youtube.com' },
            events: { onReady: function(e) { e.target.mute(); e.target.playVideo(); } }
          });
        }
        </script>
        </body></html>
        """
    }
}

/// Plays a YouTube video via the official IFrame player inside a WKWebView.
struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload only when the video changes to avoid restarting playback on every redraw.
        guard context.coordinator.loadedVideoId != videoId else { return }
        context.coordinator.loadedVideoId = videoId
        webView.loadHTMLString(YouTubeEmbed.html(videoId: videoId),
                               baseURL: URL(string: "https://www.youtube.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedVideoId: String?
    }
}
