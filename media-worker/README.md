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

## Env (optional cloud)

| Var | Purpose |
| --- | --- |
| `R2_*` | Cloudflare R2 archive (else local `data/objects`) |
| `CF_STREAM_*` | Stream ingest (Phase B cloud) |
| `SUPABASE_*` | Sync jobs to Postgres (else LocalStore JSON) |
| `YT_DLP_BIN` | Default `yt-dlp` |
| `MEDIA_MAX_DURATION_S` | Default 1200 |

## Docker

```bash
docker build -t glutt-media-worker .
docker run --rm -v "$PWD/data:/data" -e MEDIA_DATA_DIR=/data glutt-media-worker npm run pilot
```
