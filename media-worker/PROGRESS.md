# Media pipeline overnight progress

Updated as work lands. Source plans: `docs/donwloadplan.md`, `docs/downloadplanPhases.md`.

## Done

- [x] Phase 0 schema: `supabase/migrations/0011_media_source_assets.sql`
- [x] Phase 0 control plane: `vercel-ai-proxy/api/_lib/mediaIngest.js` (POST `/api/media/ingest` → health)
- [x] Phase 0/A worker: `media-worker/` (LocalStore, yt-dlp downloaders, FFmpeg normalize, Docker)
- [x] Phase A/B pilot: Eggs Benedict downloaded, archived locally, normalized, analysis-proxy + audio
- [x] Phase C manual segments materialized (ham **145–201**):
  - hollandaise 40–86
  - ham 145–201
  - muffins 215–228
  - poach 248–274
- [x] Local playback: `npm run serve-local` → `http://127.0.0.1:8791/v1/pilot/eggs-benedict`
- [x] iOS `NativeClipPlayerView` + Polly prefers native clips over YouTube IFrame
- [x] Mic hard-mute while original clip audio unmuted (ASR bleed protection)
- [x] Phase D start: scene detection (90) + coarse frames (137) on pilot
- [x] Dense frames around approved segments (boundary-refine prep)
- [x] Beef Wellington pilot segments (mustard **77–94** frame-verified; speech lead-in trimmed)
- [x] Grounding harden: reject talking-head / speech-only windows; brush/coat always refined
- [x] `scripts/rematerializePilot.js` + `scripts/verifySegmentFrames.js` for window QA

## Run locally

```bash
cd media-worker
./scripts/fetch-ytdlp.sh   # once
npm install
npm run pilot              # if data/ wiped
npm run serve-local        # leave running for simulator
```

Simulator: Glutt Beta `-seed` → Eggs Benedict → Cook with Polly. Ham label should read **2:25–3:21**.

## Still open

- **Apply** `supabase/migrations/0011_media_source_assets.sql` in Supabase SQL editor
- **Sync pilots:** `cd media-worker && cp .env.example .env` (add service role) → `npm run sync:supabase`
- **Deploy proxy** so `/api/media/clips` rewrite + `mediaClips.js` are live
- Cloudflare R2/Stream credentials → archive + signed HLS (Storage MP4s are the interim)
- ElevenLabs word transcript (worker stub ready; needs `ELEVENLABS_API_KEY`)
- Auto Gemini segmentation (Phase E) using analysis-proxy + dense frames
- HLS preload / opportunistic next-step buffering
- Drop per-video `NativeClipService.pilots` map once step matches live in Postgres

## Morning check

1. `curl http://127.0.0.1:8791/v1/pilot/eggs-benedict` — ham should be 145–201  
2. Simulator already launched with `-seed` if overnight install succeeded  
3. Eggs Benedict → Cook with Polly → ham step shows **native** player `2:25–3:21` (not YouTube 2:26–2:56)  
4. Review UI: open http://127.0.0.1:8791/review  
5. No commits/pushes were made (per request)
