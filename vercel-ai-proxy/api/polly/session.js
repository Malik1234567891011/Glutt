// Polly: mints short-lived OpenAI Realtime client secrets ("ek_...") so the
// app can open a Realtime WebSocket without ever seeing the long-lived
// OPENAI_API_KEY. Secrets expire after 10 minutes (PollyConfig.tokenTTLSeconds);
// the socket itself may live up to 60.

function resolveOpenAIKey() {
  return (
    process.env.OPENAI_API_KEY ||
    process.env.glutt_proxy_prod ||
    process.env.GLUTT_PROXY_PROD ||
    ""
  ).trim();
}

export default async function handler(req, res) {
  res.setHeader("x-glutt-proxy-version", "polly-2026-07-23-1");

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const openAIKey = resolveOpenAIKey();
  const expectedProxyKey = process.env.GLUTT_PROXY_CLIENT_KEY || "";

  if (!openAIKey) {
    return res.status(500).json({ error: "not configured" });
  }

  if (expectedProxyKey) {
    const incomingKey = req.headers["x-glutt-proxy-key"] || "";
    if (incomingKey !== expectedProxyKey) {
      return res.status(401).json({ error: "Unauthorized" });
    }
  }

  const model = (process.env.POLLY_REALTIME_MODEL || "").trim() || "gpt-realtime-2.1";
  const voice = (process.env.POLLY_VOICE || "").trim() || "marin";

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
          audio: { output: { voice } },
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
