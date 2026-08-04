import { isAuthorized } from "../_lib/auth.js";
import { logUsage, installIdFrom } from "../_lib/usage.js";
import { handleCookClips } from "../_lib/cookClips.js";
// Discover suggested feed: shown when the user opens Discover with no query.
// Returns the same shape as /discover/search. Biased by optional taste `tags`
// (comma-separated, derived from the user's saved-recipe tags); otherwise a
// rotating popular cooking query. Never paginates (the feed is short by design),
// so nextPageToken is always null.
//
// Also hosts POST cook-clip indexing (Hobby plan is capped at 12 serverless
// functions). /api/cook/clips rewrites here so the client keeps a clean URL.

function resolveYouTubeKey() {
  return (process.env.YOUTUBE_API_KEY || process.env.GLUTT_YOUTUBE_KEY || "").trim();
}

function mapItems(items) {
  return (items || [])
    .filter((it) => it && it.id && it.id.videoId)
    .map((it) => {
      const sn = it.snippet || {};
      const thumbs = sn.thumbnails || {};
      const thumb = thumbs.high || thumbs.medium || thumbs.default || null;
      return {
        videoId: it.id.videoId,
        title: sn.title || "",
        creator: sn.channelTitle || null,
        thumbnailURL: thumb ? thumb.url : null,
        durationSeconds: null,
      };
    });
}

const ROTATING_QUERIES = [
  "easy dinner",
  "high protein meal",
  "30 minute meal",
  "healthy lunch",
  "one pan dinner",
  "meal prep",
  "quick pasta",
  "chicken dinner",
  "vegetarian dinner",
  "budget weeknight meal",
];

export default async function handler(req, res) {
  // POST = Polly step-clip indexing (rewritten from /api/cook/clips).
  if (req.method === "POST") {
    return handleCookClips(req, res);
  }

  res.setHeader("x-glutt-proxy-version", "discover-2026-08-02-variety");

  if (req.method !== "GET") {
    res.setHeader("Allow", "GET, POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = resolveYouTubeKey();

  if (!apiKey) {
    return res.status(500).json({ error: "Server misconfigured: missing YOUTUBE_API_KEY" });
  }

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const tags = (req.query.tags || "")
    .toString()
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  const dayIndex = Math.floor(Date.now() / 86400000);
  const rotating = ROTATING_QUERIES[dayIndex % ROTATING_QUERIES.length];
  let q;
  if (tags.length > 0) {
    // Pair ONE taste tag with the rotating angle rather than pinning the query
    // to the top two tags. Those two are the most frequent tags across saved
    // recipes, so they essentially never change — which meant anyone with a
    // cookbook got one fixed query, forever, and the day rotation below never
    // applied to them at all. Which tag leads also walks with the day.
    const tag = tags[dayIndex % tags.length];
    q = `${tag} ${rotating}`;
  } else {
    q = rotating;
  }

  const url = new URL("https://www.googleapis.com/youtube/v3/search");
  url.searchParams.set("key", apiKey);
  url.searchParams.set("part", "snippet");
  url.searchParams.set("type", "video");
  url.searchParams.set("q", `${q} recipe`);
  url.searchParams.set("videoDuration", "short");
  url.searchParams.set("videoEmbeddable", "true");
  url.searchParams.set("safeSearch", "moderate");
  // search.list bills 100 quota units per call regardless of how many results
  // come back, so asking for 10 was paying full price for a fifth of the pool.
  // The client shuffles and de-dupes, so a bigger pool is straight variety.
  url.searchParams.set("maxResults", "50");
  url.searchParams.set("relevanceLanguage", "en");

  // Edge-cached for 6h -- rows are cache MISSES, each costing 100 YouTube quota
  // units. Tag-biased requests bypass the shared cache more often than the
  // rotating default query does, so this count should track taste diversity.
  const startedAt = Date.now();
  try {
    const upstream = await fetch(url);
    if (!upstream.ok) {
      const detail = await upstream.text();
      await logUsage({
        feature: "discover_suggested",
        model: "youtube:search.list",
        install_id: installIdFrom(req),
        duration_ms: Date.now() - startedAt,
        ok: false,
      });
      return res.status(502).json({ error: "YouTube request failed", detail: detail.slice(0, 300) });
    }
    const data = await upstream.json();
    const videos = mapItems(data.items);

    await logUsage({
      feature: "discover_suggested",
      model: "youtube:search.list",
      install_id: installIdFrom(req),
      duration_ms: Date.now() - startedAt,
    });

    // Cache hard — suggestions are near-static and this is the highest-traffic
    // (open-the-tab) call, so it must not burn quota.
    res.setHeader("Cache-Control", "s-maxage=21600, stale-while-revalidate=86400");
    return res.status(200).json({ videos, nextPageToken: null });
  } catch (error) {
    return res.status(502).json({
      error: "YouTube request failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
