/**
 * Polly voice for non-realtime speech (cook trailer briefing, etc.).
 * Uses the same POLLY_VOICE as the live Realtime session (default: marin)
 * via OpenAI gpt-4o-mini-tts — not Apple system voices.
 *
 * POST { text: string, instructions?: string, speed?: number }
 * → audio/mpeg bytes
 */
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

export default async function handler(req, res) {
  res.setHeader("x-glutt-proxy-version", "polly-speak-2026-07-24-fast");

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const openAIKey = resolveOpenAIKey();
  const openAIBaseURL = (process.env.OPENAI_BASE_URL || "https://api.openai.com/v1").replace(/\/$/, "");
  const voice = (process.env.POLLY_VOICE || "").trim() || "marin";
  const model = (process.env.POLLY_TTS_MODEL || "").trim() || "gpt-4o-mini-tts";

  if (!openAIKey) {
    return res.status(500).json({ error: "Server misconfigured: missing OPENAI_API_KEY" });
  }

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const text = typeof req.body?.text === "string" ? req.body.text.trim() : "";
  if (!text) {
    return res.status(400).json({ error: "text is required" });
  }
  if (text.length > 2200) {
    return res.status(400).json({ error: "text too long" });
  }

  const instructions =
    typeof req.body?.instructions === "string" && req.body.instructions.trim()
      ? req.body.instructions.trim().slice(0, 500)
      : "Speak like a warm chef giving a quick pre-cook rundown. Brisk and clear — not slow, not chirpy.";

  // Briefing should feel snappy. Allow client override; clamp to OpenAI's range.
  let speed = Number(req.body?.speed);
  if (!Number.isFinite(speed)) speed = 1.2;
  speed = Math.min(4, Math.max(0.25, speed));

  const startedAt = Date.now();
  // gpt-4o-mini-tts bills by input token, and the response is raw mp3 bytes with
  // no usage object, so character count is the only signal available here.
  // ai_rates prices this model per 1k input tokens; ~4 chars/token.
  const estimatedInputTokens = Math.ceil((text.length + instructions.length) / 4);

  // ElevenLabs branch: the cook picked a chef whose voice is a cloned one.
  //
  // Only the briefing can use it. In the LIVE session the voice is the Realtime
  // model's audio decoder rather than a parameter, so an owned voice there means
  // text-only output plus synthesising and playing the audio on device, which
  // takes playback outside libWebRTC and costs the echo canceller its reference.
  // Here there is no such constraint: the briefing is a plain request/response
  // that returns mp3 bytes, so the contract stays byte-identical and the client
  // needs no change.
  //
  // ELEVENLABS_API_KEY is already a production secret (Scribe v2 powers import
  // transcription), so this adds a vendor call, not a vendor.
  const elevenVoiceID = typeof req.body?.elevenLabsVoiceId === "string"
    ? req.body.elevenLabsVoiceId.trim().slice(0, 64)
    : "";
  const elevenKey = (process.env.ELEVENLABS_API_KEY || "").trim();
  if (elevenVoiceID && elevenKey && /^[A-Za-z0-9]+$/.test(elevenVoiceID)) {
    const elevenModel = (process.env.POLLY_ELEVENLABS_MODEL || "").trim() || "eleven_turbo_v2_5";
    try {
      const upstream = await fetch(
        `https://api.elevenlabs.io/v1/text-to-speech/${elevenVoiceID}?output_format=mp3_44100_128`,
        {
          method: "POST",
          headers: { "xi-api-key": elevenKey, "Content-Type": "application/json" },
          body: JSON.stringify({ text, model_id: elevenModel }),
          signal: AbortSignal.timeout(45_000),
        }
      );
      if (upstream.ok) {
        const audio = Buffer.from(await upstream.arrayBuffer());
        await logUsage({
          feature: "polly_speak",
          model: elevenModel,
          install_id: installIdFrom(req),
          input_tokens: estimatedInputTokens,
          duration_ms: Date.now() - startedAt,
        });
        res.setHeader("Cache-Control", "no-store");
        res.setHeader("Content-Type", "audio/mpeg");
        res.setHeader("x-glutt-polly-voice", elevenVoiceID);
        res.setHeader("x-glutt-polly-tts-model", elevenModel);
        return res.status(200).send(audio);
      }
      // Fall through to OpenAI rather than failing. A briefing in the wrong
      // voice is a disappointment; a briefing that 502s blocks the cook.
      const detail = (await upstream.text()).slice(0, 240);
      console.warn(`[polly/speak] elevenlabs ${upstream.status}: ${detail}`);
    } catch (error) {
      console.warn(`[polly/speak] elevenlabs failed: ${error instanceof Error ? error.message : error}`);
    }
  }

  try {
    const upstream = await fetch(`${openAIBaseURL}/audio/speech`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        voice,
        input: text,
        instructions,
        speed,
        response_format: "mp3",
      }),
      signal: AbortSignal.timeout(45_000),
    });

    if (!upstream.ok) {
      const detail = (await upstream.text()).slice(0, 240);
      await logUsage({
        feature: "polly_speak",
        model,
        install_id: installIdFrom(req),
        input_tokens: estimatedInputTokens,
        duration_ms: Date.now() - startedAt,
        ok: false,
      });
      return res.status(502).json({
        error: `upstream ${upstream.status}`,
        detail,
      });
    }

    const audio = Buffer.from(await upstream.arrayBuffer());

    await logUsage({
      feature: "polly_speak",
      model,
      install_id: installIdFrom(req),
      input_tokens: estimatedInputTokens,
      duration_ms: Date.now() - startedAt,
    });
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("Content-Type", "audio/mpeg");
    res.setHeader("x-glutt-polly-voice", voice);
    res.setHeader("x-glutt-polly-tts-model", model);
    return res.status(200).send(audio);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    const timedOut = /aborted|timeout/i.test(detail);
    return res.status(timedOut ? 504 : 502).json({
      error: timedOut ? "Speech timed out" : "Speech synthesis failed",
      detail,
    });
  }
}
