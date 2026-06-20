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

    /// URL of the backend-hosted IFrame player page. The WKWebView loads this URL
    /// directly (not via loadHTMLString) so the page has a REAL https origin.
    /// YouTube's embed requires a valid, matching origin; loadHTMLString produces
    /// an opaque origin that YouTube rejects ("This video is unavailable",
    /// errors 150/152/153). Reuses the configured proxy base so it tracks the
    /// same host as the rest of Discover.
    static func playerURL(videoId: String, baseURL: String = Secrets.aiProxyBaseURL) -> URL? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, var comps = URLComponents(string: "\(base)/discover/player") else { return nil }
        comps.queryItems = [URLQueryItem(name: "v", value: videoId)]
        return comps.url
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
        guard let url = YouTubeEmbed.playerURL(videoId: videoId) else { return }
        context.coordinator.loadedVideoId = videoId
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedVideoId: String?
    }
}
