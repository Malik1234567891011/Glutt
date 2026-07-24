import { isAuthorized } from "../_lib/auth.js";
// Discover search: keyword -> short, embeddable YouTube cooking videos.
// Returns the shape the iOS DiscoverService decodes:
//   { "videos": [ { videoId, title, creator, thumbnailURL, durationSeconds } ], "nextPageToken" }
// The YouTube Data API key lives ONLY here (server-side), never in the app.

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
        durationSeconds: null, // not returned by search.list; enrich via videos.list later if needed
      };
    });
}

export default async function handler(req, res) {
  res.setHeader("x-glutt-proxy-version", "discover-2026-06-20-1");

  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = resolveYouTubeKey();

  if (!apiKey) {
    return res.status(500).json({ error: "Server misconfigured: missing YOUTUBE_API_KEY" });
  }

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const q = (req.query.q || "").toString().trim();
  if (!q) {
    return res.status(400).json({ error: "Missing required query parameter: q" });
  }
  const pageToken = (req.query.pageToken || "").toString().trim();

  const url = new URL("https://www.googleapis.com/youtube/v3/search");
  url.searchParams.set("key", apiKey);
  url.searchParams.set("part", "snippet");
  url.searchParams.set("type", "video");
  url.searchParams.set("q", `${q} recipe`);
  url.searchParams.set("videoDuration", "short"); // < 4 min
  url.searchParams.set("videoEmbeddable", "true");
  url.searchParams.set("safeSearch", "moderate");
  url.searchParams.set("maxResults", "10");
  url.searchParams.set("relevanceLanguage", "en");
  if (pageToken) url.searchParams.set("pageToken", pageToken);

  try {
    const upstream = await fetch(url);
    if (!upstream.ok) {
      const detail = await upstream.text();
      return res.status(502).json({ error: "YouTube request failed", detail: detail.slice(0, 300) });
    }
    const data = await upstream.json();
    const videos = mapItems(data.items);

    // Cache at the Vercel edge to protect the daily YouTube quota
    // (search.list costs 100 units/call; default quota ~= 100 calls/day).
    res.setHeader("Cache-Control", "s-maxage=86400, stale-while-revalidate=604800");
    return res.status(200).json({ videos, nextPageToken: data.nextPageToken || null });
  } catch (error) {
    return res.status(502).json({
      error: "YouTube request failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
