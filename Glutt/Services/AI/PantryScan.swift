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
        You identify food items in a photo of someone's fridge, pantry, or counter.
        Return JSON: {"items": [{"name": str, "quantity": "full"|"half"|"low", "category": str}]}

        Rules:
        - name: the generic grocery name, singular where natural ("milk", "eggs", "chicken thighs"). No brands.
        - Only food and drink. Skip containers you can't identify, condiment packets, and anything you're not reasonably sure about.
        - quantity: how much appears to be left, your best guess. Default "full".
        - category: one of produce, meat, dairy, pantry, frozen, spices, other.
        - Max 25 items. If there is no food in the photo, return {"items": []}.
        """

        let response = try await LLMClient.chatJSON(
            Response.self,
            system: system,
            user: "What food items are in this photo?",
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
