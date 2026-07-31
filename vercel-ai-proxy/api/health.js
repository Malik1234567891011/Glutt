import { handleMediaIngest } from "./_lib/mediaIngest.js";
import { handleMediaClips } from "./_lib/mediaClips.js";

function wantsMediaClips(req) {
  const q = (req.query?.action || "").toString();
  if (q === "clips" || q === "media_clips") return true;
  const bodyAction = (req.body?.action || "").toString();
  if (bodyAction === "clips" || bodyAction === "media_clips") return true;
  // Rewrite from /api/media/clips → /api/health (Hobby fn budget).
  const raw =
    (req.headers["x-forwarded-uri"] ||
      req.headers["x-invoke-path"] ||
      req.url ||
      "").toString();
  return raw.includes("/media/clips");
}

export default async function handler(req, res) {
  // Native Polly clip manifests (Supabase + signed Storage URLs).
  if (wantsMediaClips(req)) {
    return handleMediaClips(req, res);
  }

  // POST /api/health with action=* → media control plane (Hobby fn budget).
  // Clean URL: /api/media/ingest rewrites here.
  if (req.method === "POST") {
    return handleMediaIngest(req, res);
  }

  // GET media ingest status (also rewritten from /api/media/ingest).
  const ingestAction = (req.query?.action || "").toString();
  const rawURL =
    (req.headers["x-forwarded-uri"] || req.headers["x-invoke-path"] || req.url || "").toString();
  if (
    req.method === "GET" &&
    (ingestAction === "status"
      || ingestAction === "enqueue"
      || req.query?.job_id
      || req.query?.source_asset_id
      || req.query?.external_id
      || rawURL.includes("/media/ingest"))
  ) {
    return handleMediaIngest(req, res);
  }

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
      has_GEMINI_API_KEY: Boolean((process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || process.env.GOOGLE_GENERATIVE_AI_API_KEY || "").trim()),
      has_POLLY_REALTIME_MODEL: Boolean((process.env.POLLY_REALTIME_MODEL || "").trim()),
      has_POLLY_VOICE: Boolean((process.env.POLLY_VOICE || "").trim()),
      // Usage logging is deliberately silent: logUsage swallows every error so a
      // sick Supabase can never break a cook. That makes "0 rows in ai_usage"
      // ambiguous between no-traffic and misconfigured, so surface the config
      // here. Presence only — never the values.
      has_SUPABASE_URL: Boolean((process.env.SUPABASE_URL || "").trim()),
      has_SUPABASE_SERVICE_ROLE_KEY: Boolean((process.env.SUPABASE_SERVICE_ROLE_KEY || "").trim()),
      node_env: process.env.NODE_ENV || "unknown",
      vercel_env: process.env.VERCEL_ENV || "unknown"
    },
    timestamp: new Date().toISOString(),
  });
}
