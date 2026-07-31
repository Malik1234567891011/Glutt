# Glutt media worker

Dedicated ingest worker for rights-cleared source videos (see `docs/downloadplanPhases.md`).

**Not** a Vercel function — downloads, FFmpeg, and archival run here.

## Pilot (Eggs Benedict)

```bash
cd media-worker
./scripts/fetch-ytdlp.sh   # once (standalone binary → bin/yt-dlp)
npm install
npm run pilot              # probe → download → archive → normalize → manual clips → evidence
npm run serve-local        # leave running for the iOS simulator
```

| URL | Purpose |
| --- | --- |
| http://127.0.0.1:8791/v1/pilot/eggs-benedict | JSON clips for the app |
| http://127.0.0.1:8791/review | Minimal human review UI |
| http://127.0.0.1:8791/health | Liveness |

Ham oracle window after pilot: **145–201** (2:25–3:21).

## Cloud sync (Supabase)

Local testing is done via `serve-local`. For phones / TestFlight / anyone not on your LAN:

1. Paste `supabase/migrations/0011_media_source_assets.sql` into the Supabase SQL editor and run it.
2. `cp .env.example .env` and set `SUPABASE_SERVICE_ROLE_KEY`.
3. `npm run sync:supabase` — upserts metadata + uploads vertical clips/posters to private bucket `glutt-media`.
4. Deploy `vercel-ai-proxy` so `GET /api/media/clips?external_id=…` is live.
5. In the app, **omit** `mediaPlaybackBaseURL` from `Secrets.local.plist` so Polly hits the proxy.

### Background jobs (user imports)

After import, the app calls `POST /api/media/ingest` (`enqueue` + YouTube `analyze`).
Native MP4 materialization is claimed by this worker:

```bash
npm run claim:supabase -- --loop --interval=30
```

Leave that running (or on a host) so queued `ingestion_jobs` become `ready` HD clips.

## Env (optional cloud)

| Var | Purpose |
| --- | --- |
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` | Sync LocalStore → Postgres + Storage |
| `R2_*` | Cloudflare R2 archive (else local `data/objects`) |
| `CF_STREAM_*` | Stream ingest (Phase B cloud) |
| `YT_DLP_BIN` | Default `yt-dlp` |
| `MEDIA_MAX_DURATION_S` | Default 1200 |

## Docker

```bash
docker build -t glutt-media-worker .
docker run --rm -v "$PWD/data:/data" -e MEDIA_DATA_DIR=/data glutt-media-worker npm run pilot
```
