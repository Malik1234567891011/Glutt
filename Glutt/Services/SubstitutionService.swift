import Foundation

/// Static, culinary-sensible substitution table. The Phase 6 AI layer will
/// extend this with context-aware swaps; this table is the offline fallback
/// and ships first per the manually-useful-before-magical principle.
enum SubstitutionService {

    struct Substitution {
        let name: String
        let explanation: String
    }

    /// Keyed by canonical ingredient name.
    private static let table: [String: [Substitution]] = [
        "heavy cream": [
            Substitution(name: "Greek yogurt + butter", explanation: "Similar richness; add yogurt off the heat so it doesn't split."),
            Substitution(name: "sour cream", explanation: "Slightly tangier, same body."),
        ],
        "greek yogurt": [
            Substitution(name: "sour cream", explanation: "Same texture, slightly less protein."),
        ],
        "sour cream": [
            Substitution(name: "greek yogurt", explanation: "Tangier and higher protein."),
        ],
        "butter": [
            Substitution(name: "olive oil", explanation: "Works for cooking; skip for baking."),
        ],
        "green onion": [
            Substitution(name: "chives", explanation: "Milder but the same fresh-onion note."),
            Substitution(name: "red onion", explanation: "Use less — sharper flavor."),
        ],
        "coriander": [
            Substitution(name: "parsley", explanation: "Loses the citrus note but keeps freshness."),
        ],
        "parsley": [
            Substitution(name: "coriander", explanation: "Adds a citrusy edge."),
        ],
        "lemon": [
            Substitution(name: "lime", explanation: "Slightly more bitter, works in most dishes."),
            Substitution(name: "white vinegar", explanation: "Use half as much — acidity only, no aroma."),
        ],
        "lime": [
            Substitution(name: "lemon", explanation: "Slightly sweeter, works in most dishes."),
        ],
        "honey": [
            Substitution(name: "maple syrup", explanation: "Same sweetness, different aroma."),
            Substitution(name: "sugar", explanation: "Dissolve in a splash of warm water first."),
        ],
        "sriracha": [
            Substitution(name: "hot sauce + honey", explanation: "Matches the sweet-heat profile."),
            Substitution(name: "chili flakes", explanation: "Heat without the garlic-sweet note."),
        ],
        "chicken broth": [
            Substitution(name: "bouillon cube + water", explanation: "Practically identical."),
            Substitution(name: "vegetable broth", explanation: "Lighter but works."),
        ],
        "basmati rice": [
            Substitution(name: "jasmine rice", explanation: "Slightly stickier, same cook time."),
        ],
        "gnocchi": [
            Substitution(name: "pasta", explanation: "Different texture; boil instead of pan-toast."),
        ],
        "panko bread crumbs": [
            Substitution(name: "crushed crackers", explanation: "Similar crunch."),
        ],
        "brown sugar": [
            Substitution(name: "sugar + honey", explanation: "Mimics the molasses moisture."),
        ],
    ]

    /// Substitutions that should never happen — flag instead of suggesting.
    private static let doNotSubstitute: Set<String> = [
        "chicken", "beef", "salmon", "egg", "flour", "yeast", "baking powder", "baking soda",
    ]

    // MARK: Diet-aware substitutions

    /// Curated swaps for ingredients that break a dietary rule or allergy —
    /// ordered best-first, chosen to keep the dish as close as possible. These
    /// are matched by keyword (substring) against the conflicting ingredient,
    /// then filtered so the suggestion is itself allowed under the user's rules.
    private static let dietTable: [(keyword: String, subs: [Substitution])] = [
        // — Pork / cured pork (halal, kosher, no-pork, vegetarian, vegan) —
        ("bacon", [
            Substitution(name: "turkey bacon", explanation: "Closest match — crisps up the same way, fully halal/kosher."),
            Substitution(name: "beef bacon", explanation: "Smoky and rich, holds up in the pan."),
            Substitution(name: "smoked turkey", explanation: "For flavour in soups and braises."),
            Substitution(name: "smoked paprika + a little oil", explanation: "Vegetarian — gives the smoky note without meat."),
        ]),
        ("ground pork", [
            Substitution(name: "ground chicken", explanation: "Leaner, takes on seasoning well — the go-to swap."),
            Substitution(name: "ground turkey", explanation: "Very close texture; add a little oil as it's lean."),
            Substitution(name: "ground beef", explanation: "Richer and juicier, keeps the dish hearty."),
        ]),
        ("pork sausage", [
            Substitution(name: "chicken sausage", explanation: "Same role, milder — the recommended swap."),
            Substitution(name: "beef sausage", explanation: "Fattier and closer in richness."),
            Substitution(name: "turkey sausage", explanation: "Lean, seasons well."),
        ]),
        ("prosciutto", [
            Substitution(name: "beef bresaola", explanation: "Cured beef with the same thin, salty bite."),
            Substitution(name: "smoked turkey", explanation: "Milder but keeps the savoury layer."),
        ]),
        ("ham", [
            Substitution(name: "turkey ham", explanation: "Direct swap, same use."),
            Substitution(name: "smoked turkey", explanation: "Great in soups and sandwiches."),
        ]),
        ("pork", [
            Substitution(name: "chicken", explanation: "The all-round swap — adjust cook time as it's leaner."),
            Substitution(name: "beef", explanation: "Keeps the dish rich and hearty."),
            Substitution(name: "turkey", explanation: "Lean and mild."),
        ]),
        ("lard", [
            Substitution(name: "butter", explanation: "Same richness for pastry and frying."),
            Substitution(name: "vegetable shortening", explanation: "Neutral, works for baking."),
        ]),
        ("gelatin", [
            Substitution(name: "agar-agar", explanation: "Plant-based setting agent — use about half the amount."),
            Substitution(name: "pectin", explanation: "Great for jams and fruit sets."),
        ]),
        // — Alcohol (halal, and anyone avoiding it) —
        ("red wine", [
            Substitution(name: "beef stock + 1 tsp vinegar", explanation: "Recommended — matches the savoury depth and acidity."),
            Substitution(name: "grape juice + a splash of vinegar", explanation: "Keeps the fruity note without alcohol."),
            Substitution(name: "pomegranate juice", explanation: "Tart and deep-coloured for braises."),
        ]),
        ("white wine", [
            Substitution(name: "chicken stock + 1 tsp lemon juice", explanation: "Recommended — same brightness and body."),
            Substitution(name: "white grape juice + a splash of vinegar", explanation: "Fruity acidity, no alcohol."),
            Substitution(name: "apple juice + vinegar", explanation: "Works in pan sauces."),
        ]),
        ("mirin", [
            Substitution(name: "rice vinegar + a little sugar", explanation: "Recommended — mimics the sweet-tangy glaze."),
            Substitution(name: "apple juice + rice vinegar", explanation: "Balanced sweet and sour."),
        ]),
        ("shaoxing wine", [
            Substitution(name: "chicken stock + a splash of rice vinegar", explanation: "Keeps the savoury base."),
            Substitution(name: "white grape juice + vinegar", explanation: "Non-alcoholic stand-in."),
        ]),
        ("beer", [
            Substitution(name: "non-alcoholic beer", explanation: "Closest flavour, no alcohol."),
            Substitution(name: "chicken or beef stock", explanation: "For batters and braises."),
        ]),
        ("wine", [
            Substitution(name: "stock + a splash of vinegar", explanation: "Recommended — savoury depth plus acidity."),
            Substitution(name: "grape juice + vinegar", explanation: "Keeps the fruity note, no alcohol."),
        ]),
        ("vodka", [
            Substitution(name: "water + a squeeze of lemon", explanation: "For vodka pasta sauce — keeps it loose and bright."),
        ]),
        ("rum", [
            Substitution(name: "apple juice + a little vanilla", explanation: "Sweet, aromatic stand-in for baking."),
        ]),
        // — Dairy (vegan, dairy-free) —
        ("butter", [
            Substitution(name: "vegan butter", explanation: "1:1 swap for cooking and baking."),
            Substitution(name: "olive oil", explanation: "For savoury cooking — use about ¾ the amount."),
            Substitution(name: "coconut oil", explanation: "Solid like butter, slight coconut note."),
        ]),
        ("milk", [
            Substitution(name: "oat milk", explanation: "Creamiest neutral swap — the recommended one."),
            Substitution(name: "soy milk", explanation: "Higher protein, works in savoury and baking."),
            Substitution(name: "almond milk", explanation: "Lighter, mild nutty note."),
        ]),
        ("cheese", [
            Substitution(name: "vegan cheese", explanation: "Melts and shreds like the real thing."),
            Substitution(name: "nutritional yeast", explanation: "For a cheesy, savoury flavour in sauces."),
        ]),
        ("cream", [
            Substitution(name: "coconut cream", explanation: "Rich and thick — the go-to dairy-free swap."),
            Substitution(name: "cashew cream", explanation: "Neutral and silky when blended."),
        ]),
        ("yogurt", [
            Substitution(name: "coconut yogurt", explanation: "Same tang and body, dairy-free."),
            Substitution(name: "soy yogurt", explanation: "Higher protein alternative."),
        ]),
        // — Egg (vegan) —
        ("egg", [
            Substitution(name: "flax egg (1 tbsp ground flax + 3 tbsp water)", explanation: "Best for binding in baking."),
            Substitution(name: "unsweetened applesauce (¼ cup)", explanation: "Adds moisture — great in cakes."),
            Substitution(name: "mashed banana (½ banana)", explanation: "Binds and sweetens lightly."),
        ]),
        // — Gluten (gluten-free) —
        ("soy sauce", [
            Substitution(name: "tamari", explanation: "Same flavour, naturally gluten-free."),
            Substitution(name: "coconut aminos", explanation: "Slightly sweeter, soy- and gluten-free."),
        ]),
        ("flour", [
            Substitution(name: "gluten-free flour blend", explanation: "1:1 swap designed for baking."),
            Substitution(name: "almond flour", explanation: "For denser bakes — adjust liquid."),
        ]),
        ("pasta", [
            Substitution(name: "gluten-free pasta", explanation: "Same dish; watch the cook time."),
            Substitution(name: "rice noodles", explanation: "Naturally gluten-free."),
        ]),
        ("bread crumbs", [
            Substitution(name: "gluten-free bread crumbs", explanation: "Direct swap for coating and binding."),
            Substitution(name: "crushed cornflakes", explanation: "Crunchy, gluten-free coating."),
        ]),
        // — Nuts (nut allergy / nut-free) —
        ("peanut", [
            Substitution(name: "sunflower seed butter", explanation: "Same creamy texture, nut-free."),
            Substitution(name: "roasted chickpeas", explanation: "For crunch without nuts."),
        ]),
        ("almond", [
            Substitution(name: "sunflower seeds", explanation: "Similar crunch, nut-free."),
            Substitution(name: "pumpkin seeds", explanation: "Toasty and nut-free."),
        ]),
        ("cashew", [
            Substitution(name: "sunflower seeds", explanation: "Blends into a creamy base, nut-free."),
        ]),
        // — Shellfish / fish (allergy, some diets) —
        ("shrimp", [
            Substitution(name: "chicken breast", explanation: "Similar quick-cook protein."),
            Substitution(name: "firm tofu", explanation: "Plant-based, soaks up the sauce."),
        ]),
    ]

    /// Diet/allergy-driven substitutions for a conflicting ingredient, best pick
    /// first. Every suggestion is re-checked against the user's own rules and
    /// allergies so we never trade one violation for another (e.g. no turkey for
    /// a vegetarian). Falls back to the general culinary table when there's no
    /// dedicated diet entry.
    static func dietSubstitutions(
        for ingredientName: String,
        rules: [DietaryRule],
        allergies: [String]
    ) -> [Substitution] {
        let canonical = IngredientCanonicalizer.canonicalize(ingredientName)
        // Most specific keyword first ("ground pork" before "pork").
        let matches = dietTable
            .filter { canonical.contains($0.keyword) }
            .sorted { $0.keyword.count > $1.keyword.count }

        var seen = Set<String>()
        var result: [Substitution] = []
        for entry in matches {
            for sub in entry.subs where !seen.contains(sub.name) {
                // Keep only swaps that are themselves compliant.
                let compliant = sub.name
                    .split(whereSeparator: { $0 == "+" || $0 == "(" })
                    .first
                    .map(String.init)
                    .map { DietGuard.isAllowed(ingredientName: $0, rules: rules, allergies: allergies) } ?? true
                guard compliant else { continue }
                seen.insert(sub.name)
                result.append(sub)
            }
        }
        if result.isEmpty {
            // Fall back to general swaps, still filtered for compliance.
            result = substitutions(for: ingredientName).filter {
                DietGuard.isAllowed(ingredientName: $0.name, rules: rules, allergies: allergies)
            }
        }
        return Array(result.prefix(3))
    }

    static func substitutions(for ingredientName: String) -> [Substitution] {
        let canonical = IngredientCanonicalizer.canonicalize(ingredientName)
        if let direct = table[canonical] { return direct }
        // Try last-word lookup: "fresh lemon juice" -> "lemon"
        if let lastWord = canonical.split(separator: " ").last.map(String.init),
           let byWord = table[lastWord] {
            return byWord
        }
        return []
    }

    static func isEssential(_ ingredientName: String) -> Bool {
        let canonical = IngredientCanonicalizer.canonicalize(ingredientName)
        return doNotSubstitute.contains { canonical.contains($0) }
    }

    /// Substitutions the user can actually make right now with their pantry —
    /// and that don't trade one problem for another (rules, allergies).
    static func availableSubstitutions(
        for ingredientName: String,
        pantry: [PantryItem],
        rules: [DietaryRule] = [],
        allergies: [String] = []
    ) -> [Substitution] {
        substitutions(for: ingredientName).filter { substitution in
            // Compound subs ("Greek yogurt + butter") need every part.
            let parts = substitution.name.split(separator: "+").map(String.init)
            return parts.allSatisfy { part in
                let canonical = IngredientCanonicalizer.canonicalize(part)
                return PantryMatcher.owns(ingredientNamed: canonical, available: pantry.filter { $0.roughQuantity != .out })
                    && DietGuard.isAllowed(ingredientName: part, rules: rules, allergies: allergies)
            }
        }
    }
}
