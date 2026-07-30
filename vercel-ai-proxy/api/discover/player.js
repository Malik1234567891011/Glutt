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
  const startRaw = parseInt((req.query.start || "").toString(), 10);
  const endRaw = parseInt((req.query.end || "").toString(), 10);
  const start = Number.isFinite(startRaw) && startRaw >= 0 ? startRaw : 0;
  const end = Number.isFinite(endRaw) && endRaw > start ? endRaw : 0;
  const mute = (req.query.mute || "1").toString() !== "0";

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
var startSec = ${start};
var endSec = ${end};
var preferMute = ${mute ? "true" : "false"};
function onYouTubeIframeAPIReady() {
  var vars = { playsinline: 1, autoplay: 1, mute: preferMute ? 1 : 0, controls: 1, rel: 0, modestbranding: 1, origin: location.origin };
  if (startSec > 0) vars.start = startSec;
  if (endSec > startSec) vars.end = endSec;
  player = new YT.Player('player', {
    videoId: '${videoId}',
    playerVars: vars,
    events: {
      onReady: function(e) {
        if (preferMute) e.target.mute();
        if (startSec > 0) e.target.seekTo(startSec, true);
        e.target.playVideo();
      },
      onStateChange: function(e) {
        // Keep a tight demo loop inside [start, end] when end is set.
        if (!endSec || endSec <= startSec) return;
        if (e.data === YT.PlayerState.ENDED) {
          e.target.seekTo(startSec, true);
          e.target.playVideo();
        }
      }
    }
  });
}
</script>
</body></html>`);
}
