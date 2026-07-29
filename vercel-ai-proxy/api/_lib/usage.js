// Records one row per upstream call into Supabase `ai_usage`.
//
// Two hard rules:
//
//   1. This must NEVER fail or meaningfully slow an upstream request. Every
//      error is swallowed and the insert is bounded by a short timeout. Losing
//      a usage row is always preferable to breaking a cook.
//
//   2. It must actually land. Vercel can freeze a Node function the instant the
//      response is sent, so a dangling fire-and-forget promise is not safe --
//      handlers await logUsage() before returning. The spec called for
//      waitUntil() from @vercel/functions, but this proxy has no package.json
//      and adding one would make Vercel start running an install step on every
//      deploy of a currently dependency-free service. We pay one bounded round
//      trip instead; against upstream calls that already take seconds, it is
//      noise. If a package.json ever lands here for other reasons, swapping the
//      await for waitUntil is a two-line change.
//
// Writes use the service-role key, which bypasses RLS. `ai_usage` has RLS on
// with zero policies, so this is the only thing on earth that can insert.

const INSERT_TIMEOUT_MS = 1200;

function config() {
  const url = (process.env.SUPABASE_URL || "").trim().replace(/\/$/, "");
  const key = (process.env.SUPABASE_SERVICE_ROLE_KEY || "").trim();
  return url && key ? { url, key } : null;
}

/**
 * Per-install identifier the app sends. Today only PollyTokenService sets it;
 * other services attach it as they are updated. Absent entirely on the
 * GluttShare extension, whose rows land with a null install_id.
 */
export function installIdFrom(req) {
  return (req.headers["x-glutt-device-id"] || "").toString().slice(0, 64) || null;
}

/** Pulls token counts out of an OpenAI-shaped `usage` object. */
export function tokensFrom(payload) {
  const u = payload && payload.usage;
  if (!u) return {};
  const input = u.prompt_tokens ?? u.input_tokens;
  const output = u.completion_tokens ?? u.output_tokens;
  return {
    input_tokens: Number.isFinite(input) ? input : null,
    output_tokens: Number.isFinite(output) ? output : null,
  };
}

/**
 * @param {object} fields  Column values for one `ai_usage` row. `feature` is
 *   required; everything else is optional and defaults to null in Postgres.
 *   Rows whose `model` has no matching `ai_rates` entry cost $0 -- that is the
 *   signal to add a rate, not an error.
 */
export async function logUsage(fields) {
  const cfg = config();
  // Unconfigured (local dev, or before the env vars are set): silently no-op,
  // matching how the proxy-key check disables itself without keys.
  if (!cfg) return;

  try {
    await fetch(`${cfg.url}/rest/v1/ai_usage`, {
      method: "POST",
      headers: {
        apikey: cfg.key,
        Authorization: `Bearer ${cfg.key}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify({ ok: true, ...fields }),
      signal: AbortSignal.timeout(INSERT_TIMEOUT_MS),
    });
  } catch {
    // Swallowed on purpose. See rule 1.
  }
}
