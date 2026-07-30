# Glutt AI Proxy (production, on Vercel)

Architecture: `iOS app -> Vercel API routes (vercel-ai-proxy/) -> OpenAI / Gemini / Spoonacular / YouTube`.
Users never see or manage API keys; Vercel auto-deploys the proxy from `main`.

## 1) Deploy

- Project folder: `vercel-ai-proxy/`
- Deploy as its own Vercel project, mapped to `api.glutt.org` (or serve it as
  `api/*` routes inside the same project as the marketing site — either works;
  a separate project keeps API and marketing deploys isolated).

### Environment variables (Vercel → Project → Settings → Environment Variables)
- `OPENAI_API_KEY` — server-side OpenAI key (chat completions + Polly realtime).
- `OPENAI_BASE_URL` — optional, defaults to `https://api.openai.com/v1`.
- `GLUTT_PROXY_CLIENT_KEY` — shared secret gate; if set, callers must send it
  back as the `x-glutt-proxy-key` header.
- `YOUTUBE_API_KEY` (or `GLUTT_YOUTUBE_KEY`) — YouTube Data API v3 key, powers Discover.
- `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) — Gemini video understanding for Polly step-clips (`POST /api/cook/clips`). Free-tier YouTube URL analysis is enough for pilots; billing optional until volume grows.
- `GEMINI_MODEL` — optional, defaults to `gemini-2.5-flash`.
- `SPOONACULAR_API_KEY` (or `SPOONACULAR_API`) — powers the Plates photo-recipe feed.
- `POLLY_REALTIME_MODEL` — optional, defaults to `gpt-realtime-2`.
- `POLLY_VOICE` — optional, defaults to `marin`.

### Health check
`GET /api/health` returns `{ ok, service, env: { has_OPENAI_API_KEY, has_YOUTUBE_API_KEY, ... } }` —
use it to confirm which env vars actually landed after a deploy.

## 2) Wire the iOS app to the proxy

In `Glutt/Services/AI/Secrets.swift` (never commit real keys):

```swift
static let aiProxyBaseURL = "https://api.glutt.org/api"
static let aiProxyClientKey = "same-value-as-GLUTT_PROXY_CLIENT_KEY"
```

If `aiProxyBaseURL` is empty, cloud AI features are disabled and the app falls
back to on-device heuristics where designed.

## 3) Endpoints

| Route | Feature | Notes |
|---|---|---|
| `POST /api/chat/completions` | import cleanup, invent-from-pantry, recipe adjust/remix, pantry/meal photo estimation, Ask Glutt | Passthrough OpenAI chat-completions shape |
| `POST /api/polly/session` | Polly live chef | Mints a short-lived OpenAI Realtime client secret (`ek_...`, ~10 min TTL) so the app opens a Realtime WebSocket without ever holding the long-lived key |
| `GET /api/discover/search?q=<dish>&pageToken=<optional>` | Recipes → Discover | YouTube keyword search for embeddable cooking videos |
| `GET /api/discover/suggested?tags=<optional>` | Discover open-tab feed | Biased by taste tags, else rotating popular query; never paginates |
| `GET /api/discover/player` | Discover / Polly clips | Embeddable player (`v`, optional `start`/`end`/`mute`) |
| `POST /api/cook/clips` | Polly step technique clips | Gemini segment+match (rewrites onto `discover/suggested` POST to stay under Hobby’s 12-function cap) |
| `GET/POST /api/plates/deck` + `/api/plates/search` | Plates photo-recipe feed | Spoonacular-backed, edge-cached per page/UTC day |

All routes that accept a client key check it via the `x-glutt-proxy-key` header
when `GLUTT_PROXY_CLIENT_KEY` is set.

### Quota notes
- YouTube `search.list` costs 100 units/call; default project quota is
  ~10,000 units/day (~100 searches/day). Responses are edge-cached
  (`Cache-Control: s-maxage`) to stretch this — request a quota increase if
  Discover usage grows.

### Verify after deploy
```sh
curl -s https://api.glutt.org/api/health | jq
curl -s -H "x-glutt-proxy-key: <key>" "https://api.glutt.org/api/discover/search?q=tofu" | head
```

## 4) Security baseline

- Rotate `OPENAI_API_KEY` before any public launch milestone.
- Set spend caps/alerts in the OpenAI dashboard — this key is shared across
  all cloud AI features and Polly sessions.
- Never commit real keys; keep `GLUTT_PROXY_CLIENT_KEY` out of git, set per
  deploy in Vercel env vars.
- Monitor Vercel logs for `5xx` rates on `/api/chat/completions` and
  `/api/polly/session` (Polly sessions fail closed if `OPENAI_API_KEY` is missing).

## 5) Future hardening (post-launch, not yet done)

- Replace the shared `GLUTT_PROXY_CLIENT_KEY` with per-user auth (JWT/session)
  once an accounts backend exists.
- Add per-user quotas and abuse controls.
- Add structured audit logs for AI actions (feature, model, latency, status, cost estimate).

## 2026-07-24 — Polly v2 hardening (Phase 4)

**Audio plane pinned at mint.** `api/polly/session.js` now pins turn detection
(`semantic_vad`, eagerness from `POLLY_VAD_EAGERNESS`, default `low`), far-field
noise reduction, transcription, and voice into the client secret. v2 clients send
only instructions + tools in `session.update`. Tuning Polly's turn-taking feel =
change the env var in Vercel → redeploy. No app release.

**Dual-key rotation.** All endpoints authorize via `api/_lib/auth.js`, which
accepts `GLUTT_PROXY_CLIENT_KEY` (key baked into shipped builds) **and**
`GLUTT_PROXY_CLIENT_KEY_NEXT` (rotation target, already set in Vercel prod).
The client key now lives in the gitignored `Glutt/Services/AI/Secrets.local.plist`
(copy `Secrets.local.example.plist`, fill in, `xcodegen generate`). Once the App
Store build carrying the NEXT key is broadly adopted: set `GLUTT_PROXY_CLIENT_KEY`
to the NEXT value, clear `_NEXT`, and the old leaked-in-git key is fully retired.

**Per-device session cap (dormant until provisioned).** `polly/session` counts
mints per device per month when `UPSTASH_REDIS_REST_URL`/`_TOKEN` exist
(`POLLY_MONTHLY_SESSION_CAP`, default 200 sessions ≈ hard bound of 200×52 min);
returns 429 → the app shows "monthly limit reached". Cap infra failures fail
OPEN — a broken counter never blocks a cook. The app sends a random per-install
UUID as `x-glutt-device-id` (no personal data).
