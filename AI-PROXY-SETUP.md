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

