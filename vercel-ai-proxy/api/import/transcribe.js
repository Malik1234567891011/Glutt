/**
 * Glutt import speech collector — ElevenLabs Scribe v2.
 *
 * App sends JSON { source_url }. We never expose the ElevenLabs key to the
 * device. Scribe accepts TikTok / YouTube / hosted media URLs via source_url.
 *
 * Env:
 *   ELEVENLABS_API_KEY   — required
 *   GLUTT_PROXY_CLIENT_KEY / GLUTT_PROXY_CLIENT_KEY_NEXT — dual-key rotation
 */
import { isAuthorized } from "../_lib/auth.js";
import { logUsage, installIdFrom } from "../_lib/usage.js";

function resolveElevenLabsKey() {
  return (
    process.env.ELEVENLABS_API_KEY ||
    process.env.ELEVEN_LABS_API_KEY ||
    ""
  ).trim();
}

export default async function handler(req, res) {
  res.setHeader("x-glutt-proxy-version", "import-transcribe-2026-07-23");

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = resolveElevenLabsKey();

  if (!apiKey) {
    return res.status(500).json({ error: "Server misconfigured: missing ELEVENLABS_API_KEY" });
  }

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const sourceURL = (req.body && req.body.source_url) || "";
  if (typeof sourceURL !== "string" || !/^https?:\/\//i.test(sourceURL.trim())) {
    return res.status(400).json({ error: "source_url must be an http(s) URL" });
  }

  const startedAt = Date.now();
  try {
    const form = new FormData();
    form.append("model_id", "scribe_v2");
    form.append("source_url", sourceURL.trim());
    form.append("timestamps_granularity", "word");
    form.append("diarize", "true");
    form.append("num_speakers", "2");
    form.append("tag_audio_events", "false");
    // Prefer clean recipe dictation over filler / verbatim ums.
    form.append("no_verbatim", "true");

    // Optional cooking keyterms from the client (caption-derived) — capped.
    const keyterms = Array.isArray(req.body?.keyterms) ? req.body.keyterms : [];
    for (const term of keyterms.slice(0, 20)) {
      if (typeof term === "string" && term.trim()) {
        form.append("keyterms", term.trim().slice(0, 80));
      }
    }

    const upstream = await fetch("https://api.elevenlabs.io/v1/speech-to-text", {
      method: "POST",
      headers: {
        "xi-api-key": apiKey,
      },
      body: form,
      // Node fetch has no timeout; Vercel function maxDuration is the backstop.
      signal: AbortSignal.timeout(55_000),
    });

    const raw = await upstream.text();
    const contentType = upstream.headers.get("content-type") || "application/json";

    // Scribe bills per minute of AUDIO, not per token. The response carries word
    // timestamps, so the end of the last word is the transcribed duration --
    // closer to the billed quantity than our wall-clock request time.
    let audioSeconds = null;
    try {
      const words = JSON.parse(raw).words;
      if (Array.isArray(words) && words.length > 0) {
        const end = words[words.length - 1].end;
        if (Number.isFinite(end)) audioSeconds = end;
      }
    } catch {
      // Not JSON, or an error body. Log the call without a duration.
    }

    await logUsage({
      feature: "transcribe",
      model: "scribe_v2",
      install_id: installIdFrom(req),
      audio_input_seconds: audioSeconds,
      duration_ms: Date.now() - startedAt,
      ok: upstream.ok,
    });

    res.status(upstream.status);
    res.setHeader("Content-Type", contentType);
    return res.send(raw);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    const timedOut = /aborted|timeout/i.test(detail);
    await logUsage({
      feature: "transcribe",
      model: "scribe_v2",
      install_id: installIdFrom(req),
      duration_ms: Date.now() - startedAt,
      ok: false,
    });
    return res.status(timedOut ? 504 : 502).json({
      error: timedOut ? "Transcription timed out" : "Upstream transcription failed",
      detail,
    });
  }
}
