# Vercel AI Proxy Quickstart (for glutt.org)

This gets AI working with secure architecture:

`iOS app -> your Vercel API route -> OpenAI`

No user API keys, no OpenAI key in the app.

## 1) Deploy proxy routes on Vercel

You have two options:

### Option A (recommended): separate Vercel project for API
- Create a new Vercel project from this folder: `vercel-ai-proxy/`
- Map domain: `api.glutt.org`

### Option B: same project as landing page
- Add these `api/*` routes into the same Vercel project that serves `glutt.org`
- Endpoints become `https://glutt.org/api/...`

Either works. Option A keeps API and marketing deploys isolated.

## 2) Configure environment variables in Vercel

Set in Project -> Settings -> Environment Variables:

- `OPENAI_API_KEY` = your real key
- `OPENAI_BASE_URL` = `https://api.openai.com/v1` (optional; default is this)
- `GLUTT_PROXY_CLIENT_KEY` = random secret string (optional but recommended)

## 3) Verify proxy is live

- `GET https://api.glutt.org/api/health` (or `https://glutt.org/api/health`)
  - should return `{ "ok": true, ... }`

## 4) Wire iOS app locally

In `Glutt/Services/AI/Secrets.swift` set:

```swift
static let aiProxyBaseURL = "https://api.glutt.org/api"
static let aiProxyClientKey = "same-value-as-GLUTT_PROXY_CLIENT_KEY"
```

If you use same-site deployment, use:

```swift
static let aiProxyBaseURL = "https://glutt.org/api"
```

## 5) Test one AI call path

In app:
- Try import cleanup OR "Invent a dish from what I have"
- If proxy works, AI response appears.
- If not, check Vercel logs for `chat/completions`.

## 6) Launch safety checklist

- Keep `OPENAI_API_KEY` only in Vercel env vars.
- Keep `aiProxyClientKey` out of git if possible (set locally per release build).
- Set OpenAI spend limits and usage alerts.
- Enable Vercel logs/monitoring for `/api/chat/completions`.

