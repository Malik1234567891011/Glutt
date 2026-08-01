import Foundation

/// Canonicalizes ingredient names so pantry matching works across naming variants
/// ("scallions" == "green onions", "chicken thighs, boneless" == "chicken thigh").
///
/// V1 approach: lowercase, strip preparation noise, singularize, then map through a synonym table.
/// Later phases can replace the synonym table with embedding-based matching without changing call sites.
enum IngredientCanonicalizer {

    static func canonicalize(_ raw: String) -> String {
        var name = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop preparation descriptors after a comma: "chicken thighs, boneless skinless"
        if let commaIndex = name.firstIndex(of: ",") {
            name = String(name[..<commaIndex])
        }

        // Strip common prep/quality words anywhere in the name. "ground" is
        // deliberately absent: it distinguishes real ingredients rather than
        // describing prep, so stripping it made ground beef indistinguishable
        // from a beef fillet.
        let noiseWords: Set<String> = [
            "fresh", "freshly", "large", "small", "medium", "chopped", "diced", "minced",
            "sliced", "grated", "shredded", "boneless", "skinless", "organic",
            "whole", "raw", "cooked", "frozen", "canned", "dried", "ripe", "of",
        ]
        name = name
            .split(separator: " ")
            .filter { !noiseWords.contains(String($0)) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        name = singularize(name)

        return synonyms[name] ?? name
    }

    /// Whether two ingredient names refer to the same thing.
    static func matches(_ a: String, _ b: String) -> Bool {
        canonicalize(a) == canonicalize(b)
    }

    private static func singularize(_ word: String) -> String {
        if word.hasSuffix("oes") { return String(word.dropLast(2)) } // tomatoes -> tomato
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" } // berries -> berry
        if word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    /// Synonym table mapping variants to one canonical form. Grows over time; seeded with common cases.
    private static let synonyms: [String: String] = [
        "scallion": "green onion",
        "spring onion": "green onion",
        "cilantro": "coriander",
        "coriander leave": "coriander",
        "garbanzo bean": "chickpea",
        "courgette": "zucchini",
        "aubergine": "eggplant",
        "capsicum": "bell pepper",
        "red pepper": "bell pepper",
        "green pepper": "bell pepper",
        "yoghurt": "yogurt",
        "greek yoghurt": "greek yogurt",
        "chicken thigh fillet": "chicken thigh",
        "chicken breast fillet": "chicken breast",
        "mince": "ground beef",
        "beef mince": "ground beef",
        "chicken mince": "ground chicken",
        "powdered sugar": "confectioners sugar",
        "icing sugar": "confectioners sugar",
        "caster sugar": "sugar",
        "granulated sugar": "sugar",
        "ap flour": "all-purpose flour",
        "plain flour": "all-purpose flour",
        "corn starch": "cornstarch",
        "corn flour": "cornstarch",
        "double cream": "heavy cream",
        "heavy whipping cream": "heavy cream",
        "single cream": "light cream",
        "stock": "broth",
        "chicken stock": "chicken broth",
        "beef stock": "beef broth",
        "vegetable stock": "vegetable broth",
    ]
}
