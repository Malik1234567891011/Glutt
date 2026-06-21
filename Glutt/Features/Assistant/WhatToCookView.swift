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
    @State private var inventMealType: MealType?
    @State private var inventHint = ""
    /// The current inline idea shown for review before saving.
    @State private var inventedDraft: ImportedRecipeDraft?
    /// Separate handle for the full review/save sheet.
    @State private var reviewDraft: ImportedRecipeDraft?
    /// Titles proposed this session, so "Something else" never repeats them.
    @State private var inventedTitles: [String] = []
    @State private var inventError: String?

    private static let timeOptions: [(label: String, minutes: Int?)] = [
        ("Any", nil), ("15 min", 15), ("30 min", 30), ("45 min", 45), ("1 hr+", 90),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    askCard
                    if LLMClient.isConfigured {
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
                                Haptics.impact(.medium)
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
            .sheet(item: $reviewDraft) { draft in
                NavigationStack {
                    ImportReviewView(draft: draft) {
                        reviewDraft = nil
                        inventedDraft = nil
                    }
                        .navigationTitle("Your new recipe")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { reviewDraft = nil }
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
                    .font(.gluttBody)
                    .lineLimit(1...3)
                    .onSubmit(ask)
                Button(action: ask) {
                    Ph.paperPlaneTilt.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(
                            askText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.Colors.border : Theme.Colors.accent
                        )
                }
                .disabled(askText.trimmingCharacters(in: .whitespaces).isEmpty || isAsking)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(Theme.Colors.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 1)
            )
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
    /// distinct from matching saved recipes. Always visible (when AI is on) so
    /// the feature is discoverable; the controls grey out until there's enough
    /// in the kitchen to cook with.
    private var inventCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Ph.magicWand.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(canInvent ? Theme.Colors.accent : Theme.Colors.textSecondary)
                Text("Invent a dish from what I have")
                    .font(.gluttHeadline)
                    .foregroundStyle(canInvent ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            }

            if canInvent {
                Text("A brand-new recipe built around your \(pantryPreview) — not one of your saved ones.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                inventControls

                if let draft = inventedDraft {
                    inventedPreview(draft)
                }
            } else {
                Text("Add a couple of things to your kitchen and Glutt will spin up an original recipe from what you have.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Button {
                } label: {
                    Text("Make something new")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttPrimary)
                .disabled(true)
            }
        }
        .cardStyle()
    }

    /// Meal-type chips + an optional free-text steer, then the generate button.
    private var inventControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    selectableChip("Any", isSelected: inventMealType == nil) {
                        inventMealType = nil
                    }
                    ForEach(MealType.allCases) { type in
                        selectableChip(type.label, isSelected: inventMealType == type) {
                            inventMealType = type
                        }
                    }
                }
            }

            TextField("Optional: \"feed 4\", \"something light\", \"quick & easy\"", text: $inventHint, axis: .vertical)
                .font(.gluttBody)
                .lineLimit(1...2)
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

            Button {
                Haptics.impact(.medium)
                invent(excludingCurrent: false)
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
    }

    /// Inline idea preview so the user can accept it or ask for another without
    /// committing to the full review/save screen first.
    private func inventedPreview(_ draft: ImportedRecipeDraft) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(draft.title ?? "New dish")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            if let summary = draft.summary, !summary.isEmpty {
                Text(summary)
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            HStack(spacing: Theme.Spacing.md) {
                if let servings = draft.servings {
                    Label("\(servings) servings", systemImage: "person.2")
                }
                let mins = (draft.prepMinutes ?? 0) + (draft.cookMinutes ?? 0)
                if mins > 0 {
                    Label("\(mins) min", systemImage: "clock")
                }
            }
            .font(.gluttCaption)
            .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    reviewDraft = draft
                } label: {
                    Text("Save this recipe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttSecondary)
                Button {
                    invent(excludingCurrent: true)
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        if isInventing { ProgressView() }
                        Text("Something else")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttSecondary)
                .disabled(isInventing)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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

    /// - Parameter excludingCurrent: when true (the "Something else" path), the
    ///   dish currently on screen is added to the avoid-list so the model is
    ///   forced to return a clearly different idea.
    private func invent(excludingCurrent: Bool) {
        guard !isInventing else { return }
        if excludingCurrent, let current = inventedDraft?.title {
            if !inventedTitles.contains(current) { inventedTitles.append(current) }
        }
        // Premium gate: AI recipe invention is a paid feature. The gated
        // `invent_recipe` placement only runs this block for subscribers
        // (or after they subscribe); non-subscribers see the paywall instead.
        InventionPaywallHook.presentBeforeInventing {
            isInventing = true
            let prefs = UserPrefs.current(in: context)
            let hint = inventHint.trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep only the most recent few titles so the prompt stays focused.
            let avoid = Array(inventedTitles.suffix(6))
            Task {
                let draft = await PantryChef.invent(
                    pantry: pantryItems,
                    prefs: prefs,
                    hint: hint.isEmpty ? nil : hint,
                    maxMinutes: maxMinutes,
                    mealType: inventMealType,
                    avoidTitles: avoid
                )
                isInventing = false
                if let draft {
                    Haptics.notify(.success)
                    inventedDraft = draft
                    if let title = draft.title, !inventedTitles.contains(title) {
                        inventedTitles.append(title)
                    }
                } else {
                    inventError = "Glutt couldn't spin up a dish from your pantry right now. Add a few more items, or try again."
                }
            }
        }
    }

    private func ask() {
        let query = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isAsking else { return }
        Haptics.impact(.medium)
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
            Haptics.notify(.success)
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
                                Haptics.selection()
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
                            Haptics.selection()
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
                                Haptics.selection()
                                mood = option
                            }
                        }
                    }
                }
            }

            Button("Update options") {
                Haptics.impact(.medium)
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
                    HStack(spacing: 4) {
                        Ph.checkCircle.fill
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Ready now")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.Colors.accent)
                    }
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
                    HStack(spacing: 4) {
                        Ph.clock.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(recommendation.recipe.timeLabel)
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Spacer()
            }

            if !recommendation.reasons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(recommendation.reasons, id: \.self) { reason in
                            reasonPill(reason)
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
                    Haptics.impact(.medium)
                    planningRecipe = recommendation.recipe
                }
                .buttonStyle(.gluttSecondary)
            }
        }
        .cardStyle()
    }

    /// A single reason rendered as a tinted pill. Reasons that describe a
    /// constraint or cost (time budget, missing items) read amber-on-warm;
    /// genuinely positive ones (you have it, rated it, uses it up) read
    /// herb-green-on-sage.
    private func reasonPill(_ reason: String) -> some View {
        let isCost = reasonIsCost(reason)
        return Text(reason)
            .font(.gluttCaption.weight(.semibold))
            .foregroundStyle(isCost ? Theme.Colors.warning : Theme.Colors.accent)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.sm + 2)
            .padding(.vertical, 5)
            .background(isCost ? Theme.Colors.warningTint : Theme.Colors.successTint)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
    }

    /// Classify a recommendation reason as a constraint/cost (amber) vs. a
    /// positive signal (herb-green). Cost reasons are about time budget or a
    /// partial pantry match; everything else is something good about the dish.
    private func reasonIsCost(_ reason: String) -> Bool {
        let lower = reason.lowercased()
        return lower.contains("missing")
            || lower.contains("fits your")
            || lower.contains("min —")
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
