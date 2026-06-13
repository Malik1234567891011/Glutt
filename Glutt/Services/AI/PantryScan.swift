import Foundation

/// Photo pantry scan: one photo of the fridge or pantry → candidate items
/// the user confirms before anything touches the inventory. Deliberately
/// humble for beta — no video, no exact quantities, no auto-commit.
enum PantryScan {

    struct ScannedItem: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var quantity: RoughQuantity
        var category: GroceryCategory
        /// Pre-checked for insertion; user can untoggle.
        var include: Bool = true
        /// Matches something already in the pantry — updates it instead of duplicating.
        var isAlreadyInPantry: Bool = false
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            let name: String
            let quantity: String?
            let category: String?
        }

        let items: [Item]
    }

    static func scan(imageData: Data, existingPantry: [PantryItem]) async throws -> [ScannedItem] {
        let system = """
        You identify food, drinks, and cooking ingredients in a photo of someone's kitchen,
        fridge, pantry, or counter — including packaged goods.

        CRITICAL: Read any visible text on bags, boxes, jars, cans, and labels to identify
        items. Many pantry staples are in packaging that doesn't look like raw food — protein
        powder, pasta, rice, flour, cereal, sauces, canned goods, spices, snacks, drinks. Use
        the label text to name them. Do NOT skip an item just because it's in a bag or box.

        Return JSON: {"items": [{"name": str, "quantity": "full"|"half"|"low", "category": str}]}

        Rules:
        - name: a useful generic grocery name. Keep the type/flavor when the label shows it and
          it matters for cooking ("whey protein powder", "marinara sauce", "basmati rice",
          "matcha latte protein powder"). Drop pure marketing words and brand names.
        - Include any edible or drinkable item or cooking ingredient, fresh OR packaged. Skip
          only clearly non-food things (cleaning supplies, utensils, dishware) and items whose
          label you truly cannot read or recognize.
        - quantity: how full the package/item looks, best guess. Default "full".
        - category: one of produce, meat, dairy, pantry, frozen, spices, other. Packaged dry
          goods, protein powder, canned goods, sauces, and snacks are "pantry".
        - Max 25 items. Only return {"items": []} if there is genuinely nothing edible or
          ingredient-like in the photo.
        """

        let response = try await LLMClient.chatJSON(
            Response.self,
            system: system,
            user: "Identify every food, drink, and grocery item here. Read the labels and packaging text to name packaged items.",
            imageData: imageData,
            timeout: 45
        )

        var seen = Set<String>()
        return response.items.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let canonical = IngredientCanonicalizer.canonicalize(name)
            guard seen.insert(canonical).inserted else { return nil }

            return ScannedItem(
                name: name,
                quantity: mapQuantity(item.quantity),
                category: mapCategory(item.category, name: name),
                isAlreadyInPantry: PantryMatcher.item(covering: canonical, in: existingPantry) != nil
            )
        }
    }

    /// Exposed for tests.
    static func mapQuantity(_ raw: String?) -> RoughQuantity {
        switch raw?.lowercased() {
        case "half": .half
        case "low": .low
        default: .full
        }
    }

    /// Exposed for tests. Trusts the model's category when valid, otherwise
    /// falls back to the keyword categorizer.
    static func mapCategory(_ raw: String?, name: String) -> GroceryCategory {
        if let raw, let category = GroceryCategory(rawValue: raw.lowercased()) {
            return category
        }
        return GroceryCategorizer.categorize(name)
    }
}
