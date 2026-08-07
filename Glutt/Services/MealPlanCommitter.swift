import Foundation
import SwiftData

/// Turns an accepted week plan into things the rest of the app already knows
/// how to use: five ordinary `Recipe` rows, one `RecipeCollection` grouping
/// them, one `MealPlan` receipt, and the consolidated list pushed into
/// `GroceryItem` with `sourceRecipeTitles` filled in, so the Groceries screen
/// shows which meals need each item without knowing plans exist.
///
/// Idempotent by `WeekPlanner.Plan.id`. Committing again after a swap updates
/// the same collection and the same list instead of stacking a second week on
/// top of the first.
@MainActor
enum MealPlanCommitter {

    @discardableResult
    static func commit(
        _ plan: WeekPlanner.Plan,
        lines: [MealPlanConsolidator.Line],
        name: String,
        in context: ModelContext
    ) -> MealPlan {
        let planName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? defaultName()
            : name.trimmingCharacters(in: .whitespaces)

        let record = existingPlan(id: plan.id, in: context)
            ?? {
                let created = MealPlan(planID: plan.id, name: planName)
                context.insert(created)
                return created
            }()

        // Titles this plan has ever claimed. Anything carrying one of these is
        // the plan's to update or clean up; anything else is the cook's own.
        let previousTitles = record.mealTitles
        let currentTitles = plan.meals.map(\.title)
        let ownedTitles = Set(previousTitles).union(currentTitles)

        record.name = planName
        record.servingsPerMeal = plan.request.servings
        record.mealCount = plan.meals.count
        record.budgetTarget = plan.request.budgetTarget
        record.ingredientTarget = plan.request.ingredientTarget
        record.estimatedCostLow = plan.cost?.low
        record.estimatedCostHigh = plan.cost?.high
        record.notes = plan.request.notes
        record.mealTitles = currentTitles

        let collection = resolveCollection(named: planName, for: record, in: context)
        record.collection = collection

        syncRecipes(plan.meals, into: collection, in: context)
        syncLines(lines, on: record, in: context)
        syncGroceries(lines, ownedTitles: ownedTitles, in: context)

        return record
    }

    /// "Week of Aug 6" — the name the collection carries into the Recipes tab.
    static func defaultName(on date: Date = .now) -> String {
        "Week of " + date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Pieces

    /// Filtered in memory rather than through a `#Predicate`, the way
    /// `RecipeSync` matches on `remoteID`: a UUID comparison is the one shape
    /// the predicate compiler is unreliable about, and a cook has a handful of
    /// plans, not thousands.
    static func existingPlan(id: UUID, in context: ModelContext) -> MealPlan? {
        let all = (try? context.fetch(FetchDescriptor<MealPlan>())) ?? []
        return all.first { $0.planID == id }
    }

    private static func resolveCollection(
        named name: String,
        for record: MealPlan,
        in context: ModelContext
    ) -> RecipeCollection {
        if let existing = record.collection {
            existing.name = name
            return existing
        }
        let all = (try? context.fetch(FetchDescriptor<RecipeCollection>())) ?? []
        if let match = all.first(where: { $0.name == name }) { return match }
        let created = RecipeCollection(name: name)
        context.insert(created)
        return created
    }

    /// Recipes are matched to meals by title. A meal that is still in the plan
    /// keeps its recipe (and everything the cook has done to it); a meal that
    /// was swapped away leaves, unless it was favorited, which is the cook
    /// saying they want to keep it whatever happens to the plan.
    private static func syncRecipes(
        _ meals: [WeekPlanner.Meal],
        into collection: RecipeCollection,
        in context: ModelContext
    ) {
        let wanted = Set(meals.map(\.title))
        for recipe in Array(collection.recipes) where !wanted.contains(recipe.title) {
            collection.recipes.removeAll { $0 === recipe }
            if !recipe.isFavorite { context.delete(recipe) }
        }

        let present = Set(collection.recipes.map(\.title))
        for meal in meals where !present.contains(meal.title) {
            let recipe = RecipeFactory.make(from: meal.draft)
            // The parser doesn't always catch a trailing "(optional)".
            for ingredient in recipe.ingredients {
                let blob = "\(ingredient.name) \(ingredient.note ?? "")".lowercased()
                if blob.contains("optional") { ingredient.isOptional = true }
            }
            context.insert(recipe)
            collection.recipes.append(recipe)
        }
    }

    /// The plan's own copy of the list, replaced wholesale. It is a snapshot of
    /// one shop, small, and never diffed against itself.
    private static func syncLines(
        _ lines: [MealPlanConsolidator.Line],
        on record: MealPlan,
        in context: ModelContext
    ) {
        for line in record.lines { context.delete(line) }
        record.lines = lines.enumerated().map { index, line in
            let row = MealPlanLine(
                name: line.name,
                quantity: line.quantity,
                unit: line.unit,
                category: line.category,
                isOptional: line.isOptional,
                recipeTitles: line.recipeTitles,
                alreadyHave: line.alreadyHave,
                sortIndex: index
            )
            context.insert(row)
            return row
        }
    }

    /// Pushes the shop into the real grocery list.
    ///
    /// Existing rows the plan put there are cleared first (identified by the
    /// meal titles they were tagged with) so a re-commit updates rather than
    /// duplicates, while a row the cook typed themselves, or one another recipe
    /// also wants, is left alone.
    private static func syncGroceries(
        _ lines: [MealPlanConsolidator.Line],
        ownedTitles: Set<String>,
        in context: ModelContext
    ) {
        var survivors: [GroceryItem] = []
        for item in (try? context.fetch(FetchDescriptor<GroceryItem>())) ?? [] {
            if item.sourceRecipeTitles.contains(where: ownedTitles.contains) {
                item.sourceRecipeTitles.removeAll(where: ownedTitles.contains)
                if item.sourceRecipeTitles.isEmpty {
                    context.delete(item)
                    continue
                }
            }
            survivors.append(item)
        }

        for line in lines where !line.alreadyHave {
            if let match = survivors.first(where: { $0.canonicalName == line.canonicalName && !$0.isChecked }) {
                match.quantity = line.quantity
                match.unit = line.unit
                for title in line.recipeTitles where !match.sourceRecipeTitles.contains(title) {
                    match.sourceRecipeTitles.append(title)
                }
                continue
            }
            let item = GroceryItem(
                name: line.name,
                category: line.category,
                isOptional: line.isOptional,
                substitutionHint: SubstitutionService.substitutions(for: line.name).first?.name,
                sourceRecipeTitles: line.recipeTitles
            )
            item.quantity = line.quantity
            item.unit = line.unit
            context.insert(item)
            survivors.append(item)
        }
    }
}
