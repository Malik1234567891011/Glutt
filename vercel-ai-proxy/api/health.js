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
      has_YOUTUBE_API_KEY: Boolean((process.env.YOUTUBE_API_KEY || process.env.GLUTT_YOUTUBE_KEY || "").trim()),
      has_SPOONACULAR_API_KEY: Boolean((process.env.SPOONACULAR_API_KEY || process.env.SPOONACULAR_API || "").trim()),
      has_ELEVENLABS_API_KEY: Boolean((process.env.ELEVENLABS_API_KEY || process.env.ELEVEN_LABS_API_KEY || "").trim()),
      has_POLLY_REALTIME_MODEL: Boolean((process.env.POLLY_REALTIME_MODEL || "").trim()),
      has_POLLY_VOICE: Boolean((process.env.POLLY_VOICE || "").trim()),
      node_env: process.env.NODE_ENV || "unknown",
      vercel_env: process.env.VERCEL_ENV || "unknown"
    },
    timestamp: new Date().toISOString(),
  });
}

