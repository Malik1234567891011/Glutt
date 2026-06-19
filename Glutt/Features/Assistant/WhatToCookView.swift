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
    @Query(sort: \FoodLog.timestamp, order: .reverse) private var logs: [FoodLog]

    @State private var maxMinutes: Int?
    @State private var mood: MealRecommender.Mood = .any
    @State private var mealSlot: MealRecommender.MealSlot = .current()
    @State private var recommendations: [MealRecommender.Recommendation]?
    @State private var planningRecipe: Recipe?
    @State private var askText = ""
    @State private var isAsking = false
    @State private var headline: String?
    @State private var isInventing = false
    @State private var inventedDraft: ImportedRecipeDraft?
    @State private var inventError: String?

    private static let timeOptions: [(label: String, minutes: Int?)] = [
        ("Any", nil), ("15 min", 15), ("30 min", 30), ("45 min", 45), ("1 hr+", 90),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    askCard
                    if canInvent {
                        inventCard
                    }
                    questionCard

                    if isAsking {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView()
                            Text("Thinking about your kitchen…")
                                .font(.gluttCaption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                    }

                    if let headline {
                        Text(headline)
                            .font(.gluttHeadline)
                            .foregroundStyle(Theme.Colors.accent)
                    }

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
            .sheet(item: $inventedDraft) { draft in
                NavigationStack {
                    ImportReviewView(draft: draft) { inventedDraft = nil }
                        .navigationTitle("Your new recipe")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { inventedDraft = nil }
                            }
                        }
                }
            }
            .alert("Couldn't invent a dish", isPresented: Binding(
                get: { inventError != nil },
                set: { if !$0 { inventError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(inventError ?? "")
            }
            // Show options immediately; the questions refine from there.
            .onAppear {
                if recommendations == nil {
                    generate()
                }
            }
        }
    }

    // MARK: - Ask anything

    /// The "just say it" path: type what you're feeling, get real options.
    private var askCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Just tell me")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            HStack(spacing: Theme.Spacing.sm) {
                TextField("\"something quick and savory with chicken\"", text: $askText, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .onSubmit(ask)
                Button(action: ask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(
                            askText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.Colors.border : Theme.Colors.accent
                        )
                }
                .disabled(askText.trimmingCharacters(in: .whitespaces).isEmpty || isAsking)
            }
        }
        .cardStyle()
    }

    // MARK: - Invent from pantry

    private var onHandItems: [PantryItem] {
        pantryItems.filter { $0.roughQuantity != .out }
    }

    private var canInvent: Bool {
        LLMClient.isConfigured && onHandItems.count >= 2
    }

    /// Create something new from scratch using what's in the kitchen —
    /// distinct from matching saved recipes.
    private var inventCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accent)
                Text("Invent a dish from what I have")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            Text("A brand-new recipe built around your \(pantryPreview) — not one of your saved ones.")
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                invent()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if isInventing { ProgressView().tint(.white) }
                    Text(isInventing ? "Cooking up an idea…" : "Make something new")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.gluttPrimary)
            .disabled(isInventing)
        }
        .cardStyle()
    }

    private var pantryPreview: String {
        let names = onHandItems
            .sorted { ($0.useSoonDate != nil ? 0 : 1) < ($1.useSoonDate != nil ? 0 : 1) }
            .prefix(3)
            .map { $0.name.lowercased() }
        switch names.count {
        case 0: return "ingredients"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]), and more"
        }
    }

    private func invent() {
        guard !isInventing else { return }
        // Premium gate: AI recipe invention is a paid feature. The gated
        // `invent_recipe` placement only runs this block for subscribers
        // (or after they subscribe); non-subscribers see the paywall instead.
        InventionPaywallHook.presentBeforeInventing {
            isInventing = true
            let prefs = UserPrefs.current(in: context)
            let hint = askText.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                let draft = await PantryChef.invent(
                    pantry: pantryItems,
                    prefs: prefs,
                    hint: hint.isEmpty ? nil : hint,
                    maxMinutes: maxMinutes
                )
                isInventing = false
                if let draft {
                    inventedDraft = draft
                } else {
                    inventError = "Glutt couldn't spin up a dish from your pantry right now. Add a few more items, or try again."
                }
            }
        }
    }

    private func ask() {
        let query = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isAsking else { return }
        isAsking = true
        headline = nil
        recommendations = nil
        let prefs = UserPrefs.current(in: context)
        Task {
            let answer = await AskGlutt.ask(
                query: query,
                recipes: recipes,
                pantry: pantryItems,
                leftovers: leftovers,
                sessions: sessions,
                prefs: prefs
            )
            recommendations = answer.recommendations
            headline = answer.headline
            isAsking = false
        }
    }

    // MARK: - Questions

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Cooking for…")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(MealRecommender.MealSlot.allCases) { slot in
                            selectableChip(slot.rawValue, isSelected: mealSlot == slot) {
                                mealSlot = slot
                                generate()
                            }
                        }
                    }
                }
            }

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
                    Label(recommendation.recipe.timeLabel, systemImage: "clock")
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

    private var eatenTodayTitles: [String] {
        let today = Calendar.current.startOfDay(for: .now)
        return logs
            .filter { Calendar.current.startOfDay(for: $0.timestamp) == today }
            .map { $0.title.lowercased() }
    }

    private func generate() {
        headline = nil
        let prefs = UserPrefs.current(in: context)
        recommendations = MealRecommender.recommend(MealRecommender.Request(
            maxMinutes: maxMinutes,
            mood: mood,
            mealSlot: mealSlot,
            recipes: recipes,
            pantry: pantryItems,
            leftovers: leftovers,
            sessions: sessions,
            tasteProfile: prefs.tasteProfile,
            rules: prefs.dietaryRules,
            allergies: prefs.allergies,
            eatenTodayTitles: eatenTodayTitles
        ))
    }
}
