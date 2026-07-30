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
import { logUsage, installIdFrom } from "../_lib/usage.js";

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
  res.setHeader("x-glutt-proxy-version", "polly-2026-07-30-reasoning");

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
  // Reasoning effort is the single biggest quality knob on gpt-realtime-2.1 and
  // we were not setting it, so Polly ran at OpenAI's default. Their migration
  // guide says "set reasoning effort to low instead of the default", which means
  // the default is HIGHER than low, but they never publish which — so leaving it
  // unset means we do not know what we are running. Pin it.
  //
  // "high" is deliberate: on the Artificial Analysis S2S index, gpt-realtime-2.1
  // goes 72.5% -> 79.1% overall between minimal and high, and agentic (tau-Voice,
  // which IS tool calling) goes 38.0% -> 45.7%. Polly calls 15 tools, so that is
  // the column that matters. Cost is ~+240ms time-to-first-audio, well inside
  // PollyConfig.responseWatchdogSeconds (4s) — but watch that number, because if
  // latency ever crosses the watchdog she starts interrupting herself to
  // apologise. Drop to "medium" if it does.
  const REASONING_EFFORTS = ["minimal", "low", "medium", "high", "xhigh"];
  const requestedEffort = (process.env.POLLY_REASONING_EFFORT || "").trim() || "high";
  // "off" is an escape hatch: omit the field entirely and take the server default.
  const effort = REASONING_EFFORTS.includes(requestedEffort) ? requestedEffort : null;
  // What we ACTUALLY minted with, after any fallback. Reported back so a bad
  // env value or a silent OpenAI rejection shows up in the debug log rather
  // than as an unexplained drop in answer quality.
  let appliedEffort = effort;

  const sessionBody = (withReasoning) => ({
    expires_after: { anchor: "created_at", seconds: 600 },
    session: {
      type: "realtime",
      model,
      ...(withReasoning && effort ? { reasoning: { effort } } : {}),
      audio: {
        input: {
          turn_detection: { type: "semantic_vad", eagerness },
          noise_reduction: { type: "far_field" },
          transcription: { model: "gpt-4o-transcribe", language: "en" },
        },
        output: { voice },
      },
    },
  });

  const mint = (withReasoning) =>
    fetch("https://api.openai.com/v1/realtime/client_secrets", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(sessionBody(withReasoning)),
    });

  const startedAt = Date.now();
  try {
    let upstream = await mint(true);
    // A rejected mint means no cook at all, so never let a tuning knob be fatal:
    // if OpenAI refuses the reasoning block (unsupported model, renamed field),
    // fall back to a plain mint rather than failing the session.
    if (!upstream.ok && effort && upstream.status === 400) {
      appliedEffort = null;
      upstream = await mint(false);
    }

    if (!upstream.ok) {
      await logUsage({
        feature: "polly_session",
        model,
        install_id: deviceId || null,
        duration_ms: Date.now() - startedAt,
        ok: false,
      });
      // Never forward the upstream body: it can echo key/request details.
      return res.status(502).json({ error: `upstream ${upstream.status}` });
    }

    const data = await upstream.json();

    // Session START only. This endpoint just mints a 10-minute client secret;
    // the WebRTC session it unlocks runs for up to 52 minutes afterwards and
    // this function is long gone by then. Audio seconds -- the thing Realtime
    // actually bills -- arrive later via POST /api/polly/usage, which the app
    // calls on session end. A polly_session row with no matching polly_realtime
    // row means the app never reported: crash, force-quit, or lost network.
    await logUsage({
      feature: "polly_session",
      model,
      install_id: deviceId || null,
      duration_ms: Date.now() - startedAt,
    });

    res.setHeader("Cache-Control", "no-store");
    res.setHeader("x-glutt-polly-reasoning", appliedEffort || "default");
    return res.status(200).json({
      value: data.value,
      expiresAt: data.expires_at ?? null,
      model,
      voice,
      reasoningEffort: appliedEffort,
    });
  } catch {
    await logUsage({
      feature: "polly_session",
      model,
      install_id: deviceId || null,
      duration_ms: Date.now() - startedAt,
      ok: false,
    });
    return res.status(502).json({ error: "upstream unreachable" });
  }
}
