// Serves the YouTube IFrame player page for Discover. The app loads this URL
// directly in its WKWebView (webView.load(URLRequest)), NOT via loadHTMLString —
// so the page has a real https origin. YouTube's IFrame embed requires a valid,
// matching origin; loadHTMLString produces an opaque origin that YouTube rejects
// with "This video is unavailable" (errors 150/152/153). Verified: same player
// errors from an opaque origin, plays correctly from a real origin.
//
// No proxy-key gate: a top-level WKWebView navigation can't attach custom headers,
// and this page holds no secret (no YouTube Data API key) — it just embeds a
// public video via the client-side IFrame API. No quota cost (no API call).
export default function handler(req, res) {
  const raw = (req.query.v || "").toString();
  // Whitelist YouTube's video-id charset to prevent injection into the inline script.
  const videoId = /^[A-Za-z0-9_-]{1,20}$/.test(raw) ? raw : "";

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "s-maxage=86400, stale-while-revalidate=604800");
  res.status(200).send(`<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>html,body{margin:0;background:#000;height:100%;overflow:hidden}#player{position:absolute;top:0;left:0;width:100%;height:100%}</style>
</head><body>
<div id="player"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player;
function onYouTubeIframeAPIReady() {
  player = new YT.Player('player', {
    videoId: '${videoId}',
    playerVars: { playsinline: 1, autoplay: 1, mute: 1, controls: 1, rel: 0, modestbranding: 1, origin: location.origin },
    events: { onReady: function(e) { e.target.mute(); e.target.playVideo(); } }
  });
}
</script>
</body></html>`);
}
