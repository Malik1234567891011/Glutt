import SwiftData
import SwiftUI

/// "Turn this into something else" — transformation ideas for a leftover,
/// personalized by the AI when available, sensible table otherwise.
struct LeftoverRemixSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantryItems: [PantryItem]
    @Query private var groceryItems: [GroceryItem]

    let leftover: Leftover

    @State private var ideas: [LeftoverRemix.Idea]?
    @State private var plannedIdea: LeftoverRemix.Idea?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if let ideas {
                        ForEach(ideas) { idea in
                            ideaCard(idea)
                        }
                    } else {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView()
                            Text("Thinking about your \(leftover.title.lowercased())…")
                                .font(.gluttCaption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xl)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Remix “\(leftover.title)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                let prefs = UserPrefs.current(in: context)
                ideas = await LeftoverRemix.ideas(
                    for: leftover,
                    pantry: pantryItems,
                    rules: prefs.dietaryRules,
                    allergies: prefs.allergies
                )
            }
        }
    }

    private func ideaCard(_ idea: LeftoverRemix.Idea) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(idea.title)
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(idea.how)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)

            if !idea.needs.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Needs:")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    ForEach(idea.needs, id: \.self) { need in
                        Chip(label: need)
                            .fixedSize()
                    }
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                if plannedIdea == idea {
                    Label("On tomorrow's plan", systemImage: "checkmark.circle.fill")
                        .font(.gluttCaption.weight(.medium))
                        .foregroundStyle(Theme.Colors.accent)
                } else {
                    Button("Plan for tomorrow") {
                        plan(idea)
                    }
                    .buttonStyle(.gluttPillFilled)
                }
                if !missingNeeds(for: idea).isEmpty {
                    Button("Add needs to list") {
                        addNeeds(for: idea)
                    }
                    .buttonStyle(.gluttPill)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// Needs the user doesn't already have in the pantry.
    private func missingNeeds(for idea: LeftoverRemix.Idea) -> [String] {
        let available = pantryItems.filter { $0.roughQuantity != .out }
        return idea.needs.filter { need in
            !PantryMatcher.owns(
                ingredientNamed: IngredientCanonicalizer.canonicalize(need),
                available: available
            )
        }
    }

    private func plan(_ idea: LeftoverRemix.Idea) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let meal = PlannedMeal(
            date: tomorrow,
            mealType: .lunch,
            leftover: leftover,
            freeformTitle: "\(idea.title) (from \(leftover.title))"
        )
        context.insert(meal)
        plannedIdea = idea
    }

    private func addNeeds(for idea: LeftoverRemix.Idea) {
        let ingredients = missingNeeds(for: idea).enumerated().map { index, need in
            RecipeIngredient(name: need, sortIndex: index)
        }
        GroceryListBuilder.add(
            ingredients: ingredients,
            from: nil,
            existing: groceryItems,
            context: context
        )
    }
}
