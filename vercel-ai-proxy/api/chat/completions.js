import { isAuthorized } from "../_lib/auth.js";
import { logUsage, installIdFrom, tokensFrom, featureFrom } from "../_lib/usage.js";
import { isAnthropicModel, callAnthropic } from "../_lib/anthropic.js";

function resolveOpenAIKey() {
  return (
    process.env.OPENAI_API_KEY ||
    process.env.glutt_proxy_prod ||
    process.env.GLUTT_PROXY_PROD ||
    ""
  ).trim();
}

export default async function handler(req, res) {
  const proxyVersion = "2026-08-31-anthropic-4";
  res.setHeader("x-glutt-proxy-version", proxyVersion);

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const openAIKey = resolveOpenAIKey();
  const openAIBaseURL = process.env.OPENAI_BASE_URL || "https://api.openai.com/v1";

  if (!openAIKey) {
    return res.status(500).json({ error: "Server misconfigured: missing OPENAI_API_KEY" });
  }

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  // The model is whatever the app asked for -- this endpoint is a pass-through.
  // A model with no ai_rates row costs $0, which is the signal to add a rate.
  const model = (req.body && req.body.model) || null;
  // Every one-shot LLM feature shares this endpoint; the header is how one
  // surface's spend stays readable apart from the rest.
  const feature = featureFrom(req, "chat");
  const startedAt = Date.now();

  // Claude goes to Anthropic, translated both ways. Everything else is the
  // pass-through this endpoint has always been.
  if (isAnthropicModel(model)) {
    const startedAtClaude = Date.now();
    const result = await callAnthropic(req.body || {});
    let usage = {};
    try { usage = tokensFrom(JSON.parse(result.raw)); } catch { /* error body */ }
    try {
      await logUsage({
        installId: installIdFrom(req), feature, model,
        ...usage, ms: Date.now() - startedAtClaude, ok: result.ok,
      });
    } catch { /* never fail a request over bookkeeping */ }
    res.setHeader("Content-Type", "application/json");
    return res.status(result.status).send(result.raw);
  }

  try {
    const upstream = await fetch(`${openAIBaseURL}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(req.body || {}),
    });

    const raw = await upstream.text();
    const contentType = upstream.headers.get("content-type") || "application/json";

    // Non-streaming, so the whole body is in hand and carries a usage object.
    // Parsing must never affect what we forward.
    let usage = {};
    try {
      usage = tokensFrom(JSON.parse(raw));
    } catch {
      // Not JSON (or an error body). Log the call without token counts.
    }

    await logUsage({
      feature,
      model,
      install_id: installIdFrom(req),
      ...usage,
      duration_ms: Date.now() - startedAt,
      ok: upstream.ok,
    });

    res.status(upstream.status);
    res.setHeader("Content-Type", contentType);
    return res.send(raw);
  } catch (error) {
    await logUsage({
      feature,
      model,
      install_id: installIdFrom(req),
      duration_ms: Date.now() - startedAt,
      ok: false,
    });
    return res.status(502).json({
      error: "Upstream AI request failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}

