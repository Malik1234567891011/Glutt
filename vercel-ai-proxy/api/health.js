export default function handler(_req, res) {
  res.status(200).json({
    ok: true,
    service: "glutt-vercel-ai-proxy",
    env: {
      has_OPENAI_API_KEY: Boolean((process.env.OPENAI_API_KEY || "").trim()),
      has_glutt_proxy_prod: Boolean((process.env.glutt_proxy_prod || "").trim()),
      has_GLUTT_PROXY_PROD: Boolean((process.env.GLUTT_PROXY_PROD || "").trim()),
      has_GLUTT_PROXY_CLIENT_KEY: Boolean((process.env.GLUTT_PROXY_CLIENT_KEY || "").trim()),
      has_OPENAI_BASE_URL: Boolean((process.env.OPENAI_BASE_URL || "").trim()),
      node_env: process.env.NODE_ENV || "unknown",
      vercel_env: process.env.VERCEL_ENV || "unknown"
    },
    timestamp: new Date().toISOString(),
  });
}

