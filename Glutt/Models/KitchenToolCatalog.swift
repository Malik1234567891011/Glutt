import Foundation

/// The preset equipment catalog powering the Kitchen › Tools checklist, and the
/// vocabulary used to detect which tools a recipe needs (for the "missing gear"
/// badge). Grouped; order defines display order.
enum KitchenToolCatalog {
    static let groups: [(category: String, tools: [String])] = [
        ("Appliances", [
            "Oven", "Stovetop", "Microwave", "Air fryer", "Slow cooker",
            "Pressure cooker", "Blender", "Immersion blender", "Food processor",
            "Stand mixer", "Hand mixer", "Rice cooker", "Toaster", "Toaster oven",
            "Deep fryer", "Waffle iron", "Griddle", "Sous vide", "Electric kettle",
        ]),
        ("Cookware", [
            "Cast iron skillet", "Nonstick pan", "Stainless steel pan", "Saucepan",
            "Stockpot", "Dutch oven", "Sheet pan", "Baking dish", "Wok", "Grill pan",
            "Roasting pan", "Muffin tin", "Loaf pan", "Cake pan", "Springform pan",
            "Pie dish", "Ramekins", "Steamer basket", "Griddle pan",
        ]),
        ("Tools", [
            "Chef's knife", "Paring knife", "Cutting board", "Mixing bowls",
            "Whisk", "Tongs", "Spatula", "Wooden spoon", "Ladle", "Peeler",
            "Kitchen scale", "Measuring cups", "Measuring spoons", "Box grater",
            "Microplane", "Colander", "Fine mesh sieve", "Rolling pin",
            "Thermometer", "Mortar and pestle", "Mandoline", "Kitchen shears",
            "Pastry brush", "Can opener", "Salad spinner", "Potato masher",
        ]),
    ]

    static let all: [String] = groups.flatMap(\.tools)

    /// Lowercased preset names — used to tell presets from custom tools.
    static let canonicalAll: Set<String> = Set(all.map { $0.lowercased() })

    static func category(for tool: String) -> String {
        let lower = tool.lowercased()
        return groups.first { group in
            group.tools.contains { $0.lowercased() == lower }
        }?.category ?? "Custom"
    }

    /// Keyword → tool, for detecting gear a recipe requires from its text.
    /// Only tools that meaningfully *gate* a recipe are worth flagging (nobody
    /// needs a "you need a chef's knife" warning), so universal basics are omitted.
    /// Each entry: the canonical tool name and the phrases that imply it.
    static let requirementKeywords: [(tool: String, phrases: [String])] = [
        ("Air fryer", ["air fryer", "air-fry", "air fry"]),
        ("Slow cooker", ["slow cooker", "crockpot", "crock pot", "crock-pot"]),
        ("Pressure cooker", ["pressure cooker", "instant pot", "instapot"]),
        ("Blender", ["blender", "blend until"]),
        ("Immersion blender", ["immersion blender", "stick blender", "hand blender"]),
        ("Food processor", ["food processor"]),
        ("Stand mixer", ["stand mixer"]),
        ("Hand mixer", ["hand mixer", "electric mixer", "electric hand"]),
        ("Rice cooker", ["rice cooker"]),
        ("Deep fryer", ["deep fryer", "deep-fry", "deep fry"]),
        ("Waffle iron", ["waffle iron", "waffle maker"]),
        ("Sous vide", ["sous vide", "sous-vide"]),
        ("Cast iron skillet", ["cast iron", "cast-iron"]),
        ("Dutch oven", ["dutch oven"]),
        ("Wok", ["wok"]),
        ("Grill pan", ["grill pan", "griddle"]),
        ("Sheet pan", ["sheet pan", "baking sheet"]),
        ("Muffin tin", ["muffin tin", "muffin pan", "cupcake tin"]),
        ("Loaf pan", ["loaf pan", "loaf tin"]),
        ("Springform pan", ["springform"]),
        ("Steamer basket", ["steamer basket", "steaming basket", "bamboo steamer"]),
        ("Mandoline", ["mandoline"]),
        ("Kitchen scale", ["kitchen scale", "weigh ", "weighing"]),
        ("Thermometer", ["thermometer", "instant-read", "instant read"]),
    ]

    /// Canonical names of tools a recipe requires, inferred from its text.
    static func requiredTools(inText text: String) -> [String] {
        let haystack = text.lowercased()
        return requirementKeywords.compactMap { entry in
            entry.phrases.contains(where: haystack.contains) ? entry.tool : nil
        }
    }
}
