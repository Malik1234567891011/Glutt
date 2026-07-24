// Polly: mints short-lived OpenAI Realtime client secrets ("ek_...") so the
// app can open a Realtime connection without ever seeing the long-lived
// OPENAI_API_KEY. Secrets expire after 10 minutes (PollyConfig.tokenTTLSeconds);
// the session itself may live up to 60.
//
// v2 (WebRTC): the AUDIO plane is pinned HERE at mint — turn detection,
// noise reduction, transcription, voice. The client's session.update carries
// only the brain plane (instructions + tools). That makes VAD/persona-voice
// tuning a Vercel env flip + redeploy, never an App Store release.
import { isAuthorized } from "../_lib/auth.js";

function resolveOpenAIKey() {
  return (
    process.env.OPENAI_API_KEY ||
    process.env.glutt_proxy_prod ||
    process.env.GLUTT_PROXY_PROD ||
    ""
  ).trim();
}

// Optional per-device monthly session cap (abuse guard, quality-first
// economics decision 2026-07-23). Inactive until Upstash env vars exist;
// counting sessions (mints), not minutes — each session hard-caps at 52 min
// client-side, so sessions × 52 bounds worst-case minutes. Any cap-infra
// failure fails OPEN: a broken counter must never block a cook.
async function deviceCapExceeded(deviceId) {
  const base = (process.env.UPSTASH_REDIS_REST_URL || "").trim();
  const token = (process.env.UPSTASH_REDIS_REST_TOKEN || "").trim();
  if (!base || !token || !deviceId) return false;
  const cap = parseInt(process.env.POLLY_MONTHLY_SESSION_CAP || "200", 10);
  const now = new Date();
  const key = `polly:sessions:${now.getUTCFullYear()}-${now.getUTCMonth() + 1}:${deviceId}`;
  try {
    const headers = { Authorization: `Bearer ${token}` };
    const r = await fetch(`${base}/incr/${encodeURIComponent(key)}`, { headers });
    const { result } = await r.json();
    if (result === 1) {
      await fetch(`${base}/expire/${encodeURIComponent(key)}/2678400`, { headers });
    }
    return Number(result) > cap;
  } catch {
    return false;
  }
}

export default async function handler(req, res) {
  res.setHeader("x-glutt-proxy-version", "polly-2026-07-24-1");

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const openAIKey = resolveOpenAIKey();
  if (!openAIKey) {
    return res.status(500).json({ error: "not configured" });
  }
  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const deviceId = (req.headers["x-glutt-device-id"] || "").toString().slice(0, 64);
  if (await deviceCapExceeded(deviceId)) {
    return res.status(429).json({ error: "Monthly Polly limit reached on this device" });
  }

  const model = (process.env.POLLY_REALTIME_MODEL || "").trim() || "gpt-realtime-2.1";
  const voice = (process.env.POLLY_VOICE || "").trim() || "marin";
  // semantic_vad eagerness is THE turn-taking feel knob (low = patient,
  // echo-safe; auto/high = snappier). Tuned during the soak without app
  // releases — shipped v1 WS clients override this in their own
  // session.update, so pinning here cannot affect them.
  const eagerness = (process.env.POLLY_VAD_EAGERNESS || "").trim() || "low";

  try {
    const upstream = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        expires_after: { anchor: "created_at", seconds: 600 },
        session: {
          type: "realtime",
          model,
          audio: {
            input: {
              turn_detection: { type: "semantic_vad", eagerness },
              noise_reduction: { type: "far_field" },
              transcription: { model: "gpt-4o-transcribe", language: "en" },
            },
            output: { voice },
          },
        },
      }),
    });

    if (!upstream.ok) {
      // Never forward the upstream body: it can echo key/request details.
      return res.status(502).json({ error: `upstream ${upstream.status}` });
    }

    const data = await upstream.json();
    res.setHeader("Cache-Control", "no-store");
    return res.status(200).json({
      value: data.value,
      expiresAt: data.expires_at ?? null,
      model,
      voice,
    });
  } catch {
    return res.status(502).json({ error: "upstream unreachable" });
  }
}
