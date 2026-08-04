import { isAuthorized } from "../_lib/auth.js";
import { logUsage, installIdFrom } from "../_lib/usage.js";
// Discover feed: an endless, paginated stream of photo recipes from
// Spoonacular. Each page is one complexSearch call (photo + macros +
// ingredients + steps + servings) normalized into Glutt's PlateCard contract.
// `pageToken` is a simple integer page cursor; each page is an independent
// random draw from the main-course corpus, so the cook can swipe forever with
// variety. Every page is edge-cached so repeat opens cost ~0 points, and the
// client shuffles, de-dupes and remembers what's been swiped on top of that.
//
// Quota is the binding constraint here, not latency: the free plan is 50
// points/day TOTAL across all users, and a page of 20 measures at 3.2 — so the
// whole product gets ~15 uncached pages a day. The cache is what makes the
// feature viable; treat any change that multiplies distinct cache keys as a
// change that multiplies the bill, and watch the quota headers set below.

function resolveSpoonacularKey() {
  // Accept either env var name so setup mismatches don't silently 500.
  return (process.env.SPOONACULAR_API_KEY || process.env.SPOONACULAR_API || "").trim();
}

// No query rotation, deliberately. A page is ONE upstream call, so any query
// narrow enough to add variety between pages also makes every card WITHIN a
// page share its theme — a rotation through "casserole", "salmon", "tacos"
// deals twenty casseroles in a row, which reads as broken even though the
// recipes differ. Narrow queries also underfill: "street food" was measured
// returning 3 usable cards for a full page's spend.
//
// `sort=random` over the whole main-course corpus does the job the query list
// was trying to do, and does it within the page as well as between pages.
const DISH_TYPE = "main course";

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
  res.setHeader("x-glutt-proxy-version", "plates-2026-08-02-variety");

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

  // Bigger pages are CHEAPER per recipe, not more expensive: the 1-point base
  // is charged per request and amortizes, while each recipe costs a measured
  // 0.11 either way. 20 works out at 0.16/recipe against 12's 0.19, and refills
  // the deck less often, so it also means fewer requests.
  const PAGE_SIZE = 20;
  const page = Math.max(0, parseInt((req.query.pageToken || "0").toString(), 10) || 0);
  const url = new URL("https://api.spoonacular.com/recipes/complexSearch");
  url.searchParams.set("apiKey", apiKey);
  url.searchParams.set("type", DISH_TYPE);
  url.searchParams.set("number", String(PAGE_SIZE));
  // No offset. It used to be the variety mechanism and was broken — it only
  // moved after a full lap of every query, some 480 cards in — but under a
  // random sort it is also meaningless, since every request reshuffles and
  // offset N is just another random slice.
  //
  // The upstream URL is now identical for every page. That is fine and
  // intended: pages are cached separately by the incoming pageToken, so each
  // one is its own upstream call and its own random draw.
  //
  // NOT setting addRecipeInformation: addRecipeNutrition turns it on implicitly.
  // (Measured cost is unchanged at 0.11/recipe either way, so it is billed
  // through the implicit enable — no saving, but no reason to ask twice.)
  url.searchParams.set("addRecipeNutrition", "true");
  url.searchParams.set("fillIngredients", "true");
  url.searchParams.set("instructionsRequired", "true");
  // Spoonacular's own docs point here rather than at the random-recipes
  // endpoint when you also need filtering. `popularity` is a stable ranking,
  // which is what made the old deck return an identical handful every time.
  url.searchParams.set("sort", "random");

  // NOTE: this response is edge-cached for 12h, so the function does not run on
  // a cache hit. Every row logged below is therefore a cache MISS -- i.e. real
  // Spoonacular quota spend, not user traffic. Do not read these counts as
  // "how many people opened the deck"; PostHog answers that.
  const startedAt = Date.now();
  try {
    const upstream = await fetch(url);
    if (!upstream.ok) {
      const detail = await upstream.text();
      await logUsage({
        feature: "plates_deck",
        model: "spoonacular:complexSearch",
        install_id: installIdFrom(req),
        duration_ms: Date.now() - startedAt,
        ok: false,
      });
      return res.status(502).json({ error: "Spoonacular request failed", detail: detail.slice(0, 300) });
    }
    const data = await upstream.json();
    const recipes = (data.results || []).map(normalizeRecipe).filter(imageWorthy);

    // The free plan is 50 points/day and Vercel keeps no runtime logs at this
    // tier, so these headers are the only way to know what a page actually
    // costs and how close to the ceiling the day is. Spoonacular starts
    // returning 402 the moment it runs out.
    const pointsForRequest = upstream.headers.get("x-api-quota-request") || "";
    const pointsUsedToday = upstream.headers.get("x-api-quota-used") || "";
    if (pointsForRequest) res.setHeader("x-glutt-spoonacular-points", pointsForRequest);
    if (pointsUsedToday) res.setHeader("x-glutt-spoonacular-used-today", pointsUsedToday);

    await logUsage({
      feature: "plates_deck",
      model: "spoonacular:complexSearch",
      install_id: installIdFrom(req),
      duration_ms: Date.now() - startedAt,
    });

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
