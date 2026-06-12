import SwiftData
import SwiftUI

/// "What should I cook?" — two quick questions, then 3-4 real options
/// from the user's own library, ranked by pantry, time, mood, and history.
struct WhatToCookView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var recipes: [Recipe]
    @Query private var pantryItems: [PantryItem]
    @Query private var leftovers: [Leftover]
    @Query private var sessions: [CookSession]

    @State private var maxMinutes: Int?
    @State private var mood: MealRecommender.Mood = .any
    @State private var recommendations: [MealRecommender.Recommendation]?
    @State private var planningRecipe: Recipe?

    private static let timeOptions: [(label: String, minutes: Int?)] = [
        ("Any", nil), ("15 min", 15), ("30 min", 30), ("45 min", 45), ("1 hr+", 90),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    questionCard

                    if let recommendations {
                        if recommendations.isEmpty {
                            EmptyStateView(
                                icon: "sparkles",
                                title: "Nothing fits",
                                message: "Try loosening the time limit or mood — or import more recipes."
                            )
                        } else {
                            ForEach(recommendations) { recommendation in
                                recommendationCard(recommendation)
                            }
                            Button("Shuffle") {
                                generate()
                            }
                            .buttonStyle(.gluttSecondary)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("What should I cook?")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $planningRecipe) { recipe in
                AddMealSheet(day: Calendar.current.startOfDay(for: .now), fixedRecipe: recipe)
            }
            // Show options immediately; the questions refine from there.
            .onAppear {
                if recommendations == nil {
                    generate()
                }
            }
        }
    }

    // MARK: - Questions

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("How much time do you have?")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Self.timeOptions, id: \.label) { option in
                        selectableChip(option.label, isSelected: maxMinutes == option.minutes) {
                            maxMinutes = option.minutes
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("In the mood for…")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(MealRecommender.Mood.allCases) { option in
                            selectableChip(option.rawValue, isSelected: mood == option) {
                                mood = option
                            }
                        }
                    }
                }
            }

            Button("Update options") {
                generate()
            }
            .buttonStyle(.gluttSecondary)
            .disabled(recipes.isEmpty)
        }
        .cardStyle()
    }

    private func selectableChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.gluttCaption.weight(.medium))
                .foregroundStyle(isSelected ? .white : Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.08))
                .clipShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results

    private func recommendationCard(_ recommendation: MealRecommender.Recommendation) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(recommendation.badge.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.Colors.accent)
                Spacer()
                if recommendation.missingCount == 0 {
                    Label("Ready now", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.Colors.accent)
                } else {
                    Text("^[\(recommendation.missingCount) item](inflect: true) missing")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.warning)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                RecipeImageView(recipe: recommendation.recipe)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.recipe.title)
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    Label("\(recommendation.recipe.totalMinutes) min", systemImage: "clock")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
            }

            if !recommendation.reasons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(recommendation.reasons, id: \.self) { reason in
                            Chip(label: reason)
                                .fixedSize()
                        }
                    }
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                NavigationLink(value: recommendation.recipe) {
                    Text("Open recipe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttSecondary)
                Button("Add to plan") {
                    planningRecipe = recommendation.recipe
                }
                .buttonStyle(.gluttSecondary)
            }
        }
        .cardStyle()
    }

    private func generate() {
        let prefs = UserPrefs.current(in: context)
        recommendations = MealRecommender.recommend(MealRecommender.Request(
            maxMinutes: maxMinutes,
            mood: mood,
            recipes: recipes,
            pantry: pantryItems,
            leftovers: leftovers,
            sessions: sessions,
            tasteProfile: prefs.tasteProfile
        ))
    }
}
