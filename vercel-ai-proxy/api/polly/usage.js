/**
 * Polly session-end usage report.
 *
 * POST { durationMs?, audioInputSeconds?, audioOutputSeconds?, model?, ok? }
 *   -> 204
 *
 * Why this exists: /api/polly/session only mints a 10-minute client secret. The
 * WebRTC session it unlocks then runs directly between the device and OpenAI for
 * up to ~52 minutes, and OpenAI Realtime bills by AUDIO SECONDS. The proxy never
 * sees that traffic, so the only party who can report the duration is the app,
 * on session end.
 *
 * This makes the numbers client-reported, which means they are untrusted: every
 * value is clamped to a session-plausible ceiling before it is written. A device
 * can under-report by simply never calling this (see the orphan-row note in
 * session.js) but it cannot inflate the bill beyond one session's worth.
 */
import { isAuthorized } from "../_lib/auth.js";
import { logUsage, installIdFrom } from "../_lib/usage.js";

// A session hard-caps at 52 min client-side; the minted secret allows 60. Give
// a little headroom, then refuse to record anything beyond it.
const MAX_SESSION_SECONDS = 3900;
// Ceiling for any single token count. Audio output runs ~1200 tokens/min, so an
// hour of solid speech is ~72k; 5M is far above any real session while still
// bounding what a hostile client can write.
const MAX_TOKENS = 5_000_000;

function seconds(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.min(n, MAX_SESSION_SECONDS);
}

function tokens(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.min(Math.round(n), MAX_TOKENS);
}

export default async function handler(req, res) {
  res.setHeader("x-glutt-proxy-version", "polly-usage-2026-07-29");

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const body = req.body || {};
  const durationMs = Number(body.durationMs);

  await logUsage({
    feature: "polly_realtime",
    model: (body.model || process.env.POLLY_REALTIME_MODEL || "").toString().trim() || "gpt-realtime-2.1",
    install_id: installIdFrom(req),
    // Exact billed counts from the server's own response.done usage objects,
    // accumulated client-side across the session. Audio and text are kept apart
    // because gpt-realtime bills audio ~8x higher.
    input_tokens: tokens(body.textInputTokens),
    output_tokens: tokens(body.textOutputTokens),
    audio_input_tokens: tokens(body.audioInputTokens),
    audio_output_tokens: tokens(body.audioOutputTokens),
    audio_input_seconds: seconds(body.audioInputSeconds),
    audio_output_seconds: seconds(body.audioOutputSeconds),
    duration_ms:
      Number.isFinite(durationMs) && durationMs >= 0
        ? Math.min(Math.round(durationMs), MAX_SESSION_SECONDS * 1000)
        : null,
    ok: body.ok !== false,
  });

  // Nothing to say back. The app is closing a session; it must never block or
  // retry on the outcome of a bookkeeping call.
  return res.status(204).end();
}
