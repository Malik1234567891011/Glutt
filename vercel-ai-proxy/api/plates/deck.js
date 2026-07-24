import { isAuthorized } from "../_lib/auth.js";
// Discover feed: an endless, paginated stream of photo recipes from
// Spoonacular. Each page is one complexSearch call (photo + macros +
// ingredients + steps + servings) normalized into Glutt's PlateCard contract.
// `pageToken` is a simple integer page cursor; we rotate the query and advance
// the Spoonacular offset per page so the cook can swipe forever with variety.
// Every page is edge-cached (by page + UTC day) so repeat opens cost ~0 points.

function resolveSpoonacularKey() {
  // Accept either env var name so setup mismatches don't silently 500.
  return (process.env.SPOONACULAR_API_KEY || process.env.SPOONACULAR_API || "").trim();
}

const ROTATING_QUERIES = [
  "high protein dinner",
  "easy weeknight dinner",
  "healthy meal prep",
  "30 minute dinner",
  "one pan dinner",
  "chicken dinner",
  "vegetarian dinner",
  "comfort food dinner",
  "mediterranean dinner",
  "budget family dinner",
];

function nutrient(nutrition, name) {
  const list = (nutrition && nutrition.nutrients) || [];
  const hit = list.find((n) => n && n.name === name);
  return hit ? Math.round(hit.amount) : null;
}

// Spoonacular's search image is a small CDN thumbnail (e.g. 312x231) that looks
// blurry blown up to a full-screen card. Rewrite the size token to the largest
// CDN render (636x393) — same URL scheme, just sharper.
function upscaleImage(url) {
  if (typeof url !== "string" || !url.includes("img.spoonacular.com/recipes/")) return url;
  return url.replace(/-\d+x\d+(\.\w+)(\?.*)?$/, "-636x393$1$2");
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
  const instr = r.analyzedInstructions || [];
  for (const block of instr) {
    for (const s of block.steps || []) {
      if (s && s.step) steps.push(s.step);
    }
  }
  const diets = Array.isArray(r.diets) ? r.diets : [];
  const dishTypes = Array.isArray(r.dishTypes) ? r.dishTypes : [];
  return {
    id: `spoonacular:${r.id}`,
    title: r.title || "",
    imageURL: upscaleImage(r.image) || null,
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

function imageWorthy(card) {
  return Boolean(card.imageURL) && card.steps.length > 0 && card.ingredients.length > 0;
}

export default async function handler(req, res) {
  res.setHeader("x-glutt-proxy-version", "plates-2026-06-26-1");

  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = resolveSpoonacularKey();

  if (!apiKey) {
    return res.status(500).json({ error: "Server misconfigured: missing SPOONACULAR_API_KEY" });
  }
  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const PAGE_SIZE = 12;
  const dayIndex = Math.floor(Date.now() / 86400000);
  // page cursor: 0, 1, 2, … Each page rotates to a different query and, once a
  // full lap of queries is done, steps the Spoonacular offset so pages stay
  // fresh. Day-seeded start so the feed differs day to day.
  const page = Math.max(0, parseInt((req.query.pageToken || "0").toString(), 10) || 0);
  const queryIndex = (dayIndex + page) % ROTATING_QUERIES.length;
  const query = ROTATING_QUERIES[queryIndex];
  const offset = Math.floor(page / ROTATING_QUERIES.length) * PAGE_SIZE;

  const url = new URL("https://api.spoonacular.com/recipes/complexSearch");
  url.searchParams.set("apiKey", apiKey);
  url.searchParams.set("query", query);
  url.searchParams.set("number", String(PAGE_SIZE));
  url.searchParams.set("offset", String(offset));
  url.searchParams.set("addRecipeInformation", "true");
  url.searchParams.set("addRecipeNutrition", "true");
  url.searchParams.set("fillIngredients", "true");
  url.searchParams.set("instructionsRequired", "true");
  url.searchParams.set("sort", "popularity");

  try {
    const upstream = await fetch(url);
    if (!upstream.ok) {
      const detail = await upstream.text();
      return res.status(502).json({ error: "Spoonacular request failed", detail: detail.slice(0, 300) });
    }
    const data = await upstream.json();
    const recipes = (data.results || []).map(normalizeRecipe).filter(imageWorthy);

    // Endless: always hand back the next cursor. Spoonacular has thousands of
    // hits per query, and we rotate queries, so the feed effectively never ends.
    const nextPageToken = String(page + 1);

    // Page-seeded + globally shared → cache hard so each page is one call.
    res.setHeader("Cache-Control", "s-maxage=43200, stale-while-revalidate=86400");
    return res.status(200).json({ deckTitle: page === 0 ? "Discover" : null, recipes, nextPageToken });
  } catch (error) {
    return res.status(502).json({
      error: "Spoonacular request failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
