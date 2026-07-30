/** Minimal Phase C review UI (docs/donwloadplan.md §10) served by localPlaybackServer. */
export function reviewHTML() {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Glutt clip review — Eggs Benedict</title>
<style>
  :root { color-scheme: dark; font-family: ui-sans-serif, system-ui, sans-serif; }
  body { margin: 0; background: #111; color: #eee; }
  main { max-width: 920px; margin: 0 auto; padding: 20px; }
  h1 { font-size: 1.25rem; margin: 0 0 12px; }
  .card { background: #1c1c1c; border-radius: 14px; padding: 14px; margin-bottom: 14px; }
  video { width: 100%; border-radius: 10px; background: #000; }
  .meta { font-size: 0.9rem; opacity: 0.85; margin-top: 8px; }
  .row { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; }
  button { background: #2E5339; color: #fff; border: 0; border-radius: 999px; padding: 8px 14px; font-weight: 700; cursor: pointer; }
  button.secondary { background: #333; }
  label { display: block; font-size: 0.75rem; opacity: 0.7; margin-top: 8px; }
  input[type=number] { width: 100px; padding: 6px; border-radius: 8px; border: 1px solid #444; background: #111; color: #fff; }
</style>
</head>
<body>
<main>
  <h1>Review · Eggs Benedict pilot</h1>
  <p style="opacity:.7;font-size:.9rem">Adjust start/end (±1s), play muted, approve locally (writes store.json).</p>
  <div id="list"></div>
</main>
<script>
async function load() {
  const res = await fetch('/v1/pilot/eggs-benedict');
  const data = await res.json();
  const root = document.getElementById('list');
  root.innerHTML = '';
  for (const clip of data.clips) {
    const card = document.createElement('div');
    card.className = 'card';
    card.innerHTML = \`
      <strong>\${clip.watch_label}</strong>
      <div class="meta">\${clip.notice || ''}</div>
      <video controls muted playsinline src="\${clip.playback_url}"></video>
      <div class="row">
        <div><label>start</label><input type="number" step="0.1" data-k="start" value="\${clip.start_seconds}"/></div>
        <div><label>end</label><input type="number" step="0.1" data-k="end" value="\${clip.end_seconds}"/></div>
      </div>
      <div class="row">
        <button data-act="-1s">−1s start</button>
        <button data-act="+1s">+1s start</button>
        <button data-act="-1e">−1s end</button>
        <button data-act="+1e">+1s end</button>
        <button class="secondary" data-act="play">Play range</button>
        <button data-act="save">Save bounds</button>
      </div>
      <div class="meta" data-status></div>
    \`;
    const video = card.querySelector('video');
    const startIn = card.querySelector('[data-k=start]');
    const endIn = card.querySelector('[data-k=end]');
    const status = card.querySelector('[data-status]');
    card.querySelectorAll('button').forEach(btn => {
      btn.onclick = async () => {
        const act = btn.dataset.act;
        let s = Number(startIn.value), e = Number(endIn.value);
        if (act === '-1s') startIn.value = (s - 1).toFixed(1);
        if (act === '+1s') startIn.value = (s + 1).toFixed(1);
        if (act === '-1e') endIn.value = (e - 1).toFixed(1);
        if (act === '+1e') endIn.value = (e + 1).toFixed(1);
        if (act === 'play') {
          s = Number(startIn.value); e = Number(endIn.value);
          // Materialized clips already trimmed — play from 0 for Level-3 assets.
          video.currentTime = 0;
          video.play();
        }
        if (act === 'save') {
          s = Number(startIn.value); e = Number(endIn.value);
          const r = await fetch('/v1/review/update-bounds', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ segment_id: clip.segment_id, start_seconds: s, end_seconds: e })
          });
          const j = await r.json();
          status.textContent = r.ok ? \`Saved \${s}–\${e}\` : (j.error || 'save failed');
        }
      };
    });
    root.appendChild(card);
  }
}
load().catch(err => { document.body.textContent = String(err); });
</script>
</body>
</html>`;
}
