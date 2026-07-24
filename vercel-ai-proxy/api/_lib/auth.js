// Shared proxy-key check with dual-key rotation support.
//
// GLUTT_PROXY_CLIENT_KEY is the key baked into shipped App Store builds;
// GLUTT_PROXY_CLIENT_KEY_NEXT is the rotation target (new builds carry it via
// the gitignored Secrets.local.plist). Both are accepted during a rotation so
// flipping the primary never bricks Polly/Plates/Discover for shipped users.
// Once an app version with the new key is broadly adopted: promote NEXT to
// primary and clear NEXT.
//
// Empty/missing keys (local dev) disable the check entirely — same behavior
// the endpoints had individually.
export function isAuthorized(req) {
  const keys = [process.env.GLUTT_PROXY_CLIENT_KEY, process.env.GLUTT_PROXY_CLIENT_KEY_NEXT]
    .map((k) => (k || "").trim())
    .filter(Boolean);
  if (keys.length === 0) return true;
  const incoming = (req.headers["x-glutt-proxy-key"] || "").toString().trim();
  return keys.includes(incoming);
}
