---
paths:
  - media-worker/**/*
  - supabase/migrations/**/*
  - docs/video.md
  - docs/donwloadplan.md
  - docs/downloadplanPhases.md
---

# Media worker / pilot clips

- End-to-end for a new pilot: fixture segments → ingest video → `finishPilot.js <externalId>` → `npm run sync:supabase -- --external-id=<id>` → verify `GET /api/media/clips?external_id=…` (`status: ready`).
- Wire pilot into `PILOT_FIXTURES` / `localPlaybackServer` path (e.g. `/v1/pilot/creme-brulee`) and iOS `NativeClipService.localPaths` when local playback is needed.
- Keep segment windows technique-focused; reject talking-head / speech-only windows when refining.
- Track status in `media-worker/PROGRESS.md`. Longer plans stay in `docs/donwloadplan.md` / `docs/video.md`.
- Never commit service-role keys or `.env` from `media-worker/`.
