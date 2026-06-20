// Discover suggested feed: shown when the user opens Discover with no query.
// Returns the same shape as /discover/search. Biased by optional taste `tags`
// (comma-separated, derived from the user's saved-recipe tags); otherwise a
// rotating popular cooking query. Never paginates (the feed is short by design),
// so nextPageToken is always null.

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
  res.setHeader("x-glutt-proxy-version", "discover-2026-06-20-1");

  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = resolveYouTubeKey();
  const expectedProxyKey = process.env.GLUTT_PROXY_CLIENT_KEY || "";

  if (!apiKey) {
    return res.status(500).json({ error: "Server misconfigured: missing YOUTUBE_API_KEY" });
  }

  if (expectedProxyKey) {
    const incomingKey = req.headers["x-glutt-proxy-key"] || "";
    if (incomingKey !== expectedProxyKey) {
      return res.status(401).json({ error: "Unauthorized" });
    }
  }

  const tags = (req.query.tags || "")
    .toString()
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  let q;
  if (tags.length > 0) {
    q = tags.slice(0, 2).join(" ");
  } else {
    // Rotate the default query by day so the open-feed feels fresh, while
    // staying highly cacheable within any given day.
    const dayIndex = Math.floor(Date.now() / 86400000);
    q = ROTATING_QUERIES[dayIndex % ROTATING_QUERIES.length];
  }

  const url = new URL("https://www.googleapis.com/youtube/v3/search");
  url.searchParams.set("key", apiKey);
  url.searchParams.set("part", "snippet");
  url.searchParams.set("type", "video");
  url.searchParams.set("q", `${q} recipe`);
  url.searchParams.set("videoDuration", "short");
  url.searchParams.set("videoEmbeddable", "true");
  url.searchParams.set("safeSearch", "moderate");
  url.searchParams.set("maxResults", "10");
  url.searchParams.set("relevanceLanguage", "en");

  try {
    const upstream = await fetch(url);
    if (!upstream.ok) {
      const detail = await upstream.text();
      return res.status(502).json({ error: "YouTube request failed", detail: detail.slice(0, 300) });
    }
    const data = await upstream.json();
    const videos = mapItems(data.items);

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
