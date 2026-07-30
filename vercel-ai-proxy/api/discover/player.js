// Serves the YouTube IFrame player page for Discover + Polly step clips.
// The app loads this URL directly in WKWebView (not loadHTMLString) so the
// page has a real https origin — required by YouTube embeds.
//
// Clip windows pass ?start=&end=. On iOS WKWebView, playerVars.start is
// unreliable (video often begins at 0); we force the window with
// loadVideoById + a time watchdog.
export default function handler(req, res) {
  const raw = (req.query.v || "").toString();
  const videoId = /^[A-Za-z0-9_-]{1,20}$/.test(raw) ? raw : "";
  const startRaw = parseInt((req.query.start || "").toString(), 10);
  const endRaw = parseInt((req.query.end || "").toString(), 10);
  const start = Number.isFinite(startRaw) && startRaw >= 0 ? startRaw : 0;
  const end = Number.isFinite(endRaw) && endRaw > start ? endRaw : 0;
  const mute = (req.query.mute || "1").toString() !== "0";

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  // Never CDN-cache clip windows — a cached start=0 page was serving every seek.
  res.setHeader("Cache-Control", "no-store");
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
var watchTimer = null;
var videoId = '${videoId}';

function clearWatch() {
  if (watchTimer) { clearInterval(watchTimer); watchTimer = null; }
}

function enforceWindow(e) {
  try {
    var t = e.getCurrentTime();
    if (startSec > 0 && t < startSec - 0.35) {
      e.seekTo(startSec, true);
      return;
    }
    if (endSec > startSec && t >= endSec - 0.15) {
      e.seekTo(startSec, true);
      e.playVideo();
    }
  } catch (err) {}
}

function onYouTubeIframeAPIReady() {
  player = new YT.Player('player', {
    // Do NOT pass videoId here — loadVideoById in onReady is what actually
    // honors start/end on iOS WKWebView.
    playerVars: {
      playsinline: 1,
      autoplay: 0,
      mute: preferMute ? 1 : 0,
      controls: 1,
      rel: 0,
      modestbranding: 1,
      origin: location.origin
    },
    events: {
      onReady: function(e) {
        if (preferMute) e.target.mute();
        var opts = { videoId: videoId };
        if (startSec > 0) opts.startSeconds = startSec;
        if (endSec > startSec) opts.endSeconds = endSec;
        e.target.loadVideoById(opts);
        clearWatch();
        watchTimer = setInterval(function() { enforceWindow(e.target); }, 250);
      },
      onStateChange: function(e) {
        if (e.data === YT.PlayerState.PLAYING) {
          enforceWindow(e.target);
        }
        if (e.data === YT.PlayerState.ENDED && endSec > startSec) {
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
