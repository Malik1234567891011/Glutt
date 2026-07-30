import net from "node:net";
import { config } from "./config.js";

const BLOCKED_HOSTS = new Set(["localhost", "metadata.google.internal", "metadata"]);

function isPrivateIp(ip) {
  if (!ip) return true;
  if (ip === "::1" || ip.startsWith("fc") || ip.startsWith("fd") || ip.startsWith("fe80")) return true;
  const parts = ip.split(".").map(Number);
  if (parts.length !== 4 || parts.some((n) => Number.isNaN(n))) return false;
  const [a, b] = parts;
  if (a === 10 || a === 127 || a === 0) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  return false;
}

/**
 * Validate ingest URLs before any network/tool use.
 * HTTPS only, host allowlist, no private IPs (best-effort DNS check optional).
 */
export function validateSourceUrl(raw) {
  let url;
  try {
    url = new URL(String(raw || "").trim());
  } catch {
    throw Object.assign(new Error("Invalid URL"), { code: "INVALID_URL" });
  }
  if (url.protocol !== "https:") {
    throw Object.assign(new Error("Only HTTPS URLs are allowed"), { code: "SCHEME_NOT_ALLOWED" });
  }
  const host = url.hostname.toLowerCase();
  if (BLOCKED_HOSTS.has(host) || host.endsWith(".local") || host.endsWith(".internal")) {
    throw Object.assign(new Error("Host not allowed"), { code: "HOST_BLOCKED" });
  }
  if (!config.allowedHosts.has(host)) {
    throw Object.assign(new Error(`Host not on allowlist: ${host}`), { code: "HOST_NOT_ALLOWLISTED" });
  }
  // Literal IP in hostname
  if (net.isIP(host) && isPrivateIp(host)) {
    throw Object.assign(new Error("Private IP blocked"), { code: "SSRF_PRIVATE_IP" });
  }
  return url;
}

export function detectPlatform(url) {
  const host = url.hostname.toLowerCase();
  if (host.includes("youtube") || host === "youtu.be") return "youtube";
  if (host.includes("tiktok")) return "tiktok";
  if (host.includes("instagram")) return "instagram";
  return "web";
}

export function youtubeExternalId(url) {
  if (url.hostname.includes("youtu.be")) {
    return url.pathname.split("/").filter(Boolean)[0] || null;
  }
  return url.searchParams.get("v");
}

export function objectKeys(sourceAssetId) {
  const base = `source_assets/${sourceAssetId}`;
  return {
    originalPrefix: `${base}/original`,
    normalized: `${base}/normalized.mp4`,
    analysisProxy: `${base}/analysis-proxy.mp4`,
    audio: `${base}/audio.m4a`,
    metadata: `${base}/metadata.json`,
  };
}
