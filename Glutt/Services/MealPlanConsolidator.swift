import Foundation

/// Folds a week's recipes into one shopping list.
///
/// This is the piece that makes a plan feel like a single shop rather than five
/// recipes stapled together. Names go through `IngredientCanonicalizer`, so
/// "yellow onion" and "onion" are one line; quantities are summed when the
/// units agree; the pantry is subtracted; and every line remembers which meals
/// asked for it, which is where "used in 3 of your 5 meals" comes from.
///
/// Pure and synchronous on purpose. It runs after every swap, so it has to be
/// cheap, and its behaviour is the invariant worth unit-testing.
enum MealPlanConsolidator {

    /// One merged line of the shop.
    struct Line: Equatable, Identifiable {
        var id: String { canonicalName }
        var name: String
        var canonicalName: String
        var quantity: Double?
        var unit: String?
        var category: GroceryCategory
        /// Only when every recipe that wants it marked it optional.
        var isOptional: Bool
        /// Meals that need this line, in plan order.
        var recipeTitles: [String]
        /// The pantry already covers it, so it stays off the shopping list.
        var alreadyHave: Bool

        /// How many of the week's meals use it.
        var mealCount: Int { recipeTitles.count }

        /// "Used in 3 meals" / "Used in 1 meal". Nil for a line only one meal
        /// wants, where the phrase adds nothing.
        var sharedLabel: String? {
            guard mealCount > 1 else { return nil }
            return "Used in \(mealCount) meals"
        }

        var displayQuantity: String? {
            guard let quantity else { return nil }
            return UnitConverter.format(quantity: quantity, unit: unit)
        }
    }

    /// What a swap or a refinement did to the list. Empty on both sides means
    /// the shop did not move, which is the outcome a swap is supposed to have.
    struct Change: Equatable {
        var added: [String] = []
        var removed: [String] = []

        var isEmpty: Bool { added.isEmpty && removed.isEmpty }

        /// One sentence for the cook. Nil when nothing moved, so the caller can
        /// show "Your shopping list didn't change" itself.
        var summary: String? {
            switch (added.isEmpty, removed.isEmpty) {
            case (true, true):
                return nil
            case (false, true):
                return "Added to your list: \(added.joined(separator: ", "))"
            case (true, false):
                return "No longer needed: \(removed.joined(separator: ", "))"
            case (false, false):
                return "Added \(added.joined(separator: ", ")). "
                    + "No longer needed: \(removed.joined(separator: ", "))"
            }
        }
    }

    /// "Salt and pepper to taste" is an instruction, not a thing to buy.
    ///
    /// Bare `salt` and `pepper` are already handled: they canonicalize cleanly
    /// and the assumed-staples check marks them `alreadyHave`, so they sit
    /// dimmed under "already in your kitchen" where they belong. The compound
    /// phrasing defeats that, because "salt and pepper to taste" canonicalizes
    /// to itself and matches no staple, so it lands on the shopping list under
    /// Produce with no quantity beside it, reading like something to pick up.
    ///
    /// Worth dropping outright rather than papering over: it eats a slot, and
    /// the cook now sets a ceiling. Someone who asked for ten things they can
    /// grab quickly has not spent one of them on seasoning they own. The line
    /// stays in the recipe, which is the only place it means anything.
    private static func isSeasoningToTaste(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("to taste")
    }

    // MARK: - Consolidate

    /// Merges the meals' ingredients into one list, ordered by aisle and then
    /// by how many meals share the line (the shared staples read first, because
    /// they are the reason the list is short).
    static func consolidate(meals: [WeekPlanner.Meal], pantry: [PantryItem] = []) -> [Line] {
        let onHand = pantry.filter { $0.roughQuantity != .out }

        var order: [String] = []
        var merged: [String: Line] = [:]

        for meal in meals {
            // A recipe that lists the same thing twice ("1 onion", "1 onion,
            // sliced") should not claim two of the five meals.
            var seenInThisMeal = Set<String>()

            for raw in meal.ingredientLines {
                let parsed = IngredientLineParser.parse(raw)
                let name = parsed.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let canonical = IngredientCanonicalizer.canonicalize(name)
                guard !canonical.isEmpty else { continue }
                guard !isSeasoningToTaste(name) else { continue }

                let isOptional = "\(raw) \(parsed.note ?? "")"
                    .localizedCaseInsensitiveContains("optional")

                // "yellow onion" and "onion" are one line, the same way the
                // pantry already treats them as one thing. Canonicalizing alone
                // doesn't get there: it strips prep words, not varieties.
                let key = order.first { sameThing($0, canonical) } ?? canonical

                guard var line = merged[key] else {
                    order.append(canonical)
                    merged[canonical] = Line(
                        name: name,
                        canonicalName: canonical,
                        quantity: parsed.quantity,
                        unit: parsed.unit,
                        category: GroceryCategorizer.categorize(name),
                        isOptional: isOptional,
                        recipeTitles: [meal.title],
                        alreadyHave: PantryMatcher.owns(
                            ingredientNamed: canonical, available: onHand
                        )
                    )
                    seenInThisMeal.insert(canonical)
                    continue
                }

                // The shortest spelling reads best on a shopping list: "onion"
                // beats "large yellow onion" when both mean the same thing.
                if name.count < line.name.count { line.name = name }
                if canonical.count < line.canonicalName.count { line.canonicalName = canonical }
                // A variant may be the one the pantry actually covers.
                line.alreadyHave = line.alreadyHave
                    || PantryMatcher.owns(ingredientNamed: canonical, available: onHand)

                if !seenInThisMeal.contains(key) {
                    line.recipeTitles.append(meal.title)
                    seenInThisMeal.insert(key)
                }

                switch (line.quantity, parsed.quantity) {
                case let (have?, add?)
                    where GroceryListBuilder.normalizedUnit(line.unit)
                        == GroceryListBuilder.normalizedUnit(parsed.unit):
                    line.quantity = have + add
                case (_?, _?):
                    // "2 cups" plus "1 lb" is not a number we can honestly show,
                    // so the line goes out without one rather than with a lie.
                    line.quantity = nil
                    line.unit = nil
                case (nil, _), (_, nil):
                    line.quantity = nil
                    line.unit = nil
                }

                // Optional only survives while every recipe treats it that way.
                line.isOptional = line.isOptional && isOptional
                merged[key] = line
            }
        }

        let lines = order.compactMap { merged[$0] }
        return sorted(lines)
    }

    /// Whether two canonical names name the same shoppable thing.
    ///
    /// Mirrors the rule `PantryMatcher.item(covering:in:)` already uses, and for
    /// the same reason: food names put the head noun last, so a shared head plus
    /// a subset of the words means one name is the other narrowed down. "onion"
    /// covers "yellow onion", "rice" covers "white rice", and neither "rice
    /// vinegar" nor "chicken broth" gets folded into its head ingredient.
    private static func sameThing(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let wordsA = a.split(separator: " ").map(String.init)
        let wordsB = b.split(separator: " ").map(String.init)
        guard let headA = wordsA.last, let headB = wordsB.last, headA == headB else { return false }
        let setA = Set(wordsA), setB = Set(wordsB)
        return setA.isSubset(of: setB) || setB.isSubset(of: setA)
    }

    /// Aisle order first (that is how the shop is walked), then the shared items
    /// inside each aisle, then alphabetical so the order is stable.
    private static func sorted(_ lines: [Line]) -> [Line] {
        let aisle = Dictionary(
            uniqueKeysWithValues: GroceryCategory.allCases.enumerated().map { ($1, $0) }
        )
        return lines.sorted { a, b in
            if a.alreadyHave != b.alreadyHave { return !a.alreadyHave }
            let ia = aisle[a.category] ?? 0, ib = aisle[b.category] ?? 0
            if ia != ib { return ia < ib }
            if a.mealCount != b.mealCount { return a.mealCount > b.mealCount }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Diff

    /// What changed between two versions of the list. Only lines the cook has
    /// to buy count: gaining or losing something already in the pantry is not a
    /// change to the shop.
    static func diff(before: [Line], after: [Line]) -> Change {
        let old = before.filter { !$0.alreadyHave }
        let new = after.filter { !$0.alreadyHave }
        let oldKeys = Set(old.map(\.canonicalName))
        let newKeys = Set(new.map(\.canonicalName))
        return Change(
            added: new.filter { !oldKeys.contains($0.canonicalName) }.map(\.name),
            removed: old.filter { !newKeys.contains($0.canonicalName) }.map(\.name)
        )
    }
}
