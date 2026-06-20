# Glutt AI Proxy Setup (production path)

This is the proper launch architecture: app -> your proxy -> OpenAI.
Users never see or manage API keys.

## 1) Deploy the proxy

Folder: `ai-proxy/`

### Quick deploy options
- Railway / Render / Fly.io / any Node host
- Containerized if you already have infra

### Required environment variables
- `OPENAI_API_KEY` = your server-side key
- `OPENAI_BASE_URL` = optional (default `https://api.openai.com/v1`)
- `GLUTT_PROXY_CLIENT_KEY` = optional shared secret gate

### Health check
- `GET /health` should return `{ ok: true, service: "glutt-ai-proxy" }`

### Chat endpoint
- `POST /v1/chat/completions` forwards request body directly to OpenAI.
- Response shape is passthrough OpenAI format (compatible with current iOS client).

## 2) Wire iOS app to proxy

Update `Glutt/Services/AI/Secrets.swift` locally (do NOT commit secrets):

```swift
static let aiProxyBaseURL = "https://api.glutt.org/v1"
static let aiProxyClientKey = "your-shared-proxy-key" // optional
```

If `aiProxyBaseURL` is empty, AI cloud features are disabled.

## 3) DNS + TLS

- Create `api.glutt.org` DNS record pointing to proxy host.
- Ensure HTTPS cert is valid.

## 4) App behavior after setup

AI features that depend on cloud will work:
- import cleanup/reconstruction
- invent-from-pantry
- recipe adjust/remix
- pantry photo scan / meal photo estimation
- ask assistant ranking layer

If proxy is down or misconfigured, app falls back gracefully where designed.

## 5) Security baseline for launch week

- Rotate `OPENAI_API_KEY` before launch.
- Set spend caps/alerts in OpenAI dashboard.
- Do not commit real keys to git.
- Add basic rate limiting at edge/host if possible.
- Monitor proxy logs and `5xx` rates.

## 6) Next hardening (post-launch)

- Replace shared proxy key with user auth (JWT/session) once accounts backend is live.
- Add per-user quotas and abuse controls.
- Add structured audit logs for AI actions (feature, model, latency, status, cost estimate).

## 7) Discover (YouTube) endpoints

The proxy also powers the Recipes → **Discover** feature. Two GET endpoints live in
`vercel-ai-proxy/api/discover/`:

- `GET /api/discover/search?q=<dish>&pageToken=<optional>` — keyword search for short,
  embeddable YouTube cooking videos.
- `GET /api/discover/suggested?tags=<comma,separated,optional>` — the open-the-tab feed
  (biased by the user's taste tags, else a rotating popular query). Never paginates.

Both return `{ "videos": [ { videoId, title, creator, thumbnailURL, durationSeconds } ], "nextPageToken" }`
and require the same `x-glutt-proxy-key` header gate as the chat endpoint.

### Additional required environment variable
- `YOUTUBE_API_KEY` = a YouTube Data API v3 key (Google Cloud Console → enable
  "YouTube Data API v3" → create an API key). Server-side only; never shipped in the app.

### Quota note
`search.list` costs 100 units/call; the default project quota is ~10,000 units/day (~100
searches/day). Responses are edge-cached (`Cache-Control: s-maxage`) to stretch this; request
a quota increase before launch.

### Verify after deploy
- `GET /api/health` → `has_YOUTUBE_API_KEY: true`
- `curl -s -H "x-glutt-proxy-key: <key>" "https://<host>/api/discover/search?q=tofu" | head`
  → JSON with a `videos` array.

