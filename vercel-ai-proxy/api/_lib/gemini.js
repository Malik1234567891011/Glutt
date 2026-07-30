// Thin Gemini generateContent helper for cook-clip indexing.
// Key stays on Vercel (GEMINI_API_KEY). YouTube URLs are passed as file_data
// so Google fetches the public video — Glutt never downloads the bytes.

export function resolveGeminiKey() {
  return (
    process.env.GEMINI_API_KEY ||
    process.env.GOOGLE_API_KEY ||
    process.env.GOOGLE_GENERATIVE_AI_API_KEY ||
    ""
  ).trim();
}

export function resolveGeminiModel() {
  return (process.env.GEMINI_MODEL || "gemini-2.5-flash").trim();
}

/**
 * @param {object} opts
 * @param {string} opts.apiKey
 * @param {string} [opts.model]
 * @param {Array<object>} opts.parts - Gemini content parts
 * @param {boolean} [opts.json]
 * @param {number} [opts.temperature]
 */
export async function geminiGenerate({
  apiKey,
  model = resolveGeminiModel(),
  parts,
  json = true,
  temperature = 0.2,
}) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  const body = {
    contents: [{ role: "user", parts }],
    generationConfig: {
      temperature,
      ...(json ? { responseMimeType: "application/json" } : {}),
    },
  };

  const upstream = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,
    },
    body: JSON.stringify(body),
  });

  const raw = await upstream.text();
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    const err = new Error(`Gemini non-JSON response (${upstream.status})`);
    err.status = upstream.status;
    err.body = raw.slice(0, 500);
    throw err;
  }

  if (!upstream.ok) {
    const message =
      parsed?.error?.message ||
      parsed?.error?.status ||
      `Gemini error ${upstream.status}`;
    const err = new Error(message);
    err.status = upstream.status;
    err.body = parsed;
    throw err;
  }

  const text = (parsed?.candidates || [])
    .flatMap((c) => c?.content?.parts || [])
    .map((p) => p?.text || "")
    .join("")
    .trim();

  return { text, raw: parsed, model };
}

/** Best-effort JSON object/array extract from model text. */
export function parseJSONText(text) {
  if (!text) throw new Error("Empty Gemini response");
  try {
    return JSON.parse(text);
  } catch {
    const start = text.search(/[\[{]/);
    const end = Math.max(text.lastIndexOf("}"), text.lastIndexOf("]"));
    if (start >= 0 && end > start) {
      return JSON.parse(text.slice(start, end + 1));
    }
    throw new Error("Could not parse Gemini JSON");
  }
}
