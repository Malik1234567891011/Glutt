# Glutt AI Proxy (production, on Vercel)

Architecture: `iOS app -> Vercel API routes (vercel-ai-proxy/) -> OpenAI / Spoonacular / YouTube`.
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
| `GET /api/discover/player` | Discover | Embeddable player helper |
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
