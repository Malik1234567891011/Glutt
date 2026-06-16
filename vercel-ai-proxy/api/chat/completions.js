export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const openAIKey =
    process.env.OPENAI_API_KEY ||
    process.env.glutt_proxy_prod ||
    process.env.GLUTT_PROXY_PROD ||
    "";
  const openAIBaseURL = process.env.OPENAI_BASE_URL || "https://api.openai.com/v1";
  const expectedProxyKey = process.env.GLUTT_PROXY_CLIENT_KEY || "";

  if (!openAIKey) {
    return res.status(500).json({ error: "Server misconfigured: missing OPENAI_API_KEY" });
  }

  if (expectedProxyKey) {
    const incomingKey = req.headers["x-glutt-proxy-key"] || "";
    if (incomingKey !== expectedProxyKey) {
      return res.status(401).json({ error: "Unauthorized" });
    }
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

    res.status(upstream.status);
    res.setHeader("Content-Type", contentType);
    return res.send(raw);
  } catch (error) {
    return res.status(502).json({
      error: "Upstream AI request failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}

