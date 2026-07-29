/**
 * Reddit post fetcher for Glutt import.
 *
 * Reddit's public site often Cloudflare-challenges datacenter IPs, so the app
 * tries on-device `.json` first and falls back here.
 *
 * Strategy (in order):
 *   1. Official OAuth app-only token (REDDIT_CLIENT_ID + REDDIT_CLIENT_SECRET)
 *      → GET oauth.reddit.com/comments/{id}
 *   2. Unauthenticated www.reddit.com/...json (sometimes works)
 *   3. PullPush archive by submission id (last resort; may lag on brand-new posts)
 *
 * POST { source_url: string }
 * → normalized JSON for RedditImport.payload(fromProxyJSON:)
 *
 * Env:
 *   REDDIT_CLIENT_ID / REDDIT_CLIENT_SECRET — optional but recommended
 *   GLUTT_PROXY_CLIENT_KEY / GLUTT_PROXY_CLIENT_KEY_NEXT — dual-key auth
 */
import { isAuthorized } from "../_lib/auth.js";

const USER_AGENT = "web:com.omarlahmimi.glutt:v1.1 (by /u/GluttApp)";

function postIDFromURL(raw) {
  try {
    const u = new URL(raw);
    const parts = u.pathname.split("/").filter(Boolean);
    const idx = parts.indexOf("comments");
    if (idx >= 0 && parts[idx + 1]) {
      const id = parts[idx + 1].toLowerCase();
      if (/^[a-z0-9]+$/.test(id)) return id;
    }
    // redd.it/{id}
    if (/(^|\.)redd\.it$/i.test(u.hostname) && parts[0] && /^[a-z0-9]+$/i.test(parts[0])) {
      return parts[0].toLowerCase();
    }
  } catch {
    /* ignore */
  }
  return null;
}

function imageFromPost(post) {
  try {
    const src = post?.preview?.images?.[0]?.source?.url;
    if (typeof src === "string" && src) return src.replace(/&amp;/g, "&");
  } catch {
    /* ignore */
  }
  if (typeof post?.thumbnail === "string" && post.thumbnail.startsWith("http")) {
    return post.thumbnail;
  }
  if (typeof post?.url === "string" && /i\.redd\.it|preview\.redd\.it/i.test(post.url)) {
    return post.url;
  }
  return null;
}

function flattenComments(children, limit = 25, out = []) {
  if (!Array.isArray(children)) return out;
  for (const node of children) {
    if (out.length >= limit) break;
    if (!node || node.kind !== "t1" || !node.data) continue;
    const body = node.data.body || "";
    if (body && body !== "[removed]" && body !== "[deleted]") {
      out.push({
        author: node.data.author || "",
        body,
        score: Number(node.data.score) || 0,
        is_submitter: !!node.data.is_submitter,
        stickied: !!node.data.stickied,
      });
    }
    const replies = node.data.replies;
    if (replies && typeof replies === "object" && replies.data?.children) {
      flattenComments(replies.data.children, limit, out);
    }
  }
  return out;
}

function normalizePost(post, comments = []) {
  return {
    title: post.title || "",
    author: post.author || "",
    selftext: post.selftext || "",
    permalink: post.permalink || "",
    url: post.url || "",
    is_self: !!post.is_self,
    image_url: imageFromPost(post),
    subreddit: post.subreddit || null,
    comments,
  };
}

async function redditOAuthToken() {
  const id = (process.env.REDDIT_CLIENT_ID || "").trim();
  const secret = (process.env.REDDIT_CLIENT_SECRET || "").trim();
  if (!id || !secret) return null;

  const basic = Buffer.from(`${id}:${secret}`).toString("base64");
  const res = await fetch("https://www.reddit.com/api/v1/access_token", {
    method: "POST",
    headers: {
      Authorization: `Basic ${basic}`,
      "User-Agent": USER_AGENT,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) return null;
  const json = await res.json();
  return typeof json.access_token === "string" ? json.access_token : null;
}

async function fetchViaOAuth(postID) {
  const token = await redditOAuthToken();
  if (!token) return null;

  const res = await fetch(`https://oauth.reddit.com/comments/${postID}?raw_json=1`, {
    headers: {
      Authorization: `Bearer ${token}`,
      "User-Agent": USER_AGENT,
      Accept: "application/json",
    },
    signal: AbortSignal.timeout(20_000),
  });
  if (!res.ok) return null;
  const listing = await res.json();
  if (!Array.isArray(listing) || !listing[0]?.data?.children?.[0]?.data) return null;
  const post = listing[0].data.children[0].data;
  const comments = flattenComments(listing[1]?.data?.children || []);
  return normalizePost(post, comments);
}

async function fetchViaPublicJSON(sourceURL) {
  try {
    const u = new URL(sourceURL);
    let path = u.pathname.replace(/\/$/, "");
    if (!path.endsWith(".json")) path += ".json";
    const jsonURL = `https://www.reddit.com${path}?raw_json=1`;
    const res = await fetch(jsonURL, {
      headers: {
        "User-Agent": USER_AGENT,
        Accept: "application/json",
      },
      signal: AbortSignal.timeout(20_000),
    });
    if (!res.ok) return null;
    const text = await res.text();
    if (!text.startsWith("[") && !text.startsWith("{")) return null;
    const listing = JSON.parse(text);
    const arr = Array.isArray(listing) ? listing : [listing];
    const post = arr[0]?.data?.children?.[0]?.data;
    if (!post) return null;
    const comments = flattenComments(arr[1]?.data?.children || []);
    return normalizePost(post, comments);
  } catch {
    return null;
  }
}

async function fetchViaPullPush(postID) {
  const subRes = await fetch(
    `https://api.pullpush.io/reddit/search/submission/?ids=${encodeURIComponent(postID)}`,
    {
      headers: { "User-Agent": "Glutt/1.1 (recipe-import)", Accept: "application/json" },
      signal: AbortSignal.timeout(20_000),
    }
  );
  if (!subRes.ok) return null;
  const subJSON = await subRes.json();
  const post = subJSON?.data?.[0];
  if (!post) return null;

  let comments = [];
  try {
    const cRes = await fetch(
      `https://api.pullpush.io/reddit/search/comment/?link_id=t3_${encodeURIComponent(postID)}&size=25&sort=score`,
      {
        headers: { "User-Agent": "Glutt/1.1 (recipe-import)", Accept: "application/json" },
        signal: AbortSignal.timeout(20_000),
      }
    );
    if (cRes.ok) {
      const cJSON = await cRes.json();
      comments = (cJSON?.data || [])
        .filter((c) => c?.body && c.body !== "[removed]" && c.body !== "[deleted]")
        .map((c) => ({
          author: c.author || "",
          body: c.body,
          score: Number(c.score) || 0,
          is_submitter: !!c.is_submitter,
          stickied: !!c.stickied,
        }));
    }
  } catch {
    /* comments optional */
  }

  return normalizePost(post, comments);
}

export default async function handler(req, res) {
  res.setHeader("x-glutt-proxy-version", "import-reddit-2026-07-25");

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const sourceURL = (req.body && req.body.source_url) || "";
  if (typeof sourceURL !== "string" || !/^https?:\/\//i.test(sourceURL.trim())) {
    return res.status(400).json({ error: "source_url must be an http(s) URL" });
  }

  const postID = postIDFromURL(sourceURL.trim());
  if (!postID) {
    return res.status(400).json({
      error: "Not a Reddit post URL",
      detail: "Need /r/{sub}/comments/{id}/… or redd.it/{id}",
    });
  }

  try {
    const payload =
      (await fetchViaOAuth(postID)) ||
      (await fetchViaPublicJSON(sourceURL.trim())) ||
      (await fetchViaPullPush(postID));

    if (!payload || !payload.title) {
      return res.status(502).json({ error: "Could not load Reddit post" });
    }

    res.setHeader("Cache-Control", "no-store");
    return res.status(200).json(payload);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    return res.status(502).json({ error: "Reddit fetch failed", detail });
  }
}
