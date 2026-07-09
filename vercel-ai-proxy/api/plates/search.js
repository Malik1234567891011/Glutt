// Explore/search: live Spoonacular complexSearch by query, paginated via
// offset. Cached per (query) for a day. Same PlateCard contract as deck.js.

function resolveSpoonacularKey() {
  // Accept either env var name so setup mismatches don't silently 500.
  return (process.env.SPOONACULAR_API_KEY || process.env.SPOONACULAR_API || "").trim();
}

function nutrient(nutrition, name) {
  const list = (nutrition && nutrition.nutrients) || [];
  const hit = list.find((n) => n && n.name === name);
  return hit ? Math.round(hit.amount) : null;
}

function normalizeRecipe(r) {
  const nutrition = r.nutrition || {};
  const ingredients = (r.extendedIngredients || []).map((ing) => ({
    raw: ing.original || ing.originalString || ing.name || "",
    name: ing.name || null,
    quantity: typeof ing.amount === "number" ? ing.amount : null,
    unit: ing.unit || null,
  }));
  const steps = [];
  for (const block of r.analyzedInstructions || []) {
    for (const s of block.steps || []) {
      if (s && s.step) steps.push(s.step);
    }
  }
  const diets = Array.isArray(r.diets) ? r.diets : [];
  const dishTypes = Array.isArray(r.dishTypes) ? r.dishTypes : [];
  return {
    id: `spoonacular:${r.id}`,
    title: r.title || "",
    imageURL: r.image || null,
    source: "spoonacular",
    sourceURL: r.sourceUrl || null,
    creator: r.creditsText || r.sourceName || null,
    license: "spoonacular",
    summary: typeof r.summary === "string" ? r.summary.replace(/<[^>]+>/g, "").slice(0, 280) : null,
    servings: typeof r.servings === "number" ? r.servings : null,
    prepMinutes: 0,
    cookMinutes: typeof r.readyInMinutes === "number" ? r.readyInMinutes : null,
    difficulty: "beginner",
    tags: [...new Set([...dishTypes, ...diets])],
    dietFlags: diets,
    macros: {
      calories: nutrient(nutrition, "Calories"),
      protein: nutrient(nutrition, "Protein"),
      carbs: nutrient(nutrition, "Carbohydrates"),
      fat: nutrient(nutrition, "Fat"),
      estimated: false,
    },
    ingredients,
    steps,
    nutritionNote: null,
  };
}

const PAGE_SIZE = 12;

export default async function handler(req, res) {
  res.setHeader("x-glutt-proxy-version", "plates-2026-06-26-1");

  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = resolveSpoonacularKey();
  const expectedProxyKey = process.env.GLUTT_PROXY_CLIENT_KEY || "";
  if (!apiKey) {
    return res.status(500).json({ error: "Server misconfigured: missing SPOONACULAR_API_KEY" });
  }
  if (expectedProxyKey) {
    const incomingKey = req.headers["x-glutt-proxy-key"] || "";
    if (incomingKey !== expectedProxyKey) {
      return res.status(401).json({ error: "Unauthorized" });
    }
  }

  const q = (req.query.q || "").toString().trim();
  if (!q) {
    return res.status(400).json({ error: "Missing q" });
  }
  const offset = Math.max(0, parseInt((req.query.pageToken || "0").toString(), 10) || 0);

  const url = new URL("https://api.spoonacular.com/recipes/complexSearch");
  url.searchParams.set("apiKey", apiKey);
  url.searchParams.set("query", q);
  url.searchParams.set("number", String(PAGE_SIZE));
  url.searchParams.set("offset", String(offset));
  url.searchParams.set("addRecipeInformation", "true");
  url.searchParams.set("addRecipeNutrition", "true");
  url.searchParams.set("fillIngredients", "true");
  url.searchParams.set("instructionsRequired", "true");

  try {
    const upstream = await fetch(url);
    if (!upstream.ok) {
      const detail = await upstream.text();
      return res.status(502).json({ error: "Spoonacular request failed", detail: detail.slice(0, 300) });
    }
    const data = await upstream.json();
    const recipes = (data.results || []).map(normalizeRecipe).filter((c) => c.imageURL);
    const total = typeof data.totalResults === "number" ? data.totalResults : 0;
    const nextOffset = offset + PAGE_SIZE;
    const nextPageToken = nextOffset < total ? String(nextOffset) : null;

    res.setHeader("Cache-Control", "s-maxage=86400, stale-while-revalidate=604800");
    return res.status(200).json({ deckTitle: null, recipes, nextPageToken });
  } catch (error) {
    return res.status(502).json({
      error: "Spoonacular request failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
